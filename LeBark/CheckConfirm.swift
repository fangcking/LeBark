import SwiftUI
import UIKit

/// 结账状态变更的二次确认（三个页面共用）。
///
/// 用系统原生 UIAlertController，而不是 SwiftUI 的 .alert(item:)：
/// .alert(item:) 挂在根视图上，弹窗出现/消失会重建整个 TabView + List，
/// 在「确认后列表行立刻消失」的场景下会让 UITableView 内部状态不一致而闪退。
/// 原生弹窗不参与 SwiftUI 视图树，配合「下一帧再改数据」可彻底避开。
final class CheckConfirm: ObservableObject {
    weak var store: LedgerStore?

    func attach(_ store: LedgerStore) { self.store = store }

    /// 单人切换
    func request(person: CheckoutPerson) {
        let checked = !person.checked
        present(title: checked ? "确认标记为已结账？" : "确认取消结账？",
                message: "「\(person.name)」\(checked ? "标记为已结账" : "改回未结账")",
                ids: [person.id], setChecked: checked)
    }

    /// 批量设置
    func request(ids: Set<UUID>, checked: Bool) {
        guard !ids.isEmpty else { return }
        present(title: checked ? "确认标记为已结账？" : "确认取消结账？",
                message: "将把 \(ids.count) 人\(checked ? "标记为已结账" : "改回未结账")",
                ids: ids, setChecked: checked)
    }

    private func present(title: String, message: String, ids: Set<UUID>, setChecked: Bool) {
        guard let vc = Self.topViewController(), vc.presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        let confirmTitle = setChecked ? "确认结账" : "确认取消"
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { [weak self] _ in
            guard let store = self?.store else { return }
            // 弹窗已 dismiss，下一帧再改数据，避免列表刷新与弹窗动画叠加
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                store.setChecked(ids, checked: setChecked)
            }
        })
        vc.present(alert, animated: true)
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base = base {
            root = base
        } else {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            root = window?.rootViewController
        }
        guard let vc = root else { return nil }
        if let nav = vc as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = vc.presentedViewController { return topViewController(base: presented) }
        return vc
    }
}
