import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel: DashboardViewModel
    @State private var selectedMetric: AppMetric = .earnings
    @State private var selectedAdUnitMetric: AppMetric = .earnings
    @State private var showAllApps = false
    @State private var showAllAdUnits = false

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DateRangePills(selection: $appState.dateRangeOption)
                        .onChange(of: appState.dateRangeOption) { _, newValue in
                            appState.dateRange = newValue.range()
                            Task { await loadReportIfNeeded() }
                        }
                    heroCard
                    metricsGrid
                    if shouldShowChart {
                        chartSection
                    }
                    SectionHeader(title: "Apps", subtitle: "Performance by app")
                    metricPills
                    appsList
                    if appSummaries.count > 5 {
                        Button(showAllApps ? "Show Less" : "Show More") {
                            withAnimation(.easeInOut) {
                                showAllApps.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SectionHeader(title: "Ad Units", subtitle: "Performance by ad unit")
                    adUnitMetricPills
                    adUnitsList
                    if adUnitSummaries.count > 5 {
                        Button(showAllAdUnits ? "Show Less" : "Show More") {
                            withAnimation(.easeInOut) {
                                showAllAdUnits.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadReportIfNeeded()
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
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.63, blue: 0.60), Color(red: 0.12, green: 0.36, blue: 0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 180, height: 180)
                        .offset(x: 120, y: -90)
                )

            VStack(alignment: .leading, spacing: 10) {
                Text("Estimated earnings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(formatCurrency(totals?.estimatedEarnings))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    if let delta = percentChange(current: totals?.estimatedEarnings, previous: viewModel.previousReport?.totals.estimatedEarnings) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(formatDelta(delta))
                        Text(comparisonLabel)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Image(systemName: "arrow.up.right")
                            .opacity(0)
                        Text("--")
                            .opacity(0)
                        Text(comparisonLabel)
                            .foregroundStyle(.white.opacity(0.7))
                            .opacity(0)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(heroDeltaColor)
                Text(appState.dateRangeOption.rawValue)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
        }
        .frame(height: 160)
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    private var metricsGrid: some View {
        let totals = viewModel.report?.totals
        let previousTotals = viewModel.previousReport?.totals
        let matchRateValue = matchRate(for: totals)
        let previousMatchRate = matchRate(for: previousTotals)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Impressions",
                value: formatInt(totals?.impressions),
                subtitle: "Total",
                systemImage: "eye",
                delta: percentChange(current: totals?.impressions, previous: previousTotals?.impressions),
                deltaLabel: comparisonLabel
            )
            MetricTile(
                title: "Clicks",
                value: formatInt(totals?.clicks),
                subtitle: "Total",
                systemImage: "cursorarrow.click",
                delta: percentChange(current: totals?.clicks, previous: previousTotals?.clicks),
                deltaLabel: comparisonLabel
            )
            MetricTile(
                title: "Ad Requests",
                value: formatInt(totals?.adRequests),
                subtitle: "Total",
                systemImage: "antenna.radiowaves.left.and.right",
                delta: percentChange(current: totals?.adRequests, previous: previousTotals?.adRequests),
                deltaLabel: comparisonLabel
            )
            MetricTile(
                title: "Match Rate",
                value: formatPercent(matchRateValue),
                subtitle: "Matched / Requests",
                systemImage: "checkmark.seal",
                delta: percentChange(current: matchRateValue, previous: previousMatchRate),
                deltaLabel: comparisonLabel
            )
            MetricTile(
                title: "Observed eCPM",
                value: formatCurrency(totals?.observedECPM),
                subtitle: "Per 1K",
                systemImage: "speedometer",
                delta: percentChange(current: totals?.observedECPM, previous: previousTotals?.observedECPM),
                deltaLabel: comparisonLabel
            )
        }
    }

    private var metricPills: some View {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppMetric.allCases, id: \.self) { metric in
                            AppFilterPill(title: metric.title, isSelected: selectedMetric == metric) {
                                selectedMetric = metric
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var adUnitMetricPills: some View {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppMetric.allCases, id: \.self) { metric in
                            AppFilterPill(title: metric.title, isSelected: selectedAdUnitMetric == metric) {
                                selectedAdUnitMetric = metric
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
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
                VStack(spacing: 12) {
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
                VStack(spacing: 12) {
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

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Earnings Trend", subtitle: "Last \(appState.dateRangeOption.rawValue)")
            if let data = chartData, !data.isEmpty {
                EarningsChartView(
                    data: data,
                    domain: chartDomain,
                    currencyCode: appState.selectedAccount?.currencyCode ?? "USD"
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

    private var shouldShowChart: Bool {
        switch appState.dateRangeOption {
        case .today, .yesterday:
            return false
        case .last7Days, .thisMonth, .lastMonth:
            return true
        }
    }

    private var chartData: [ChartPoint]? {
        guard let report = viewModel.report else { return nil }
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


    private func loadReportIfNeeded() async {
        guard let account = appState.selectedAccount else { return }
        let range = appState.dateRange
        let compareRange = appState.dateRangeOption.comparisonRange(for: range)
        if let prefetched = appState.prefetchedReport,
           prefetched.accountId == account.id,
           prefetched.range == range,
           prefetched.timeZone == account.reportingTimeZone {
            viewModel.report = prefetched.report
            viewModel.errorMessage = nil
            viewModel.isLoading = false
            viewModel.previousReport = nil
            Task { await viewModel.loadAppMetadata(accountId: account.id) }
            Task { await viewModel.loadAdUnitMetadata(accountId: account.id) }
            return
        }
        await viewModel.load(accountId: account.id, range: range, compareRange: compareRange, timeZone: account.reportingTimeZone)
        Task { await viewModel.loadAppMetadata(accountId: account.id) }
        Task { await viewModel.loadAdUnitMetadata(accountId: account.id) }
        if let report = viewModel.report {
            appState.prefetchedReport = PrefetchedReport(
                accountId: account.id,
                range: range,
                timeZone: account.reportingTimeZone,
                report: report
            )
        }
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

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func matchRate(for totals: AdMobMetrics?) -> Double? {
        guard let totals, totals.adRequests > 0 else { return nil }
        return Double(totals.matchedRequests) / Double(totals.adRequests)
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
            return AppSummary(
                appName: appName,
                earnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: ecpm,
                matchRate: matchRate,
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
            case .ecpm:
                return lhs.eCPM > rhs.eCPM
            case .matchRate:
                return lhs.matchRate > rhs.matchRate
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
            let adFormat = viewModel.adUnitFormats[adUnitName]
            return AdUnitSummary(
                adUnitName: adUnitName,
                appName: appName,
                earnings: earnings,
                impressions: impressions,
                clicks: clicks,
                eCPM: ecpm,
                matchRate: matchRate,
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
            case .ecpm:
                return lhs.eCPM > rhs.eCPM
            case .matchRate:
                return lhs.matchRate > rhs.matchRate
            }
        }
    }

    private var visibleAppSummaries: [AppSummary] {
        showAllApps ? appSummaries : Array(appSummaries.prefix(5))
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
        case .ecpm:
            return formatCurrency(summary.eCPM)
        case .matchRate:
            return formatPercent(summary.matchRate)
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
        case .ecpm:
            return formatCurrency(summary.eCPM)
        case .matchRate:
            return formatPercent(summary.matchRate)
        }
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
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private var heroDeltaColor: Color {
        guard let delta = percentChange(current: viewModel.report?.totals.estimatedEarnings,
                                        previous: viewModel.previousReport?.totals.estimatedEarnings) else {
            return Color.white.opacity(0.85)
        }
        return delta >= 0 ? Color.green.opacity(0.95) : Color.red.opacity(0.95)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
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

    @State private var selectedPoint: ChartPoint?

    var body: some View {
        Chart(data) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Earnings", point.earnings)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)

            PointMark(
                x: .value("Date", point.date),
                y: .value("Earnings", point.earnings)
            )
            .symbolSize(22)
            .foregroundStyle(Color.accentColor.opacity(0.85))

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

            if let selectedPoint, selectedPoint.date == point.date {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(Color.primary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
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
                                .fill(Color(uiColor: .secondarySystemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
                        )
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...max(1, data.map { $0.earnings }.max() ?? 1))
        .frame(height: 200)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
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
                                let origin = geometry[plotFrame].origin
                                let location = CGPoint(
                                    x: value.location.x - origin.x,
                                    y: value.location.y - origin.y
                                )
                                if let date: Date = proxy.value(atX: location.x),
                                   let nearest = nearestPoint(to: date),
                                   let snappedX = proxy.position(forX: nearest.date) {
                                    let dx = abs(snappedX - location.x)
                                    if dx < 18 {
                                        selectedPoint = nearest
                                    } else {
                                        selectedPoint = nil
                                    }
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
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let delta: Double?
    let deltaLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let delta {
                HStack(spacing: 6) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(formatDelta(delta))
                    Text(deltaLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        )
    }

    private func formatDelta(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }
}

private struct AppSummary: Identifiable {
    let id = UUID()
    let appName: String
    let earnings: Double
    let impressions: Int
    let clicks: Int
    let eCPM: Double
    let matchRate: Double
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
    let eCPM: Double
    let matchRate: Double
    let adFormat: String?
}

private struct AppFilterPill: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
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
                Text(metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
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
                Text(metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct AdUnitIconView: View {
    let adFormat: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.18))
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1)
        )
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
    case ecpm
    case matchRate

    var title: String {
        switch self {
        case .earnings: return "Earnings"
        case .impressions: return "Impressions"
        case .clicks: return "Clicks"
        case .ecpm: return "eCPM"
        case .matchRate: return "Match Rate"
        }
    }
}
