import Foundation

// MARK: - 读取 BARK 历史消息（巨魔环境，按分组过滤）
//
// BARK 有两个数据源（已核对官方源码 Finb/Bark master）：
//   1) 完整备份：BARK「设置 → 导出/导入 → 导出」生成的 bark_messages_*.json
//      数组，每条含 id/title/body/group/createDate(Unix 秒)，body 不截断。
//      导出时文件先落在 BARK 容器 tmp/，之后可能被分享到「文件」App。
//      这就是拿到全部 451 条历史、且不依赖 Realm 库的正确路径。
//   2) 小组件快照：group.bark/recent_messages_snapshot.json
//      全局仅最近 100 条、body 截断 500 字符 —— 只能作为「最新增量」补充。
//
// 不链接 RealmSwift：此前静态链接会让本 App 在巨魔伪签名环境下启动闪退。
// 这里全部用 Foundation 解析 JSON，零第三方依赖。

enum BarkReader {

    struct BarkMessage {
        var id: String = ""
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

    private struct RawResult {
        var messages: [BarkMessage] = []
        var detail: String = ""
        var error: String?
    }

    private static let appGroup = "group.bark"
    private static let snapshotName = "recent_messages_snapshot.json"
    private static let backupPrefix = "bark_messages_"
    private static let pickedName = "bark_import.json"

    // MARK: 对外入口

    static func readAll(group: String) -> ReadResult {
        let backup = readBackups()
        let snap = readSnapshotRaw()

        // 备份在前（body 完整），快照补上尚未导出的最新消息；按 id 去重
        var seen = Set<String>()
        var all: [BarkMessage] = []
        for m in backup.messages + snap.messages {
            let key = messageKey(m)
            if seen.contains(key) { continue }
            seen.insert(key)
            all.append(m)
        }

        var result = ReadResult()
        var groups: [String] = []
        for m in all {
            if let g = m.group, !g.isEmpty, !groups.contains(g) { groups.append(g) }
        }
        result.availableGroups = groups

        let target = group.trimmingCharacters(in: .whitespaces)
        let matched = all.filter { m in
            guard let g = m.group else { return false }
            return g.trimmingCharacters(in: .whitespaces) == target
        }.sorted { ($0.createDate ?? .distantPast) < ($1.createDate ?? .distantPast) }

        if matched.isEmpty {
            let list = groups.isEmpty ? "（没有分组信息）" : groups.joined(separator: "、")
            result.error = "没有读到「\(target)」分组。现有分组：\(list)。备份 \(backup.messages.count) 条、快照 \(snap.messages.count) 条。可在设置里改分组名，或先在 BARK 导出一次备份。"
            return result
        }

        let df = DateFormatter(); df.dateFormat = "MM-dd"
        let dates = matched.compactMap { $0.createDate }.sorted()
        let range = dates.isEmpty ? "无日期" : "\(df.string(from: dates[0]))~\(df.string(from: dates[dates.count - 1]))"
        result.messages = matched
        let b = backup.detail.isEmpty ? "无备份" : backup.detail
        result.source = "BARK备份[\(b)] \(backup.messages.count) 条 + 快照 \(snap.messages.count) 条 · \(target) \(matched.count) 条（最早~最新 \(range)）"
        return result
    }

    private static func messageKey(_ m: BarkMessage) -> String {
        if !m.id.isEmpty { return "id:" + m.id }
        return "text:" + (m.title ?? "") + "|" + (m.body ?? "") + "|" + String(describing: m.createDate)
    }

    // MARK: 路径 A —— BARK 官方导出的完整备份 JSON

    private static func readBackups() -> RawResult {
        var r = RawResult()
        let fm = FileManager.default
        var files: [URL] = []

        // BARK 数据容器：导出文件会先写到 tmp/，用户「存储到文件」后原件仍在
        for container in barkContainers() {
            for sub in ["tmp", "Documents", "Library/Caches"] {
                let dir = container.appendingPathComponent(sub, isDirectory: true)
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for name in names where name.hasPrefix(backupPrefix) && name.hasSuffix(".json") {
                    files.append(dir.appendingPathComponent(name))
                }
            }
        }

        // 本 App 目录：用户从「文件」App 共享/文档选择器复制进来的备份
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            for dir in [docs, docs.appendingPathComponent("Inbox", isDirectory: true)] {
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for name in names where (name.hasPrefix(backupPrefix) || name == pickedName) && name.hasSuffix(".json") {
                    files.append(dir.appendingPathComponent(name))
                }
            }
        }

        // App Group（用户手动放进来时也能识别）
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
           let names = try? fm.contentsOfDirectory(atPath: g.path) {
            for name in names where (name.hasPrefix(backupPrefix) || name == pickedName) && name.hasSuffix(".json") {
                files.append(g.appendingPathComponent(name))
            }
        }

        // 同一个文件可能被找到多次，按路径去重
        var seenPath = Set<String>()
        files = files.filter { seenPath.insert($0.path).inserted }

        // 新导出的优先（重复 id 时保留最新一份）
        files.sort { a, b in modDate(a) > modDate(b) }

        var count = 0
        var details: [String] = []
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            for item in arr {
                var m = BarkMessage()
                m.id = item["id"] as? String ?? ""
                m.title = item["title"] as? String
                m.body = item["body"] as? String
                m.group = item["group"] as? String
                m.createDate = parseDate(item["createDate"])
                r.messages.append(m)
                count += 1
            }
            details.append(url.lastPathComponent)
        }
        r.detail = details.joined(separator: "、")
        if count == 0 && !files.isEmpty {
            r.error = "找到了 \(files.count) 个备份文件但解析失败，请确认是 BARK 导出的 JSON 数组。"
        }
        return r
    }

    /// 扫描其他 App 容器，找到含 bark.realm 或 bark_messages_*.json 的那个
    private static func barkContainers() -> [URL] {
        let fm = FileManager.default
        let root = "/var/mobile/Containers/Data/Application"
        guard let dirs = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        let base = URL(fileURLWithPath: root, isDirectory: true)
        var out: [URL] = []
        for d in dirs {
            let container = base.appendingPathComponent(d, isDirectory: true)
            if fm.fileExists(atPath: container.appendingPathComponent("Documents/bark.realm").path) {
                out.append(container)
                continue
            }
            let tmp = container.appendingPathComponent("tmp", isDirectory: true)
            if let names = try? fm.contentsOfDirectory(atPath: tmp.path),
               names.contains(where: { $0.hasPrefix(backupPrefix) && $0.hasSuffix(".json") }) {
                out.append(container)
            }
        }
        return out
    }

    // MARK: 路径 B —— 小组件快照（最近 100 条，仅作增量）

    private static func readSnapshotRaw() -> RawResult {
        var r = RawResult()
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            r.error = "读不到 BARK 快照容器"
            return r
        }
        let url = groupURL.appendingPathComponent(snapshotName)
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = obj["messages"] as? [[String: Any]] else {
            r.error = "没读到 BARK 快照"
            return r
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for item in arr {
            var m = BarkMessage()
            m.id = item["id"] as? String ?? ""
            m.title = item["title"] as? String
            m.body = item["body"] as? String
            m.group = item["group"] as? String
            if let s = item["createDate"] as? String {
                m.createDate = try? decoder.decode(Date.self, from: Data("\"\(s)\"".utf8))
            } else {
                m.createDate = parseDate(item["createDate"])
            }
            r.messages.append(m)
        }
        r.detail = "\(r.messages.count) 条"
        return r
    }

    private static func modDate(_ url: URL) -> Date {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let d = attrs[.modificationDate] as? Date else { return .distantPast }
        return d
    }

    /// BARK 导出用 Unix 秒（Int64），小组件快照用 ISO8601 字符串，两种都兼容
    private static func parseDate(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let d = value as? Double { return Date(timeIntervalSince1970: d) }
        if let i = value as? Int { return Date(timeIntervalSince1970: Double(i)) }
        if let s = value as? String {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(Date.self, from: Data("\"\(s)\"".utf8))
        }
        return nil
    }

    /// 把用户在「文件」App 里选中的备份复制到本 App Documents，供以后每次同步复用
    @discardableResult
    static func savePickedBackup(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data), obj is [[String: Any]],
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let dest = docs.appendingPathComponent(pickedName)
        return (try? data.write(to: dest, options: .atomic)) != nil
    }
}

// MARK: - 把 BARK 消息导入到账本

extension LedgerStore {
    @discardableResult
    func importBarkMessages(_ messages: [BarkReader.BarkMessage]) -> IngestResult {
        var total = IngestResult()
        var mismatchCount = 0
        batch {
            for m in messages {
                let title = m.title ?? ""
                let body = m.body ?? ""
                guard !title.isEmpty || !body.isEmpty else { continue }
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
        }
        total.hasMismatch = mismatchCount > 0
        return total
    }
}
