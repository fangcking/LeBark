import Foundation
import RealmSwift

// MARK: - 读取 BARK 历史消息（巨魔环境，按分组过滤）
//
// BARK 存储机制（来自官方源码 Finb/Bark，已核对 master 分支）：
// 1) 完整历史：BARK 主 App 沙盒 Documents/bark.realm（Realm，schemaVersion 19，未加密）
//    每条 Message 字段：id / title / body / group / createDate / expireDate
// 2) 小组件快照：App Group group.bark 下 recent_messages_snapshot.json
//    仅最近 100 条，且 body 被截断到 500 字符 → 这就是「只能拉到 2 天」的根因
//
// 策略：优先读完整 Realm（全历史，不截断）→ 按 group 过滤 → 解析入库；
//       Realm 读取失败时回退到快照。我们自己的库持续累积，不受两者条数限制。

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
    private static let barkBundleID = "me.fin.bark"

    // MARK: 对外入口：先 Realm，失败回退快照

    static func readAll(group: String) -> ReadResult {
        let realmResult = readRealm(group: group)
        if realmResult.error == nil, !realmResult.messages.isEmpty {
            return realmResult
        }
        let snapResult = readSnapshot(group: group, fallbackGroups: realmResult.availableGroups)
        if !snapResult.messages.isEmpty { return snapResult }
        // 两路都没数据：给出更完整的错误说明
        var r = realmResult
        if let se = snapResult.error { r.error = se }
        else if r.error == nil { r.error = "没有读到「\(group)」分组的消息。" }
        return r
    }

    // MARK: 路径 A —— 完整 Realm

    /// 与 BARK 的 Message 表结构保持一致（只读打开，不写）
    private class BarkRealmMessage: Object {
        @Persisted(primaryKey: true) var id: String = ""
        @Persisted var title: String?
        @Persisted var subtitle: String?
        @Persisted var body: String?
        @Persisted var bodyType: String?
        @Persisted var url: String?
        @Persisted var image: String?
        @Persisted var group: String?
        @Persisted var createDate: Date?
        @Persisted var expireDate: Date?
        override static func primaryKey() -> String? { "id" }
    }

    /// 找到 BARK 容器里的 bark.realm 路径（脱沙盒后扫描 /var/mobile/Containers/Data/Application）
    private static func findBarkRealmURL() -> URL? {
        let fm = FileManager.default
        // 先试公共容器根目录下所有 App 容器
        var roots = ["/var/mobile/Containers/Data/Application"]
        // 同级容器目录（NSHomeDirectory 的上一级）
        let homeParent = (NSHomeDirectory() as NSString).deletingLastPathComponent
        if !roots.contains(homeParent) { roots.append(homeParent) }
        for root in roots {
            guard let dirs = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for d in dirs {
                let docs = "\(root)/\(d)/Documents/bark.realm"
                if fm.fileExists(atPath: docs) { return URL(fileURLWithPath: docs) }
                let groupOld = "\(root)/\(d)/Library/Application Support/bark.realm"
                if fm.fileExists(atPath: groupOld) { return URL(fileURLWithPath: groupOld) }
            }
        }
        // App Group 旧路径（老版本 BARK 曾把库放这里）
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            let old = g.appendingPathComponent("bark.realm")
            if fm.fileExists(atPath: old.path) { return old }
        }
        return nil
    }

    private static func readRealm(group: String) -> ReadResult {
        var result = ReadResult()
        guard let url = findBarkRealmURL() else {
            result.error = "未找到 BARK 数据库文件（bark.realm）。请确认 BARK 已安装且打开过一次。"
            return result
        }
        var config = Realm.Configuration(fileURL: url, readOnly: true)
        config.schemaVersion = 19
        config.objectTypes = [BarkRealmMessage.self]
        guard let realm = try? Realm(configuration: config) else {
            result.error = "BARK 数据库打开失败（可能被 BARK 占用或版本不匹配），将尝试快照。"
            return result
        }

        let all = realm.objects(BarkRealmMessage.self)
        // 收集全部可用分组（用于错误提示）
        var groups: [String] = []
        for obj in all {
            if let g = obj.group, !g.isEmpty, !groups.contains(g) { groups.append(g) }
        }
        result.availableGroups = groups

        let target = group.trimmingCharacters(in: .whitespaces)
        let matched = all.filter { obj in
            guard let g = obj.group else { return false }
            return g.trimmingCharacters(in: .whitespaces) == target
        }
        // 只要「今日汇总」类消息，按时间正序便于解析
        let summaries = matched.filter { ($0.title ?? "").contains("汇总") }
            .sorted { ($0.createDate ?? .distantPast) < ($1.createDate ?? .distantPast) }

        for obj in summaries {
            result.messages.append(BarkMessage(id: obj.id, title: obj.title, body: obj.body,
                                               group: obj.group, createDate: obj.createDate))
        }
        if result.messages.isEmpty {
            let list = groups.isEmpty ? "（BARK 里没有分组信息）" : groups.joined(separator: "、")
            result.error = "BARK 数据库里没有「\(target)」分组的汇总消息。现有分组：\(list)。可在设置里改分组名。"
        } else {
            result.source = "BARK 完整历史 Realm · \(target) 分组（\(result.messages.count) 条）"
        }
        return result
    }

    // MARK: 路径 B —— 快照（兜底）

    private static func readSnapshot(group: String, fallbackGroups: [String] = []) -> ReadResult {
        var result = ReadResult()
        result.availableGroups = fallbackGroups
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            result.error = "读不到 BARK 快照容器。请确认本 App 用巨魔带 App Group 权限安装。"
            return result
        }
        let url = groupURL.appendingPathComponent(snapshotName)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["messages"] as? [[String: Any]] else {
            result.error = "没读到 BARK 快照，且完整历史也不可用。请确认 BARK 有历史消息。"
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
            result.error = "快照里没有「\(target)」分组的汇总消息。现有分组：\(list)。"
            return result
        }
        result.messages = matched
        result.source = "BARK 小组件快照 · \(target) 分组（\(matched.count) 条，可能截断）"
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
