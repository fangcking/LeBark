import SwiftUI
import UserNotifications

@main
struct LeBarkApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var sync = SyncManager.shared
    @StateObject private var confirm = CheckConfirm()

    init() {
        CrashLogger.install()
        Notifier.requestAuth()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(confirm)
                .onAppear {
                    sync.attach(store)
                    confirm.attach(store)
                    sync.start()
                }
        }
    }
}
