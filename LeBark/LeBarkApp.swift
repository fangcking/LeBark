import SwiftUI
import UserNotifications

@main
struct LeBarkApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var sync = SyncManager.shared

    init() {
        Notifier.requestAuth()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(sync)
                .onAppear {
                    sync.attach(store)
                    sync.start()
                }
        }
    }
}
