import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ReportViewModel

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: ReportViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        FilterBar(accountName: appState.selectedAccount?.displayName ?? "No account", rangeText: rangeText)
                        DateRangePills(selection: $appState.dateRangeOption)
                            .onChange(of: appState.dateRangeOption) { _, newValue in
                                appState.dateRange = newValue.range()
                                Task { await loadReportIfNeeded() }
                            }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }

                if viewModel.isLoading {
                    ProgressView("Loading report...")
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                } else if (viewModel.report?.rows.isEmpty ?? true) {
                    Text("No data for this date range.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.report?.rows ?? []) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(row.appName) - \(row.adUnitName)")
                                .font(.subheadline)
                            Text("Earnings: \(formatCurrency(row.metrics.estimatedEarnings)) | Impr: \(formatInt(row.metrics.impressions)) | Clicks: \(formatInt(row.metrics.clicks))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Reports")
            .task {
                await loadReportIfNeeded()
            }
        }
    }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: appState.dateRange.startDate)) - \(formatter.string(from: appState.dateRange.endDate))"
    }

    private func loadReportIfNeeded() async {
        guard let account = appState.selectedAccount else { return }
        await viewModel.load(accountId: account.id, range: appState.dateRange, timeZone: account.reportingTimeZone)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.selectedAccount?.currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func formatInt(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
