import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: DashboardViewModel

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: "Summary", subtitle: subtitleText)
                    DateRangePills(selection: $appState.dateRangeOption)
                        .onChange(of: appState.dateRangeOption) { _, newValue in
                            appState.dateRange = newValue.range()
                            Task { await loadReportIfNeeded() }
                        }
                    summaryGrid
                    chartSection
                    SectionHeader(title: "Top Rows", subtitle: "Recent activity by app and ad unit")
                    rowsList
                }
                .padding(16)
            }
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        Task {
                            await environment.authManager.signOut()
                            appState.user = nil
                        }
                    }
                }
            }
            .task {
                await loadReportIfNeeded()
            }
        }
    }

    private var subtitleText: String {
        guard let account = appState.selectedAccount else { return "Select an account" }
        return "Account: \(account.displayName)"
    }

    private var summaryGrid: some View {
        let totals = viewModel.report?.totals
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "Estimated", value: formatCurrency(totals?.estimatedEarnings), subtitle: "Earnings")
                StatCard(title: "Impressions", value: formatInt(totals?.impressions), subtitle: "Total")
            }
            HStack(spacing: 12) {
                StatCard(title: "Clicks", value: formatInt(totals?.clicks), subtitle: "Total")
                StatCard(title: "eCPM", value: formatCurrency(totals?.eCPM), subtitle: "Per 1K")
            }
        }
    }

    private var rowsList: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView("Loading report...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if (viewModel.report?.rows.isEmpty ?? true) {
                Text("No data for this date range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(viewModel.report?.rows.prefix(5) ?? []) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(row.appName) - \(row.adUnitName)")
                            .font(.subheadline)
                        Text("Earnings: \(formatCurrency(row.metrics.estimatedEarnings)) | Impr: \(formatInt(row.metrics.impressions))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Earnings Trend", subtitle: "Last \(appState.dateRangeOption.rawValue)")
            if let data = chartData, !data.isEmpty {
                Chart(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Earnings", point.earnings)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Earnings", point.earnings)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYScale(domain: 0...max(1, chartData?.map { $0.earnings }.max() ?? 1))
                .frame(height: 200)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            } else if viewModel.isLoading {
                ProgressView("Loading chart...")
            } else {
                Text("No chart data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartData: [ChartPoint]? {
        guard let rows = viewModel.report?.rows else { return nil }
        let grouped = Dictionary(grouping: rows, by: { Calendar.current.startOfDay(for: $0.date) })
        return grouped.map { date, rows in
            let total = rows.reduce(0) { $0 + $1.metrics.estimatedEarnings }
            return ChartPoint(date: date, earnings: total)
        }
        .sorted { $0.date < $1.date }
    }

    private func loadReportIfNeeded() async {
        guard let account = appState.selectedAccount else { return }
        await viewModel.load(accountId: account.id, range: appState.dateRange, timeZone: account.reportingTimeZone)
    }

    private func formatCurrency(_ value: Double?) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.selectedAccount?.currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else { return "--" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

private struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let earnings: Double
}
