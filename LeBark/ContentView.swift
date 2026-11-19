import SwiftUI

struct ContentView: View {
    // 这里不要声明 @EnvironmentObject：本视图并不读取 store/sync。
    // 一旦声明，store 或同步状态每次变化都会重建整个 TabView，
    // 连带结账名单全量过滤排序几千条记录，切页/同步时明显卡顿。
    // store/sync 已在 LeBarkApp 注入环境，各子视图各自声明即可正常访问。

    var body: some View {
        TabView {
            TodayView().tabItem {
                Label("今日", systemImage: "sun.max.fill")
            }
            PeopleView().tabItem {
                Label("结账名单", systemImage: "person.3.fill")
            }
            WeekView().tabItem {
                Label("按周", systemImage: "calendar.badge.clock")
            }
            SettingsView().tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
        .accentColor(.brandIndigo)
    }
}

// MARK: - 通用小组件

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Color(hex: "1B2439").opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation { self.message = nil }
                        }
                    }
            }
        }
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// 名字点击即复制，带「已复制」反馈
struct CopyNameButton: View {
    let name: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = name
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(copied ? .brandGreen : .brandIndigo)
            }
        }
        .buttonStyle(.plain)
    }
}
