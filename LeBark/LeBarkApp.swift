import SwiftUI
import UserNotifications

@main
struct LeBarkApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var sync = SyncManager.shared
    @StateObject private var confirm = CheckConfirm()
    @Environment(\.scenePhase) private var scenePhase

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
                // 始终使用浅色模式，不跟随系统深色模式（深色下固定色值会显示错乱）
                .preferredColorScheme(.light)
                .onAppear {
                    sync.attach(store)
                    confirm.attach(store)
                    sync.start()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { store.flush() }
                }
        }
    }
}
