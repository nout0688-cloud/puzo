import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer

struct Track: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: String
    var title: String
    var artist: String
    var artwork: String?
}

enum RepeatMode: Int { case off, all, one }

/// Drives the official SoundCloud widget inside a hidden WKWebView
/// and exposes lock-screen / Control Center controls.
final class PlayerEngine: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var tracks: [Track] = [] { didSet { save() } }
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var position: Double = 0   // seconds
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var errorText: String?

    let webView: WKWebView
    private var artworkImage: UIImage?
    private let storeKey = "puzo.tracks"

    var current: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(self, name: "puzo")
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://soundcloud.com"))
        if let d = UserDefaults.standard.data(forKey: storeKey),
           let t = try? JSONDecoder().decode([Track].self, from: d) { tracks = t }
        setupAudioSession()
        setupRemote()
    }

    // MARK: Library
    private func save() {
        if let d = try? JSONEncoder().encode(tracks) { UserDefaults.standard.set(d, forKey: storeKey) }
    }

    func add(link raw: String) async {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.contains("soundcloud.com") || link.contains("on.soundcloud.com"),
              var comps = URLComponents(string: "https://soundcloud.com/oembed") else {
            await MainActor.run { errorText = "Это не ссылка SoundCloud" }
            return
        }
        comps.queryItems = [.init(name: "format", value: "json"), .init(name: "url", value: link)]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let t = Track(url: link,
                          title: o["title"] as? String ?? link,
                          artist: o["author_name"] as? String ?? "",
                          artwork: o["thumbnail_url"] as? String)
            await MainActor.run { tracks.append(t); errorText = nil }
        } catch {
            await MainActor.run { errorText = "Не удалось добавить ссылку" }
        }
    }

    func remove(at offsets: IndexSet) {
        let playing = current?.id
        tracks.remove(atOffsets: offsets)
        currentIndex = tracks.firstIndex { $0.id == playing }
    }

    // MARK: Playback
    func play(index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
        position = 0; duration = 0
        let t = tracks[index]
        loadArtwork(t.artwork)
        js("loadTrack(\(Self.q(t.url)))")
        isPlaying = true
        updateNowPlaying()
    }

    func toggle() {
        if current == nil { if !tracks.isEmpty { play(index: 0) }; return }
        js(isPlaying ? "w.pause()" : "w.play()")
    }

    func next(auto: Bool = false) {
        guard !tracks.isEmpty else { return }
        if auto && repeatMode == .one, let i = currentIndex { play(index: i); return }
        if shuffle { play(index: Int.random(in: 0..<tracks.count)); return }
        let n = (currentIndex ?? -1) + 1
        if n < tracks.count { play(index: n) }
        else if repeatMode == .all || !auto { play(index: 0) }
        else { isPlaying = false; updateNowPlaying() }
    }

    func previous() {
        if position > 3 { seek(0); return }
        guard !tracks.isEmpty else { return }
        play(index: max(0, (currentIndex ?? 0) - 1))
    }

    func seek(_ s: Double) { position = s; js("w.seekTo(\(Int(s * 1000)))"); updateNowPlaying() }

    func cycleRepeat() { repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3)! }

    // MARK: Bridge
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any], let type = d["type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "play": self.isPlaying = true
            case "pause": self.isPlaying = false
            case "finish": self.next(auto: true)
            case "progress":
                self.position = (d["pos"] as? Double ?? 0) / 1000
            case "duration":
                self.duration = (d["ms"] as? Double ?? 0) / 1000
            default: break
            }
            self.updateNowPlaying()
        }
    }

    private func js(_ s: String) { webView.evaluateJavaScript(s, completionHandler: nil) }
    private static func q(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let arr = String(data: data ?? Data(), encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    // MARK: System integration
    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.js("w.play()"); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.js("w.pause()"); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
    }

    private func loadArtwork(_ s: String?) {
        artworkImage = nil
        guard let s, let u = URL(string: s.replacingOccurrences(of: "-large", with: "-t500x500")) else { return }
        URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
            guard let d, let img = UIImage(data: d) else { return }
            DispatchQueue.main.async { self?.artworkImage = img; self?.updateNowPlaying() }
        }.resume()
    }

    private func updateNowPlaying() {
        guard let t = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Widget page
    static let html = """
    <html><body>
    <script src="https://w.soundcloud.com/player/api.js"></script>
    <script>
    var w = null;
    function post(o){ window.webkit.messageHandlers.puzo.postMessage(o); }
    function bind(){
      w.bind(SC.Widget.Events.PLAY, function(){ post({type:'play'}); w.getDuration(function(d){ post({type:'duration', ms:d}); }); });
      w.bind(SC.Widget.Events.PAUSE, function(){ post({type:'pause'}); });
      w.bind(SC.Widget.Events.FINISH, function(){ post({type:'finish'}); });
      w.bind(SC.Widget.Events.PLAY_PROGRESS, function(e){ post({type:'progress', pos:e.currentPosition}); });
    }
    function loadTrack(url){
      if (w === null) {
        var f = document.createElement('iframe');
        f.allow = 'autoplay';
        f.src = 'https://w.soundcloud.com/player/?auto_play=true&url=' + encodeURIComponent(url);
        document.body.appendChild(f);
        w = SC.Widget(f);
        w.bind(SC.Widget.Events.READY, function(){ bind(); w.play(); });
      } else {
        w.load(url, {auto_play: true});
      }
    }
    </script></body></html>
    """
}

/// Keeps the hidden web view inside the view hierarchy (needed for background audio).
struct HiddenWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
