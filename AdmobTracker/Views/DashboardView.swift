import SwiftUI
import Charts
import WidgetKit

private let summaryAnimation = Animation.easeInOut(duration: 0.25)

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedMetric: AppMetric = .earnings
    @State private var selectedCountryMetric: AppMetric = .earnings
    @State private var selectedAdUnitMetric: AppMetric = .earnings
    @State private var showAllApps = false
    @State private var showAllCountries = false
    @State private var showAllAdUnits = false
    @State private var didLoad = false
    @State private var selectedEarningsPoint: ChartPoint?

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    heroCard
                    metricsGrid
                    HStack{
                        SectionHeader(title: "Apps", subtitle: "Performance by app")
                        appMetricMenu
                    }
                    appsList
                    if appSummaries.count > 5 {
                        ShowMoreRowButton(title: showAllApps ? "Show Less" : "Show More") {
                            withAnimation(.easeInOut) {
                                showAllApps.toggle()
                            }
                        }
                    }
                    HStack {
                        SectionHeader(title: "Countries", subtitle: "Performance by country")
                        countryMetricMenu
                    }
                    countriesList
                    if countrySummaries.count > 5 {
                        ShowMoreRowButton(title: showAllCountries ? "Show Less" : "Show More") {
                            withAnimation(.easeInOut) {
                                showAllCountries.toggle()
                            }
                        }
                    }
                    HStack{
                        SectionHeader(title: "Ad Units", subtitle: "Performance by ad unit")
                        adUnitMetricMenu
                    }
                    adUnitsList
                    if adUnitSummaries.count > 5 {
                        ShowMoreRowButton(title: showAllAdUnits ? "Show Less" : "Show More") {
                            withAnimation(.easeInOut) {
                                showAllAdUnits.toggle()
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable {
                await loadReportIfNeeded(force: true)
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Date Range", selection: $appState.dateRangeOption) {
                            ForEach(DateRangeOption.allCases) { option in
                                Text(option.rawValue)
                                    .tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("Date range: \(appState.dateRangeOption.rawValue)")
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                await loadReportIfNeeded()
            }
            .onChange(of: appState.dateRangeOption) { _, newValue in
                appState.dateRange = newValue.range()
                Task { await loadReportIfNeeded() }
            }
            .onChange(of: appState.selectedAccount) { _, _ in
                Task { await loadReportIfNeeded() }
            }
        }
    }

    private var subtitleText: String {
        guard let account = appState.selectedAccount else { return "Select an account" }
        return "Account: \(account.displayName)"
    }

    private var heroCard: some View {
        let totals = viewModel.report?.totals
        let heroValue = formatCurrency(selectedEarningsPoint?.earnings ?? totals?.estimatedEarnings)
        return VStack(spacing: 12) {
            Text("Estimated Earnings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(heroValue)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(summaryAnimation, value: heroValue)

            HStack(spacing: 6) {
                if let selectedEarningsPoint {
                    Text(formatShortDate(selectedEarningsPoint.date))
                        .foregroundStyle(.secondary)
                } else if let delta = percentChange(current: totals?.estimatedEarnings, previous: viewModel.previousReport?.totals.estimatedEarnings) {
                    Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                    Text(formatDelta(delta))
                        .contentTransition(.numericText())
                        .animation(summaryAnimation, value: formatDelta(delta))
                    Text(comparisonLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(heroDeltaColor)

            if viewModel.isLoading {
                ProgressView("Loading chart...")
                    .frame(height: 170)
            } else if let data = chartData, !data.isEmpty {
                EarningsChartView(
                    data: data,
                    domain: chartDomain,
                    currencyCode: appState.selectedAccount?.currencyCode ?? "USD",
                    isCompact: true,
                    selectedPoint: $selectedEarningsPoint
                )
            } else {
                Text("No chart data available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var metricsGrid: some View {
        let totals = viewModel.report?.totals
        let previousTotals = viewModel.previousReport?.totals
        let matchRateValue = matchRate(for: totals)
        let previousMatchRate = matchRate(for: previousTotals)
        let ctrValue = clickThroughRate(for: totals)
        let previousCTR = clickThroughRate(for: previousTotals)
        let dailyTotals = dailyMetricTotals(for: viewModel.report)
        let previousDailyTotals = dailyMetricTotals(for: viewModel.previousReport)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricSparklineCard(
                title: "Impressions",
                value: formatInt(totals?.impressions),
                delta: percentChange(current: totals?.impressions, previous: previousTotals?.impressions),
                values: sparklineValues(
                    current: dailyTotals.map { Double($0.impressions) },
                    previous: previousDailyTotals.map { Double($0.impressions) }
                )
            )

            MetricSparklineCard(
                title: "Clicks",
                value: formatInt(totals?.clicks),
                delta: percentChange(current: totals?.clicks, previous: previousTotals?.clicks),
                values: sparklineValues(
                    current: dailyTotals.map { Double($0.clicks) },
                    previous: previousDailyTotals.map { Double($0.clicks) }
                )
            )

            MetricSparklineCard(
                title: "Ad Requests",
                value: formatInt(totals?.adRequests),
                delta: percentChange(current: totals?.adRequests, previous: previousTotals?.adRequests),
                values: sparklineValues(
                    current: dailyTotals.map { Double($0.adRequests) },
                    previous: previousDailyTotals.map { Double($0.adRequests) }
                )
            )

            MetricSparklineCard(
                title: "Match Rate",
                value: formatPercent(matchRateValue),
                delta: percentChange(current: matchRateValue, previous: previousMatchRate),
                values: sparklineValues(
                    current: dailyTotals.map { matchRate(for: $0) ?? 0 },
                    previous: previousDailyTotals.map { matchRate(for: $0) ?? 0 }
                )
            )

            MetricSparklineCard(
                title: "Observed eCPM",
                value: formatCurrency(totals?.observedECPM),
                delta: percentChange(current: totals?.observedECPM, previous: previousTotals?.observedECPM),
                values: sparklineValues(
                    current: dailyTotals.map(\.observedECPM),
                    previous: previousDailyTotals.map(\.observedECPM)
                )
            )

            MetricSparklineCard(
                title: "CTR",
                value: formatPercent(ctrValue),
                delta: percentChange(current: ctrValue, previous: previousCTR),
                values: sparklineValues(
                    current: dailyTotals.map { clickThroughRate(for: $0) ?? 0 },
                    previous: previousDailyTotals.map { clickThroughRate(for: $0) ?? 0 }
                )
            )
        }
    }

    private var appMetricMenu: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading report...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if appSummaries.isEmpty {
                Text("No app data for this date range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Menu {
                    Picker("App Metric", selection: $selectedMetric) {
                        ForEach(AppMetric.allCases, id: \.self) { metric in
                            Text(metric.title)
                                .tag(metric)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedMetric.title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.cardBackground)
                    )
                }
                .accessibilityLabel("App metric: \(selectedMetric.title)")
            }
        }
    }

    private var adUnitMetricMenu: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading report...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if adUnitSummaries.isEmpty {
                Text("No ad unit data for this date range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Menu {
                    Picker("Ad Unit Metric", selection: $selectedAdUnitMetric) {
                        ForEach(AppMetric.allCases, id: \.self) { metric in
                            Text(metric.title)
                                .tag(metric)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedAdUnitMetric.title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.cardBackground)
                    )
                }
                .accessibilityLabel("Ad unit metric: \(selectedAdUnitMetric.title)")
            }
        }
    }

    private var countryMetricMenu: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if countrySummaries.isEmpty {
                EmptyView()
            } else {
                Menu {
                    Picker("Country Metric", selection: $selectedCountryMetric) {
                        ForEach(AppMetric.allCases, id: \.self) { metric in
                            Text(metric.title)
                                .tag(metric)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedCountryMetric.title)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.cardBackground)
                    )
                }
                .accessibilityLabel("Country metric: \(selectedCountryMetric.title)")
            }
        }
    }

    private var appsList: some View {
        Group {
            if viewModel.isLoading {
                EmptyView()
            } else if viewModel.errorMessage != nil {
                EmptyView()
            } else if appSummaries.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 5) {
                    ForEach(visibleAppSummaries) { summary in
                        AppRowCard(
                            name: summary.appName,
                            metricLabel: selectedMetric.title,
                            metricValue: valueForMetric(selectedMetric, summary: summary),
                            platform: summary.platform,
                            iconURL: summary.iconURL
                        )
                    }
                }
            }
        }
    }

    private var adUnitsList: some View {
        Group {
            if viewModel.isLoading {
                EmptyView()
            } else if viewModel.errorMessage != nil {
                EmptyView()
            } else if adUnitSummaries.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 5) {
                    ForEach(visibleAdUnitSummaries) { summary in
                        AdUnitRowCard(
                            name: summary.adUnitName,
                            appName: summary.appName,
                            metricLabel: selectedAdUnitMetric.title,
                            metricValue: valueForMetric(selectedAdUnitMetric, summary: summary),
                            adFormat: summary.adFormat
                        )
                    }
                }
            }
        }
    }

    private var countriesList: some View {
        Group {
            if viewModel.isLoading || viewModel.errorMessage != nil {
                EmptyView()
            } else if countrySummaries.isEmpty {
                Text("No country data for this date range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 5) {
                    ForEach(visibleCountrySummaries) { country in
                        CountryRowCard(
                            name: country.name,
                            flag: flagEmoji(for: country.code),
                            metricLabel: selectedCountryMetric.title,
                            metricValue: valueForMetric(selectedCountryMetric, country: country)
                        )
                    }
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Earnings Trend", subtitle: "Last \(appState.dateRangeOption.rawValue)")
            if let data = chartData, !data.isEmpty {
                EarningsChartView(
                    data: data,
                    domain: chartDomain,
                    currencyCode: appState.selectedAccount?.currencyCode ?? "USD",
                    isCompact: false,
                    selectedPoint: $selectedEarningsPoint
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
        guard let report = viewModel.report else { return nil }

        if appState.dateRangeOption == .today || appState.dateRangeOption == .yesterday {
            guard let previousReport = viewModel.previousReport else {
                return [ChartPoint(date: report.startDate, earnings: report.totals.estimatedEarnings)]
            }
            return [
                ChartPoint(date: previousReport.startDate, earnings: previousReport.totals.estimatedEarnings),
                ChartPoint(date: report.startDate, earnings: report.totals.estimatedEarnings)
            ]
        }

        let calendar = calendarForAccount()
        let start = calendar.startOfDay(for: report.startDate)
        let end = calendar.startOfDay(for: report.endDate)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day else { return nil }

        let grouped = Dictionary(grouping: report.rows, by: { calendar.startOfDay(for: $0.date) })
        return (0...max(days, 0)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let rows = grouped[date] ?? []
            let total = rows.reduce(0) { $0 + $1.metrics.estimatedEarnings }
            return ChartPoint(date: date, earnings: total)
        }
    }

    private var chartDomain: ClosedRange<Date> {
        if let data = chartData,
           let firstDate = data.first?.date,
           let lastDate = data.last?.date,
           firstDate < lastDate {
            return firstDate...lastDate
        }
        let calendar = calendarForAccount()
        let start = calendar.startOfDay(for: appState.dateRange.startDate)
        let end = calendar.startOfDay(for: appState.dateRange.endDate)
        return start...end
    }


    private func calendarForAccount() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZoneId = appState.selectedAccount?.reportingTimeZone,
           let timeZone = TimeZone(identifier: timeZoneId) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = TimeZone.current
        }
        return calendar
    }


    private func loadReportIfNeeded(force: Bool = false) async {
        guard let account = appState.selectedAccount else { return }
        let range = appState.dateRange
        let compareRange = appState.dateRangeOption.comparisonRange(for: range)
        await viewModel.load(accountId: account.id, range: range, compareRange: compareRange, timeZone: account.reportingTimeZone)
        await saveWidgetSnapshots(account: account)
        Task { await viewModel.loadAppMetadata(accountId: account.id, force: force) }
        Task { await viewModel.loadAdUnitMetadata(accountId: account.id, force: force) }
    }

    private func saveWidgetSnapshots(account: AdMobAccount) async {
        if appState.isGuest {
            WidgetBackgroundRefreshCoordinator.disable()
        } else {
            _ = await WidgetSnapshotRefresher.refresh(account: account, apiClient: environment.apiClient)
            WidgetBackgroundRefreshCoordinator.schedule()
        }
    }

    private func formatCurrency(_ value: Double?) -> String {
        guard let value else { return "0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = appState.selectedAccount?.currencyCode ?? "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else { return "0.00" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private func matchRate(for totals: AdMobMetrics?) -> Double? {
        guard let totals, totals.adRequests > 0 else { return nil }
        return Double(totals.matchedRequests) / Double(totals.adRequests)
    }

    private func clickThroughRate(for totals: AdMobMetrics?) -> Double? {
        guard let totals, totals.impressions > 0 else { return nil }
        return Double(totals.clicks) / Double(totals.impressions)
    }

    private func sparklineValues(current: [Double], previous: [Double]) -> [Double] {
        switch appState.dateRangeOption {
        case .today, .yesterday:
            return [previous.last, current.last].compactMap { $0 }
        case .last7Days, .thisMonth, .lastMonth:
            return current
        }
    }

    private func dailyMetricTotals(for report: AdMobReport?) -> [AdMobMetrics] {
        guard let rows = report?.rows else { return [] }
        let calendar = Calendar.current
        let groupedRows = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }

        return groupedRows.keys.sorted().compactMap { date in
            guard let rows = groupedRows[date] else { return nil }
            let earnings = rows.reduce(0) { $0 + $1.metrics.estimatedEarnings }
            let impressions = rows.reduce(0) { $0 + $1.metrics.impressions }
            let clicks = rows.reduce(0) { $0 + $1.metrics.clicks }
            let adRequests = rows.reduce(0) { $0 + $1.metrics.adRequests }
            let matchedRequests = rows.reduce(0) { $0 + $1.metrics.matchedRequests }
            let eCPM = impressions > 0 ? earnings / Double(impressions) * 1_000 : 0

            return AdMobMetrics(
                estimatedEarnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: eCPM,
                adRequests: adRequests,
                matchedRequests: matchedRequests,
                observedECPM: eCPM
            )
        }
    }


    private var appSummaries: [AppSummary] {
        guard let rows = viewModel.report?.rows else { return [] }
        let grouped = Dictionary(grouping: rows, by: { $0.appName })
        let summaries = grouped.map { appName, rows in
            let earnings = rows.reduce(0) { $0 + $1.metrics.estimatedEarnings }
            let impressions = rows.reduce(0) { $0 + $1.metrics.impressions }
            let clicks = rows.reduce(0) { $0 + $1.metrics.clicks }
            let adRequests = rows.reduce(0) { $0 + $1.metrics.adRequests }
            let matchedRequests = rows.reduce(0) { $0 + $1.metrics.matchedRequests }
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            let matchRate = adRequests > 0 ? Double(matchedRequests) / Double(adRequests) : 0
            let ctr = impressions > 0 ? Double(clicks) / Double(impressions) : 0
            return AppSummary(
                appName: appName,
                earnings: earnings,
                impressions: impressions,
                clicks: clicks,
                adRequests: adRequests,
                eCPM: ecpm,
                matchRate: matchRate,
                ctr: ctr,
                platform: viewModel.appPlatforms[appName],
                iconURL: viewModel.appIconURLs[appName]
            )
        }
        return summaries.sorted { lhs, rhs in
            switch selectedMetric {
            case .earnings:
                return lhs.earnings > rhs.earnings
            case .impressions:
                return lhs.impressions > rhs.impressions
            case .clicks:
                return lhs.clicks > rhs.clicks
            case .adRequests:
                return lhs.adRequests > rhs.adRequests
            case .ecpm:
                return lhs.eCPM > rhs.eCPM
            case .matchRate:
                return lhs.matchRate > rhs.matchRate
            case .ctr:
                return lhs.ctr > rhs.ctr
            }
        }
    }

    private var adUnitSummaries: [AdUnitSummary] {
        guard let rows = viewModel.report?.rows else { return [] }
        let grouped = Dictionary(grouping: rows, by: { "\($0.adUnitName)|\($0.appName)" })
        let summaries = grouped.map { _, rows in
            let adUnitName = rows.first?.adUnitName ?? "Unknown Ad Unit"
            let appName = rows.first?.appName ?? "Unknown App"
            let earnings = rows.reduce(0) { $0 + $1.metrics.estimatedEarnings }
            let impressions = rows.reduce(0) { $0 + $1.metrics.impressions }
            let clicks = rows.reduce(0) { $0 + $1.metrics.clicks }
            let adRequests = rows.reduce(0) { $0 + $1.metrics.adRequests }
            let matchedRequests = rows.reduce(0) { $0 + $1.metrics.matchedRequests }
            let ecpm = impressions > 0 ? (earnings / Double(impressions) * 1000.0) : 0
            let matchRate = adRequests > 0 ? Double(matchedRequests) / Double(adRequests) : 0
            let ctr = impressions > 0 ? Double(clicks) / Double(impressions) : 0
            let adFormat = viewModel.adUnitFormats[adUnitName]
            return AdUnitSummary(
                adUnitName: adUnitName,
                appName: appName,
                earnings: earnings,
                impressions: impressions,
                clicks: clicks,
                adRequests: adRequests,
                eCPM: ecpm,
                matchRate: matchRate,
                ctr: ctr,
                adFormat: adFormat
            )
        }

        return summaries.sorted { lhs, rhs in
            switch selectedAdUnitMetric {
            case .earnings:
                return lhs.earnings > rhs.earnings
            case .impressions:
                return lhs.impressions > rhs.impressions
            case .clicks:
                return lhs.clicks > rhs.clicks
            case .adRequests:
                return lhs.adRequests > rhs.adRequests
            case .ecpm:
                return lhs.eCPM > rhs.eCPM
            case .matchRate:
                return lhs.matchRate > rhs.matchRate
            case .ctr:
                return lhs.ctr > rhs.ctr
            }
        }
    }

    private var visibleAppSummaries: [AppSummary] {
        showAllApps ? appSummaries : Array(appSummaries.prefix(5))
    }

    private var countrySummaries: [AdMobCountrySummary] {
        viewModel.countrySummaries.sorted { lhs, rhs in
            switch selectedCountryMetric {
            case .earnings: return lhs.earnings > rhs.earnings
            case .impressions: return lhs.impressions > rhs.impressions
            case .clicks: return lhs.clicks > rhs.clicks
            case .adRequests: return lhs.adRequests > rhs.adRequests
            case .ecpm: return lhs.eCPM > rhs.eCPM
            case .matchRate: return countryMatchRate(lhs) > countryMatchRate(rhs)
            case .ctr: return countryCTR(lhs) > countryCTR(rhs)
            }
        }
    }

    private var visibleCountrySummaries: [AdMobCountrySummary] {
        showAllCountries ? countrySummaries : Array(countrySummaries.prefix(5))
    }

    private var visibleAdUnitSummaries: [AdUnitSummary] {
        showAllAdUnits ? adUnitSummaries : Array(adUnitSummaries.prefix(5))
    }

    private func valueForMetric(_ metric: AppMetric, summary: AppSummary) -> String {
        switch metric {
        case .earnings:
            return formatCurrency(summary.earnings)
        case .impressions:
            return formatInt(summary.impressions)
        case .clicks:
            return formatInt(summary.clicks)
        case .adRequests:
            return formatInt(summary.adRequests)
        case .ecpm:
            return formatCurrency(summary.eCPM)
        case .matchRate:
            return formatPercent(summary.matchRate)
        case .ctr:
            return formatPercent(summary.ctr)
        }
    }

    private func valueForMetric(_ metric: AppMetric, summary: AdUnitSummary) -> String {
        switch metric {
        case .earnings:
            return formatCurrency(summary.earnings)
        case .impressions:
            return formatInt(summary.impressions)
        case .clicks:
            return formatInt(summary.clicks)
        case .adRequests:
            return formatInt(summary.adRequests)
        case .ecpm:
            return formatCurrency(summary.eCPM)
        case .matchRate:
            return formatPercent(summary.matchRate)
        case .ctr:
            return formatPercent(summary.ctr)
        }
    }

    private func valueForMetric(_ metric: AppMetric, country: AdMobCountrySummary) -> String {
        switch metric {
        case .earnings: return formatCurrency(country.earnings)
        case .impressions: return formatInt(country.impressions)
        case .clicks: return formatInt(country.clicks)
        case .adRequests: return formatInt(country.adRequests)
        case .ecpm: return formatCurrency(country.eCPM)
        case .matchRate: return formatPercent(countryMatchRate(country))
        case .ctr: return formatPercent(countryCTR(country))
        }
    }

    private func countryMatchRate(_ country: AdMobCountrySummary) -> Double {
        guard country.adRequests > 0 else { return 0 }
        return Double(country.matchedRequests) / Double(country.adRequests)
    }

    private func countryCTR(_ country: AdMobCountrySummary) -> Double {
        guard country.impressions > 0 else { return 0 }
        return Double(country.clicks) / Double(country.impressions)
    }

    private func flagEmoji(for countryCode: String?) -> String? {
        guard let countryCode, countryCode.count == 2 else { return nil }
        let scalars = countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    private func percentChange(current: Int?, previous: Int?) -> Double? {
        guard let current, let previous, previous != 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }

    private func percentChange(current: Double?, previous: Double?) -> Double? {
        guard let current, let previous, previous != 0 else { return nil }
        return (current - previous) / previous
    }

    private func formatDelta(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private var heroDeltaColor: Color {
        guard let delta = percentChange(current: viewModel.report?.totals.estimatedEarnings,
                                        previous: viewModel.previousReport?.totals.estimatedEarnings) else {
            return Color.secondary
        }
        return delta >= 0 ? Color.green.opacity(0.95) : Color.red.opacity(0.95)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = calendarForAccount().timeZone
        return formatter.string(from: date)
    }

    private var comparisonLabel: String {
        switch appState.dateRangeOption {
        case .today, .yesterday:
            return "vs last week"
        case .last7Days:
            return "vs prev 7D"
        case .thisMonth:
            return "vs last month"
        case .lastMonth:
            return "vs month before"
        }
    }
}

private struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let earnings: Double
}

private struct EarningsChartView: View {
    let data: [ChartPoint]
    let domain: ClosedRange<Date>
    let currencyCode: String
    let isCompact: Bool
    @Binding var selectedPoint: ChartPoint?

    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Earnings", point.earnings)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if !isCompact || data.count == 1 {
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Earnings", point.earnings)
                )
                .symbolSize(22)
                .foregroundStyle(Color.accentColor.opacity(0.85))
            }

            AreaMark(
                x: .value("Date", point.date),
                y: .value("Earnings", point.earnings)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.1), Color.accentColor.opacity(0.05), Color.accentColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let selectedPoint, selectedPoint.date == point.date {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [4]))
                    .annotation(position: .top, alignment: tooltipAlignment(for: selectedPoint.date)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatShortDate(selectedPoint.date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(formatCurrency(selectedPoint.earnings))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.cardBackground)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
                        )
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, data.map { $0.earnings }.max() ?? 1))
        .frame(height: isCompact ? 170 : 200)
        .padding(isCompact ? 0 : 12)
        .background(
            Group {
                if !isCompact {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.cardBackground)
                }
            }
        )
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let plotX = min(max(value.location.x - frame.origin.x, 0), frame.width)
                                let location = CGPoint(x: plotX, y: value.location.y - frame.origin.y)
                                if let date: Date = proxy.value(atX: location.x),
                                   let nearest = nearestPoint(to: date) {
                                    selectedPoint = nearest
                                }
                            }
                            .onEnded { _ in
                                selectedPoint = nil
                            }
                    )
            }
        }
    }

    private func nearestPoint(to date: Date) -> ChartPoint? {
        data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func tooltipAlignment(for date: Date) -> Alignment {
        let start = domain.lowerBound.timeIntervalSince1970
        let end = domain.upperBound.timeIntervalSince1970
        let current = date.timeIntervalSince1970
        let progress = (current - start) / max(end - start, 1)
        if progress < 0.2 {
            return .leading
        }
        if progress > 0.8 {
            return .trailing
        }
        return .center
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct AppSummary: Identifiable {
    let id = UUID()
    let appName: String
    let earnings: Double
    let impressions: Int
    let clicks: Int
    let adRequests: Int
    let eCPM: Double
    let matchRate: Double
    let ctr: Double
    let platform: String?
    let iconURL: URL?
}

private struct AdUnitSummary: Identifiable {
    let id = UUID()
    let adUnitName: String
    let appName: String
    let earnings: Double
    let impressions: Int
    let clicks: Int
    let adRequests: Int
    let eCPM: Double
    let matchRate: Double
    let ctr: Double
    let adFormat: String?
}

private struct ShowMoreRowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AppRowCard: View {
    let name: String
    let metricLabel: String
    let metricValue: String
    let platform: String?
    let iconURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(name: name, iconURL: iconURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let platform, !platform.isEmpty {
                    Text(platformDisplay(platform))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(metricValue)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(summaryAnimation, value: metricValue)
                Text(metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }

    private func platformDisplay(_ platform: String) -> String {
        switch platform.uppercased() {
        case "IOS": return "iOS"
        case "ANDROID": return "Android"
        default: return platform
        }
    }
}

private struct CountryRowCard: View {
    let name: String
    let flag: String?
    let metricLabel: String
    let metricValue: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Text(flag ?? "--")
                    .font(.title3)
            }
            .frame(width: 44, height: 44)

            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(metricValue)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Text(metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }
}

private struct AdUnitRowCard: View {
    let name: String
    let appName: String
    let metricLabel: String
    let metricValue: String
    let adFormat: String?

    var body: some View {
        HStack(spacing: 12) {
            AdUnitIconView(adFormat: adFormat)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(appName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(metricValue)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(summaryAnimation, value: metricValue)
                Text(metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
                )
        )
    }
}

private struct AppIconView: View {
    let name: String
    let iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
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
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
        )
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.18))
            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }
}

private enum AppMetric: CaseIterable {
    case earnings
    case impressions
    case clicks
    case adRequests
    case ecpm
    case matchRate
    case ctr

    var title: String {
        switch self {
        case .earnings: return "Earnings"
        case .impressions: return "Impressions"
        case .clicks: return "Clicks"
        case .adRequests: return "Ad Requests"
        case .ecpm: return "eCPM"
        case .matchRate: return "Match Rate"
        case .ctr: return "CTR"
        }
    }
}
