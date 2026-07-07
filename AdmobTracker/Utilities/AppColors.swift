import SwiftUI

extension Color {
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
    })

    static let cardBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground
    })
}
