import SwiftUI

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
                    .tabItem { Label("Главная", systemImage: "flame.fill") }
                    .tag(0)

                searchTab
                    .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                    .tag(1)

                likesTab
                    .tabItem { Label("Лайки", systemImage: "heart.fill") }
                    .tag(2)

                accountTab
                    .tabItem { Label("Профиль", systemImage: "person.crop.circle.fill") }
                    .tag(3)
            }

            if p.current != nil {
                MiniPlayer { showNow = true }
                    .padding(.bottom, 54)
            }
            HiddenWebView(webView: p.webView).frame(width: 1, height: 1).opacity(0.01)
        }
        .alert("Вставить ссылку SoundCloud", isPresented: $showAdd) {
            TextField("https://soundcloud.com/...", text: $link)
            Button("Открыть") { let l = link; Task { await p.add(link: l) } }
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
                .navigationTitle("Вход в SoundCloud")
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

    // MARK: - 1. HOME TAB (SoundCloud Discovery & Recommendations)
    private var homeTab: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.05, blue: 0.02), .black, .black],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // My Wave Hero Banner
                        myWaveBanner

                        // Genre Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(p.genres, id: \.self) { g in
                                    Button {
                                        Task { await p.loadHome(genre: g) }
                                    } label: {
                                        Text(g)
                                            .font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                p.selectedGenre == g
                                                    ? AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                                    : AnyShapeStyle(Color.white.opacity(0.08)),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Personalized "For You" Carousel
                        if !p.forYouTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(
                                    title: p.currentUser != nil ? "Для тебя, \(p.currentUser!.username)" : "Рекомендации для тебя",
                                    subtitle: "Подобрано на основе твоих лайков и вайба"
                                ) {
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
                                                FeaturedTrackCard(track: t, isPlaying: p.current?.url == t.url && p.isPlaying)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Recently Played
                        if !p.recentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Недавно слушал", subtitle: "Продолжи с того же места") {
                                    p.playQueue(p.recentTracks, startIndex: 0)
                                    showNow = true
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
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
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Featured Mixes & Playlists
                        if !p.featuredPlaylists.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Плейлисты и миксы • \(p.selectedGenre)")
                                    .font(.title3.bold())
                                    .padding(.horizontal)

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
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // More Like Your Likes
                        if !p.relatedToRecentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Похожее на твои треки", subtitle: "Свежие находки SoundCloud") {
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
                                                FeaturedTrackCard(track: t, isPlaying: p.current?.url == t.url && p.isPlaying)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Trending Tracks List
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "В тренде • \(p.selectedGenre)", subtitle: "Полные версии популярных треков") {
                                p.playQueue(p.trendingTracks, startIndex: 0)
                                showNow = true
                            }

                            if p.isLoadingHome && p.trendingTracks.isEmpty {
                                HStack { Spacer(); ProgressView("Загружаем тренды..."); Spacer() }
                                    .padding(.vertical, 30)
                            } else {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(p.trendingTracks.prefix(25).enumerated()), id: \.element.id) { idx, t in
                                        TrackRow(
                                            track: t,
                                            isCurrent: p.current?.url == t.url,
                                            isLiked: p.isLiked(t),
                                            onTap: {
                                                p.playQueue(p.trendingTracks, startIndex: idx)
                                                showNow = true
                                            },
                                            onLike: { p.toggleLike(t) },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
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
                    HStack(spacing: 12) {
                        if p.speed != .normal {
                            Text(p.speed.shortLabel)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange, in: Capsule())
                        }
                        Button {
                            link = UIPasteboard.general.string ?? ""
                            showAdd = true
                        } label: {
                            Image(systemName: "link.badge.plus")
                        }
                    }
                }
            }
        }
    }

    private var myWaveBanner: some View {
        Button {
            p.startMyWave()
            showNow = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.35, blue: 0.0),
                        Color(red: 0.85, green: 0.1, blue: 0.35),
                        Color(red: 0.25, green: 0.05, blue: 0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 155)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.title2.bold())
                            Text("МОЯ ВОЛНА")
                                .font(.caption.weight(.heavy))
                                .tracking(1.5)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Spacer()
                        Text(p.currentUser != nil ? "Поток для \(p.currentUser!.username)" : "Бесконечный поток")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Твои лайки + похожие бэнгеры без 30-сек превью")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 58, height: 58)
                            .shadow(color: .black.opacity(0.3), radius: 10)
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.black)
                            .offset(x: 2)
                    }
                }
                .padding(20)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. SEARCH TAB (Tracks, Playlists, Artists + Trending Tags)
    private var searchTab: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.orange)
                        TextField("Трек, артист, плейлист или ссылка...", text: $query)
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
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        Button("Найти") {
                            Task { await p.search(query: query) }
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.orange, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    // Scope Picker
                    Picker("Тип", selection: $searchScope) {
                        Text("Треки (\(p.searchResults.count))").tag(0)
                        Text("Плейлисты (\(p.searchPlaylists.count))").tag(1)
                        Text("Артисты (\(p.searchUsers.count))").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if p.isSearching {
                        Spacer()
                        ProgressView("Ищем в SoundCloud...")
                        Spacer()
                    } else if query.isEmpty && p.searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Быстрый поиск по вайбу")
                                    .font(.headline)
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(VibePreset.all) { item in
                                        Button {
                                            query = item.title
                                            Task { await p.search(query: item.title) }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: item.icon)
                                                    .foregroundStyle(item.color)
                                                Text(item.title)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Spacer()
                                            }
                                            .padding(14)
                                            .background(item.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(item.color.opacity(0.35), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
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
                                            onLike: { p.toggleLike(t) },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                } else if searchScope == 1 {
                                    ForEach(p.searchPlaylists) { pl in
                                        Button {
                                            selectedPlaylist = pl
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: pl.artwork).frame(width: 60, height: 60)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(pl.title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                                    Text(pl.author).font(.caption).foregroundStyle(.secondary)
                                                    Text("\(pl.trackCount) треков").font(.caption2).foregroundStyle(.orange)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    ForEach(p.searchUsers) { u in
                                        Button {
                                            selectedArtist = u
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: u.avatarUrl)
                                                    .frame(width: 56, height: 56)
                                                    .clipShape(Circle())
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(u.username).font(.subheadline.bold()).foregroundStyle(.white)
                                                    Text("\(u.followersCount ?? 0) подписчиков • \(u.trackCount ?? 0) треков")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 4)
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

    // MARK: - 3. LIKES & PLAYLISTS TAB (Synced with Account + Local Favorites)
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
                Color.black.ignoresSafeArea()
                VStack(spacing: 10) {
                    Picker("Раздел", selection: $likesScope) {
                        Text("Лайки (\(combinedLikes.count))").tag(0)
                        Text("Плейлисты (\(p.accountPlaylists.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if likesScope == 0 {
                        if combinedLikes.isEmpty && likesFilter.isEmpty {
                            Spacer()
                            VStack(spacing: 14) {
                                Image(systemName: "heart.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.orange)
                                Text("Твои лайки появятся здесь")
                                    .font(.title3.bold())
                                Text("Войди в аккаунт во вкладке «Профиль», чтобы подтянуть все лайки из SoundCloud, или нажимай сердечко на любых треках.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                                if p.currentUser == nil {
                                    Button("Перейти к входу в аккаунт") { tab = 3 }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                }
                            }
                            Spacer()
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Поиск среди лайков...", text: $likesFilter)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                if !likesFilter.isEmpty {
                                    Button { likesFilter = "" } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)

                            HStack(spacing: 12) {
                                Button {
                                    p.shuffle = false
                                    p.playQueue(combinedLikes, startIndex: 0)
                                    showNow = true
                                } label: {
                                    Label("Слушать все", systemImage: "play.fill")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.black)
                                }

                                Button {
                                    p.shuffle = true
                                    p.playQueue(combinedLikes.shuffled(), startIndex: 0)
                                    showNow = true
                                } label: {
                                    Label("Перемешать", systemImage: "shuffle")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal)

                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(combinedLikes.enumerated()), id: \.element.id) { idx, t in
                                        TrackRow(
                                            track: t,
                                            isCurrent: p.current?.url == t.url,
                                            isLiked: true,
                                            onTap: {
                                                p.playQueue(combinedLikes, startIndex: idx)
                                                showNow = true
                                            },
                                            onLike: { p.toggleLike(t) },
                                            onRadio: {
                                                Task {
                                                    await p.startTrackRadio(t)
                                                    showNow = true
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
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
                            Text("Плейлисты аккаунта не найдены.\nВойди в аккаунт или ищи плейлисты во вкладке «Поиск».")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(p.accountPlaylists) { pl in
                                        Button {
                                            selectedPlaylist = pl
                                        } label: {
                                            HStack(spacing: 12) {
                                                Cover(url: pl.artwork).frame(width: 64, height: 64)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(pl.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                                                    Text(pl.author).font(.caption).foregroundStyle(.secondary)
                                                    Text("\(pl.trackCount) треков").font(.caption2).foregroundStyle(.orange)
                                                }
                                                Spacer()
                                                Image(systemName: "play.circle.fill")
                                                    .font(.title2)
                                                    .foregroundStyle(.orange)
                                            }
                                            .padding(12)
                                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                                            .padding(.horizontal)
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
            .navigationTitle("Моя коллекция")
            .toolbar {
                if p.currentUser != nil {
                    Button {
                        Task { await p.fetchAccountData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - 4. ACCOUNT TAB
    private var accountTab: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    if let user = p.currentUser {
                        VStack(spacing: 18) {
                            // Profile Header Card
                            VStack(spacing: 12) {
                                Cover(url: user.avatarUrl)
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.orange, lineWidth: 2))

                                Text(user.username)
                                    .font(.title2.bold())

                                Text(p.oauthToken != nil ? "OAuth-сессия SoundCloud активна" : "Синхронизация по профилю SoundCloud")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.orange)

                                HStack(spacing: 28) {
                                    StatView(value: "\(p.accountTracks.count)", label: "Лайков")
                                    StatView(value: "\(p.accountPlaylists.count)", label: "Плейлистов")
                                    StatView(value: "\(user.followersCount ?? 0)", label: "Подписчиков")
                                }
                                .padding(.top, 4)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))

                            HStack(spacing: 12) {
                                Button {
                                    Task {
                                        await p.fetchAccountData()
                                        await p.loadHome(genre: p.selectedGenre)
                                    }
                                } label: {
                                    Label("Обновить данные", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.black)
                                }

                                Button(role: .destructive) {
                                    p.logout()
                                } label: {
                                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                        .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.red)
                                }
                            }

                            if p.oauthToken == nil {
                                Button {
                                    showWebLogin = true
                                } label: {
                                    HStack {
                                        Image(systemName: "key.fill")
                                        Text("Войти через браузер для приватных треков")
                                    }
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding()
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "waveform.badge.person.crop")
                                .font(.system(size: 56))
                                .foregroundStyle(.orange)
                                .padding(.top, 20)

                            Text("Подключи свой SoundCloud")
                                .font(.title2.bold())

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Быстрый вход по нику или ссылке")
                                    .font(.headline)
                                Text("Просто введи свой ник или ссылку на профиль SoundCloud — мы сразу загрузим твои лайки, плейлисты и настроим персональную «Мою волну».")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    TextField("username или soundcloud.com/...", text: $profileInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(12)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                                    Button("Войти") {
                                        Task { await p.loginByProfile(input: profileInput) }
                                    }
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.black)
                                    .disabled(profileInput.trimmingCharacters(in: .whitespaces).isEmpty || p.isLoadingAccount)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Полный вход через SoundCloud Web")
                                    .font(.headline)
                                Text("Авторизуйся в официальном окне SoundCloud — приложение автоматически перехватит OAuth-токен без API ключей.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    showWebLogin = true
                                } label: {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Открыть вход SoundCloud")
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                            if p.isLoadingAccount {
                                ProgressView("Синхронизация аккаунта...")
                            }
                        }
                        .padding()
                    }
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Профиль")
        }
    }
}

// MARK: - Reusable Cards & Rows

struct VibePreset: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let color: Color

    static let all: [VibePreset] = [
        VibePreset(title: "Brazilian Phonk", icon: "bolt.fill", color: .orange),
        VibePreset(title: "Slowed + Reverb", icon: "moon.stars.fill", color: .purple),
        VibePreset(title: "Nightcore / Sped Up", icon: "sparkles", color: .pink),
        VibePreset(title: "Dark Trap / Opium", icon: "flame.fill", color: .red),
        VibePreset(title: "Hyperpop / Glitch", icon: "waveform.path.ecg", color: .cyan),
        VibePreset(title: "Russian Rap", icon: "headphones", color: .blue),
        VibePreset(title: "Lo-Fi Chill", icon: "cup.and.saucer.fill", color: .mint),
        VibePreset(title: "Hard Techno / Rave", icon: "speaker.wave.3.fill", color: .yellow)
    ]
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    var onPlayAll: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onPlayAll) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text("Все")
                }
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }
}

struct FeaturedTrackCard: View {
    let track: Track
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Cover(url: track.artwork)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                ZStack {
                    Circle().fill(Color.orange).frame(width: 34, height: 34)
                    Image(systemName: isPlaying ? "waveform" : "play.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                }
                .padding(8)
            }
            Text(track.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150)
    }
}

struct CompactTrackCard: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Cover(url: track.artwork).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption.bold())
                    .foregroundStyle(isCurrent ? .orange : .white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 185, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PlaylistCard: View {
    let playlist: SCPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Cover(url: playlist.artwork)
                    .frame(width: 145, height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text("\(playlist.trackCount) тр.")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
            Text(playlist.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(playlist.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 145)
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
                        Cover(url: track.artwork).frame(width: 54, height: 54)
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.45))
                                .frame(width: 54, height: 54)
                            Image(systemName: "waveform")
                                .foregroundStyle(.orange)
                                .font(.title3.bold())
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(isCurrent ? Color.orange : .white)

                        HStack(spacing: 6) {
                            Text(track.artist)
                                .lineLimit(1)
                            if let dur = track.durationMs, dur > 0 {
                                Text("• \(formatMs(dur))")
                            }
                            if let plays = track.playbackCount, plays > 0 {
                                Text("• ▶ \(formatCount(plays))")
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
                    .foregroundStyle(isLiked ? .orange : .secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onRadio) {
                    Label("Запустить радио по треку", systemImage: "dot.radiowaves.left.and.right")
                }
                Button(action: onLike) {
                    Label(isLiked ? "Убрать из лайков" : "В лайки", systemImage: isLiked ? "heart.slash" : "heart")
                }
                Button {
                    UIPasteboard.general.string = track.url
                } label: {
                    Label("Скопировать ссылку", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct StatView: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Cover: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0.replacingOccurrences(of: "-large", with: "-t500x500")) }) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.white.opacity(0.08)
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Cover(url: playlist.artwork)
                            .frame(width: 170, height: 170)
                            .shadow(radius: 20)
                            .padding(.top, 12)

                        VStack(spacing: 4) {
                            Text(playlist.title).font(.title3.bold()).multilineTextAlignment(.center)
                            Text(playlist.author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        if !tracks.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    onPlay(tracks, 0)
                                    dismiss()
                                } label: {
                                    Label("Слушать", systemImage: "play.fill")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.black)
                                }
                                Button {
                                    onPlay(tracks.shuffled(), 0)
                                    dismiss()
                                } label: {
                                    Label("Перемешать", systemImage: "shuffle")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if loading {
                            ProgressView("Загружаем треки плейлиста...")
                                .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 6) {
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
                                    .padding(.horizontal)
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
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Cover(url: artist.avatarUrl)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.orange, lineWidth: 2))
                            .padding(.top, 12)

                        Text(artist.username).font(.title2.bold())
                        Text("\(artist.followersCount ?? 0) подписчиков")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !tracks.isEmpty {
                            Button {
                                onPlay(tracks, 0)
                                dismiss()
                            } label: {
                                Label("Слушать популярные треки", systemImage: "play.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.black)
                            }
                            .padding(.horizontal)
                        }

                        if loading {
                            ProgressView("Загружаем треки артиста...")
                                .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 6) {
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
                                    .padding(.horizontal)
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

// MARK: - MiniPlayer & Full-Screen NowPlayingView

struct MiniPlayer: View {
    @EnvironmentObject var p: PlayerEngine
    var open: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Cover(url: p.current?.artwork).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.current?.title ?? "")
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if p.speed != .normal {
                            Text(p.speed.shortLabel)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                                .foregroundStyle(.black)
                        }
                    }
                    Text(p.current?.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let t = p.current {
                    Button { p.toggleLike(t) } label: {
                        Image(systemName: p.isLiked(t) ? "heart.fill" : "heart")
                            .foregroundStyle(p.isLiked(t) ? .orange : .white)
                    }
                    .padding(.horizontal, 4)
                }
                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                }
                .padding(.horizontal, 6)
                Button { p.next() } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .font(.title3)
            .padding(10)

            GeometryReader { geo in
                let ratio = p.duration > 0 ? min(max(p.position / p.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.1))
                    Rectangle().fill(Color.orange).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 2)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 10)
        .onTapGesture(perform: open)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss
    @State private var scrub: Double?
    @State private var showQueue = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Cover(url: p.current?.artwork)
                .scaledToFill()
                .blur(radius: 75)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                // Top Bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.bold())
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(p.autoRadio ? "АВТОВОЛНА ВКЛ" : "СЕЙЧАС ИГРАЕТ")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.orange)
                        if let mins = p.sleepMinutesRemaining {
                            Text("Сон через \(mins) мин")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Menu {
                        Section("Таймер сна") {
                            Button("Выключить таймер") { p.setSleepTimer(minutes: nil) }
                            Button("Через 15 минут") { p.setSleepTimer(minutes: 15) }
                            Button("Через 30 минут") { p.setSleepTimer(minutes: 30) }
                            Button("Через 60 минут") { p.setSleepTimer(minutes: 60) }
                        }
                        Section("Режим волны") {
                            Toggle("Бесконечная автоволна", isOn: $p.autoRadio)
                            Toggle("Изменять тон (Pitch) со скоростью", isOn: $p.pitchShift)
                        }
                        if let t = p.current {
                            Button {
                                UIPasteboard.general.string = t.url
                            } label: {
                                Label("Скопировать ссылку", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.bold())
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()

                // Animated Album Artwork
                Cover(url: p.current?.artwork)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                    .scaleEffect(p.isPlaying ? 1.0 : 0.88)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: p.isPlaying)
                    .padding(.horizontal, 32)

                // Title & Like Row
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.current?.title ?? "")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(p.current?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let t = p.current {
                        Button { p.toggleLike(t) } label: {
                            Image(systemName: p.isLiked(t) ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(p.isLiked(t) ? .orange : .white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 28)

                // Vibe Speed Selector (Slowed / Normal / Nightcore)
                HStack(spacing: 8) {
                    ForEach(PlaybackSpeed.allCases) { mode in
                        Button {
                            p.speed = mode
                        } label: {
                            Text(mode.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    p.speed == mode ? Color.orange : Color.white.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(p.speed == mode ? .black : .white)
                        }
                    }
                }

                // Scrubber
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { scrub ?? p.position }, set: { scrub = $0 }),
                        in: 0...max(p.duration, 1)
                    ) { editing in
                        if !editing, let s = scrub { p.seek(s); scrub = nil }
                    }
                    .tint(.orange)

                    HStack {
                        Text(fmt(scrub ?? p.position))
                        Spacer()
                        Text(fmt(p.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)

                // Main Transport Controls
                HStack(spacing: 32) {
                    Button { p.shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(p.shuffle ? Color.orange : .white.opacity(0.7))
                    }
                    Button { p.previous() } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    Button { p.toggle() } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 74, height: 74)
                                .shadow(color: .orange.opacity(0.45), radius: 14)
                            Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title.bold())
                                .foregroundStyle(.black)
                        }
                    }
                    Button { p.next() } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                    Button { p.cycleRepeat() } label: {
                        Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(p.repeatMode == .off ? Color.white.opacity(0.7) : .orange)
                    }
                }
                .foregroundStyle(.white)
                .font(.title3)

                // Bottom Utility Bar (Track Radio & Queue)
                HStack(spacing: 20) {
                    if let t = p.current {
                        Button {
                            Task { await p.startTrackRadio(t) }
                        } label: {
                            Label("Похожие (Волна)", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }

                    Button {
                        showQueue = true
                    } label: {
                        Label("Очередь (\(p.queue.count))", systemImage: "list.bullet")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.bottom, 12)
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

struct QueueSheetView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    ForEach(Array(p.queue.enumerated()), id: \.element.id) { idx, t in
                        Button {
                            p.play(index: idx)
                        } label: {
                            HStack(spacing: 12) {
                                Cover(url: t.artwork).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(p.currentIndex == idx ? .orange : .white)
                                        .lineLimit(1)
                                    Text(t.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if p.currentIndex == idx {
                                    Image(systemName: "waveform").foregroundStyle(.orange)
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
            .navigationTitle("Очередь (\(p.queue.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
