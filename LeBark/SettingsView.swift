import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var sync: SyncManager
    @State private var showImport = false
    @State private var showClearConfirm = false
    @State private var newServer = ""
    @State private var toast: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {

                    // 自动同步
                    VStack(alignment: .leading, spacing: 12) {
                        Label("BARK 自动同步", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("进入 App 自动拉取一次，之后每 60 秒拉取一次。数据存进本 App，不受 BARK 快照 100 条截断限制，也不再需要局域网监听。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text("分组名").font(.system(size: 12.5)).foregroundColor(.subtle)
                            TextField("乐币", text: $store.barkGroup)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 14))
                        }
                        HStack {
                            Image(systemName: sync.syncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                                .foregroundColor(sync.syncing ? .brandOrange : .brandGreen)
                            Text(sync.syncing ? "正在拉取…" : (sync.lastDetail.isEmpty ? "等待首次同步" : sync.lastDetail))
                                .font(.system(size: 11.5)).foregroundColor(.subtle)
                                .lineLimit(2)
                            Spacer()
                            Button("立即刷新") { sync.syncNow(); toast = "正在刷新…" }
                                .font(.system(size: 12.5, weight: .semibold)).foregroundColor(.brandIndigo)
                        }
                    }
                    .cardStyle()

                    // 服务器名单（顺序即今日汇总的展示顺序）
                    VStack(alignment: .leading, spacing: 10) {
                        Label("服务器编号（按此顺序展示）", systemImage: "server.rack")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("今日汇总按下面的顺序从上到下排列。可点 × 删除、拖动下方顺序调整需重建，当前按添加顺序。")
                            .font(.system(size: 11)).foregroundColor(.subtle)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(Array(store.servers.enumerated()), id: \.offset) { idx, s in
                                HStack(spacing: 5) {
                                    Text("\(idx + 1). \(s)").font(.system(size: 12, weight: .medium)).foregroundColor(.brandIndigo)
                                    Button { store.removeServer(s) } label: {
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
                            Button { store.addServer(newServer); newServer = "" } label: {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.brandIndigo)
                            }
                        }
                    }
                    .cardStyle()

                    // 粘贴导入（兜底）
                    Button { showImport = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.brandIndigo.opacity(0.12)).frame(width: 40, height: 40)
                                Image(systemName: "doc.on.clipboard.fill").foregroundColor(.brandIndigo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("粘贴导入 / 手动拉取").font(.system(size: 15, weight: .semibold)).foregroundColor(.ink)
                                Text("自动同步失败时的兜底：手动拉取 BARK 或粘贴汇总文本")
                                    .font(.system(size: 11.5)).foregroundColor(.subtle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.subtle)
                        }
                    }
                    .buttonStyle(.plain)
                    .cardStyle()

                    // 数据管理
                    VStack(alignment: .leading, spacing: 10) {
                        Label("数据管理", systemImage: "externaldrive.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("名单 \(store.persons.count) 条 · 异常 \(store.abnormals.count) 条 · 汇总 \(store.summaries.count) 条")
                            .font(.system(size: 11.5)).foregroundColor(.subtle)
                        Text("数据文件：\(LedgerStore.dataFilePath)")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.subtle)
                            .textSelection(.enabled)
                        Text("数据存在手机本机 Documents 目录，覆盖安装更新 App 不会删除。若卸载 App 会一并删除，重要数据请先复制上述路径文件备份。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
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
                Button("清空", role: .destructive) { store.clearAll(); toast = "数据已清空" }
            } message: {
                Text("将删除本机所有名单、异常与汇总记录，不可恢复。")
            }
            .toast($toast)
        }
    }
}

// MARK: - 粘贴导入 / 手动拉取

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
                    VStack(alignment: .leading, spacing: 10) {
                        Label("手动从 BARK 拉取「\(store.barkGroup)」分组", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        Text("优先读 BARK 完整历史数据库（全量、不截断），失败时回退小组件快照。只取这个分组的汇总消息。")
                            .font(.system(size: 11)).foregroundColor(.subtle)
                            .fixedSize(horizontal: false, vertical: true)
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
                                        let warn = imported.hasMismatch ? " ⚠️解析\(imported.parsedPersons)/声明\(imported.expectedAccounts)人" : ""
                                        resultText = "从 \(r.source) 拉取 \(r.messages.count) 条 → 名单 +\(imported.personsAdded)，更新 \(imported.personsUpdated)，异常 +\(imported.abnormalsAdded)\(warn)"
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                if barkReading { ProgressView().progressViewStyle(.circular) }
                                Text(barkReading ? "正在拉取…" : "拉取并导入")
                                    .font(.system(size: 14.5, weight: .semibold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(LinearGradient(colors: [.brandGreen, Color(hex: "0EA5A0")], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain).disabled(barkReading)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("粘贴汇总文本", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.subtle)
                        TextEditor(text: $text)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 160).padding(8)
                            .background(Color(hex: "F7F8FC"))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Button { if let s = UIPasteboard.general.string { text = s } } label: {
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
                        .datePickerStyle(.compact).labelsHidden()
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
            .navigationTitle("导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private func key(from d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private func datePickerDate(from k: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: k) ?? Date()
    }
}
