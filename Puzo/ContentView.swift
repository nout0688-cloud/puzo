import SwiftUI

struct ContentView: View {
    @EnvironmentObject var p: PlayerEngine
    @State private var showNow = false
    @State private var showAdd = false
    @State private var showWebLogin = false
    @State private var link = ""
    @State private var query = ""
    @State private var profileInput = ""
    @State private var tab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                libraryTab
                    .tabItem { Label("Медиатека", systemImage: "music.note.list") }
                    .tag(0)

                searchTab
                    .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                    .tag(1)

                accountTab
                    .tabItem { Label("Аккаунт", systemImage: "person.crop.circle") }
                    .tag(2)
            }

            if p.current != nil {
                MiniPlayer { showNow = true }
                    .padding(.bottom, 54)
            }
            HiddenWebView(webView: p.webView).frame(width: 1, height: 1).opacity(0.01)
        }
        .alert("Добавить ссылку", isPresented: $showAdd) {
            TextField("https://soundcloud.com/...", text: $link)
            Button("Добавить") { let l = link; Task { await p.add(link: l) } }
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
        .fullScreenCover(isPresented: $showNow) { NowPlayingView() }
    }

    // MARK: Library Tab
    private var libraryTab: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    ForEach(Array(p.tracks.enumerated()), id: \.element.id) { i, t in
                        Button { p.play(index: i); showNow = true } label: {
                            TrackRow(track: t, isCurrent: p.currentIndex == i)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { p.remove(at: $0) }
                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .overlay {
                    if p.tracks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.orange)
                            Text("Пусто. Найди треки во вкладке «Поиск»,\nвойди в аккаунт или нажми + для ссылки")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Puzo")
            .toolbar {
                Button { link = UIPasteboard.general.string ?? ""; showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: Search Tab
    private var searchTab: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Трек, артист или ссылка SoundCloud...", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await p.search(query: query) } }
                        if !query.isEmpty {
                            Button { query = ""; p.searchResults = [] } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        Button("Найти") {
                            Task { await p.search(query: query) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if p.isSearching {
                        Spacer()
                        ProgressView("Ищем в SoundCloud...")
                        Spacer()
                    } else if p.searchResults.isEmpty {
                        Spacer()
                        Text("Введи название трека или исполнителя\n(работает напрямую без API-ключей)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Spacer()
                    } else {
                        List {
                            ForEach(p.searchResults) { t in
                                HStack(spacing: 12) {
                                    Button {
                                        p.addTrack(t, playImmediately: true)
                                        showNow = true
                                    } label: {
                                        TrackRow(track: t, isCurrent: p.current?.url == t.url)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        p.addTrack(t, playImmediately: false)
                                    } label: {
                                        Image(systemName: p.isSaved(t) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.title3)
                                            .foregroundStyle(p.isSaved(t) ? .orange : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.clear)
                            }
                            Color.clear.frame(height: 80).listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Поиск")
        }
    }

    // MARK: Account Tab
    private var accountTab: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let user = p.currentUser {
                    List {
                        Section {
                            HStack(spacing: 14) {
                                Cover(url: user.avatarUrl).frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.username).font(.headline)
                                    Text(p.oauthToken != nil ? "Сессия SoundCloud активна" : "Публичная синхронизация")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Выйти", role: .destructive) { p.logout() }
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white.opacity(0.06))

                            if !p.accountTracks.isEmpty {
                                Button {
                                    p.importAllAccountTracks()
                                } label: {
                                    Label("Добавить все лайки в медиатеку (\(p.accountTracks.count))", systemImage: "arrow.down.to.line")
                                        .foregroundStyle(.orange)
                                }
                                .listRowBackground(Color.white.opacity(0.06))
                            }
                        }

                        Section("Лайки аккаунта (\(p.accountTracks.count))") {
                            if p.isLoadingAccount {
                                HStack { Spacer(); ProgressView(); Spacer() }
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(p.accountTracks) { t in
                                    HStack(spacing: 12) {
                                        Button {
                                            p.addTrack(t, playImmediately: true)
                                            showNow = true
                                        } label: {
                                            TrackRow(track: t, isCurrent: p.current?.url == t.url)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            p.addTrack(t, playImmediately: false)
                                        } label: {
                                            Image(systemName: p.isSaved(t) ? "checkmark.circle.fill" : "plus.circle")
                                                .font(.title3)
                                                .foregroundStyle(p.isSaved(t) ? .orange : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                        Color.clear.frame(height: 80).listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .refreshable { await p.fetchAccountLikes() }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.orange)
                                .padding(.top, 24)

                            Text("Вход в SoundCloud без API")
                                .font(.title3.bold())

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Способ 1 — Полный вход через WebView")
                                    .font(.subheadline.bold())
                                Text("Авторизуйся на странице SoundCloud — приложение само перехватит сессионный токен и подгрузит твои лайки.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    showWebLogin = true
                                } label: {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Войти через SoundCloud Web")
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            .padding()
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Способ 2 — Быстрый вход по нику / ссылке")
                                    .font(.subheadline.bold())
                                Text("Без пароля: введи свой ник или ссылку на профиль SoundCloud, чтобы синхронизировать лайки.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("username или soundcloud.com/...", text: $profileInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(10)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                    Button("Войти") {
                                        Task { await p.loginByProfile(input: profileInput) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .disabled(profileInput.trimmingCharacters(in: .whitespaces).isEmpty || p.isLoadingAccount)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                            if p.isLoadingAccount {
                                ProgressView("Загружаем профиль...")
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Аккаунт")
        }
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    var body: some View {
        HStack(spacing: 12) {
            Cover(url: track.artwork).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.orange : .white)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct Cover: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0.replacingOccurrences(of: "-large", with: "-t500x500")) }) { img in
            img.resizable().scaledToFill()
        } placeholder: { Color.gray.opacity(0.3) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var p: PlayerEngine
    var open: () -> Void
    var body: some View {
        HStack {
            Cover(url: p.current?.artwork).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.current?.title ?? "").font(.subheadline.bold()).lineLimit(1)
                Text(p.current?.artist ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill") }
                .padding(.horizontal, 6)
            Button { p.next() } label: { Image(systemName: "forward.fill") }
        }
        .font(.title3).padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal).onTapGesture(perform: open)
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var p: PlayerEngine
    @Environment(\.dismiss) var dismiss
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Cover(url: p.current?.artwork).scaledToFill().blur(radius: 60).opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8)
                    .onTapGesture { dismiss() }
                Spacer()
                Cover(url: p.current?.artwork).aspectRatio(1, contentMode: .fit).padding(.horizontal, 30)
                    .shadow(radius: 30)
                VStack(spacing: 4) {
                    Text(p.current?.title ?? "").font(.title3.bold()).lineLimit(2)
                    Text(p.current?.artist ?? "").foregroundStyle(.secondary)
                }.multilineTextAlignment(.center).padding(.horizontal)
                VStack {
                    Slider(value: Binding(get: { scrub ?? p.position }, set: { scrub = $0 }),
                           in: 0...max(p.duration, 1)) { editing in
                        if !editing, let s = scrub { p.seek(s); scrub = nil }
                    }
                    HStack { Text(fmt(scrub ?? p.position)); Spacer(); Text(fmt(p.duration)) }
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 30)
                HStack(spacing: 34) {
                    Button { p.shuffle.toggle() } label: {
                        Image(systemName: "shuffle").foregroundStyle(p.shuffle ? Color.orange : .white)
                    }
                    Button { p.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { p.toggle() } label: {
                        Image(systemName: p.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 72))
                    }
                    Button { p.next() } label: { Image(systemName: "forward.fill").font(.title) }
                    Button { p.cycleRepeat() } label: {
                        Image(systemName: p.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(p.repeatMode == .off ? Color.white : .orange)
                    }
                }.foregroundStyle(.white).font(.title2)
                Spacer()
            }
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s); return String(format: "%d:%02d", t / 60, t % 60)
    }
}
