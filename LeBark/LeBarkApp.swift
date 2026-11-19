import SwiftUI
import UserNotifications

@main
struct LeBarkApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var sync = SyncManager.shared
    @StateObject private var confirm = CheckConfirm()

    init() {
        Notifier.requestAuth()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(confirm)
                .checkConfirm(confirm)
                .onAppear {
                    sync.attach(store)
                    sync.start()
                }
        }
    }
}
