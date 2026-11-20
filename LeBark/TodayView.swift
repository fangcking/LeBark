import SwiftUI
import UIKit

struct TodayView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var sync: SyncManager
    @State private var toast: String?
    @State private var detailServer: ServerIdent? = nil
    /// 当前日期 key。App 后台挂起跨天后视图不会重建，若用 let 常量会永远停在
    /// 初始化那天的日期 → 回前台后仍显示昨天数据（而同步时间已更新为今天）。
    /// 这里用 @State，并在视图出现/回前台/系统日期变化时刷新，确保跨天后自动切到今天。
    @State private var today: String = PushParser.todayKey()

    private var todayPersons: [CheckoutPerson] {
        store.persons.filter { $0.dateKey == today }
    }
    private var todayAbnormals: [AbnormalRecord] {
        store.abnormals.filter { $0.dateKey == today }
    }
    private var todaySummaries: [ServerSummary] {
        store.summaries.filter { $0.dateKey == today }
    }
    private var unchecked: [CheckoutPerson] { todayPersons.filter { !$0.checked } }
    private var checked: [CheckoutPerson] { todayPersons.filter { $0.checked } }
    private var totalAmount: Double { todayPersons.reduce(0) { $0 + $1.amount } }
    private var checkedAmount: Double { checked.reduce(0) { $0 + $1.amount } }

    /// 今日抢到的金币总数（优先用推送汇总的 coinsOK，避免遗漏时少算；无汇总时用明细累加）
    private var todayCoins: Int {
        let fromSummary = todaySummaries.reduce(0) { $0 + $1.coinsOK }
        return fromSummary > 0 ? fromSummary : todayPersons.reduce(0) { $0 + $1.coins }
    }

    /// 服务器顺序：严格按设置里的顺序，再补上数据里出现但设置里没有的
    private var orderedServers: [String] {
        var result: [String] = []
        for s in store.servers where !result.contains(s) { result.append(s) }
        for s in todaySummaries.map({ $0.server }) where !result.contains(s) { result.append(s) }
        for s in todayPersons.map({ $0.server }) where !result.contains(s) { result.append(s) }
        return result
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    syncBar
                    statsRow
                    serverSection
                    if !todayAbnormals.isEmpty { abnormalSection }
                    if todayPersons.isEmpty { emptyCard }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("今日结账")
            .navigationBarTitleDisplayMode(.inline)
            .toast($toast)
            // 跨天/回前台时刷新「今天」：后台挂起的视图不会重建，必须主动更新日期 key
            .onAppear { today = PushParser.todayKey() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                today = PushParser.todayKey()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                today = PushParser.todayKey()
            }
            .sheet(item: $detailServer) { item in
                ServerDetailView(server: item.value,
                                 persons: todayPersons.filter { $0.server == item.value },
                                 summary: todaySummaries.first { $0.server == item.value })
            }
        }
    }

    // MARK: 同步状态条（自动拉取）

    private var syncBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: sync.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(sync.syncing ? .brandOrange : .brandGreen)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sync.syncing ? "正在从 BARK 拉取…" : "自动同步中（每 60 秒）")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundColor(.ink)
                    if let at = store.lastSyncAt {
                        Text("上次更新 \(timeText(at))　分组「\(store.barkGroup)」")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                    } else {
                        Text("分组「\(store.barkGroup)」· 数据存本机，不受 BARK 条数限制")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                    }
                }
                Spacer()
                Button {
                    sync.syncNow()
                    toast = "正在刷新…"
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.brandIndigo)
                }
            }
            if !sync.lastDetail.isEmpty {
                Text(sync.lastDetail)
                    .font(.system(size: 11)).foregroundColor(.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !sync.lastError.isEmpty {
                Text(sync.lastError)
                    .font(.system(size: 11)).foregroundColor(.brandOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: 顶部主视觉：今日抢到金币总数 + 对应金额

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [.brandIndigo, .brandPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 50, height: 50)
                    Image(systemName: "yensign.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("乐币 · 今日抢到").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                    Text(DateUtil.displayCN(today)).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(todayCoins)").font(.system(size: 28, weight: .bold)).foregroundColor(.white).monospacedDigit()
                    Text("金币　¥\(String(format: "%.2f", totalAmount))")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.9)).monospacedDigit()
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandIndigo.opacity(0.28), radius: 16, x: 0, y: 8)
    }

    // MARK: 统计三宫格

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCell(title: "今日名单", value: "\(todayPersons.count)", sub: "人", color: .brandIndigo)
            statCell(title: "已结账", value: "\(checked.count)", sub: String(format: "¥%.2f", checkedAmount), color: .brandGreen)
            statCell(title: "待结账", value: "\(unchecked.count)", sub: String(format: "¥%.2f", totalAmount - checkedAmount), color: .brandOrange)
        }
    }

    private func statCell(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 11.5)).foregroundColor(.subtle)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(color).monospacedDigit()
            Text(sub).font(.system(size: 11)).foregroundColor(.subtle).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: 各服务器汇总

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("各服务器今日汇总", systemImage: "server.rack")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(.subtle)
                Spacer()
                Text("\(todaySummaries.count)/\(orderedServers.count) 台")
                    .font(.system(size: 11.5)).foregroundColor(.subtle)
            }
            ForEach(orderedServers, id: \.self) { srv in
                serverCard(srv)
            }
        }
        .cardStyle()
    }

    private func serverCard(_ srv: String) -> some View {
        let sum = todaySummaries.first { $0.server == srv }
        let people = todayPersons.filter { $0.server == srv }
        let un = people.filter { !$0.checked }.count
        return Button {
            detailServer = ServerIdent(value: srv)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(sum == nil ? Color.gray.opacity(0.12) : Color.brandIndigo.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Text(srv).font(.system(size: 12, weight: .bold))
                        .foregroundColor(sum == nil ? .subtle : .brandIndigo)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let s = sum {
                        Text("金币 \(s.coinsOK)/\(s.coinsTotal)   账号 \(s.accountsOK)/\(s.accountsTotal)")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.ink)
                        HStack(spacing: 6) {
                            Text("名单 \(people.count) 人 · 未结账 \(un) 人")
                                .font(.system(size: 11.5)).foregroundColor(un > 0 ? .brandOrange : .brandGreen)
                            if s.mismatch {
                                Text("⚠️解析\(s.parsedPersons)/声明\(s.accountsOK)")
                                    .font(.system(size: 10.5, weight: .medium)).foregroundColor(.red)
                            }
                        }
                    } else {
                        Text("尚未推送").font(.system(size: 13)).foregroundColor(.subtle)
                        Text(" — ").font(.system(size: 11.5)).foregroundColor(.subtle)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.subtle)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 异常信息

    private var abnormalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("异常信息（\(todayAbnormals.count)）", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13.5, weight: .semibold)).foregroundColor(.brandOrange)
            ForEach(todayAbnormals) { a in
                HStack(alignment: .top, spacing: 8) {
                    Text(a.server).font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.brandOrange.opacity(0.85))
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        CopyNameButton(name: a.name)
                        Text(a.reason).font(.system(size: 11.5)).foregroundColor(.subtle)
                    }
                    Spacer()
                }
                .padding(.vertical, 5)
                if a.id != todayAbnormals.last?.id { Divider() }
            }
        }
        .cardStyle()
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 30)).foregroundColor(.subtle)
            Text("今天还没有数据").font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
            Text("App 正在自动从 BARK 拉取「\(store.barkGroup)」分组数据，也可到设置里手动刷新或粘贴导入。")
                .font(.system(size: 12)).foregroundColor(.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardStyle()
    }
}

// MARK: - 单台服务器今日明细（点击汇总卡片右侧箭头进入）

struct ServerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var confirm: CheckConfirm
    let server: String
    let persons: [CheckoutPerson]
    let summary: ServerSummary?

    /// 时间倒序：日期 → 位置 → 毫秒，均大到小
    private var sorted: [CheckoutPerson] {
        persons.sorted { a, b in
            if a.position != b.position { return a.position.compare(b.position, options: .numeric) == .orderedDescending }
            if a.timeCode != b.timeCode { return a.timeCode.compare(b.timeCode, options: .numeric) == .orderedDescending }
            return a.name < b.name
        }
    }

    var body: some View {
        NavigationView {
            List {
                if let s = summary {
                    Section(header: Text("推送统计")) {
                        HStack { Text("金币"); Spacer(); Text("\(s.coinsOK)/\(s.coinsTotal)").foregroundColor(.brandIndigo) }
                        HStack { Text("账号（抢到/总数）"); Spacer(); Text("\(s.accountsOK)/\(s.accountsTotal)").foregroundColor(.brandIndigo) }
                        HStack {
                            Text("解析校验")
                            Spacer()
                            if s.mismatch {
                                Text("⚠️ 解析 \(s.parsedPersons) 人 ≠ 声明 \(s.accountsOK) 人，可能遗漏")
                                    .foregroundColor(.red).font(.system(size: 12))
                            } else {
                                Text("✓ 一致（\(s.parsedPersons) 人）").foregroundColor(.brandGreen)
                            }
                        }
                    }
                }
                Section(header: Text("单账号明细（\(sorted.count)）")) {
                    ForEach(sorted) { p in
                        HStack(spacing: 10) {
                            Button {
                                confirm.request(person: p)
                            } label: {
                                Image(systemName: p.checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(p.checked ? .brandGreen : .gray.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 3) {
                                CopyNameButton(name: p.name)
                                Text("位置 \(p.position) · \(p.timeCode)ms · 金 \(p.coins)")
                                    .font(.system(size: 11)).foregroundColor(.subtle)
                            }
                            Spacer()
                            Text(String(format: "¥%.2f", p.amount))
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandOrange)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("服务器 \(server) · 明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct ServerIdent: Identifiable {
    let value: String
    var id: String { value }
}
