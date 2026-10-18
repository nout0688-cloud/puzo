import SwiftUI
import UIKit

private enum Theme {
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.17)
    static let border = Color.white.opacity(0.07)
    static let accent = Color(red: 1.0, green: 0.33, blue: 0.0)
}

private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

struct ContentView: View {
    @EnvironmentObject var p: PlayerEngine
    @State private var showNow = false
    @State private var showAdd = false
    @State private var showWebLogin = false
    @State private var link = ""
    @State private var query = ""
    @State private var searchScope = 0
    @State private var likesScope = 0
    @State private var likesFilter = ""
    @State private var profileInput = ""
    @State private var tab = 0
    @State private var selectedPlaylist: SCPlaylist?
    @State private var selectedArtist: SCUser?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                homeTab
                    .tabItem { Label("Главная", systemImage: "house.fill") }
                    .tag(0)

                searchTab
                    .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                    .tag(1)

                likesTab
                    .tabItem { Label("Медиатека", systemImage: "heart.fill") }
                    .tag(2)

                accountTab
                    .tabItem { Label("Профиль", systemImage: "person.fill") }
                    .tag(3)
            }
            .tint(.white)

            if p.current != nil {
                MiniPlayer {
                    haptic(.light)
                    showNow = true
                }
                .padding(.bottom, 54)
            }
            HiddenWebView(webView: p.webView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .preferredColorScheme(.dark)
        .alert("Открыть по ссылке", isPresented: $showAdd) {
            TextField("https://soundcloud.com/...", text: $link)
            Button("Открыть") {
                let l = link
                Task {
                    await p.add(link: l)
                    if p.current != nil { showNow = true }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Ошибка", isPresented: .constant(p.errorText != nil)) {
            Button("OK") { p.errorText = nil }
        } message: { Text(p.errorText ?? "") }
        .sheet(isPresented: $showWebLogin) {
            NavigationStack {
                SoundCloudLoginWebView { tok, cid in
                    p.handleCapturedAuth(token: tok, clientId: cid)
                    if let tok, !tok.isEmpty {
                        showWebLogin = false
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("SoundCloud")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { showWebLogin = false }
                    }
                }
            }
        }
        .sheet(item: $selectedPlaylist) { pl in
            PlaylistDetailView(playlist: pl) { tracks, idx in
                p.playQueue(tracks, startIndex: idx)
                showNow = true
            }
        }
        .sheet(item: $selectedArtist) { artist in
            ArtistDetailView(artist: artist) { tracks, idx in
                p.playQueue(tracks, startIndex: idx)
                showNow = true
            }
        }
        .fullScreenCover(isPresented: $showNow) { NowPlayingView() }
    }

    // MARK: - 1. HOME TAB
    private var homeTab: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        myWaveBanner

                        // Genre Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(p.genres, id: \.self) { g in
                                    let active = p.selectedGenre == g
                                    Button {
                                        haptic(.light)
                                        Task { await p.loadHome(genre: g) }
                                    } label: {
                                        Text(g)
                                            .font(.subheadline.weight(active ? .semibold : .regular))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(
                                                active ? Color.white : Theme.surface,
                                                in: Capsule()
                                            )
                                            .foregroundStyle(active ? .black : .white.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if !p.forYouTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Для тебя") {
                                    p.playQueue(p.forYouTracks, startIndex: 0)
                                    showNow = true
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(Array(p.forYouTracks.prefix(15).enumerated()), id: \.element.id) { idx, t in
                                            Button {
                                                p.playQueue(p.forYouTracks, startIndex: idx)
                                                showNow = true
                                            } label: {
                                                FeaturedTrackCard(track: t, isCurrent: p.current?.url == t.url)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !p.recentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Недавние") {
                                    p.playQueue(p.recentTracks, startIndex: 0)
                                    showNow = true
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(p.recentTracks.prefix(12).enumerated()), id: \.element.id) { idx, t in
                                            Button {
                                                p.playQueue(p.recentTracks, startIndex: idx)
                                                showNow = true
                                            } label: {
                                                CompactTrackCard(track: t, isCurrent: p.current?.url == t.url)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !p.featuredPlaylists.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Плейлисты")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(p.featuredPlaylists) { pl in
                                            Button {
                                                selectedPlaylist = pl
                                            } label: {
                                                PlaylistCard(playlist: pl)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !p.relatedToRecentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Похожее") {
                                    p.playQueue(p.relatedToRecentTracks, startIndex: 0)
                                    showNow = true
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(Array(p.relatedToRecentTracks.prefix(12).enumerated()), id: \.element.id) { idx, t in
                                            Button {
                                                p.playQueue(p.relatedToRecentTracks, startIndex: idx)
                                                showNow = true
                                            } label: {
                                                FeaturedTrackCard(track: t, isCurrent: p.current?.url == t.url)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: p.selectedGenre) {
                                p.playQueue(p.trendingTracks, startIndex: 0)
                                showNow = true
                            }

                            if p.isLoadingHome && p.trendingTracks.isEmpty {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 32)
                            } else {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(p.trendingTracks.prefix(25).enumerated()), id: \.element.id) { idx, t in
                                        TrackRow(
                                            track: t,
                                            isCurrent: p.current?.url == t.url,
                                            isLiked: p.isLiked(t),
                                            onTap: {
                                                p.playQueue(p.trendingTracks, startIndex: idx)
                                                showNow = true
                                            },
                                            onLike: {
                                                haptic(.light)
                                                p.toggleLike(t)
                                            },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 110)
                    }
                    .padding(.top, 8)
                }
                .refreshable {
                    await p.loadHome(genre: p.selectedGenre)
                }
            }
            .navigationTitle("Puzo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        link = UIPasteboard.general.string ?? ""
                        showAdd = true
                    } label: {
                        Image(systemName: "link")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    private var myWaveBanner: some View {
        Button {
            haptic(.medium)
            p.startMyWave()
            showNow = true
        } label: {
            ZStack {
                if let art = p.forYouTracks.first?.artwork ?? p.trendingTracks.first?.artwork {
                    Cover(url: art)
                        .frame(maxWidth: .infinity)
                        .frame(height: 136)
                        .blur(radius: 36)
                        .opacity(0.45)
                        .clipped()
                }
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.black.opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 6, height: 6)
                            Text("ПОТОК")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text("Моя волна")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(p.currentUser != nil ? "Настроено под \(p.currentUser!.username)" : "Бесконечный микс по твоим вкусам")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 48, height: 48)
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                            .offset(x: 1)
                    }
                }
                .padding(20)
            }
            .frame(height: 136)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. SEARCH TAB
    private var searchTab: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    // Clean Search Field (auto-searches on typing)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Треки, артисты или ссылка...", text: $query)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await p.search(query: query) } }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                p.searchResults = []
                                p.searchPlaylists = []
                                p.searchUsers = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .task(id: query) {
                        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else { return }
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        await p.search(query: q)
                    }

                    if !query.isEmpty || !p.searchResults.isEmpty {
                        Picker("Тип", selection: $searchScope) {
                            Text("Треки").tag(0)
                            Text("Плейлисты").tag(1)
                            Text("Артисты").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }

                    if p.isSearching && p.searchResults.isEmpty {
                        Spacer()
                        ProgressView().tint(.secondary)
                        Spacer()
                    } else if query.isEmpty && p.searchResults.isEmpty {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Жанры и настроение")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)

                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(VibePreset.all) { item in
                                        Button {
                                            haptic(.light)
                                            query = item.title
                                            Task { await p.search(query: item.title) }
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(item.title)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Text(item.subtitle)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 13)
                                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(Theme.border, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.top, 6)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 2) {
                                if searchScope == 0 {
                                    ForEach(Array(p.searchResults.enumerated()), id: \.element.id) { idx, t in
                                        TrackRow(
                                            track: t,
                                            isCurrent: p.current?.url == t.url,
                                            isLiked: p.isLiked(t),
                                            onTap: {
                                                p.playQueue(p.searchResults, startIndex: idx)
                                                showNow = true
                                            },
                                            onLike: {
                                                haptic(.light)
                                                p.toggleLike(t)
                                            },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                } else if searchScope == 1 {
                                    ForEach(p.searchPlaylists) { pl in
                                        Button {
                                            selectedPlaylist = pl
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: pl.artwork, radius: 8)
                                                    .frame(width: 52, height: 52)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(pl.title)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Text("\(pl.author) · \(pl.trackCount) тр.")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    ForEach(p.searchUsers) { u in
                                        Button {
                                            selectedArtist = u
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: u.avatarUrl, radius: 24)
                                                    .frame(width: 48, height: 48)
                                                    .clipShape(Circle())
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(u.username)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.white)
                                                    Text("\(u.followersCount ?? 0) подписчиков")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Spacer(minLength: 110)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Поиск")
        }
    }

    // MARK: - 3. LIBRARY / LIKES TAB
    private var combinedLikes: [Track] {
        var result: [Track] = []
        var seen = Set<String>()
        for t in p.likedTracks + p.accountTracks where !seen.contains(t.url) {
            seen.insert(t.url)
            result.append(t)
        }
        if likesFilter.trimmingCharacters(in: .whitespaces).isEmpty {
            return result
        }
        let q = likesFilter.lowercased()
        return result.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
    }

    private var likesTab: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    Picker("Раздел", selection: $likesScope) {
                        Text("Треки (\(combinedLikes.count))").tag(0)
                        Text("Плейлисты (\(p.accountPlaylists.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if likesScope == 0 {
                        if combinedLikes.isEmpty && likesFilter.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "heart")
                                    .font(.system(size: 38, weight: .light))
                                    .foregroundStyle(.secondary)
                                Text("Нет сохраненных треков")
                                    .font(.headline)
                                Text("Отмечай треки сердечком или подключи профиль SoundCloud.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                if p.currentUser == nil {
                                    Button("Подключить профиль") { tab = 3 }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(.white, in: Capsule())
                                        .foregroundStyle(.black)
                                        .padding(.top, 4)
                                }
                            }
                            Spacer()
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("Фильтр по медиатеке", text: $likesFilter)
                                    .font(.subheadline)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                if !likesFilter.isEmpty {
                                    Button { likesFilter = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.horizontal, 16)

                            HStack(spacing: 10) {
                                Button {
                                    haptic(.light)
                                    p.shuffle = false
                                    p.playQueue(combinedLikes, startIndex: 0)
                                    showNow = true
                                } label: {
                                    Label("Слушать", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.black)
                                }

                                Button {
                                    haptic(.light)
                                    p.shuffle = true
                                    p.playQueue(combinedLikes.shuffled(), startIndex: 0)
                                    showNow = true
                                } label: {
                                    Label("Перемешать", systemImage: "shuffle")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 16)

                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(combinedLikes.enumerated()), id: \.element.id) { idx, t in
                                        TrackRow(
                                            track: t,
                                            isCurrent: p.current?.url == t.url,
                                            isLiked: true,
                                            onTap: {
                                                p.playQueue(combinedLikes, startIndex: idx)
                                                showNow = true
                                            },
                                            onLike: {
                                                haptic(.light)
                                                p.toggleLike(t)
                                            },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                    Spacer(minLength: 110)
                                }
                            }
                            .refreshable {
                                await p.fetchAccountData()
                            }
                        }
                    } else {
                        if p.accountPlaylists.isEmpty {
                            Spacer()
                            Text("Плейлисты появятся после подключения профиля")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            Spacer()
                        } else {
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 8) {
                                    ForEach(p.accountPlaylists) { pl in
                                        Button {
                                            selectedPlaylist = pl
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: pl.artwork, radius: 10)
                                                    .frame(width: 56, height: 56)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(pl.title)
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Text("\(pl.author) · \(pl.trackCount) тр.")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(10)
                                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .padding(.horizontal, 16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Spacer(minLength: 110)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Медиатека")
            .toolbar {
                if p.currentUser != nil {
                    Button {
                        Task { await p.fetchAccountData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - 4. ACCOUNT TAB
    private var accountTab: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    if let user = p.currentUser {
                        VStack(spacing: 16) {
                            VStack(spacing: 14) {
                                Cover(url: user.avatarUrl, radius: 40)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())

                                VStack(spacing: 4) {
                                    Text(user.username)
                                        .font(.title3.weight(.bold))
                                    Text("SoundCloud подключен")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 32) {
                                    StatView(value: "\(p.accountTracks.count)", label: "Лайки")
                                    StatView(value: "\(p.accountPlaylists.count)", label: "Плейлисты")
                                    StatView(value: "\(user.followersCount ?? 0)", label: "Подписчики")
                                }
                                .padding(.top, 4)
                            }
                            .padding(22)
                            .frame(maxWidth: .infinity)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            )

                            HStack(spacing: 10) {
                                Button {
                                    Task {
                                        await p.fetchAccountData()
                                        await p.loadHome(genre: p.selectedGenre)
                                    }
                                } label: {
                                    Text("Синхронизировать")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.black)
                                }

                                Button(role: .destructive) {
                                    p.logout()
                                } label: {
                                    Text("Выйти")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.red)
                                }
                            }

                            if p.oauthToken == nil {
                                Button {
                                    showWebLogin = true
                                } label: {
                                    HStack {
                                        Text("Войти с паролем (для закрытых плейлистов)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(14)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .padding(16)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("По нику или ссылке")
                                    .font(.headline)
                                Text("Введи свой ник SoundCloud, чтобы загрузить лайки и плейлисты.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    TextField("username или ссылка", text: $profileInput)
                                        .font(.subheadline)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 11)
                                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Button("Готово") {
                                        Task { await p.loginByProfile(input: profileInput) }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(.black)
                                    .disabled(profileInput.trimmingCharacters(in: .whitespaces).isEmpty || p.isLoadingAccount)
                                }
                            }
                            .padding(16)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Через аккаунт SoundCloud")
                                    .font(.headline)
                                Text("Если профиль закрытый или нужен доступ к личным подборкам.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showWebLogin = true
                                } label: {
                                    Text("Войти через SoundCloud")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(16)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            )

                            if p.isLoadingAccount {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(16)
                    }
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Профиль")
        }
    }
}

// MARK: - Reusable Minimalist Components

struct VibePreset: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String

    static let all: [VibePreset] = [
        VibePreset(title: "Phonk", subtitle: "Drift · Memphis · Brazilian"),
        VibePreset(title: "Slowed + Reverb", subtitle: "Atmospheric · Late night"),
        VibePreset(title: "Nightcore", subtitle: "Sped up · High energy"),
        VibePreset(title: "Opium / Dark Trap", subtitle: "Rage · Synth · Underground"),
        VibePreset(title: "Hyperpop", subtitle: "Glitch · Digicore"),
        VibePreset(title: "Russian Rap", subtitle: "Хип-хоп · Андерграунд"),
        VibePreset(title: "Lo-Fi Beats", subtitle: "Chill · Study · Instrumental"),
        VibePreset(title: "Hard Techno", subtitle: "Industrial · Rave · 150 BPM")
    ]
}

struct SectionHeader: View {
    let title: String
    var onPlayAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button(action: onPlayAll) {
                Text("Слушать все")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct FeaturedTrackCard: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Cover(url: track.artwork, radius: 12)
                .frame(width: 140, height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCurrent ? Theme.accent : Theme.border, lineWidth: isCurrent ? 1.5 : 0.5)
                )

            Text(track.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isCurrent ? Theme.accent : .white)
                .lineLimit(1)
            Text(track.artist)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
    }
}

struct CompactTrackCard: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Cover(url: track.artwork, radius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCurrent ? Theme.accent : .white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 180, alignment: .leading)
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PlaylistCard: View {
    let playlist: SCPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Cover(url: playlist.artwork, radius: 12)
                .frame(width: 140, height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
            Text(playlist.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("\(playlist.author) · \(playlist.trackCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isLiked: Bool
    var onTap: () -> Void
    var onLike: () -> Void
    var onRadio: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Cover(url: track.artwork, radius: 8)
                            .frame(width: 48, height: 48)
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 48, height: 48)
                            Image(systemName: "waveform")
                                .foregroundStyle(Theme.accent)
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(isCurrent ? Theme.accent : .white)

                        HStack(spacing: 4) {
                            Text(track.artist)
                                .lineLimit(1)
                            if let dur = track.durationMs, dur > 0 {
                                Text("· \(formatMs(dur))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: onLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.subheadline)
                    .foregroundStyle(isLiked ? Theme.accent : .white.opacity(0.35))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onRadio) {
                    Label("Радио по треку", systemImage: "dot.radiowaves.left.and.right")
                }
                Button(action: onLike) {
                    Label(isLiked ? "Убрать из медиатеки" : "Сохранить", systemImage: isLiked ? "heart.slash" : "heart")
                }
                Button {
                    UIPasteboard.general.string = track.url
                } label: {
                    Label("Скопировать ссылку", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 32)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button(action: onRadio) {
                Label("Радио по треку", systemImage: "dot.radiowaves.left.and.right")
            }
            Button(action: onLike) {
                Label(isLiked ? "Убрать из медиатеки" : "Сохранить", systemImage: isLiked ? "heart.slash" : "heart")
            }
            Button {
                UIPasteboard.general.string = track.url
            } label: {
                Label("Скопировать ссылку", systemImage: "link")
            }
        }
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct StatView: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Cover: View {
    let url: String?
    var radius: CGFloat = 10

    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0.replacingOccurrences(of: "-large", with: "-t500x500")) }) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Theme.surfaceElevated
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Playlist & Artist Detail Sheets

struct PlaylistDetailView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss
    let playlist: SCPlaylist
    var onPlay: ([Track], Int) -> Void
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Cover(url: playlist.artwork, radius: 14)
                            .frame(width: 160, height: 160)
                            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                            .padding(.top, 12)

                        VStack(spacing: 4) {
                            Text(playlist.title)
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.center)
                            Text(playlist.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)

                        if !tracks.isEmpty {
                            HStack(spacing: 10) {
                                Button {
                                    onPlay(tracks, 0)
                                    dismiss()
                                } label: {
                                    Label("Слушать", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.black)
                                }
                                Button {
                                    onPlay(tracks.shuffled(), 0)
                                    dismiss()
                                } label: {
                                    Label("Перемешать", systemImage: "shuffle")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if loading {
                            ProgressView().tint(.secondary).padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                    TrackRow(
                                        track: t,
                                        isCurrent: p.current?.url == t.url,
                                        isLiked: p.isLiked(t),
                                        onTap: {
                                            onPlay(tracks, idx)
                                            dismiss()
                                        },
                                        onLike: { p.toggleLike(t) },
                                        onRadio: {
                                            Task {
                                                await p.startTrackRadio(t)
                                                dismiss()
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                tracks = await p.fetchPlaylistFull(playlist)
                loading = false
            }
        }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss
    let artist: SCUser
    var onPlay: ([Track], Int) -> Void
    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Cover(url: artist.avatarUrl, radius: 52)
                            .frame(width: 104, height: 104)
                            .clipShape(Circle())
                            .padding(.top, 12)

                        VStack(spacing: 4) {
                            Text(artist.username).font(.title3.weight(.bold))
                            Text("\(artist.followersCount ?? 0) подписчиков")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !tracks.isEmpty {
                            Button {
                                onPlay(tracks, 0)
                                dismiss()
                            } label: {
                                Label("Слушать", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(.black)
                            }
                            .padding(.horizontal, 16)
                        }

                        if loading {
                            ProgressView().tint(.secondary).padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, t in
                                    TrackRow(
                                        track: t,
                                        isCurrent: p.current?.url == t.url,
                                        isLiked: p.isLiked(t),
                                        onTap: {
                                            onPlay(tracks, idx)
                                            dismiss()
                                        },
                                        onLike: { p.toggleLike(t) },
                                        onRadio: {
                                            Task {
                                                await p.startTrackRadio(t)
                                                dismiss()
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(artist.username)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                tracks = await p.fetchArtistTracks(userId: artist.id)
                loading = false
            }
        }
    }
}

// MARK: - Minimalist MiniPlayer & Full-Screen NowPlayingView

struct MiniPlayer: View {
    @EnvironmentObject var p: PlayerEngine
    var open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Cover(url: p.current?.artwork, radius: 8)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.current?.title ?? "")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if p.speed != .normal {
                            Text(p.speed.shortLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.14), in: Capsule())
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    Text(p.current?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let t = p.current {
                    Button {
                        haptic(.light)
                        p.toggleLike(t)
                    } label: {
                        Image(systemName: p.isLiked(t) ? "heart.fill" : "heart")
                            .font(.subheadline)
                            .foregroundStyle(p.isLiked(t) ? Theme.accent : .white.opacity(0.7))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    haptic(.light)
                    p.toggle()
                } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            GeometryReader { geo in
                let dur = max(p.duration, Double(p.current?.durationMs ?? 0) / 1000.0)
                let ratio = dur > 0 ? min(max(p.position / dur, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Rectangle().fill(Color.white.opacity(0.85)).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 2)
        }
        .background(Theme.surfaceElevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { val in
                    if val.translation.width < -40 {
                        haptic(.light)
                        p.next()
                    } else if val.translation.width > 40 {
                        haptic(.light)
                        p.previous()
                    } else if val.translation.height < -30 {
                        open()
                    }
                }
        )
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss
    @State private var scrub: Double?
    @State private var isScrubbing = false
    @State private var showQueue = false
    @State private var dragOffset: CGFloat = 0

    private var effectiveDuration: Double {
        if p.duration > 1 { return p.duration }
        if let ms = p.current?.durationMs, ms > 0 { return Double(ms) / 1000.0 }
        return 180
    }

    private var currentPos: Double {
        min(max(scrub ?? p.position, 0), effectiveDuration)
    }

    var body: some View {
        GeometryReader { screen in
            ZStack {
                Theme.bg.ignoresSafeArea()

                // Ambient blurred cover strictly constrained to screen dimensions
                Cover(url: p.current?.artwork, radius: 0)
                    .frame(width: screen.size.width, height: screen.size.height)
                    .blur(radius: 85)
                    .opacity(0.32)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.3), .black.opacity(0.65), Theme.bg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipped()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Grab handle
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    // Minimalist Top Bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            if let mins = p.sleepMinutesRemaining {
                                Text("Таймер · \(mins) мин")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            } else if p.autoRadio {
                                Text("Автоволна")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }

                        Spacer()

                        Menu {
                            Section("Скорость и тон") {
                                ForEach(PlaybackSpeed.allCases) { mode in
                                    Button {
                                        p.speed = mode
                                    } label: {
                                        if p.speed == mode {
                                            Label(mode.label, systemImage: "checkmark")
                                        } else {
                                            Text(mode.label)
                                        }
                                    }
                                }
                                Toggle("Менять тон (Pitch)", isOn: $p.pitchShift)
                            }
                            Section("Воспроизведение") {
                                Toggle("Бесконечная автоволна", isOn: $p.autoRadio)
                            }
                            Section("Таймер сна") {
                                Button("Выключить") { p.setSleepTimer(minutes: nil) }
                                Button("15 минут") { p.setSleepTimer(minutes: 15) }
                                Button("30 минут") { p.setSleepTimer(minutes: 30) }
                                Button("60 минут") { p.setSleepTimer(minutes: 60) }
                            }
                            if let t = p.current {
                                Button {
                                    UIPasteboard.general.string = t.url
                                } label: {
                                    Label("Скопировать ссылку", systemImage: "link")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 16)

                    // Artwork
                    let artSize = min(screen.size.width - 56, screen.size.height * 0.39)
                    Cover(url: p.current?.artwork, radius: 18)
                        .frame(width: artSize, height: artSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
                        .scaleEffect(p.isPlaying ? 1.0 : 0.93)
                        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: p.isPlaying)

                    Spacer(minLength: 22)

                    // Track Info + Heart
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.current?.title ?? "Не выбран трек")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(p.current?.artist ?? "SoundCloud")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        Spacer()

                        if let t = p.current {
                            Button {
                                haptic(.light)
                                p.toggleLike(t)
                            } label: {
                                Image(systemName: p.isLiked(t) ? "heart.fill" : "heart")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(p.isLiked(t) ? Theme.accent : .white.opacity(0.65))
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.07), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)

                    // Tactile Minimalist Progress Bar (Apple Music style)
                    VStack(spacing: 6) {
                        MinimalScrubber(
                            progress: effectiveDuration > 0 ? currentPos / effectiveDuration : 0,
                            isDragging: $isScrubbing,
                            onScrubChange: { ratio in
                                scrub = ratio * effectiveDuration
                            },
                            onScrubEnd: { ratio in
                                let target = ratio * effectiveDuration
                                scrub = target
                                haptic(.light)
                                p.seek(target)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    scrub = nil
                                }
                            }
                        )
                        .frame(height: 28)

                        HStack {
                            Text(fmt(currentPos))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(isScrubbing ? .white : .white.opacity(0.45))

                            Spacer()

                            if p.isLoadingTrack {
                                Text("Загрузка...")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.4))
                            }

                            Spacer()

                            Text("-\(fmt(max(0, effectiveDuration - currentPos)))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(isScrubbing ? .white : .white.opacity(0.45))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                    Spacer(minLength: 18)

                    // Primary Transport Controls
                    HStack(spacing: 0) {
                        Button {
                            haptic(.light)
                            p.shuffle.toggle()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(p.shuffle ? .white : .white.opacity(0.4))
                                Circle()
                                    .fill(p.shuffle ? Theme.accent : .clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(width: 44, height: 44)
                        }

                        Spacer()

                        Button {
                            haptic(.light)
                            p.previous()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                        }

                        Spacer()

                        Button {
                            haptic(.medium)
                            p.toggle()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 66, height: 66)
                                Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.black)
                                    .offset(x: p.isPlaying ? 0 : 2)
                            }
                        }

                        Spacer()

                        Button {
                            haptic(.light)
                            p.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                        }

                        Spacer()

                        Button {
                            haptic(.light)
                            p.cycleRepeat()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(p.repeatMode == .off ? .white.opacity(0.4) : .white)
                                Circle()
                                    .fill(p.repeatMode == .off ? .clear : Theme.accent)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    // Compact Bottom Bar: Speed, Radio, Queue
                    HStack(spacing: 12) {
                        Button {
                            haptic(.light)
                            p.cycleSpeed()
                        } label: {
                            HStack(spacing: 5) {
                                if p.speed != .normal {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 6, height: 6)
                                }
                                Text(p.speed.label)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                p.speed != .normal ? Color.white.opacity(0.14) : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(p.speed != .normal ? .white : .white.opacity(0.65))
                        }

                        Spacer()

                        if let t = p.current {
                            Button {
                                haptic(.light)
                                Task { await p.startTrackRadio(t) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                    Text("Волна")
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.06), in: Capsule())
                                .foregroundStyle(.white.opacity(0.75))
                            }
                        }

                        Button {
                            haptic(.light)
                            showQueue = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "list.bullet")
                                Text("\(p.queue.count)")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.06), in: Capsule())
                            .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
                }
                .frame(width: screen.size.width)
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { val in
                            if !isScrubbing && val.translation.height > 0 && abs(val.translation.height) > abs(val.translation.width) {
                                dragOffset = val.translation.height
                            }
                        }
                        .onEnded { val in
                            if !isScrubbing && val.translation.height > 100 && abs(val.translation.height) > abs(val.translation.width) {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheetView()
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct MinimalScrubber: View {
    let progress: Double
    @Binding var isDragging: Bool
    var onScrubChange: (Double) -> Void
    var onScrubEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = min(max(progress, 0), 1)
            let barHeight: CGFloat = isDragging ? 9 : 4

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: barHeight)

                Capsule()
                    .fill(isDragging ? Color.white : Color.white.opacity(0.88))
                    .frame(width: max(barHeight, width * clamped), height: barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isDragging {
                            isDragging = true
                            haptic(.light)
                        }
                        let r = min(max(val.location.x / width, 0), 1)
                        onScrubChange(r)
                    }
                    .onEnded { val in
                        let r = min(max(val.location.x / width, 0), 1)
                        isDragging = false
                        onScrubEnd(r)
                    }
            )
        }
    }
}

struct QueueSheetView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    ForEach(Array(p.queue.enumerated()), id: \.element.id) { idx, t in
                        Button {
                            p.play(index: idx)
                        } label: {
                            HStack(spacing: 12) {
                                Cover(url: t.artwork, radius: 6)
                                    .frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                        .font(.subheadline.weight(p.currentIndex == idx ? .semibold : .regular))
                                        .foregroundStyle(p.currentIndex == idx ? Theme.accent : .white)
                                        .lineLimit(1)
                                    Text(t.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if p.currentIndex == idx {
                                    Image(systemName: "waveform")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        p.queue.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
