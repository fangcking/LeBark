import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var sync: SyncManager

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
