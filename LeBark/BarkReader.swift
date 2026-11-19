import Foundation

// MARK: - 读取 BARK 历史消息（巨魔环境，按分组过滤）
//
// BARK 存储机制（来自官方源码 Finb/Bark，已核对 master 分支）：
//   小组件快照：App Group group.bark 下 recent_messages_snapshot.json
//   每条含 title / body / group / createDate，字段规整，可精确按分组过滤。
//
// 为什么不用 RealmSwift 读完整历史：
//   RealmSwift 静态库在本 App 的 TrollStore 伪签名（ldid）环境下会在启动阶段崩溃（闪退）。
//   且从 Realm 二进制里无法可靠还原 group 与 createDate（二进制时间戳），
//   强行提取会把历史消息日期归错。因此改为纯 Foundation 读快照，零第三方依赖。
//
// 数据完整性靠「自动同步 + 本地持久累积」保障：
//   SyncManager 每 60 秒拉一次，快照里最近 100 条会不断被拉进我们自己的库并永久保存，
//   不受快照滚动覆盖影响。 installs 越久，本地历史越全。

enum BarkReader {

    struct BarkMessage {
        var id: String = UUID().uuidString
        var title: String?
        var body: String?
        var group: String?
        var createDate: Date?
    }

    struct ReadResult {
        var messages: [BarkMessage] = []
        var availableGroups: [String] = []
        var source: String = ""
        var error: String?
    }

    private static let appGroup = "group.bark"
    private static let snapshotName = "recent_messages_snapshot.json"

    /// 对外入口：读 BARK 快照，按分组过滤
    static func readAll(group: String) -> ReadResult {
        readSnapshot(group: group)
    }

    private static func readSnapshot(group: String) -> ReadResult {
        var result = ReadResult()
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            result.error = "读不到 BARK 快照容器。请确认本 App 用巨魔带 App Group 权限安装。"
            return result
        }
        let url = groupURL.appendingPathComponent(snapshotName)
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = obj["messages"] as? [[String: Any]] else {
            result.error = "没读到 BARK 快照。请确认 BARK 已安装且有历史消息，本 App 用巨魔带 App Group 权限安装。"
            return result
        }

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var out: [BarkMessage] = []
        for item in arr {
            var m = BarkMessage()
            m.title = item["title"] as? String
            m.body = item["body"] as? String
            m.group = item["group"] as? String
            if let g = m.group, !g.isEmpty, !result.availableGroups.contains(g) { result.availableGroups.append(g) }
            if let s = item["createDate"] as? String {
                m.createDate = try? decoder.decode(Date.self, from: Data("\"\(s)\"".utf8))
            }
            out.append(m)
        }

        let target = group.trimmingCharacters(in: .whitespaces)
        let matched = out.filter { m in
            guard let g = m.group else { return false }
            return g.trimmingCharacters(in: .whitespaces) == target && (m.title ?? "").contains("汇总")
        }.sorted { ($0.createDate ?? .distantPast) < ($1.createDate ?? .distantPast) }

        if matched.isEmpty {
            let list = result.availableGroups.isEmpty ? "（快照里没有分组信息）" : result.availableGroups.joined(separator: "、")
            result.error = "快照里没有「\(target)」分组的汇总消息。现有分组：\(list)。可在设置里改分组名。"
            return result
        }
        result.messages = matched
        result.source = "BARK 快照 · \(target) 分组（\(matched.count) 条）"
        return result
    }
}

// MARK: - 把 BARK 消息导入到账本

extension LedgerStore {
    @discardableResult
    func importBarkMessages(_ messages: [BarkReader.BarkMessage]) -> IngestResult {
        var total = IngestResult()
        var mismatchCount = 0
        for m in messages {
            guard let title = m.title, title.contains("汇总") else { continue }
            let body = m.body ?? ""
            let dateKey: String
            if let d = m.createDate {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                dateKey = f.string(from: d)
            } else {
                dateKey = PushParser.todayKey()
            }
            let r = ingest(title: title, body: body, dateKey: dateKey)
            total.personsAdded += r.personsAdded
            total.personsUpdated += r.personsUpdated
            total.abnormalsAdded += r.abnormalsAdded
            total.summaryUpdated = total.summaryUpdated || r.summaryUpdated
            total.expectedAccounts += r.expectedAccounts
            total.parsedPersons += r.parsedPersons
            if r.hasMismatch { mismatchCount += 1 }
            if !r.parsedServer.isEmpty { total.parsedServer = r.parsedServer }
        }
        total.hasMismatch = mismatchCount > 0
        return total
    }
}
