import SwiftUI

struct AdUnitIconView: View {
    let adFormat: String?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
        )
    }

    private var assetName: String? {
        switch adFormat?.uppercased() {
        case "BANNER":
            return "banner"
        case "INTERSTITIAL":
            return "interstitial"
        case "REWARDED":
            return "rewarded"
        case "REWARDED_INTERSTITIAL":
            return "rewardedinterstitial"
        case "NATIVE":
            return "nativeAdvanced"
        case "APP_OPEN":
            return "appopen"
        default:
            return nil
        }
    }

    private var iconName: String {
        switch adFormat?.uppercased() {
        case "BANNER":
            return "rectangle"
        case "INTERSTITIAL":
            return "rectangle.stack"
        case "REWARDED":
            return "gift"
        case "REWARDED_INTERSTITIAL":
            return "giftcard"
        case "NATIVE":
            return "square.text.square"
        default:
            return "megaphone"
        }
    }
}
