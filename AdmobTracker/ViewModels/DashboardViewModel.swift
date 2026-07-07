import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var report: AdMobReport?
    @Published var previousReport: AdMobReport?
    @Published var countrySummaries: [AdMobCountrySummary] = []
    @Published var errorMessage: String?
    @Published var appIconURLs: [String: URL] = [:]
    @Published var appPlatforms: [String: String] = [:]
    @Published var adUnitFormats: [String: String] = [:]
    @Published var adUnitAppIds: [String: String] = [:]

    private let apiClient: AdMobAPIClient
    private let appStoreClient: AppStoreLookupClient
    private let playStoreClient: PlayStoreLookupClient
    private var loadedAppMetadataAccountId: String?
    private var loadedAdUnitMetadataAccountId: String?

    init(apiClient: AdMobAPIClient, appStoreClient: AppStoreLookupClient? = nil, playStoreClient: PlayStoreLookupClient? = nil) {
        self.apiClient = apiClient
        self.appStoreClient = appStoreClient ?? LiveAppStoreLookupClient()
        self.playStoreClient = playStoreClient ?? LivePlayStoreLookupClient()
    }

    func load(accountId: String, range: DateRange, compareRange: DateRange, timeZone: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            async let currentTask = apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
            async let previousTask = apiClient.fetchReport(accountId: accountId, range: compareRange, timeZone: timeZone)
            async let countryTask = apiClient.fetchCountryReport(accountId: accountId, range: range, timeZone: timeZone)
            report = try await currentTask
            do {
                previousReport = try await previousTask
            } catch {
                // Keep prior comparison data if the refresh comparison fails.
            }
            do {
                countrySummaries = try await countryTask
            } catch {
                // Keep prior country data if the country report fails.
            }
        } catch is CancellationError {
            // Ignore cancellation errors from refresh/task invalidation.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Ignore URL cancellation errors surfaced as URLError.
        } catch {
            errorMessage = "Unable to load report: \(ErrorMessageFormatter.message(for: error))"
        }
        isLoading = false
    }

    func loadPreviousReport(accountId: String, range: DateRange, timeZone: String?) async {
        do {
            previousReport = try await apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
        } catch {
            // Keep prior comparison data if the refresh comparison fails.
        }
    }

    func fetchWidgetTrendReport(accountId: String, range: DateRange, timeZone: String?) async -> AdMobReport? {
        do {
            return try await apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
        } catch {
            return nil
        }
    }

    func loadAppMetadata(accountId: String, force: Bool = false) async {
        if !force, loadedAppMetadataAccountId == accountId, !appIconURLs.isEmpty {
            return
        }
        do {
            let apps = try await apiClient.fetchApps(accountId: accountId)
            var platforms: [String: String] = [:]
            for app in apps {
                if let platform = app.platform {
                    platforms[app.displayName] = platform
                }
            }

            var icons: [String: URL] = [:]
            try await withThrowingTaskGroup(of: (String, URL?).self) { group in
                for app in apps {
                    guard let appStoreId = app.appStoreId else { continue }
                    let name = app.displayName
                    let platform = app.platform?.uppercased()
                    group.addTask {
                        if platform == "ANDROID" {
                            let url = try await self.playStoreClient.fetchIconURL(packageName: appStoreId)
                            return (name, url)
                        }
                        let url = try await self.appStoreClient.fetchIconURL(appStoreId: appStoreId)
                        return (name, url)
                    }
                }

                for try await (name, url) in group {
                    if let url {
                        icons[name] = url
                    }
                }
            }

            await MainActor.run {
                self.appPlatforms = platforms
                self.appIconURLs = icons
                self.loadedAppMetadataAccountId = accountId
            }
        } catch {
            // Keep metadata empty if the call fails.
        }
    }

    func loadAdUnitMetadata(accountId: String, force: Bool = false) async {
        if !force, loadedAdUnitMetadataAccountId == accountId, !adUnitFormats.isEmpty {
            return
        }
        do {
            let adUnits = try await apiClient.fetchAdUnits(accountId: accountId)
            var formats: [String: String] = [:]
            var appIds: [String: String] = [:]
            for unit in adUnits {
                formats[unit.displayName] = unit.adFormat
                appIds[unit.displayName] = unit.appId
            }
            await MainActor.run {
                self.adUnitFormats = formats
                self.adUnitAppIds = appIds
                self.loadedAdUnitMetadataAccountId = accountId
            }
        } catch {
            // Keep metadata empty if the call fails.
        }
    }
}
