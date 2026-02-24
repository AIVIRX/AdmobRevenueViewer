import SwiftUI

struct FilterBar: View {
    let accountName: String
    let rangeText: String

    var body: some View {
        HStack(spacing: 12) {
            Label(accountName, systemImage: "person.crop.circle")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
            Spacer()
            Label(rangeText, systemImage: "calendar")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
        }
    }
}
