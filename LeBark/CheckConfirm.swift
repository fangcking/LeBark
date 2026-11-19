import SwiftUI

/// 结账状态变更的二次确认状态（三个页面共用）。
/// 用 .environmentObject 注入，任意页面调用 request() 弹出确认框，避免误触。
final class CheckConfirm: ObservableObject {
    @Published var pending: Pending? = nil

    struct Pending: Identifiable {
        let id = UUID()
        let ids: Set<UUID>          // 受影响的人
        let setChecked: Bool        // true=标记已结账，false=取消结账
        let name: String            // 单人时显示名字；批量时为人数描述
        let isBatch: Bool
    }

    /// 单人切换
    func request(person: CheckoutPerson) {
        pending = Pending(ids: [person.id],
                          setChecked: !person.checked,
                          name: person.name,
                          isBatch: false)
    }

    /// 批量设置
    func request(ids: Set<UUID>, checked: Bool) {
        guard !ids.isEmpty else { return }
        pending = Pending(ids: ids,
                          setChecked: checked,
                          name: "\(ids.count) 人",
                          isBatch: true)
    }

    func cancel() { pending = nil }
}

// MARK: - 通用的确认弹窗 modifier（挂在 TabView 根上，一处覆盖全部页面）

struct CheckConfirmModifier: ViewModifier {
    @EnvironmentObject private var store: LedgerStore
    @ObservedObject var confirm: CheckConfirm

    func body(content: Content) -> some View {
        content.alert(item: $confirm.pending) { p in
            Alert(
                title: Text(p.setChecked ? "确认标记为已结账？" : "确认取消结账？"),
                message: Text(p.isBatch
                    ? "将把 \(p.name) \(p.setChecked ? "标记为已结账" : "改回未结账")"
                    : "「\(p.name)」\(p.setChecked ? "标记为已结账" : "改回未结账")"),
                primaryButton: .default(Text(p.setChecked ? "确认结账" : "确认取消")) {
                    // 先关弹窗，再改数据。SwiftUI 在弹窗 dismiss 的同一帧里删除
                    // 列表行（已结账列表取消勾选时行会消失）会触发 UITableView
                    // 内部不一致而闪退，延后一帧即可彻底避开。
                    confirm.pending = nil
                    let ids = p.ids, checked = p.setChecked
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        store.setChecked(ids, checked: checked)
                    }
                },
                secondaryButton: .cancel(Text("取消")) {
                    confirm.pending = nil
                }
            )
        }
    }
}

extension View {
    func checkConfirm(_ confirm: CheckConfirm) -> some View {
        modifier(CheckConfirmModifier(confirm: confirm))
    }
}
