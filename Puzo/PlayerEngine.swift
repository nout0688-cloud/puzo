import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer

struct Track: Identifiable, Codable, Equatable {
    var id = UUID()
    var scId: Int?
    var url: String
    var title: String
    var artist: String
    var artwork: String?
    var durationMs: Int?
}

struct SCUser: Codable, Equatable {
    var id: Int
    var username: String
    var avatarUrl: String?
    var permalinkUrl: String
}

enum RepeatMode: Int { case off, all, one }

/// Drives the official SoundCloud widget inside a hidden WKWebView,
/// scrapes client_id dynamically from SoundCloud web assets for keyless search,
/// and handles cookie/interceptor-based account login without official API keys.
final class PlayerEngine: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var tracks: [Track] = [] { didSet { save() } }
    @Published var searchResults: [Track] = []
    @Published var accountTracks: [Track] = []
    @Published var isSearching = false
    @Published var isLoadingAccount = false
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var position: Double = 0   // seconds
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var errorText: String?

    @Published var currentUser: SCUser? { didSet { saveUser() } }
    @Published var oauthToken: String? {
        didSet {
            if let t = oauthToken { UserDefaults.standard.set(t, forKey: tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: tokenKey) }
        }
    }

    let webView: WKWebView
    private var artworkImage: UIImage?
    private let storeKey = "puzo.tracks"
    private let userKey = "puzo.user"
    private let tokenKey = "puzo.oauthToken"
    private let clientIdKey = "puzo.clientId"
    private var cachedClientId: String = UserDefaults.standard.string(forKey: "puzo.clientId") ?? "tHVbSbDP4TaoMbPppngv6Tdry83vNbMQ"

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

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
        if let ud = UserDefaults.standard.data(forKey: userKey),
           let u = try? JSONDecoder().decode(SCUser.self, from: ud) { currentUser = u }
        oauthToken = UserDefaults.standard.string(forKey: tokenKey)

        setupAudioSession()
        setupRemote()

        Task {
            _ = try? await refreshClientId()
            if currentUser != nil {
                await fetchAccountLikes()
            }
        }
    }

    // MARK: Persistence
    private func save() {
        if let d = try? JSONEncoder().encode(tracks) { UserDefaults.standard.set(d, forKey: storeKey) }
    }

    private func saveUser() {
        if let u = currentUser, let d = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(d, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }
    }

    // MARK: Keyless Client ID & API-v2 Helper
    func updateClientId(_ id: String) {
        guard id.count >= 16 else { return }
        cachedClientId = id
        UserDefaults.standard.set(id, forKey: clientIdKey)
    }

    private func refreshClientId() async throws -> String {
        var req = URLRequest(url: URL(string: "https://soundcloud.com")!)
        req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        let (htmlData, _) = try await URLSession.shared.data(for: req)
        let html = String(data: htmlData, encoding: .utf8) ?? ""

        let scriptRegex = try NSRegularExpression(pattern: #"https://a-v2\.sndcdn\.com/assets/[^"]+\.js"#)
        let matches = scriptRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let urls = matches.compactMap { Range($0.range, in: html).map { String(html[$0]) } }

        let idRegex = try NSRegularExpression(pattern: #"client_id\s*:\s*"([a-zA-Z0-9]{32})""#)
        for urlStr in urls.suffix(4).reversed() {
            guard let u = URL(string: urlStr) else { continue }
            var jsReq = URLRequest(url: u)
            jsReq.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
            if let (jsData, _) = try? await URLSession.shared.data(for: jsReq),
               let js = String(data: jsData, encoding: .utf8),
               let m = idRegex.firstMatch(in: js, range: NSRange(js.startIndex..., in: js)),
               let r = Range(m.range(at: 1), in: js) {
                let cid = String(js[r])
                await MainActor.run { self.updateClientId(cid) }
                return cid
            }
        }
        return cachedClientId
    }

    private func apiGet(_ path: String, query: [URLQueryItem] = [], retry: Bool = true) async throws -> Any {
        var comps = URLComponents(string: path.hasPrefix("http") ? path : "https://api-v2.soundcloud.com\(path)")!
        var items = query
        if !items.contains(where: { $0.name == "client_id" }) {
            items.append(URLQueryItem(name: "client_id", value: cachedClientId))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        req.setValue("https://soundcloud.com/", forHTTPHeaderField: "Referer")
        if let token = oauthToken, !token.isEmpty {
            req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, (http.statusCode == 401 || http.statusCode == 403), retry {
            _ = try? await refreshClientId()
            return try await apiGet(path, query: query, retry: false)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func parseTrack(_ dict: [String: Any]) -> Track? {
        guard let permalink = dict["permalink_url"] as? String,
              let title = dict["title"] as? String else { return nil }
        let user = dict["user"] as? [String: Any]
        let artist = (dict["publisher_metadata"] as? [String: Any])?["artist"] as? String
            ?? user?["username"] as? String
            ?? "SoundCloud"
        let artwork = (dict["artwork_url"] as? String) ?? (user?["avatar_url"] as? String)
        let scId = dict["id"] as? Int
        let dur = dict["duration"] as? Int
        return Track(scId: scId, url: permalink, title: title, artist: artist, artwork: artwork, durationMs: dur)
    }

    // MARK: Track Search (without official API)
    func search(query raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            await MainActor.run { searchResults = [] }
            return
        }
        if q.contains("soundcloud.com/") {
            await add(link: q)
            return
        }
        await MainActor.run { isSearching = true }
        defer { Task { @MainActor in isSearching = false } }

        do {
            let json = try await apiGet("/search/tracks", query: [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "limit", value: "30")
            ])
            if let root = json as? [String: Any],
               let coll = root["collection"] as? [[String: Any]] {
                let parsed = coll.compactMap(Self.parseTrack)
                await MainActor.run { self.searchResults = parsed }
                return
            }
        } catch {
            // Fallback to HTML hydration scrape if api-v2 fails
            if let fallback = try? await scrapeHydrationSearch(query: q), !fallback.isEmpty {
                await MainActor.run { self.searchResults = fallback }
                return
            }
            await MainActor.run { self.errorText = "Ошибка поиска: \(error.localizedDescription)" }
        }
    }

    private func scrapeHydrationSearch(query: String) async throws -> [Track] {
        var comps = URLComponents(string: "https://soundcloud.com/search/sounds")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        var req = URLRequest(url: comps.url!)
        req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(data: data, encoding: .utf8) ?? ""
        guard let start = html.range(of: "window.__sc_hydration = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex) else { return [] }
        let rawJson = String(html[start.upperBound..<end.lowerBound])
        guard let jData = rawJson.data(using: .utf8),
              let arr = try JSONSerialization.jsonObject(with: jData) as? [[String: Any]] else { return [] }
        for item in arr where (item["hydratable"] as? String) == "search" {
            if let d = item["data"] as? [String: Any],
               let coll = d["collection"] as? [[String: Any]] {
                return coll.compactMap(Self.parseTrack)
            }
        }
        return []
    }

    // MARK: Account Login (Web Cookie / OAuth Token & Profile Resolve)
    func handleCapturedAuth(token: String?, clientId: String?) {
        if let cid = clientId, !cid.isEmpty { updateClientId(cid) }
        guard let token = token, !token.isEmpty else { return }
        let cleaned = token.replacingOccurrences(of: "OAuth ", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned != oauthToken else { return }
        DispatchQueue.main.async {
            self.oauthToken = cleaned
            Task { await self.fetchMe() }
        }
    }

    func fetchMe() async {
        await MainActor.run { isLoadingAccount = true }
        defer { Task { @MainActor in isLoadingAccount = false } }
        do {
            let json = try await apiGet("/me")
            if let dict = json as? [String: Any],
               let id = dict["id"] as? Int,
               let username = dict["username"] as? String {
                let user = SCUser(
                    id: id,
                    username: username,
                    avatarUrl: dict["avatar_url"] as? String,
                    permalinkUrl: dict["permalink_url"] as? String ?? "https://soundcloud.com"
                )
                await MainActor.run { self.currentUser = user }
                await fetchAccountLikes()
            }
        } catch {
            await MainActor.run { self.errorText = "Не удалось загрузить профиль" }
        }
    }

    func loginByProfile(input raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !trimmed.isEmpty else { return }
        let urlStr = trimmed.hasPrefix("http") ? trimmed : "https://soundcloud.com/\(trimmed)"
        await MainActor.run { isLoadingAccount = true }
        defer { Task { @MainActor in isLoadingAccount = false } }

        do {
            let json = try await apiGet("/resolve", query: [URLQueryItem(name: "url", value: urlStr)])
            if let dict = json as? [String: Any],
               let id = dict["id"] as? Int,
               let username = dict["username"] as? String {
                let user = SCUser(
                    id: id,
                    username: username,
                    avatarUrl: dict["avatar_url"] as? String,
                    permalinkUrl: dict["permalink_url"] as? String ?? urlStr
                )
                await MainActor.run { self.currentUser = user }
                await fetchAccountLikes()
            } else {
                await MainActor.run { self.errorText = "Профиль не найден" }
            }
        } catch {
            await MainActor.run { self.errorText = "Не удалось найти профиль: \(error.localizedDescription)" }
        }
    }

    func fetchAccountLikes() async {
        guard let uid = currentUser?.id else { return }
        await MainActor.run { isLoadingAccount = true }
        defer { Task { @MainActor in isLoadingAccount = false } }
        do {
            let json = try await apiGet("/users/\(uid)/track_likes", query: [
                URLQueryItem(name: "limit", value: "50")
            ])
            if let root = json as? [String: Any],
               let coll = root["collection"] as? [[String: Any]] {
                let liked = coll.compactMap { item -> Track? in
                    if let t = item["track"] as? [String: Any] { return Self.parseTrack(t) }
                    return Self.parseTrack(item)
                }
                await MainActor.run { self.accountTracks = liked }
            }
        } catch {
            await MainActor.run { self.errorText = "Не удалось загрузить лайки" }
        }
    }

    func importAllAccountTracks() {
        for t in accountTracks where !tracks.contains(where: { $0.url == t.url }) {
            tracks.append(t)
        }
    }

    func logout() {
        oauthToken = nil
        currentUser = nil
        accountTracks = []
        let store = WKWebsiteDataStore.default()
        store.httpCookieStore.getAllCookies { cookies in
            for c in cookies where c.domain.contains("soundcloud") {
                store.httpCookieStore.delete(c)
            }
        }
    }

    // MARK: Library
    func addTrack(_ t: Track, playImmediately: Bool = false) {
        if let existing = tracks.firstIndex(where: { $0.url == t.url }) {
            if playImmediately { play(index: existing) }
            return
        }
        tracks.insert(t, at: 0)
        if playImmediately { play(index: 0) }
    }

    func isSaved(_ t: Track) -> Bool {
        tracks.contains(where: { $0.url == t.url })
    }

    func add(link raw: String) async {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.contains("soundcloud.com") || link.contains("on.soundcloud.com") else {
            await MainActor.run { errorText = "Это не ссылка SoundCloud" }
            return
        }
        // Try resolve first (supports tracks and playlists!)
        if let json = try? await apiGet("/resolve", query: [URLQueryItem(name: "url", value: link)]),
           let dict = json as? [String: Any] {
            if let kind = dict["kind"] as? String, kind == "playlist",
               let rawTracks = dict["tracks"] as? [[String: Any]] {
                let parsed = rawTracks.compactMap(Self.parseTrack)
                if !parsed.isEmpty {
                    await MainActor.run {
                        for t in parsed where !self.tracks.contains(where: { $0.url == t.url }) {
                            self.tracks.append(t)
                        }
                        self.errorText = nil
                    }
                    return
                }
            } else if let single = Self.parseTrack(dict) {
                await MainActor.run {
                    self.addTrack(single)
                    self.errorText = nil
                }
                return
            }
        }

        // Fallback to oembed
        guard var comps = URLComponents(string: "https://soundcloud.com/oembed") else { return }
        comps.queryItems = [.init(name: "format", value: "json"), .init(name: "url", value: link)]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let t = Track(url: link,
                          title: o["title"] as? String ?? link,
                          artist: o["author_name"] as? String ?? "",
                          artwork: o["thumbnail_url"] as? String)
            await MainActor.run { addTrack(t); errorText = nil }
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

/// In-app SoundCloud Web Login view that extracts `oauth_token` cookie and `Authorization` headers without API keys.
struct SoundCloudLoginWebView: UIViewRepresentable {
    var onTokenCaptured: (String?, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTokenCaptured: onTokenCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        let hookJS = """
        (function() {
          function send(tok, cid) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scAuth) {
              window.webkit.messageHandlers.scAuth.postMessage({token: tok || '', clientId: cid || ''});
            }
          }
          function checkCookies() {
            var m = document.cookie.match(/(?:^|;\\s*)oauth_token=([^;]+)/);
            if (m && m[1]) send(decodeURIComponent(m[1]), '');
          }
          setInterval(checkCookies, 1000);
          var origOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            if (typeof url === 'string') {
              var m = url.match(/[?&]client_id=([a-zA-Z0-9]{16,})/);
              if (m) send('', m[1]);
            }
            return origOpen.apply(this, arguments);
          };
          var origHeader = XMLHttpRequest.prototype.setRequestHeader;
          XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            if (name && name.toLowerCase() === 'authorization' && value) {
              send(value, '');
            }
            return origHeader.apply(this, arguments);
          };
          var origFetch = window.fetch;
          if (origFetch) {
            window.fetch = function(input, init) {
              try {
                var url = (typeof input === 'string') ? input : (input && input.url) || '';
                var m = url.match(/[?&]client_id=([a-zA-Z0-9]{16,})/);
                if (m) send('', m[1]);
                if (init && init.headers) {
                  var h = init.headers;
                  var auth = (h.get ? h.get('Authorization') : (h['Authorization'] || h['authorization']));
                  if (auth) send(auth, '');
                }
              } catch(e) {}
              return origFetch.apply(this, arguments);
            };
          }
        })();
        """
        ucc.addUserScript(WKUserScript(source: hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.add(context.coordinator, name: "scAuth")
        cfg.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        wv.load(URLRequest(url: URL(string: "https://soundcloud.com/signin")!))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTokenCaptured: (String?, String?) -> Void
        init(onTokenCaptured: @escaping (String?, String?) -> Void) {
            self.onTokenCaptured = onTokenCaptured
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] {
                let tok = body["token"] as? String
                let cid = body["clientId"] as? String
                if (tok != nil && !tok!.isEmpty) || (cid != nil && !cid!.isEmpty) {
                    onTokenCaptured(tok, cid)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                if let c = cookies.first(where: { $0.name == "oauth_token" && $0.domain.contains("soundcloud") }),
                   !c.value.isEmpty {
                    self?.onTokenCaptured(c.value, nil)
                }
            }
        }
    }
}
