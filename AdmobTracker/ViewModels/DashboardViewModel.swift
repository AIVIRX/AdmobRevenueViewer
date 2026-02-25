import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var report: AdMobReport?
    @Published var previousReport: AdMobReport?
    @Published var errorMessage: String?
    @Published var appIconURLs: [String: URL] = [:]
    @Published var appPlatforms: [String: String] = [:]
    @Published var adUnitFormats: [String: String] = [:]
    @Published var adUnitAppIds: [String: String] = [:]

    private let apiClient: AdMobAPIClient
    private let appStoreClient: AppStoreLookupClient
    private var loadedAppMetadataAccountId: String?
    private var loadedAdUnitMetadataAccountId: String?

    init(apiClient: AdMobAPIClient, appStoreClient: AppStoreLookupClient? = nil) {
        self.apiClient = apiClient
        self.appStoreClient = appStoreClient ?? LiveAppStoreLookupClient()
    }

    func load(accountId: String, range: DateRange, compareRange: DateRange, timeZone: String?) async {
        isLoading = true
        errorMessage = nil
        previousReport = nil
        do {
            async let currentTask = apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
            async let previousTask = apiClient.fetchReport(accountId: accountId, range: compareRange, timeZone: timeZone)
            report = try await currentTask
            do {
                previousReport = try await previousTask
            } catch {
                previousReport = nil
            }
        } catch {
            errorMessage = "Unable to load report: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadAppMetadata(accountId: String) async {
        if loadedAppMetadataAccountId == accountId, !appIconURLs.isEmpty {
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
                    group.addTask {
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

    func loadAdUnitMetadata(accountId: String) async {
        if loadedAdUnitMetadataAccountId == accountId, !adUnitFormats.isEmpty {
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
