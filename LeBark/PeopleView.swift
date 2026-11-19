import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var search = ""
    @State private var filter: Filter = .unchecked
    @State private var toast: String?
    @State private var showCheckedInList = true
    @State private var dateFilter: DateFilter = .all

    enum Filter: String, CaseIterable { case unchecked = "未结账", checked = "已结账", all = "全部" }
    enum DateFilter: String, CaseIterable { case all = "所有日期", today = "今天", week = "本周" }

    private var filtered: [CheckoutPerson] {
        var arr = store.persons
        switch dateFilter {
        case .today: arr = arr.filter { $0.dateKey == PushParser.todayKey() }
        case .week:
            let wk = DateUtil.mondayKey(of: PushParser.todayKey())
            arr = arr.filter { DateUtil.mondayKey(of: $0.dateKey) == wk }
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
        return arr.sorted { a, b in
            if a.dateKey != b.dateKey { return a.dateKey > b.dateKey }
            if a.server != b.server { return a.server < b.server }
            return a.position.compare(b.position, options: .numeric) == .orderedAscending
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

                if filtered.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(grouped, id: \.key) { group in
                            Section(header: sectionHeader(group)) {
                                ForEach(group.items) { person in
                                    personRow(person)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("结账名单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜名字 / 服务器 / 时间码")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.setChecked(allVisibleIDs, checked: true)
                            toast = "已将当前 \(allVisibleIDs.count) 人标记为已结账"
                        } label: {
                            Label("当前结果全部标记已结账", systemImage: "checkmark.circle")
                        }
                        Button {
                            store.setChecked(allVisibleIDs, checked: false)
                            toast = "已取消当前 \(allVisibleIDs.count) 人的结账标记"
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
                store.toggleChecked(p)
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
                    Text("服 \(p.server)").font(.system(size: 11)).foregroundColor(.subtle)
                    if !p.position.isEmpty { Text("位 \(p.position)").font(.system(size: 11)).foregroundColor(.subtle) }
                    if !p.timeCode.isEmpty { Text("\(p.timeCode)ms").font(.system(size: 11)).foregroundColor(.subtle) }
                    Text("金 \(p.coins)").font(.system(size: 11)).foregroundColor(.subtle)
                    if p.checked { Text("已结账").font(.system(size: 11, weight: .medium)).foregroundColor(.brandGreen) }
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                store.toggleChecked(p)
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
