import Foundation

// MARK: - 读取 BARK 历史消息（巨魔环境，按分组过滤）

/// BARK 存储机制（来自官方源码 Finb/Bark）：
/// - App Group `group.bark` 下有 `recent_messages_snapshot.json`（最近 100 条消息快照）
/// - 每条消息字段：title / body / group / createDate
/// - 快照是纯 JSON，带 group 字段，能可靠地按「乐币」分组过滤
///
/// 策略：读取快照 → 按分组名过滤 → 解析成结账名单 → 存进我们自己的 App（UserDefaults）。
/// 我们自己的库会持续累积，不受 BARK 快照只保留 100 条的限制。
enum BarkReader {

    struct BarkMessage {
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

    /// 读取快照原文（不过滤），返回消息 + 全部可用分组
    private static func loadSnapshot() -> (messages: [BarkMessage], groups: [String])? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }

        let url = groupURL.appendingPathComponent(snapshotName)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["messages"] as? [[String: Any]] else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [BarkMessage] = []
        var groups: [String] = []
        for item in arr {
            var m = BarkMessage()
            m.title = item["title"] as? String
            m.body = item["body"] as? String
            m.group = item["group"] as? String
            if let g = m.group, !g.isEmpty, !groups.contains(g) { groups.append(g) }
            if let s = item["createDate"] as? String {
                m.createDate = try? decoder.decode(Date.self, from: Data("\"\(s)\"".utf8))
            }
            out.append(m)
        }
        return (out, groups)
    }

    /// 只读取指定分组的消息
    static func readAll(group: String) -> ReadResult {
        var result = ReadResult()
        guard let snap = loadSnapshot() else {
            result.error = "没读到 BARK 快照。请确认：1) BARK 已安装且有历史消息；2) 本 App 用巨魔带 App Group 权限安装；3) BARK 版本支持小组件快照。"
            return result
        }

        result.availableGroups = snap.groups
        let target = group.trimmingCharacters(in: .whitespaces)
        let matched = snap.messages.filter { m in
            guard let g = m.group else { return false }
            return g.trimmingCharacters(in: .whitespaces) == target
        }

        if matched.isEmpty {
            let list = snap.groups.isEmpty ? "（快照里没有分组信息）" : snap.groups.joined(separator: "、")
            result.error = "快照里没有「\(target)」分组的消息。现有分组：\(list)。可在设置里改分组名。"
            return result
        }

        result.messages = matched
        result.source = "BARK 快照 · \(target) 分组（\(matched.count) 条）"
        return result
    }
}

// MARK: - 把 BARK 消息导入到账本（只导入汇总类）

extension LedgerStore {
    /// 从 BARK 历史批量导入：只收「今日汇总」类消息，解析出结账名单，存进本 App
    @discardableResult
    func importBarkMessages(_ messages: [BarkReader.BarkMessage]) -> IngestResult {
        var total = IngestResult()
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
            if !r.parsedServer.isEmpty { total.parsedServer = r.parsedServer }
        }
        return total
    }
}
