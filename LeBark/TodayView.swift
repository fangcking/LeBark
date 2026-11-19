import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var server: PushHTTPServer
    @State private var toast: String?

    private let today = PushParser.todayKey()

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

    private var knownServers: [String] {
        let fromStore = Set(store.servers)
        let fromData = Set(todaySummaries.map { $0.server })
        return Array(fromStore.union(fromData)).sorted()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    pullBarkButton
                    statsRow
                    guideCard
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
        }
    }

    // MARK: 从 BARK 拉取按钮

    private var pullBarkButton: some View {
        Button {
            toast = "正在从 BARK 拉取「\(store.barkGroup)」分组…"
            DispatchQueue.global(qos: .userInitiated).async {
                let r = BarkReader.readAll(group: store.barkGroup)
                DispatchQueue.main.async {
                    if let err = r.error {
                        toast = "拉取失败：\(err)"
                    } else {
                        let imported = store.importBarkMessages(r.messages)
                        toast = "拉取 \(r.messages.count) 条 → 名单 +\(imported.personsAdded)，更新 \(imported.personsUpdated)"
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("从 BARK 拉取「\(store.barkGroup)」分组").font(.system(size: 14.5, weight: .bold))
                    Text("读取历史消息，自动解析成结账名单").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(LinearGradient(colors: [.brandGreen, Color(hex: "0EA5A0")], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: Color(hex: "0EA5A0").opacity(0.28), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: 顶部主视觉

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
                    Text("乐币 · 今日结账").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                    Text(DateUtil.displayCN(today)).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(unchecked.count)").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    Text("待结账").font(.system(size: 11)).foregroundColor(.white.opacity(0.85))
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
            statCell(title: "未结账", value: "\(unchecked.count)", sub: String(format: "¥%.2f", totalAmount - checkedAmount), color: .brandOrange)
        }
    }

    private func statCell(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 11.5)).foregroundColor(.subtle)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(color).monospacedDigit()
            Text(sub).font(.system(size: 11)).foregroundColor(.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: 使用引导

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("接收状态", systemImage: server.running ? "waveform.path.ecg" : "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(server.running ? Color.brandGreen : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(server.running ? "监听中" : "已停止")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(server.running ? .brandGreen : .subtle)
                }
            }
            Text(server.statusText)
                .font(.system(size: 12))
                .foregroundColor(.ink.opacity(0.7))
            if let ip = NetworkInfo.localIP() {
                Text("数据接收地址  http://\(ip):\(store.serverPort)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.brandIndigo)
                    .textSelection(.enabled)
            } else {
                Text("未获取到局域网 IP，去「设置」查看")
                    .font(.system(size: 11.5)).foregroundColor(.brandOrange)
            }
        }
        .cardStyle()
    }

    // MARK: 各服务器汇总

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("各服务器今日汇总", systemImage: "server.rack")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(.subtle)
                Spacer()
                Text("\(todaySummaries.count)/\(knownServers.count) 台")
                    .font(.system(size: 11.5)).foregroundColor(.subtle)
            }

            ForEach(knownServers, id: \.self) { srv in
                serverCard(srv)
            }
        }
        .cardStyle()
    }

    private func serverCard(_ srv: String) -> some View {
        let sum = todaySummaries.first { $0.server == srv }
        let people = todayPersons.filter { $0.server == srv }
        let un = people.filter { !$0.checked }.count
        return HStack(spacing: 12) {
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
                    Text("名单 \(people.count) 人 · 未结账 \(un) 人")
                        .font(.system(size: 11.5)).foregroundColor(un > 0 ? .brandOrange : .brandGreen)
                } else {
                    Text("尚未推送").font(.system(size: 13)).foregroundColor(.subtle)
                    Text(" — ").font(.system(size: 11.5)).foregroundColor(.subtle)
                }
            }
            Spacer()
            if sum != nil {
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.subtle)
            }
        }
        .padding(.vertical, 6)
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
            Text("今天还没有收到推送").font(.system(size: 14, weight: .medium)).foregroundColor(.ink)
            Text("服务器推送到下方地址后，名单会自动出现在这里。也可以在「设置 → 粘贴导入」手动录入。")
                .font(.system(size: 12)).foregroundColor(.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardStyle()
    }
}
