import SwiftUI

struct ContentView: View {
    @EnvironmentObject var p: PlayerEngine
    @State private var showNow = false
    @State private var showAdd = false
    @State private var link = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                List {
                    ForEach(Array(p.tracks.enumerated()), id: \.element.id) { i, t in
                        Button { p.play(index: i); showNow = true } label: {
                            HStack(spacing: 12) {
                                Cover(url: t.artwork).frame(width: 52, height: 52)
                                VStack(alignment: .leading) {
                                    Text(t.title).lineLimit(1)
                                        .foregroundStyle(p.currentIndex == i ? Color.orange : .white)
                                    Text(t.artist).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { p.remove(at: $0) }
                    Color.clear.frame(height: 70).listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .overlay {
                    if p.tracks.isEmpty {
                        Text("Нажми + и вставь ссылку на трек SoundCloud")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }
                }
                if p.current != nil { MiniPlayer { showNow = true } }
                HiddenWebView(webView: p.webView).frame(width: 1, height: 1).opacity(0.01)
            }
            .navigationTitle("Puzo")
            .toolbar {
                Button { link = UIPasteboard.general.string ?? ""; showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
            .alert("Добавить ссылку", isPresented: $showAdd) {
                TextField("https://soundcloud.com/...", text: $link)
                Button("Добавить") { let l = link; Task { await p.add(link: l) } }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Ошибка", isPresented: .constant(p.errorText != nil)) {
                Button("OK") { p.errorText = nil }
            } message: { Text(p.errorText ?? "") }
            .fullScreenCover(isPresented: $showNow) { NowPlayingView() }
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
            Text(p.current?.title ?? "").lineLimit(1)
            Spacer()
            Button { p.toggle() } label: { Image(systemName: p.isPlaying ? "pause.fill" : "play.fill") }
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
