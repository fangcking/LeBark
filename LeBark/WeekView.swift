import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var confirm: CheckConfirm
    @State private var selectedMonday = DateUtil.mondayKey(of: PushParser.todayKey())
    @State private var mode: Mode = .unchecked
    @State private var showScreenshot = false
    @State private var toast: String?

    enum Mode: String, CaseIterable { case unchecked = "未结账", checked = "已结账", all = "全部" }

    private var weekPersons: [CheckoutPerson] {
        store.persons.filter { DateUtil.mondayKey(of: $0.dateKey) == selectedMonday }
    }
    private var shown: [CheckoutPerson] {
        switch mode {
        case .unchecked: return weekPersons.filter { !$0.checked }
        case .checked: return weekPersons.filter { $0.checked }
        case .all: return weekPersons
        }
    }
    private var grouped: [(key: String, items: [CheckoutPerson])] {
        // 时间倒序：日期从新到旧
        let keys = Array(Set(shown.map { $0.dateKey })).sorted(by: >)
        return keys.map { k in
            (k, shown.filter { $0.dateKey == k }.sorted { a, b in
                if a.position != b.position { return a.position.compare(b.position, options: .numeric) == .orderedDescending }
                if a.timeCode != b.timeCode { return a.timeCode.compare(b.timeCode, options: .numeric) == .orderedDescending }
                return a.name < b.name
            })
        }
    }
    private var totalAmount: Double { shown.reduce(0) { $0 + $1.amount } }
    private var serverKeys: [String] { Array(Set(weekPersons.map { $0.server })).sorted() }

    private func shiftWeek(_ delta: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: selectedMonday) else { return }
        let nd = Calendar.current.date(byAdding: .day, value: 7 * delta, to: d) ?? d
        selectedMonday = f.string(from: nd)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    weekNav
                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    summaryCard

                    if shown.isEmpty {
                        emptyCard
                    } else {
                        ForEach(grouped, id: \.key) { g in dayCard(g) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("按周名单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(isActive: $showScreenshot) {
                        WeekScreenshotView(mondayKey: selectedMonday,
                                           persons: shown,
                                           mode: mode.rawValue)
                    } label: {
                        Label("截图", systemImage: "camera.viewfinder")
                            .foregroundColor(.brandIndigo)
                    }
                    .disabled(shown.isEmpty)
                }
            }
            .toast($toast)
        }
    }

    private var weekNav: some View {
        HStack {
            Button { shiftWeek(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundColor(.brandIndigo)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(DateUtil.weekRangeLabel(mondayKey: selectedMonday))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.ink)
                Text("本周 \(weekPersons.count) 人 · 服务器 \(serverKeys.count) 台")
                    .font(.system(size: 11.5)).foregroundColor(.subtle)
            }
            Spacer()
            Button { shiftWeek(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundColor(.brandIndigo)
            }
        }
        .padding(.horizontal, 6)
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("总名单").font(.system(size: 11)).foregroundColor(.subtle)
                Text("\(weekPersons.count)").font(.system(size: 20, weight: .bold)).foregroundColor(.ink)
            }.frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            VStack(spacing: 4) {
                Text("未结账").font(.system(size: 11)).foregroundColor(.subtle)
                Text("\(weekPersons.filter { !$0.checked }.count)").font(.system(size: 20, weight: .bold)).foregroundColor(.brandOrange)
            }.frame(maxWidth: .infinity)
            Divider().frame(height: 30)
            VStack(spacing: 4) {
                Text("金额").font(.system(size: 11)).foregroundColor(.subtle)
                Text(String(format: "¥%.1f", totalAmount)).font(.system(size: 18, weight: .bold)).foregroundColor(.brandGreen).monospacedDigit()
            }.frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .cardStyle()
    }

    private func dayCard(_ group: (key: String, items: [CheckoutPerson])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(DateUtil.displayCN(group.key), systemImage: "calendar")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(.subtle)
                Spacer()
                Button {
                    let names = group.items.map { $0.name }.joined(separator: "\n")
                    UIPasteboard.general.string = names
                    toast = "已复制 \(DateUtil.displayCN(group.key)) 的 \(group.items.count) 个名字"
                } label: {
                    Label("复制名单", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.brandIndigo)
                }
            }
            ForEach(group.items) { p in
                HStack(spacing: 8) {
                    Text(p.server).font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.brandIndigo.opacity(0.85)).clipShape(Capsule())
                    CopyNameButton(name: p.name)
                    Spacer()
                    Text(String(format: "¥%.2f", p.amount))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandOrange).monospacedDigit()
                    Button {
                        confirm.request(person: p)
                    } label: {
                        Image(systemName: p.checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16)).foregroundColor(p.checked ? .brandGreen : .gray.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 5)
                if p.id != group.items.last?.id { Divider() }
            }
        }
        .cardStyle()
    }

    private var abnormalCard: some View {
        let arr = store.abnormals.filter { DateUtil.mondayKey(of: $0.dateKey) == selectedMonday }
        return Group {
            if !arr.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("本周异常（\(arr.count)）", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandOrange)
                    ForEach(arr) { a in
                        HStack(spacing: 8) {
                            Text(a.dateKey).font(.system(size: 11)).foregroundColor(.subtle)
                            CopyNameButton(name: a.name)
                            Spacer()
                            Text(a.reason).font(.system(size: 11)).foregroundColor(.subtle).lineLimit(1)
                        }
                    }
                }
                .cardStyle()
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 30)).foregroundColor(.subtle)
            Text("这一周没有符合条件的记录").font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).cardStyle()
    }
}

// MARK: - 截图专用视图（干净白底，适合直接截屏发群）

struct WeekScreenshotView: View {
    let mondayKey: String
    let persons: [CheckoutPerson]
    let mode: String

    private var grouped: [(key: String, items: [CheckoutPerson])] {
        // 时间倒序：日期从新到旧，明细按位置/毫秒从大到小
        let keys = Array(Set(persons.map { $0.dateKey })).sorted(by: >)
        return keys.map { k in
            (k, persons.filter { $0.dateKey == k }.sorted { a, b in
                if a.position != b.position { return a.position.compare(b.position, options: .numeric) == .orderedDescending }
                if a.timeCode != b.timeCode { return a.timeCode.compare(b.timeCode, options: .numeric) == .orderedDescending }
                return a.name < b.name
            })
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(grouped, id: \.key) { g in
                        VStack(alignment: .leading, spacing: 8) {
                            // 每天单独标题：截图里一眼看出是哪一天的数据
                            Text(DateUtil.fullCN(g.key))
                                .font(.system(size: 15, weight: .bold)).foregroundColor(.ink)

                            // 明细只保留三项：名字 / 金币 / 需结账金额
                            HStack(spacing: 6) {
                                Text("名字").font(.system(size: 10.5)).foregroundColor(.subtle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("金币").font(.system(size: 10.5)).foregroundColor(.subtle)
                                    .frame(width: 48, alignment: .trailing)
                                Text("需结账").font(.system(size: 10.5)).foregroundColor(.subtle)
                                    .frame(width: 72, alignment: .trailing)
                            }

                            ForEach(g.items) { p in
                                HStack(spacing: 6) {
                                    Text(p.name)
                                        .font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                    Text("\(p.coins)")
                                        .font(.system(size: 13)).foregroundColor(.subtle)
                                        .frame(width: 48, alignment: .trailing).monospacedDigit()
                                    Text("¥\(String(format: "%.2f", p.amount))")
                                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandOrange)
                                        .frame(width: 72, alignment: .trailing).monospacedDigit()
                                }
                                .padding(.vertical, 2.5)
                            }
                        }
                        .padding(14)
                        .background(Color(hex: "F7F8FC"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            // 截图专用页不显示标题，截图里只留日期 + 名单数据
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let text = grouped.map { g in
                            "【\(DateUtil.fullCN(g.key))】\n"
                                + g.items.map { "\($0.name)  \($0.coins)  ¥\(String(format: "%.2f", $0.amount))" }.joined(separator: "\n")
                        }.joined(separator: "\n\n")
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc").foregroundColor(.brandIndigo)
                    }
                }
            }
        }
    }
}
