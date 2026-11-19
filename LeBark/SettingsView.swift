import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var server: PushHTTPServer
    @State private var showImport = false
    @State private var showClearConfirm = false
    @State private var newServer = ""
    @State private var toast: String?
    @State private var editingPort: String = ""

    private var pushURL: String { NetworkInfo.pushURL(port: store.serverPort) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {

                    // 服务器状态
                    VStack(alignment: .leading, spacing: 12) {
                        Label("数据接收服务（局域网直连，可选）", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)

                        Text("通知继续用你现有的 BARK，这里只负责收数据做统计。若 7 台机器和手机同内网，可让它们直接 POST 到下方地址；否则用「粘贴导入」即可。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(server.running ? Color.brandGreen : Color.gray.opacity(0.5))
                                    .frame(width: 9, height: 9)
                                Text(server.running ? "运行中" : "已停止")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(server.running ? .brandGreen : .subtle)
                            }
                            Spacer()
                            Button(server.running ? "停止" : "启动") {
                                if server.running { server.stop() }
                                else { server.start(port: store.serverPort) }
                            }
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandIndigo)
                        }

                        Toggle("打开 App 自动启动", isOn: $store.autoStartServer)
                            .font(.system(size: 13.5)).tint(.brandIndigo)

                        Toggle("收数据时也弹本地通知（默认关，避免和 BARK 重复）", isOn: $store.notifyOnPush)
                            .font(.system(size: 13.5)).tint(.brandIndigo)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("局域网数据接收地址（发给各服务器，可选）")
                                .font(.system(size: 11.5)).foregroundColor(.subtle)
                            HStack {
                                Text(pushURL)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.brandIndigo)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = pushURL
                                    toast = "推送地址已复制"
                                } label: {
                                    Image(systemName: "doc.on.doc").foregroundColor(.brandIndigo)
                                }
                            }
                            Text("各服务器把汇总 POST 到这个地址即可，格式见下方说明。手机需与服务器同局域网。")
                                .font(.system(size: 11)).foregroundColor(.subtle)
                        }
                        .padding(12)
                        .background(Color(hex: "F7F8FC"))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .cardStyle()

                    // 端口
                    VStack(alignment: .leading, spacing: 10) {
                        Label("监听端口", systemImage: "number")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        HStack(spacing: 10) {
                            TextField("8765", text: $editingPort)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 16)).monospacedDigit()
                            Button("应用") {
                                if let p = UInt16(editingPort), p > 1024 {
                                    store.serverPort = p
                                    if store.autoStartServer { server.start(port: p) }
                                    toast = "端口已改为 \(p)"
                                } else {
                                    toast = "端口需为 1025~65535"
                                }
                            }
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.brandIndigo)
                        }
                        Text("改端口后需重启服务；默认 8765。若提示端口占用，换个数字即可。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                    }
                    .cardStyle()
                    .onAppear { editingPort = String(store.serverPort) }

                    // 服务器名单
                    VStack(alignment: .leading, spacing: 10) {
                        Label("服务器编号（用于统计展示）", systemImage: "server.rack")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("推送里没带编号时，可在这里维护一份，方便看哪台没推。")
                            .font(.system(size: 11)).foregroundColor(.subtle)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(store.servers, id: \.self) { s in
                                HStack(spacing: 5) {
                                    Text(s).font(.system(size: 12.5, weight: .medium)).foregroundColor(.brandIndigo)
                                    Button {
                                        store.removeServer(s)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.subtle)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.brandIndigo.opacity(0.08))
                                .clipShape(Capsule())
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("新编号，如 206", text: $newServer)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 14))
                            Button {
                                store.addServer(newServer)
                                newServer = ""
                            } label: {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.brandIndigo)
                            }
                        }
                    }
                    .cardStyle()

                    // 粘贴导入
                    Button {
                        showImport = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.brandIndigo.opacity(0.12)).frame(width: 40, height: 40)
                                Image(systemName: "doc.on.clipboard.fill").foregroundColor(.brandIndigo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("粘贴导入").font(.system(size: 15, weight: .semibold)).foregroundColor(.ink)
                                Text("从 BARK 复制历史消息，或手动粘贴汇总文本")
                                    .font(.system(size: 11.5)).foregroundColor(.subtle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.subtle)
                        }
                    }
                    .buttonStyle(.plain)
                    .cardStyle()

                    // 接口格式说明
                    VStack(alignment: .leading, spacing: 8) {
                        Label("推送接口格式", systemImage: "questionmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("POST JSON：")
                            .font(.system(size: 11.5, weight: .medium)).foregroundColor(.ink)
                        Text("{\"title\":\"[202]今日汇总\",\"body\":\"金币:203/12684,账号:2/44\\n[21][929]:82unicorn:金 90,[22.5]\\n异常信息:\"}")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundColor(.subtle)
                            .textSelection(.enabled)
                        Text("也可 GET：\(pushURL)/[202]今日汇总/正文   或   ?title=..&body=..")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundColor(.subtle)
                            .textSelection(.enabled)
                        Text("最近接收：\(server.lastRawRequest.isEmpty ? "—" : server.lastRawRequest)")
                            .font(.system(size: 10.5)).foregroundColor(.subtle)
                            .lineLimit(2)
                    }
                    .cardStyle()

                    // 数据管理
                    VStack(alignment: .leading, spacing: 10) {
                        Label("数据管理", systemImage: "externaldrive.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        HStack {
                            Text("名单 \(store.persons.count) 条 · 异常 \(store.abnormals.count) 条 · 汇总 \(store.summaries.count) 条")
                                .font(.system(size: 11.5)).foregroundColor(.subtle)
                            Spacer()
                            Button("清空全部") { showClearConfirm = true }
                                .font(.system(size: 12.5, weight: .medium)).foregroundColor(.red)
                        }
                    }
                    .cardStyle()

                    Text("乐币BARK · 数据仅保存在本机 · iOS 15+")
                        .font(.system(size: 11)).foregroundColor(.subtle)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                }
                .padding(16)
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showImport) { ImportView().environmentObject(store) }
            .alert("确认清空", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    store.clearAll()
                    toast = "数据已清空"
                }
            } message: {
                Text("将删除本机所有名单、异常与汇总记录，不可恢复。")
            }
            .toast($toast)
        }
    }
}

// MARK: - 粘贴导入

struct ImportView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var dateKey = PushParser.todayKey()
    @State private var resultText = ""
    @State private var barkReading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 从 BARK 一键读取（只拉指定分组）
                    VStack(alignment: .leading, spacing: 10) {
                        Label("从 BARK 拉取「\(store.barkGroup)」分组", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("用巨魔权限读取本机 BARK 历史，只取下面这个分组的消息，自动解析成结账名单存进本 App。本 App 的数据会一直累积，不受 BARK 快照条数限制。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text("分组名").font(.system(size: 12.5)).foregroundColor(.subtle)
                            TextField("乐币", text: $store.barkGroup)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 14))
                        }

                        Button {
                            barkReading = true
                            let group = store.barkGroup
                            DispatchQueue.global(qos: .userInitiated).async {
                                let r = BarkReader.readAll(group: group)
                                DispatchQueue.main.async {
                                    barkReading = false
                                    if let err = r.error {
                                        resultText = "读取失败：\(err)"
                                    } else {
                                        let imported = store.importBarkMessages(r.messages)
                                        resultText = "从 \(r.source) 拉取 \(r.messages.count) 条 → 名单 +\(imported.personsAdded)，更新 \(imported.personsUpdated)，异常 +\(imported.abnormalsAdded)"
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                if barkReading {
                                    ProgressView().progressViewStyle(.circular)
                                }
                                Text(barkReading ? "正在拉取…" : "拉取并导入")
                                    .font(.system(size: 14.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(colors: [.brandGreen, Color(hex: "0EA5A0")], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(barkReading)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("粘贴汇总文本", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        TextEditor(text: $text)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(Color(hex: "F7F8FC"))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color(hex: "E3E8F3"), lineWidth: 1))
                        Button {
                            if let s = UIPasteboard.general.string { text = s }
                        } label: {
                            Label("从剪贴板粘贴", systemImage: "clipboard")
                                .font(.system(size: 12.5, weight: .medium)).foregroundColor(.brandIndigo)
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("归属日期", systemImage: "calendar")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        DatePicker("", selection: Binding(
                            get: { datePickerDate(from: dateKey) },
                            set: { dateKey = key(from: $0) }
                        ), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        Text("从 BARK 复制历史消息时，选对应日期，名单会归到那一天。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                    }
                    .cardStyle()

                    if !resultText.isEmpty {
                        Text(resultText)
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.brandGreen)
                            .frame(maxWidth: .infinity).padding(12)
                            .background(Color.brandGreen.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let r = store.importPaste(text, dateKey: dateKey)
                        resultText = "导入完成：名单 +\(r.personsAdded)，更新 \(r.personsUpdated)，异常 +\(r.abnormalsAdded)"
                    } label: {
                        Text("解析并导入").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(LinearGradient(colors: [.brandIndigo, .brandPurple], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text("支持一次粘贴多条汇总（按「[编号]今日汇总」自动切分）。重复导入不会生成重复名单。")
                        .font(.system(size: 11.5)).foregroundColor(.subtle).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background(Color(hex: "F5F7FC").ignoresSafeArea())
            .navigationTitle("粘贴导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.foregroundColor(.brandIndigo)
                }
            }
        }
    }

    private func key(from d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private func datePickerDate(from k: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: k) ?? Date()
    }
}
