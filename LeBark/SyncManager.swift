import Foundation
import SwiftUI
import UIKit

/// 统一的 BARK 拉取调度：进入 App 拉取一次，之后每 60 秒自动拉取一次。
/// 数据存进我们自己的 LedgerStore（本地持久化），不依赖 BARK 快照的 100 条限制。
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var syncing = false
    @Published var lastSyncAt: Date? = nil
    @Published var lastDetail: String = ""
    @Published var lastError: String = ""

    private var timer: Timer?
    private weak var store: LedgerStore?
    private var running = false

    private init() {}

    func attach(_ store: LedgerStore) {
        self.store = store
    }

    /// 进入 App 调用：立即拉一次 + 启动每分钟定时
    func start() {
        guard !running else { return }
        running = true
        sync()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sync()
        }
        // 进后台/回前台也各拉一次，避免定时在挂起期间错过
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
    }

    func syncNow() { sync() }

    private func sync() {
        guard let store = store, !syncing else { return }
        let group = store.barkGroup
        syncing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = BarkReader.readAll(group: group)
            DispatchQueue.main.async {
                guard let store = self.store else { self.syncing = false; return }
                self.syncing = false
                if let err = r.error {
                    self.lastError = err
                    self.lastDetail = "拉取失败：\(err)"
                    return
                }
                self.lastError = ""
                let imp = store.importBarkMessages(r.messages)
                store.lastSyncAt = Date()
                let warn = imp.hasMismatch ? " ⚠️\(imp.parsedPersons)/\(imp.expectedAccounts)人" : ""
                self.lastDetail = "\(r.source) → 名单 +\(imp.personsAdded)，更新 \(imp.personsUpdated)\(warn)"
                store.lastSyncDetail = self.lastDetail
                // 有新增时发一条本地通知（轻量提示，不依赖 APNs）
                if imp.personsAdded > 0 {
                    Notifier.push(title: "乐币BARK 已更新",
                                  body: "新增 \(imp.personsAdded) 人\(warn)")
                }
            }
        }
    }
}
