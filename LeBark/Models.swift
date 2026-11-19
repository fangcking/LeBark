import Foundation
import SwiftUI

// MARK: - 结账人记录

/// 一条「抢到并需要结账」的人。名字是可复制、可搜索的核心字段。
struct CheckoutPerson: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var server: String          // 服务器编号，如 202
    var dateKey: String         // yyyy-MM-dd
    var position: String        // 位置/序号，如 21
    var timeCode: String        // 抢兑时间（毫秒），如 929 / 932 → 0.929 秒
    var name: String            // 结账人名字，如 82unicorn
    var coins: Int              // 抢到的金币，如 90
    var amount: Double          // 结账金额，如 22.5
    var checked: Bool = false   // 是否已结账
    var checkedAt: Date? = nil
    var note: String = ""

    /// 唯一键：同一台服务器同一天同一位置同一人只算一条（重复推送覆盖）
    var dedupeKey: String { "\(server)|\(dateKey)|\(position)|\(timeCode)|\(name)" }
}

/// 一条异常记录（超出个人每周限制等），单独记录，不计入结账名单
struct AbnormalRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var server: String
    var dateKey: String
    var position: String
    var name: String
    var reason: String
    var raw: String = ""

    var dedupeKey: String { "A|\(server)|\(dateKey)|\(position)|\(name)|\(reason)" }
}

/// 一台服务器某天的汇总数字
struct ServerSummary: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var server: String
    var dateKey: String
    var coinsOK: Int
    var coinsTotal: Int
    var accountsOK: Int
    var accountsTotal: Int
    var parsedPersons: Int = 0     // 实际从明细解析出的人数
    var mismatch: Bool = false     // 解析人数与推送声明的成功账号数不一致
    var receivedAt: Date = Date()

    var dedupeKey: String { "S|\(server)|\(dateKey)" }
}

struct IngestResult {
    var personsAdded: Int = 0
    var personsUpdated: Int = 0
    var abnormalsAdded: Int = 0
    var summaryUpdated: Bool = false
    var parsedServer: String = ""
    var dateKey: String = ""
    var expectedAccounts: Int = 0   // 推送声明的抢到人数（账号成功数）
    var parsedPersons: Int = 0      // 实际解析出的人数
    var hasMismatch: Bool = false   // 两者不一致，可能解析遗漏

    var isEmpty: Bool {
        personsAdded == 0 && personsUpdated == 0 && abnormalsAdded == 0 && !summaryUpdated
    }
}

// MARK: - 推送解析器

enum PushParser {
    /// 解析一条推送。title 形如「[202]今日汇总」，body 是多行正文。
    /// 有些机器把全部内容都塞进 body，title 为空；两种都支持。
    static func parse(title: String, body: String, fallbackDate: String? = nil) -> IngestResult {
        let dateKey = fallbackDate ?? todayKey()
        let text = [title, body].joined(separator: "\n")
        let lines = text
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var server = ""
        var coinsOK = 0, coinsTotal = 0, accountsOK = 0, accountsTotal = 0
        var foundSummary = false
        var foundPerson = false
        var foundAbnormal = false
        var persons: [CheckoutPerson] = []
        var abnormals: [AbnormalRecord] = []
        var inAbnormalSection = false

        for line in lines {
            // 1) 标题里的服务器编号：[202]今日汇总
            if server.isEmpty, let m = firstMatch(#"^\[(\d{2,5})\].*汇总"#, line) {
                server = m[1]
                continue
            }
            // body 里也可能带 [202]今日汇总
            if let m = firstMatch(#"^\[(\d{2,5})\].*汇总"#, line) {
                if server.isEmpty { server = m[1] }
                continue
            }

            // 2) 统计行：金币:203/12684,账号:2/44（兼容全角冒号/逗号、空格）
            if let m = firstMatch(#"金币\s*[:：]\s*(\d+)\s*/\s*(\d+)\s*[,，]\s*账号\s*[:：]\s*(\d+)\s*/\s*(\d+)"#, line) {
                coinsOK = int(m[1]); coinsTotal = int(m[2])
                accountsOK = int(m[3]); accountsTotal = int(m[4])
                foundSummary = true
                continue
            }

            // 3) 异常信息分节标记
            if line.contains("异常信息") {
                inAbnormalSection = true
                continue
            }

            // 4) 异常行：[25][0495 常 A10][超出个人每周限制]
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\[([^\]]+)\]"#, line) {
                var a = AbnormalRecord(server: server, dateKey: dateKey,
                                       position: m[1], name: m[2].trimmingCharacters(in: .whitespaces),
                                       reason: m[3].trimmingCharacters(in: .whitespaces), raw: line)
                if a.server.isEmpty { a.server = "未知" }
                abnormals.append(a)
                foundAbnormal = true
                continue
            }

            // 5) 正常结账行：[21][929]:82unicorn:金 90,[22.5]
            //    位置   时间码   名字      金币  金额
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\s*[:：]\s*(.+?)\s*[:：]\s*金\s*([\d.]+)\s*[,，]\s*\[([\d.]+)\]"#, line) {
                var p = CheckoutPerson(server: server, dateKey: dateKey,
                                       position: m[1], timeCode: m[2],
                                       name: m[3].trimmingCharacters(in: .whitespaces),
                                       coins: int(m[4]), amount: Double(m[5]) ?? 0)
                if p.server.isEmpty { p.server = "未知" }
                persons.append(p)
                foundPerson = true
                continue
            }

            // 5b) 兼容变体：[21][929]:名字:金 90,22.5（金额没有方括号）
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\s*[:：]\s*(.+?)\s*[:：]\s*金\s*([\d.]+)\s*[,，]\s*([\d.]+)"#, line) {
                var p = CheckoutPerson(server: server, dateKey: dateKey,
                                       position: m[1], timeCode: m[2],
                                       name: m[3].trimmingCharacters(in: .whitespaces),
                                       coins: int(m[4]), amount: Double(m[5]) ?? 0)
                if p.server.isEmpty { p.server = "未知" }
                persons.append(p)
                foundPerson = true
                continue
            }

            // 5c) 兼容变体：[21][929]:名字:金 90（无金额，按金币/4 推算）
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\s*[:：]\s*(.+?)\s*[:：]\s*金\s*([\d.]+)"#, line) {
                let coin = int(m[4])
                var p = CheckoutPerson(server: server, dateKey: dateKey,
                                       position: m[1], timeCode: m[2],
                                       name: m[3].trimmingCharacters(in: .whitespaces),
                                       coins: coin, amount: Double(coin) / 4.0)
                if p.server.isEmpty { p.server = "未知" }
                persons.append(p)
                foundPerson = true
                continue
            }

            // 5d) 兼容变体：名字:金 90,[22.5]（无前缀编号）
            if let m = firstMatch(#"^(.+?)\s*[:：]\s*金\s*([\d.]+)\s*[,，]\s*\[([\d.]+)\]"#, line) {
                var p = CheckoutPerson(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                       position: "", timeCode: "",
                                       name: m[1].trimmingCharacters(in: .whitespaces),
                                       coins: int(m[2]), amount: Double(m[3]) ?? 0)
                persons.append(p)
                foundPerson = true
                continue
            }

            // 6) 异常段里的纯文本名字行（如「5 WX-静 超出个人每周限制」）兜底
            if inAbnormalSection, !line.contains("异常信息"),
               let m = firstMatch(#"^\[?(\d+)\]?\s+(.+?)\s+(超出|异常|失败|未)"#, line) {
                let a = AbnormalRecord(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                       position: m[1], name: m[2].trimmingCharacters(in: .whitespaces),
                                       reason: line, raw: line)
                abnormals.append(a)
                foundAbnormal = true
            }
        }

        return IngestResult(personsAdded: persons.count,
                            abnormalsAdded: abnormals.count,
                            summaryUpdated: foundSummary,
                            parsedServer: server,
                            dateKey: dateKey)
    }

    /// 解析后返回结构化对象（供 Store 落库）
    static func parseDetailed(title: String, body: String, fallbackDate: String? = nil) -> (persons: [CheckoutPerson], abnormals: [AbnormalRecord], summary: ServerSummary?) {
        let dateKey = fallbackDate ?? todayKey()
        let text = [title, body].joined(separator: "\n")
        let lines = text.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var server = ""
        var coinsOK = 0, coinsTotal = 0, accountsOK = 0, accountsTotal = 0
        var persons: [CheckoutPerson] = []
        var abnormals: [AbnormalRecord] = []
        var summary: ServerSummary?

        for line in lines {
            if let m = firstMatch(#"^\[(\d{2,5})\].*汇总"#, line) {
                server = m[1]; continue
            }
            if let m = firstMatch(#"金币\s*[:：]\s*(\d+)\s*/\s*(\d+)\s*[,，]\s*账号\s*[:：]\s*(\d+)\s*/\s*(\d+)"#, line) {
                coinsOK = int(m[1]); coinsTotal = int(m[2])
                accountsOK = int(m[3]); accountsTotal = int(m[4])
                summary = ServerSummary(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                        coinsOK: coinsOK, coinsTotal: coinsTotal,
                                        accountsOK: accountsOK, accountsTotal: accountsTotal)
                continue
            }
            if line.contains("异常信息") { continue }
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\[([^\]]+)\]"#, line) {
                var a = AbnormalRecord(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                       position: m[1], name: m[2].trimmingCharacters(in: .whitespaces),
                                       reason: m[3].trimmingCharacters(in: .whitespaces), raw: line)
                abnormals.append(a); continue
            }
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\s*[:：]\s*(.+?)\s*[:：]\s*金\s*([\d.]+)\s*[,，]\s*\[([\d.]+)\]"#, line) {
                var p = CheckoutPerson(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                       position: m[1], timeCode: m[2],
                                       name: m[3].trimmingCharacters(in: .whitespaces),
                                       coins: int(m[4]), amount: Double(m[5]) ?? 0)
                persons.append(p); continue
            }
            if let m = firstMatch(#"^\[([^\]]+)\]\[([^\]]+)\]\s*[:：]\s*(.+?)\s*[:：]\s*金\s*([\d.]+)"#, line) {
                let coin = int(m[4])
                var p = CheckoutPerson(server: server.isEmpty ? "未知" : server, dateKey: dateKey,
                                       position: m[1], timeCode: m[2],
                                       name: m[3].trimmingCharacters(in: .whitespaces),
                                       coins: coin, amount: Double(coin) / 4.0)
                persons.append(p); continue
            }
        }
        return (persons, abnormals, summary)
    }

    private static func int(_ s: String) -> Int {
        Int(s.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return groups
    }

    static func todayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - 数据存储（本机持久化）

final class LedgerStore: ObservableObject {
    @Published var persons: [CheckoutPerson] = [] { didSet { persistIfNeeded() } }
    @Published var abnormals: [AbnormalRecord] = [] { didSet { persistIfNeeded() } }
    @Published var summaries: [ServerSummary] = [] { didSet { persistIfNeeded() } }
    @Published var servers: [String] = ["710", "2673", "201", "202", "203", "204", "205"] { didSet { persistIfNeeded() } }
    @Published var barkGroup: String = "乐币" { didSet { persistIfNeeded() } }
    @Published var lastEvent: String = ""
    @Published var lastSyncAt: Date? = nil
    @Published var lastSyncDetail: String = ""

    private var loaded = false
    private var batching = false

    init() {
        load()
        loaded = true
    }

    /// 一次导入几百条历史时，合并成一次写盘，避免主线程被反复 JSON 编码卡住
    func batch(_ work: () -> Void) {
        batching = true
        defer {
            batching = false
            persist()
        }
        work()
    }

    private func persistIfNeeded() {
        if !batching { persist() }
    }

    /// 接收一条推送并落库（去重）
    @discardableResult
    func ingest(title: String, body: String, dateKey: String? = nil) -> IngestResult {
        let parsed = PushParser.parseDetailed(title: title, body: body, fallbackDate: dateKey)
        var result = IngestResult(parsedServer: persons.first?.server ?? "", dateKey: dateKey ?? PushParser.todayKey())

        var personKeys = Set(persons.map { $0.dedupeKey })
        for var p in parsed.persons {
            if personKeys.contains(p.dedupeKey) {
                // 同名重复推送：更新金额/金币，不覆盖已结账状态
                if let idx = persons.firstIndex(where: { $0.dedupeKey == p.dedupeKey }) {
                    let wasChecked = persons[idx].checked
                    let oldCheckedAt = persons[idx].checkedAt
                    let oldNote = persons[idx].note
                    p.checked = wasChecked; p.checkedAt = oldCheckedAt; p.note = oldNote
                    if persons[idx] != p {
                        persons[idx] = p
                        result.personsUpdated += 1
                    }
                }
            } else {
                personKeys.insert(p.dedupeKey)
                persons.append(p)
                result.personsAdded += 1
            }
        }

        var abnormalKeys = Set(abnormals.map { $0.dedupeKey })
        for a in parsed.abnormals where !abnormalKeys.contains(a.dedupeKey) {
            abnormalKeys.insert(a.dedupeKey)
            abnormals.append(a)
            result.abnormalsAdded += 1
        }

        // 数据校验：推送声明的「账号成功数」应等于解析出的名单人数
        if var s = parsed.summary {
            let parsedCount = parsed.persons.count
            s.parsedPersons = parsedCount
            s.mismatch = s.accountsOK > 0 && s.accountsOK != parsedCount
            result.expectedAccounts = s.accountsOK
            result.parsedPersons = parsedCount
            result.hasMismatch = s.mismatch
            if let idx = summaries.firstIndex(where: { $0.dedupeKey == s.dedupeKey }) {
                if summaries[idx] != s {
                    s.id = summaries[idx].id
                    summaries[idx] = s
                    result.summaryUpdated = true
                }
            } else {
                summaries.append(s)
                result.summaryUpdated = true
            }
        }

        result.parsedServer = parsed.persons.first?.server ?? parsed.summary?.server ?? ""
        result.dateKey = parsed.summary?.dateKey ?? (dateKey ?? PushParser.todayKey())
        let warn = result.hasMismatch ? " ⚠️解析\(result.parsedPersons)/声明\(result.expectedAccounts)人" : ""
        lastEvent = "收到 \(result.parsedServer) 汇总：+\(result.personsAdded) 人，异常 +\(result.abnormalsAdded)\(warn)"
        return result
    }

    /// 粘贴导入：支持一次粘多条（用「今日汇总」分块）
    @discardableResult
    func importPaste(_ text: String, dateKey: String? = nil) -> IngestResult {
        var total = IngestResult()
        let chunks = splitPushes(text)
        for (title, body) in chunks {
            let r = ingest(title: title, body: body, dateKey: dateKey)
            total.personsAdded += r.personsAdded
            total.personsUpdated += r.personsUpdated
            total.abnormalsAdded += r.abnormalsAdded
            total.summaryUpdated = total.summaryUpdated || r.summaryUpdated
            if !r.parsedServer.isEmpty { total.parsedServer = r.parsedServer }
        }
        return total
    }

    /// 按「[编号]今日汇总」切分多条推送
    private func splitPushes(_ text: String) -> [(String, String)] {
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var chunks: [(String, String)] = []
        var currentTitle = ""
        var current: [String] = []
        for line in lines {
            if firstMatch(#"^\[(\d{2,5})\].*汇总"#, line) != nil {
                if !current.isEmpty || !currentTitle.isEmpty {
                    chunks.append((currentTitle, current.joined(separator: "\n")))
                }
                currentTitle = line.trimmingCharacters(in: .whitespaces)
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty || !currentTitle.isEmpty {
            chunks.append((currentTitle, current.joined(separator: "\n")))
        }
        if chunks.isEmpty { chunks.append(("", text)) }
        return chunks
    }

    func toggleChecked(_ person: CheckoutPerson) {
        guard let idx = persons.firstIndex(where: { $0.id == person.id }) else { return }
        persons[idx].checked.toggle()
        persons[idx].checkedAt = persons[idx].checked ? Date() : nil
    }

    func setChecked(_ ids: Set<UUID>, checked: Bool) {
        guard !ids.isEmpty else { return }
        // 一次性替换数组：原来逐个下标修改会让 @Published 连续触发多次，
        // 列表正在刷新时重复写盘/重绘是已结账页取消勾选闪退的诱因之一。
        var next = persons
        let now = Date()
        for idx in next.indices where ids.contains(next[idx].id) {
            next[idx].checked = checked
            next[idx].checkedAt = checked ? now : nil
        }
        persons = next
    }

    func deletePerson(_ person: CheckoutPerson) {
        persons.removeAll { $0.id == person.id }
    }

    func clearAll() {
        persons = []; abnormals = []; summaries = []
    }

    func addServer(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !servers.contains(t) else { return }
        servers.append(t)
    }

    func removeServer(_ s: String) {
        servers.removeAll { $0 == s }
    }

    // MARK: 持久化

    private static let kPersons = "lebark.persons"
    private static let kAbnormals = "lebark.abnormals"
    private static let kSummaries = "lebark.summaries"
    private static let kServers = "lebark.servers"
    private static let kBarkGroup = "lebark.barkgroup"

    /// 数据文件放在 App 的 Documents 目录：TrollStore 覆盖安装（更新 App）时 bundle id 不变，
    /// 容器不会删除，文件与 UserDefaults 都会保留；这里额外落一份 JSON，方便备份/迁移。
    private static var dataFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("lebark_data.json")
    }

    private struct Snapshot: Codable {
        var persons: [CheckoutPerson]
        var abnormals: [AbnormalRecord]
        var summaries: [ServerSummary]
        var servers: [String]
        var barkGroup: String
    }

    private func persist() {
        guard loaded else { return }
        let snap = Snapshot(persons: persons, abnormals: abnormals,
                            summaries: summaries, servers: servers, barkGroup: barkGroup)
        // 主：Documents 目录下的 JSON（原子写入，防中断损坏）
        if let data = try? JSONEncoder().encode(snap), let url = Self.dataFileURL {
            try? data.write(to: url, options: .atomic)
        }
        // 镜像：UserDefaults（兼容旧逻辑，作为兜底）
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(persons) { d.set(data, forKey: Self.kPersons) }
        if let data = try? JSONEncoder().encode(abnormals) { d.set(data, forKey: Self.kAbnormals) }
        if let data = try? JSONEncoder().encode(summaries) { d.set(data, forKey: Self.kSummaries) }
        d.set(servers, forKey: Self.kServers)
        d.set(barkGroup, forKey: Self.kBarkGroup)
    }

    private func load() {
        // 优先读 Documents JSON
        if let url = Self.dataFileURL,
           let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            persons = snap.persons
            abnormals = snap.abnormals
            summaries = snap.summaries
            servers = snap.servers
            barkGroup = snap.barkGroup
            return
        }
        // 兜底：读旧版 UserDefaults
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.kPersons),
           let arr = try? JSONDecoder().decode([CheckoutPerson].self, from: data) { persons = arr }
        if let data = d.data(forKey: Self.kAbnormals),
           let arr = try? JSONDecoder().decode([AbnormalRecord].self, from: data) { abnormals = arr }
        if let data = d.data(forKey: Self.kSummaries),
           let arr = try? JSONDecoder().decode([ServerSummary].self, from: data) { summaries = arr }
        if let arr = d.stringArray(forKey: Self.kServers), !arr.isEmpty { servers = arr }
        barkGroup = d.string(forKey: Self.kBarkGroup) ?? "乐币"
    }

    /// 数据文件所在目录（供设置页展示）
    static var dataFilePath: String { dataFileURL?.path ?? "（不可访问）" }

    private func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var g: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i); g.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return g
    }
}

// MARK: - 主题色 & 通用样式（沿用短信转发工程风格）

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                   .replacingOccurrences(of: "#", with: "")
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static let brandIndigo = Color(hex: "4F46E5")
    static let brandPurple = Color(hex: "7C3AED")
    static let brandOrange = Color(hex: "F59E0B")
    static let brandGreen  = Color(hex: "10B981")
    static let ink         = Color(hex: "1B2439")
    static let subtle      = Color(hex: "8A96AD")
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.055), radius: 14, x: 0, y: 5)
    }
}

// MARK: - 日期工具

enum DateUtil {
    static func mondayKey(of dateKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateKey) else { return dateKey }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let wk = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        return f.string(from: wk)
    }

    static func weekRangeLabel(mondayKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let mon = f.date(from: mondayKey) else { return mondayKey }
        let sun = Calendar.current.date(byAdding: .day, value: 6, to: mon) ?? mon
        return "\(mondayKey) ~ \(f.string(from: sun))"
    }

    static func displayCN(_ dateKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateKey) else { return dateKey }
        let out = DateFormatter(); out.dateFormat = "M月d日"
        let wd = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let w = Calendar.current.component(.weekday, from: d) - 1
        return "\(out.string(from: d)) \(wd[w])"
    }

    /// 截图标题用：完整年月日 + 星期，如 2026年11月19日 周四
    static func fullCN(_ dateKey: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: dateKey) else { return dateKey }
        let out = DateFormatter(); out.dateFormat = "yyyy年M月d日"
        let wd = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let w = Calendar.current.component(.weekday, from: d) - 1
        return "\(out.string(from: d)) \(wd[w])"
    }
}
