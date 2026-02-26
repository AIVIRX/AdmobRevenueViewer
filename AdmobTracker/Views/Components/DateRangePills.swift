import SwiftUI

struct DateRangePills: View {
    @Binding var selection: DateRangeOption

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(DateRangeOption.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selection == option ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                            )
                            .foregroundStyle(selection == option ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
