import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var confirm: CheckConfirm
    @State private var search = ""
    @State private var filter: Filter = .unchecked
    @State private var toast: String?
    // 默认显示本周：历史有几百条时，一进来只看本周，列表更轻量
    @State private var dateFilter: DateFilter = .week

    enum Filter: String, CaseIterable { case unchecked = "未结账", checked = "已结账", all = "全部" }
    enum DateFilter: String, CaseIterable { case week = "本周", month = "本月", today = "今天", all = "所有日期" }

    private var filtered: [CheckoutPerson] {
        var arr = store.persons
        switch dateFilter {
        case .today: arr = arr.filter { $0.dateKey == PushParser.todayKey() }
        case .week:
            let wk = DateUtil.mondayKey(of: PushParser.todayKey())
            arr = arr.filter { DateUtil.mondayKey(of: $0.dateKey) == wk }
        case .month:
            let month = DateUtil.monthKey(of: PushParser.todayKey())
            arr = arr.filter { DateUtil.monthKey(of: $0.dateKey) == month }
        case .all: break
        }
        if !search.isEmpty {
            let q = search.lowercased()
            arr = arr.filter { $0.name.lowercased().contains(q) || $0.server.contains(q) || $0.timeCode.contains(q) }
        }
        switch filter {
        case .unchecked: arr = arr.filter { !$0.checked }
        case .checked: arr = arr.filter { $0.checked }
        case .all: break
        }
        // 时间倒序：日期从新到旧；同日内按位置、毫秒从大到小
        return arr.sorted { a, b in
            if a.dateKey != b.dateKey { return a.dateKey > b.dateKey }
            if a.server != b.server { return a.server.compare(b.server, options: .numeric) == .orderedDescending }
            if a.position != b.position { return a.position.compare(b.position, options: .numeric) == .orderedDescending }
            if a.timeCode != b.timeCode { return a.timeCode.compare(b.timeCode, options: .numeric) == .orderedDescending }
            return a.name < b.name
        }
    }

    private var grouped: [(key: String, items: [CheckoutPerson])] {
        let keys = Array(Set(filtered.map { $0.dateKey })).sorted(by: >)
        return keys.map { k in (k, filtered.filter { $0.dateKey == k }) }
    }

    private var allVisibleIDs: Set<UUID> { Set(filtered.map { $0.id }) }
    private var currentAmount: Double { filtered.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8)

                HStack(spacing: 8) {
                    Picker("日期", selection: $dateFilter) {
                        ForEach(DateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text("\(filtered.count) 人 · ¥\(String(format: "%.2f", currentAmount))")
                        .font(.system(size: 12.5, weight: .medium)).foregroundColor(.subtle)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                // 始终使用 List 占满剩余空间：空结果也放进 List，避免普通 VStack
                // 在 .searchable 下无法填满、search bar 下方出现白屏的问题。
                List {
                    if filtered.isEmpty {
                        Section {
                            emptyView
                                .listRowBackground(Color(hex: "F5F7FC"))
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        ForEach(grouped, id: \.key) { group in
                            Section(header: sectionHeader(group)) {
                                ForEach(group.items) { person in
                                    personRow(person)
                                }
                            }
                        }
                    }
                }
                // 切换筛选/日期时重建列表，避免切换「已结账」后内容向下偏移的布局异常
                .id("\(filter.rawValue)-\(dateFilter.rawValue)-\(search)")
                .listStyle(.insetGrouped)
                .animation(nil, value: filter)
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("结账名单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜名字 / 服务器 / 时间码")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            confirm.request(ids: allVisibleIDs, checked: true)
                        } label: {
                            Label("当前结果全部标记已结账", systemImage: "checkmark.circle")
                        }
                        Button {
                            confirm.request(ids: allVisibleIDs, checked: false)
                        } label: {
                            Label("当前结果取消结账标记", systemImage: "xmark.circle")
                        }
                        Divider()
                        Button {
                            let names = filtered.map { $0.name }.joined(separator: "\n")
                            UIPasteboard.general.string = names
                            toast = "已复制 \(filtered.count) 个名字"
                        } label: {
                            Label("复制当前所有名字", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundColor(.brandIndigo)
                    }
                }
            }
            .toast($toast)
        }
    }

    private func sectionHeader(_ group: (key: String, items: [CheckoutPerson])) -> some View {
        let un = group.items.filter { !$0.checked }.count
        return HStack {
            Text(DateUtil.displayCN(group.key)).font(.system(size: 12.5, weight: .semibold))
            Spacer()
            Text("\(group.items.count) 人 · 未结 \(un)")
                .font(.system(size: 11.5)).foregroundColor(un > 0 ? .brandOrange : .brandGreen)
        }
    }

    private func personRow(_ p: CheckoutPerson) -> some View {
        HStack(spacing: 12) {
            Button {
                confirm.request(person: p)
            } label: {
                Image(systemName: p.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(p.checked ? .brandGreen : Color.gray.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    CopyNameButton(name: p.name)
                    Spacer(minLength: 0)
                    Text(String(format: "¥%.2f", p.amount))
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.brandOrange).monospacedDigit()
                }
                HStack(spacing: 10) {
                    Text("金 \(p.coins)").font(.system(size: 11)).foregroundColor(.subtle)
                    if p.checked { Text("已结账").font(.system(size: 11, weight: .medium)).foregroundColor(.brandGreen) }
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                confirm.request(person: p)
            } label: {
                Label(p.checked ? "取消" : "结账", systemImage: p.checked ? "xmark" : "checkmark")
            }
            .tint(p.checked ? .gray : .brandGreen)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .unchecked ? "checkmark.circle" : "person.slash")
                .font(.system(size: 34)).foregroundColor(.subtle)
            Text(filter == .unchecked ? "没有未结账的人" : "没有匹配的记录")
                .font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
            Text(filter == .unchecked ? "全部都结清了，👍" : "换个筛选或搜索词试试")
                .font(.system(size: 12)).foregroundColor(.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
