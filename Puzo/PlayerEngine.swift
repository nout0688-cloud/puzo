import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: String { url }
    var scId: Int?
    var url: String
    var title: String
    var artist: String
    var artistId: Int?
    var artistAvatar: String?
    var artwork: String?
    var durationMs: Int?
    var playbackCount: Int?
    var likesCount: Int?
    var genre: String?
    var streamUrl: String?
    var hlsUrl: String?
}

struct SCPlaylist: Identifiable, Codable, Equatable {
    var id: Int
    var title: String
    var author: String
    var artwork: String?
    var trackCount: Int
    var permalinkUrl: String
    var tracks: [Track]
}

struct SCUser: Identifiable, Codable, Equatable {
    var id: Int
    var username: String
    var avatarUrl: String?
    var permalinkUrl: String
    var followersCount: Int?
    var trackCount: Int?
    var likesCount: Int?
}

enum RepeatMode: Int { case off, all, one }

enum PlaybackSpeed: Double, CaseIterable, Identifiable {
    case slowed = 0.85
    case normal = 1.0
    case spedUp = 1.18

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .slowed: return "Slowed 0.85x"
        case .normal: return "1.0x"
        case .spedUp: return "Nightcore 1.2x"
        }
    }
    var shortLabel: String {
        switch self {
        case .slowed: return "0.85x"
        case .normal: return "1x"
        case .spedUp: return "1.2x"
        }
    }
}

final class PlayerEngine: NSObject, ObservableObject, WKScriptMessageHandler {
    // Queue & Library
    @Published var queue: [Track] = []
    @Published var currentIndex: Int?
    @Published var likedTracks: [Track] = [] { didSet { saveLikes() } }
    @Published var recentTracks: [Track] = [] { didSet { saveRecents() } }

    // Home & Discovery
    @Published var forYouTracks: [Track] = []
    @Published var trendingTracks: [Track] = []
    @Published var relatedToRecentTracks: [Track] = []
    @Published var featuredPlaylists: [SCPlaylist] = []
    @Published var selectedGenre: String = "Phonk"
    @Published var isLoadingHome = false

    // Search
    @Published var searchResults: [Track] = []
    @Published var searchPlaylists: [SCPlaylist] = []
    @Published var searchUsers: [SCUser] = []
    @Published var isSearching = false

    // Account
    @Published var currentUser: SCUser? { didSet { saveUser() } }
    @Published var accountTracks: [Track] = []
    @Published var accountPlaylists: [SCPlaylist] = []
    @Published var isLoadingAccount = false
    @Published var oauthToken: String? {
        didSet {
            if let t = oauthToken { UserDefaults.standard.set(t, forKey: tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: tokenKey) }
        }
    }

    // Playback state
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var autoRadio = true
    @Published var speed: PlaybackSpeed = .normal { didSet { applySpeed() } }
    @Published var pitchShift = true { didSet { applySpeed() } }
    @Published var sleepMinutesRemaining: Int?
    @Published var errorText: String?

    let genres = ["Phonk", "Hip-Hop & Rap", "Hyperpop", "Electronic", "Trap", "Cloud Rap", "Lo-Fi", "Techno", "Drum & Bass", "Ambient"]

    let webView: WKWebView
    private var avPlayer = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var usingNativePlayer = false
    private var sleepTimer: Timer?
    private var artworkImage: UIImage?

    private let likesKey = "puzo.liked.v2"
    private let recentsKey = "puzo.recents.v2"
    private let userKey = "puzo.user"
    private let tokenKey = "puzo.oauthToken"
    private let clientIdKey = "puzo.clientId"
    private var cachedClientId: String = UserDefaults.standard.string(forKey: "puzo.clientId") ?? "tHVbSbDP4TaoMbPppngv6Tdry83vNbMQ"

    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    var current: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
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

        if let d = UserDefaults.standard.data(forKey: likesKey),
           let t = try? JSONDecoder().decode([Track].self, from: d) { likedTracks = t }
        if let d = UserDefaults.standard.data(forKey: recentsKey),
           let t = try? JSONDecoder().decode([Track].self, from: d) { recentTracks = t }
        if let ud = UserDefaults.standard.data(forKey: userKey),
           let u = try? JSONDecoder().decode(SCUser.self, from: ud) { currentUser = u }
        oauthToken = UserDefaults.standard.string(forKey: tokenKey)

        setupAudioSession()
        setupNativePlayer()
        setupRemote()

        Task {
            _ = try? await refreshClientId()
            if currentUser != nil {
                await fetchAccountData()
            }
            await loadHome(genre: selectedGenre)
        }
    }

    // MARK: Persistence
    private func saveLikes() {
        if let d = try? JSONEncoder().encode(likedTracks) { UserDefaults.standard.set(d, forKey: likesKey) }
    }

    private func saveRecents() {
        if let d = try? JSONEncoder().encode(recentTracks) { UserDefaults.standard.set(d, forKey: recentsKey) }
    }

    private func saveUser() {
        if let u = currentUser, let d = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(d, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }
    }

    // MARK: Keyless Client ID & API-v2
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

    func apiGet(_ path: String, query: [URLQueryItem] = [], retry: Bool = true) async throws -> Any {
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

    // MARK: Parsers (filters out 30s Go+ SNIP/BLOCK previews)
    static func parseTrack(_ dict: [String: Any]) -> Track? {
        guard let permalink = dict["permalink_url"] as? String,
              let title = dict["title"] as? String else { return nil }

        let policy = (dict["policy"] as? String) ?? "ALLOW"
        if policy == "SNIP" || policy == "BLOCK" { return nil }

        let dur = dict["duration"] as? Int ?? 0
        if dur > 0 && dur <= 31_000 { return nil } // skip 30-sec previews

        let user = dict["user"] as? [String: Any]
        let artist = (dict["publisher_metadata"] as? [String: Any])?["artist"] as? String
            ?? user?["username"] as? String
            ?? "SoundCloud"
        let artistId = user?["id"] as? Int
        let artistAvatar = user?["avatar_url"] as? String
        let artwork = (dict["artwork_url"] as? String) ?? artistAvatar
        let scId = dict["id"] as? Int
        let plays = dict["playback_count"] as? Int
        let likes = dict["likes_count"] as? Int
        let genre = dict["genre"] as? String

        var progressive: String?
        var hls: String?
        if let media = dict["media"] as? [String: Any],
           let transcodings = media["transcodings"] as? [[String: Any]] {
            for tr in transcodings {
                guard let u = tr["url"] as? String,
                      let fmt = tr["format"] as? [String: Any],
                      let proto = fmt["protocol"] as? String else { continue }
                let preset = (tr["preset"] as? String) ?? ""
                if preset.contains("preview") { continue }
                if proto == "progressive" { progressive = u }
                else if proto == "hls" && hls == nil { hls = u }
            }
        }

        return Track(
            scId: scId,
            url: permalink,
            title: title,
            artist: artist,
            artistId: artistId,
            artistAvatar: artistAvatar,
            artwork: artwork,
            durationMs: dur > 0 ? dur : nil,
            playbackCount: plays,
            likesCount: likes,
            genre: genre,
            streamUrl: progressive,
            hlsUrl: hls
        )
    }

    static func parsePlaylist(_ dict: [String: Any]) -> SCPlaylist? {
        guard let id = dict["id"] as? Int,
              let title = dict["title"] as? String,
              let permalink = dict["permalink_url"] as? String else { return nil }
        let user = dict["user"] as? [String: Any]
        let author = user?["username"] as? String ?? "SoundCloud"
        let rawTracks = (dict["tracks"] as? [[String: Any]]) ?? []
        let parsedTracks = rawTracks.compactMap(Self.parseTrack)
        let artwork = (dict["artwork_url"] as? String)
            ?? parsedTracks.first?.artwork
            ?? (user?["avatar_url"] as? String)
        let count = (dict["track_count"] as? Int) ?? parsedTracks.count
        return SCPlaylist(
            id: id,
            title: title,
            author: author,
            artwork: artwork,
            trackCount: count,
            permalinkUrl: permalink,
            tracks: parsedTracks
        )
    }

    static func parseUser(_ dict: [String: Any]) -> SCUser? {
        guard let id = dict["id"] as? Int,
              let username = dict["username"] as? String else { return nil }
        return SCUser(
            id: id,
            username: username,
            avatarUrl: dict["avatar_url"] as? String,
            permalinkUrl: dict["permalink_url"] as? String ?? "https://soundcloud.com",
            followersCount: dict["followers_count"] as? Int,
            trackCount: dict["track_count"] as? Int,
            likesCount: dict["likes_count"] as? Int
        )
    }

    // MARK: Home & Recommendations (SoundCloud-style Feed)
    func loadHome(genre: String? = nil) async {
        let g = genre ?? selectedGenre
        await MainActor.run {
            self.selectedGenre = g
            self.isLoadingHome = true
        }
        defer { Task { @MainActor in self.isLoadingHome = false } }

        // 1. Personalized "For You" based on account likes, local likes, or recent plays
        var seeds: [Int] = []
        seeds.append(contentsOf: accountTracks.prefix(4).compactMap(\.scId))
        seeds.append(contentsOf: recentTracks.prefix(3).compactMap(\.scId))
        seeds.append(contentsOf: likedTracks.prefix(3).compactMap(\.scId))

        if let firstSeed = seeds.first {
            if let relJson = try? await apiGet("/tracks/\(firstSeed)/related", query: [URLQueryItem(name: "limit", value: "25")]),
               let relRoot = relJson as? [String: Any],
               let relColl = relRoot["collection"] as? [[String: Any]] {
                let relParsed = relColl.compactMap(Self.parseTrack)
                if !relParsed.isEmpty {
                    await MainActor.run { self.forYouTracks = relParsed }
                }
            }
        }

        if seeds.count > 1, let secondSeed = seeds.dropFirst().first {
            if let rel2Json = try? await apiGet("/tracks/\(secondSeed)/related", query: [URLQueryItem(name: "limit", value: "20")]),
               let rel2Root = rel2Json as? [String: Any],
               let rel2Coll = rel2Root["collection"] as? [[String: Any]] {
                let rel2Parsed = rel2Coll.compactMap(Self.parseTrack)
                if !rel2Parsed.isEmpty {
                    await MainActor.run { self.relatedToRecentTracks = rel2Parsed }
                }
            }
        }

        // 2. Genre Trending / Banger Tracks
        if let json = try? await apiGet("/search/tracks", query: [
            URLQueryItem(name: "q", value: "\(g)热门 OR \(g)"),
            URLQueryItem(name: "limit", value: "35")
        ]) {
            if let root = json as? [String: Any],
               let coll = root["collection"] as? [[String: Any]] {
                var parsed = coll.compactMap(Self.parseTrack)
                parsed.sort { ($0.playbackCount ?? 0) > ($1.playbackCount ?? 0) }
                await MainActor.run {
                    self.trendingTracks = parsed
                    if self.forYouTracks.isEmpty {
                        self.forYouTracks = Array(parsed.shuffled().prefix(15))
                    }
                }
            }
        }

        // 3. Curated Playlists for selected genre
        if let plJson = try? await apiGet("/search/playlists", query: [
            URLQueryItem(name: "q", value: "\(g) mix"),
            URLQueryItem(name: "limit", value: "10")
        ]),
           let plRoot = plJson as? [String: Any],
           let plColl = plRoot["collection"] as? [[String: Any]] {
            let pls = plColl.compactMap(Self.parsePlaylist)
            await MainActor.run { self.featuredPlaylists = pls }
        }
    }

    /// Launches non-stop "My Wave" radio seeded from account likes, recents, or trending
    func startMyWave() {
        var pool: [Track] = []
        pool.append(contentsOf: forYouTracks)
        pool.append(contentsOf: accountTracks)
        pool.append(contentsOf: likedTracks)
        pool.append(contentsOf: trendingTracks)
        var unique: [Track] = []
        var seen = Set<String>()
        for t in pool.shuffled() where !seen.contains(t.url) {
            seen.insert(t.url)
            unique.append(t)
        }
        guard !unique.isEmpty else { return }
        autoRadio = true
        playQueue(unique, startIndex: 0)
    }

    /// Starts radio based on a specific track
    func startTrackRadio(_ seed: Track) async {
        guard let scId = seed.scId else {
            await MainActor.run { playQueue([seed], startIndex: 0) }
            return
        }
        do {
            let json = try await apiGet("/tracks/\(scId)/related", query: [URLQueryItem(name: "limit", value: "30")])
            if let root = json as? [String: Any],
               let coll = root["collection"] as? [[String: Any]] {
                let related = coll.compactMap(Self.parseTrack)
                await MainActor.run {
                    self.playQueue([seed] + related, startIndex: 0)
                }
            }
        } catch {
            await MainActor.run { playQueue([seed], startIndex: 0) }
        }
    }

    // MARK: Search (Tracks, Playlists, Artists)
    func search(query raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            await MainActor.run {
                searchResults = []
                searchPlaylists = []
                searchUsers = []
            }
            return
        }
        if q.contains("soundcloud.com/") {
            await add(link: q)
            return
        }
        await MainActor.run { isSearching = true }
        defer { Task { @MainActor in isSearching = false } }

        async let tRes = searchTracks(q: q)
        async let pRes = searchPlaylistsReq(q: q)
        async let uRes = searchUsersReq(q: q)

        let (tracks, playlists, users) = await (tRes, pRes, uRes)
        await MainActor.run {
            self.searchResults = tracks
            self.searchPlaylists = playlists
            self.searchUsers = users
        }
    }

    private func searchTracks(q: String) async -> [Track] {
        guard let json = try? await apiGet("/search/tracks", query: [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "35")
        ]),
        let root = json as? [String: Any],
        let coll = root["collection"] as? [[String: Any]] else { return [] }
        return coll.compactMap(Self.parseTrack)
    }

    private func searchPlaylistsReq(q: String) async -> [SCPlaylist] {
        guard let json = try? await apiGet("/search/playlists", query: [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "15")
        ]),
        let root = json as? [String: Any],
        let coll = root["collection"] as? [[String: Any]] else { return [] }
        return coll.compactMap(Self.parsePlaylist)
    }

    private func searchUsersReq(q: String) async -> [SCUser] {
        guard let json = try? await apiGet("/search/users", query: [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "15")
        ]),
        let root = json as? [String: Any],
        let coll = root["collection"] as? [[String: Any]] else { return [] }
        return coll.compactMap(Self.parseUser)
    }

    func fetchArtistTracks(userId: Int) async -> [Track] {
        guard let json = try? await apiGet("/users/\(userId)/tracks", query: [URLQueryItem(name: "limit", value: "40")]),
              let root = json as? [String: Any],
              let coll = root["collection"] as? [[String: Any]] else { return [] }
        return coll.compactMap(Self.parseTrack)
    }

    func fetchPlaylistFull(_ playlist: SCPlaylist) async -> [Track] {
        if !playlist.tracks.isEmpty && playlist.tracks.count >= min(playlist.trackCount, 5) {
            return playlist.tracks
        }
        guard let json = try? await apiGet("/playlists/\(playlist.id)"),
              let dict = json as? [String: Any],
              let rawTracks = dict["tracks"] as? [[String: Any]] else {
            return playlist.tracks
        }
        let direct = rawTracks.compactMap(Self.parseTrack)
        // SoundCloud sometimes returns stub tracks with only `id` for large playlists; resolve batch of IDs
        let missingIds = rawTracks.compactMap { item -> Int? in
            if item["title"] == nil, let id = item["id"] as? Int { return id }
            return nil
        }.prefix(35)
        if !missingIds.isEmpty {
            let idsParam = missingIds.map(String.init).joined(separator: ",")
            if let extraJson = try? await apiGet("/tracks", query: [URLQueryItem(name: "ids", value: idsParam)]),
               let extraArr = extraJson as? [[String: Any]] {
                return direct + extraArr.compactMap(Self.parseTrack)
            }
        }
        return direct
    }

    // MARK: Account Login & Sync
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
            if let dict = json as? [String: Any], let user = Self.parseUser(dict) {
                await MainActor.run { self.currentUser = user }
                await fetchAccountData()
                await loadHome(genre: selectedGenre)
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
            if let dict = json as? [String: Any], let user = Self.parseUser(dict) {
                await MainActor.run { self.currentUser = user }
                await fetchAccountData()
                await loadHome(genre: selectedGenre)
            } else {
                await MainActor.run { self.errorText = "Профиль не найден" }
            }
        } catch {
            await MainActor.run { self.errorText = "Не удалось найти профиль: \(error.localizedDescription)" }
        }
    }

    func fetchAccountData() async {
        guard let uid = currentUser?.id else { return }
        await MainActor.run { isLoadingAccount = true }
        defer { Task { @MainActor in isLoadingAccount = false } }

        // 1. User liked tracks
        if let json = try? await apiGet("/users/\(uid)/track_likes", query: [URLQueryItem(name: "limit", value: "80")]),
           let root = json as? [String: Any],
           let coll = root["collection"] as? [[String: Any]] {
            let liked = coll.compactMap { item -> Track? in
                if let t = item["track"] as? [String: Any] { return Self.parseTrack(t) }
                return Self.parseTrack(item)
            }
            await MainActor.run { self.accountTracks = liked }
        }

        // 2. User playlists & liked playlists
        var allPlaylists: [SCPlaylist] = []
        if let plJson = try? await apiGet("/users/\(uid)/playlists", query: [URLQueryItem(name: "limit", value: "25")]),
           let plRoot = plJson as? [String: Any],
           let plColl = plRoot["collection"] as? [[String: Any]] {
            allPlaylists.append(contentsOf: plColl.compactMap(Self.parsePlaylist))
        }
        if let lplJson = try? await apiGet("/users/\(uid)/playlist_likes", query: [URLQueryItem(name: "limit", value: "25")]),
           let lplRoot = lplJson as? [String: Any],
           let lplColl = lplRoot["collection"] as? [[String: Any]] {
            let parsed = lplColl.compactMap { item -> SCPlaylist? in
                if let p = item["playlist"] as? [String: Any] { return Self.parsePlaylist(p) }
                return Self.parsePlaylist(item)
            }
            allPlaylists.append(contentsOf: parsed)
        }
        await MainActor.run { self.accountPlaylists = allPlaylists }
    }

    func logout() {
        oauthToken = nil
        currentUser = nil
        accountTracks = []
        accountPlaylists = []
        let store = WKWebsiteDataStore.default()
        store.httpCookieStore.getAllCookies { cookies in
            for c in cookies where c.domain.contains("soundcloud") {
                store.httpCookieStore.delete(c)
            }
        }
    }

    // MARK: Likes & Links
    func toggleLike(_ t: Track) {
        if let idx = likedTracks.firstIndex(where: { $0.url == t.url }) {
            likedTracks.remove(at: idx)
        } else {
            likedTracks.insert(t, at: 0)
        }
    }

    func isLiked(_ t: Track) -> Bool {
        likedTracks.contains(where: { $0.url == t.url }) || accountTracks.contains(where: { $0.url == t.url })
    }

    func add(link raw: String) async {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.contains("soundcloud.com") || link.contains("on.soundcloud.com") else {
            await MainActor.run { errorText = "Это не ссылка SoundCloud" }
            return
        }
        if let json = try? await apiGet("/resolve", query: [URLQueryItem(name: "url", value: link)]),
           let dict = json as? [String: Any] {
            if let kind = dict["kind"] as? String, kind == "playlist",
               let pl = Self.parsePlaylist(dict) {
                let tracks = await fetchPlaylistFull(pl)
                if !tracks.isEmpty {
                    await MainActor.run {
                        self.playQueue(tracks, startIndex: 0)
                        self.errorText = nil
                    }
                    return
                }
            } else if let single = Self.parseTrack(dict) {
                await MainActor.run {
                    if !self.likedTracks.contains(where: { $0.url == single.url }) {
                        self.likedTracks.insert(single, at: 0)
                    }
                    self.playQueue([single] + self.queue, startIndex: 0)
                    self.errorText = nil
                }
                return
            }
        }
        await MainActor.run { errorText = "Не удалось открыть ссылку" }
    }

    // MARK: Playback & Native Streaming
    func playQueue(_ list: [Track], startIndex: Int = 0) {
        guard !list.isEmpty, list.indices.contains(startIndex) else { return }
        queue = list
        play(index: startIndex)
    }

    func play(index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        position = 0
        let t = queue[index]
        duration = Double(t.durationMs ?? 0) / 1000.0

        // Record in recent history
        recentTracks.removeAll { $0.url == t.url }
        recentTracks.insert(t, at: 0)
        if recentTracks.count > 40 { recentTracks = Array(recentTracks.prefix(40)) }

        loadArtwork(t.artwork)
        isPlaying = true
        updateNowPlaying()

        // Try direct native AVPlayer streaming first for instant start & speed/pitch controls
        Task {
            if let directURL = await resolveStreamURL(for: t) {
                await MainActor.run {
                    self.usingNativePlayer = true
                    self.js("if(w) w.pause();")
                    let item = AVPlayerItem(url: directURL)
                    item.audioTimePitchAlgorithm = self.pitchShift ? .varispeed : .timeDomain
                    self.avPlayer.replaceCurrentItem(with: item)
                    self.avPlayer.play()
                    self.avPlayer.rate = Float(self.speed.rawValue)
                }
            } else {
                await MainActor.run {
                    self.usingNativePlayer = false
                    self.avPlayer.pause()
                    self.js("loadTrack(\(Self.q(t.url)))")
                }
            }
        }

        // If near end of queue and autoRadio is enabled, prefetch related tracks
        if autoRadio && index >= queue.count - 2, let scId = t.scId {
            Task { await appendAutoRadio(seedId: scId) }
        }
    }

    private func resolveStreamURL(for track: Track) async -> URL? {
        var transcodingEndpoint = track.streamUrl ?? track.hlsUrl
        if transcodingEndpoint == nil {
            if let json = try? await apiGet("/resolve", query: [URLQueryItem(name: "url", value: track.url)]),
               let dict = json as? [String: Any],
               let resolved = Self.parseTrack(dict) {
                transcodingEndpoint = resolved.streamUrl ?? resolved.hlsUrl
            }
        }
        guard let endpoint = transcodingEndpoint else { return nil }
        if let json = try? await apiGet(endpoint),
           let dict = json as? [String: Any],
           let urlStr = dict["url"] as? String,
           let u = URL(string: urlStr) {
            return u
        }
        return nil
    }

    private func appendAutoRadio(seedId: Int) async {
        guard let json = try? await apiGet("/tracks/\(seedId)/related", query: [URLQueryItem(name: "limit", value: "15")]),
              let root = json as? [String: Any],
              let coll = root["collection"] as? [[String: Any]] else { return }
        let related = coll.compactMap(Self.parseTrack)
        await MainActor.run {
            for r in related where !self.queue.contains(where: { $0.url == r.url }) {
                self.queue.append(r)
            }
        }
    }

    func toggle() {
        if current == nil {
            if !queue.isEmpty { play(index: 0) }
            else if !forYouTracks.isEmpty { playQueue(forYouTracks, startIndex: 0) }
            return
        }
        if usingNativePlayer {
            if isPlaying {
                avPlayer.pause()
                isPlaying = false
            } else {
                avPlayer.play()
                avPlayer.rate = Float(speed.rawValue)
                isPlaying = true
            }
            updateNowPlaying()
        } else {
            js(isPlaying ? "w.pause()" : "w.play()")
        }
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        if auto && repeatMode == .one, let i = currentIndex { play(index: i); return }
        if shuffle && queue.count > 1 { play(index: Int.random(in: 0..<queue.count)); return }
        let n = (currentIndex ?? -1) + 1
        if n < queue.count { play(index: n) }
        else if repeatMode == .all || !auto { play(index: 0) }
        else { isPlaying = false; updateNowPlaying() }
    }

    func previous() {
        if position > 3 { seek(0); return }
        guard !queue.isEmpty else { return }
        play(index: max(0, (currentIndex ?? 0) - 1))
    }

    func seek(_ s: Double) {
        position = s
        if usingNativePlayer {
            avPlayer.seek(to: CMTime(seconds: s, preferredTimescale: 600))
        } else {
            js("w.seekTo(\(Int(s * 1000)))")
        }
        updateNowPlaying()
    }

    func cycleRepeat() { repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3)! }

    private func applySpeed() {
        guard usingNativePlayer else { return }
        avPlayer.currentItem?.audioTimePitchAlgorithm = pitchShift ? .varispeed : .timeDomain
        if isPlaying {
            avPlayer.rate = Float(speed.rawValue)
        }
        updateNowPlaying()
    }

    // MARK: Sleep Timer
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepMinutesRemaining = minutes
        guard let minutes, minutes > 0 else { return }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if let rem = self.sleepMinutesRemaining {
                if rem <= 1 {
                    self.sleepMinutesRemaining = nil
                    t.invalidate()
                    if self.isPlaying { self.toggle() }
                } else {
                    self.sleepMinutesRemaining = rem - 1
                }
            }
        }
    }

    // MARK: Native AVPlayer Observers
    private func setupNativePlayer() {
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, self.usingNativePlayer else { return }
            let sec = time.seconds
            if sec.isFinite && sec >= 0 {
                self.position = sec
            }
            if let dur = self.avPlayer.currentItem?.duration.seconds, dur.isFinite && dur > 0 {
                self.duration = dur
            }
            self.updateNowPlaying()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.usingNativePlayer,
                  let item = note.object as? AVPlayerItem,
                  item == self.avPlayer.currentItem else { return }
            self.next(auto: true)
        }
    }

    // MARK: WebView Bridge (Fallback)
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard !usingNativePlayer,
              let d = m.body as? [String: Any],
              let type = d["type"] as? String else { return }
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
        c.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPlaying { self.toggle() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.toggle() }
            return .success
        }
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed.rawValue : 0.0
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

struct HiddenWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

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
