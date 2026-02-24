import UIKit

enum GoogleSignInHelper {
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        guard let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        return findTopViewController(root)
    }

    private static func findTopViewController(_ root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return findTopViewController(presented)
        }
        if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
            return findTopViewController(visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return findTopViewController(selected)
        }
        return root
    }
}
