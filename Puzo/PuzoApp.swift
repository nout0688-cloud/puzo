import SwiftUI

@main
struct PuzoApp: App {
    @StateObject private var player = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}
