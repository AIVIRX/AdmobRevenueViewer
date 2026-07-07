import SwiftUI

struct TwelveMonthEarningsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: TwelveMonthEarningsViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: TwelveMonthEarningsViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if viewModel.isLoading && viewModel.earnings.isEmpty {
                        ProgressView("Loading 12 months...")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.earnings.isEmpty {
                        ContentUnavailableView(
                            "Unable to Load Earnings",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if viewModel.earnings.isEmpty {
                        ContentUnavailableView(
                            "No Monthly Earnings",
                            systemImage: "calendar",
                            description: Text("No earnings were reported during this period.")
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(viewModel.earnings.enumerated()), id: \.element.id) { index, earning in
                                MonthlyEarningsTile(
                                    earning: earning,
                                    previous: index > 0 ? viewModel.earnings[index - 1] : nil,
                                    currencyCode: appState.selectedAccount?.currencyCode ?? "USD",
                                    timeZoneIdentifier: appState.selectedAccount?.reportingTimeZone
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(String(currentYear) + " Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await load(force: true)
            }
            .task(id: appState.selectedAccount?.id) {
                await load()
            }
        }
    }

    private func load(force: Bool = false) async {
        guard let account = appState.selectedAccount else { return }
        await viewModel.load(account: account, force: force)
    }

    private var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        if let identifier = appState.selectedAccount?.reportingTimeZone,
           let timeZone = TimeZone(identifier: identifier) {
            calendar.timeZone = timeZone
        }
        return calendar.component(.year, from: Date())
    }
}

private struct MonthlyEarningsTile: View {
    let earning: AdMobMonthlyEarning
    let previous: AdMobMonthlyEarning?
    let currencyCode: String
    let timeZoneIdentifier: String?

    private var delta: Double? {
        guard !isFutureMonth, let previous, previous.estimatedEarnings != 0 else { return nil }
        return (earning.estimatedEarnings - previous.estimatedEarnings) / previous.estimatedEarnings
    }

    private var isFutureMonth: Bool {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return earning.month > currentMonth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(formatMonth(earning.month))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(isFutureMonth ? "-" : formatCurrency(earning.estimatedEarnings))
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if isFutureMonth {
                Text("Upcoming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let delta {
                Label(
                    formatDelta(delta),
                    systemImage: delta >= 0 ? "arrow.up" : "arrow.down"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
            } else {
                Text("No comparison")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private func formatDelta(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: abs(value))) ?? "0%"
    }
}
