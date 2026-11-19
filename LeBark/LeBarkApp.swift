import SwiftUI
import UserNotifications

@main
struct LeBarkApp: App {
    @StateObject private var store = LedgerStore()
    @StateObject private var server = PushHTTPServer()

    init() {
        Notifier.requestAuth()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(server)
                .onAppear {
                    SilenceKeeper.shared.start()
                    if store.autoStartServer {
                        server.start(port: store.serverPort)
                    }
                    server.onPush = { title, body in
                        let result = store.ingest(title: title, body: body)
                        if store.notifyOnPush {
                            let n = result.personsAdded + result.abnormalsAdded
                            Notifier.push(title: title.isEmpty ? "乐币BARK · \(result.parsedServer)" : title,
                                          body: n > 0 ? "新增 \(result.personsAdded) 人结账名单，异常 \(result.abnormalsAdded) 条" : "收到推送，无新增名单")
                        }
                    }
                }
        }
    }
}
