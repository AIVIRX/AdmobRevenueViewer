import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: InsightsViewModel

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DateRangePills(selection: $appState.dateRangeOption)
                        .onChange(of: appState.dateRangeOption) { _, newValue in
                            appState.dateRange = newValue.range()
                            Task { await loadIfNeeded() }
                        }

                    SectionHeader(title: "Insights", subtitle: "Highlights for this period")
                    insightsGrid

                    SectionHeader(title: "Countries", subtitle: "Top markets by earnings")
                    countriesList
                }
                .padding(16)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await loadIfNeeded()
            }
            .task {
                await loadIfNeeded()
            }
            .onChange(of: appState.selectedAccount) { _, _ in
                Task { await loadIfNeeded() }
            }
        }
    }

    private var insightsGrid: some View {
        let highlights = insightCards
        return VStack(spacing: 12) {
            ForEach(highlights) { item in
                InsightCard(
                    title: item.title,
                    value: item.value,
                    subtitle: item.subtitle,
                    systemImage: item.systemImage,
                    appIconURL: item.appIconURL
                )
            }
        }
    }

    private var countriesList: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading countries...")
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if sortedCountries.isEmpty {
                Text("No country data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedCountries.prefix(10)) { country in
                        CountryRowCard(
                            name: country.name,
                            flag: flagEmoji(for: country.code),
                            value: formatCurrency(country.earnings),
                            subtitle: "eCPM \(formatCurrency(country.eCPM))"
                        )
                    }
                }
            }
        }
    }

    private var insightCards: [InsightCardItem] {
        guard let report = viewModel.report else { return [] }
        let appTotals = aggregate(by: \.appName, rows: report.rows)
        let adUnitTotals = aggregate(by: \.adUnitName, rows: report.rows)

        let topApp = appTotals.sorted(by: { $0.metrics.estimatedEarnings > $1.metrics.estimatedEarnings }).first
        let topAdUnit = adUnitTotals.sorted(by: { $0.metrics.estimatedEarnings > $1.metrics.estimatedEarnings }).first
        let bestECPM = appTotals.sorted(by: { $0.metrics.eCPM > $1.metrics.eCPM }).first

        return [
            InsightCardItem(
                title: "Top App",
                value: topApp?.name ?? "--",
                subtitle: topApp.map { formatCurrency($0.metrics.estimatedEarnings) } ?? "--",
                systemImage: "app.badge",
                appIconURL: topApp.flatMap { viewModel.appIconURLs[$0.name] }
            ),
            InsightCardItem(
                title: "Top Ad Unit",
                value: topAdUnit?.name ?? "--",
                subtitle: topAdUnit.map { formatCurrency($0.metrics.estimatedEarnings) } ?? "--",
                systemImage: "rectangle.stack",
                appIconURL: nil
            ),
            InsightCardItem(
                title: "Best eCPM",
                value: bestECPM?.name ?? "--",
                subtitle: bestECPM.map { formatCurrency($0.metrics.eCPM) } ?? "--",
                systemImage: "chart.line.uptrend.xyaxis",
                appIconURL: bestECPM.flatMap { viewModel.appIconURLs[$0.name] }
            )
        ]
    }

    private var sortedCountries: [AdMobCountrySummary] {
        viewModel.countrySummaries.sorted(by: { $0.earnings > $1.earnings })
    }

    private func aggregate(by keyPath: KeyPath<AdMobReportRow, String>, rows: [AdMobReportRow]) -> [AggregatedItem] {
        var map: [String: AdMobMetrics] = [:]
        for row in rows {
            let key = row[keyPath: keyPath]
            let current = map[key] ?? AdMobMetrics(
                estimatedEarnings: 0,
                impressions: 0,
                clicks: 0,
                eCPM: 0,
                adRequests: 0,
                matchedRequests: 0,
                observedECPM: 0
            )
            let earnings = current.estimatedEarnings + row.metrics.estimatedEarnings
            let impressions = current.impressions + row.metrics.impressions
            let clicks = current.clicks + row.metrics.clicks
            let eCPM = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            map[key] = AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: eCPM,
                adRequests: current.adRequests + row.metrics.adRequests,
                matchedRequests: current.matchedRequests + row.metrics.matchedRequests,
                observedECPM: eCPM
            )
        }
        return map.map { AggregatedItem(name: $0.key, metrics: $0.value) }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.selectedAccount?.currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func loadIfNeeded() async {
        guard let account = appState.selectedAccount else { return }
        await viewModel.load(accountId: account.id, range: appState.dateRange, timeZone: account.reportingTimeZone)
    }

    private func flagEmoji(for code: String?) -> String? {
        guard let code, code.count == 2 else { return nil }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for scalar in code.uppercased().unicodeScalars {
            guard let regional = UnicodeScalar(base + scalar.value) else { return nil }
            scalars.append(regional)
        }
        return String(scalars)
    }
}

private struct AggregatedItem: Identifiable {
    let id = UUID()
    let name: String
    let metrics: AdMobMetrics
}

private struct InsightCardItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let appIconURL: URL?
}

private struct InsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let appIconURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            InsightIconView(systemImage: systemImage, appIconURL: appIconURL, title: value)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }
}

private struct CountryRowCard: View {
    let name: String
    let flag: String?
    let value: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let flag {
                        Text(flag)
                            .font(.headline)
                    }
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }
}

private struct InsightIconView: View {
    let systemImage: String
    let appIconURL: URL?
    let title: String

    var body: some View {
        Group {
            if let appIconURL {
                AsyncImage(url: appIconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
        )
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
            if appIconURL == nil {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
            } else {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }

    private var initials: String {
        let parts = title.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + second).uppercased()
        return combined.isEmpty ? "A" : combined
    }
}
