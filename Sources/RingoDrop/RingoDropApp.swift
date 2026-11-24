//
//  RingoDropApp.swift
//  RingoDrop (りんご雫) — Native macOS SwiftUI Liquid Glass App Store IPA Downloader
//
//  https://github.com/zorroforever/RingoDrop
//  License: MIT
//

import AppKit
import Combine
import Foundation
import Security
import SwiftUI

// MARK: - Storefront Region Definition (CN 🇨🇳 / JP 🇯🇵 / US 🇺🇸)

enum StoreRegion: String, CaseIterable, Identifiable, Codable {
    case cn = "CN"
    case jp = "JP"
    case us = "US"

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .cn: return "🇨🇳"
        case .jp: return "🇯🇵"
        case .us: return "🇺🇸"
        }
    }

    var shortName: String {
        switch self {
        case .cn: return "国区"
        case .jp: return "日区"
        case .us: return "美区"
        }
    }

    var cuteLabel: String {
        switch self {
        case .cn: return "🇨🇳 国区"
        case .jp: return "🇯🇵 日区"
        case .us: return "🇺🇸 美区"
        }
    }

    var jpSubtitle: String {
        switch self {
        case .cn: return "中国本土ストア"
        case .jp: return "日本ストア"
        case .us: return "米国ストア"
        }
    }

    var freeWord: String {
        switch self {
        case .cn: return "免费"
        case .jp: return "無料"
        case .us: return "Free"
        }
    }

    var accentColor: Color {
        switch self {
        case .cn: return Color(red: 1.0, green: 0.42, blue: 0.52)
        case .jp: return Color(red: 0.38, green: 0.82, blue: 1.0)
        case .us: return Color(red: 0.62, green: 0.58, blue: 1.0)
        }
    }
}

// MARK: - Download Mode for Delisted & Normal Apps

enum DelistedDownloadStrategy: String, CaseIterable, Identifiable {
    case smartAuto = "SMART"
    case purchasedDirect = "PURCHASED_DIRECT"
    case freeForceClaim = "FREE_CLAIM"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartAuto:
            return "✨ 智能模式 (自动领券 + 已购穿透回退)"
        case .purchasedDirect:
            return "🔓 已购下架直下 (仅传 -i 数字ID 绕过目录)"
        case .freeForceClaim:
            return "🎁 未购免费领券直下 (强制申领免费许可并下载)"
        }
    }

    var shortBadge: String {
        switch self {
        case .smartAuto: return "智能一键"
        case .purchasedDirect: return "已购穿透"
        case .freeForceClaim: return "免费领券"
        }
    }
}

// MARK: - Data Models

struct RegionListingInfo: Hashable {
    let region: StoreRegion
    var version: String
    var priceText: String
    var isFree: Bool
}

struct StoreAppItem: Identifiable, Hashable {
    let trackId: Int64
    var id: Int64 { trackId }
    var trackName: String
    var bundleId: String
    var sellerName: String
    var artworkUrl512: String
    var primaryGenreName: String
    var fileSizeBytes: String?

    // Per-region listings (CN / JP / US)
    var listings: [StoreRegion: RegionListingInfo] = [:]

    var fallbackVersion: String?
    var isDelistedOrRecovered: Bool = false
    var presetNote: String?

    var displayVersion: String {
        listings[.cn]?.version
            ?? listings[.jp]?.version
            ?? listings[.us]?.version
            ?? fallbackVersion
            ?? "最新版"
    }

    var isFreeInAnyRegion: Bool {
        listings.values.contains(where: \.isFree)
    }

    var formattedSize: String {
        guard let str = fileSizeBytes, let bytes = Double(str), bytes > 0 else {
            return ""
        }
        let mb = bytes / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}

struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesRawItem]
}

struct ITunesRawItem: Decodable {
    let trackId: Int64?
    let trackName: String?
    let bundleId: String?
    let sellerName: String?
    let artworkUrl512: String?
    let artworkUrl100: String?
    let version: String?
    let price: Double?
    let formattedPrice: String?
    let primaryGenreName: String?
    let fileSizeBytes: String?
}

struct RegionAccountSlot: Identifiable {
    let region: StoreRegion
    var id: String { region.rawValue }
    var email: String = ""
    var displayName: String = ""
    var hasSavedPassword: Bool = false
    var hasCookieSnapshot: Bool = false
}

struct ActiveAccountStatus {
    var isLoggedIn: Bool = false
    var email: String = ""
    var name: String = ""
    var detectedRegion: StoreRegion?
    var rawOutput: String = ""
}

struct DownloadTaskState {
    var isRunning: Bool = false
    var statusText: String = ""
    var downloadedFilePath: String?
    var isError: Bool = false
}

// MARK: - Keychain Helper (Owned by RingoDrop.app — Zero Modal Prompts)

enum RingoKeychain {
    private static let service = "moe.haruka.ringodrop.accounts"

    static func savePassword(_ password: String, for accountKey: String) {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func loadPassword(for accountKey: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for accountKey: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Built-in Delisted / Cross-Region Preset Catalog

let kPresetDelistedApps: [StoreAppItem] = [
    StoreAppItem(
        trackId: 932747118,
        trackName: "Shadowrocket",
        bundleId: "com.liguangming.Shadowrocket",
        sellerName: "Shadow Launch Technology Limited",
        artworkUrl512: "",
        primaryGenreName: "网络工具",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "2.2.x",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美在架 · 纯数字 ID 932747118 支持已购账号穿透直下最新版"
    ),
    StoreAppItem(
        trackId: 686449807,
        trackName: "Telegram Messenger",
        bundleId: "ph.telegra.Telegraph",
        sellerName: "Telegram FZ-LLC",
        artworkUrl512: "",
        primaryGenreName: "社交沟通",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "最新版",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美免费 · 国区老号已购直下，或日美账号一键免费领券下载"
    ),
    StoreAppItem(
        trackId: 1443988620,
        trackName: "Quantumult X",
        bundleId: "com.crossutility.quantumult-x",
        sellerName: "Cross Utility Limited",
        artworkUrl512: "",
        primaryGenreName: "网络工具",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "最新版",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美在架 · 已购账号通过数字 ID 1443988620 穿透直下"
    ),
    StoreAppItem(
        trackId: 1442620678,
        trackName: "Surge 5",
        bundleId: "com.nssurge.inc.surge-ios",
        sellerName: "Surge Networks Limited",
        artworkUrl512: "",
        primaryGenreName: "网络工具",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "最新版",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美免费本体 · 支持一键免费领券入库并下载 IPA"
    ),
    StoreAppItem(
        trackId: 1373567447,
        trackName: "Loon",
        bundleId: "com.ruikq.decar",
        sellerName: "Loon Team",
        artworkUrl512: "",
        primaryGenreName: "网络工具",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "最新版",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美在架 · 纯数字 ID 1373567447 支持已购账号直下"
    ),
    StoreAppItem(
        trackId: 1596063349,
        trackName: "Stash",
        bundleId: "ws.stash.app.ios",
        sellerName: "Stash Networks",
        artworkUrl512: "",
        primaryGenreName: "网络工具",
        fileSizeBytes: nil,
        listings: [:],
        fallbackVersion: "最新版",
        isDelistedOrRecovered: true,
        presetNote: "国区已下架 / 日美在架 · 纯数字 ID 1596063349 支持已购账号直下"
    )
]

// MARK: - Main ViewModel

@MainActor
final class RingoDropViewModel: ObservableObject {
    // Search & Multi-Country Selection
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var searchResults: [StoreAppItem] = kPresetDelistedApps
    @Published var selectedSearchRegions: Set<StoreRegion> = [.cn, .jp, .us]
    @Published var resultFilterRegion: String = "ALL" // ALL, CN, JP, US, DELISTED
    @Published var enableDelistedRadar: Bool = true

    // Download Strategy
    @Published var downloadStrategy: DelistedDownloadStrategy = .smartAuto

    // Settings
    @Published var proxyEnabled: Bool {
        didSet { UserDefaults.standard.set(proxyEnabled, forKey: "ringodrop.proxyEnabled") }
    }
    @Published var proxyURL: String {
        didSet { UserDefaults.standard.set(proxyURL, forKey: "ringodrop.proxyURL") }
    }
    @Published var ipatoolPath: String {
        didSet { UserDefaults.standard.set(ipatoolPath, forKey: "ringodrop.ipatoolPath") }
    }
    @Published var downloadDirectory: String {
        didSet { UserDefaults.standard.set(downloadDirectory, forKey: "ringodrop.downloadDir") }
    }

    // 3-Country Account Slots (CN / JP / US)
    @Published var accountSlots: [StoreRegion: RegionAccountSlot] = [:]
    @Published var activeAccount = ActiveAccountStatus()
    @Published var activeRegionTag: StoreRegion = .cn {
        didSet { UserDefaults.standard.set(activeRegionTag.rawValue, forKey: "ringodrop.activeRegion") }
    }

    // Account Sheet Form
    @Published var editingRegion: StoreRegion = .cn
    @Published var loginEmail: String = ""
    @Published var loginPassword: String = ""
    @Published var login2FACode: String = ""
    @Published var savePasswordInKeychain: Bool = true
    @Published var isLoggingIn: Bool = false
    @Published var showAccountSheet: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var showDelistedExtractorSheet: Bool = false

    // Delisted Extractor Sheet Form
    @Published var extractorInput: String = ""
    @Published var extractorName: String = ""
    @Published var extractorTargetRegion: StoreRegion = .cn
    @Published var extractorStrategy: DelistedDownloadStrategy = .smartAuto

    // Per-app task & version states
    @Published var downloadStates: [Int64: DownloadTaskState] = [:]
    @Published var appVersions: [Int64: [String]] = [:]
    @Published var loadingVersionsFor: Set<Int64> = []
    @Published var selectedVersionForApp: [Int64: String] = [:]

    // Console log
    @Published var logs: [String] = []
    @Published var showConsole: Bool = false

    init() {
        let savedProxyEnabled = UserDefaults.standard.object(forKey: "ringodrop.proxyEnabled") as? Bool ?? true
        let savedProxyURL = UserDefaults.standard.string(forKey: "ringodrop.proxyURL") ?? "http://127.0.0.1:7890"
        let detectedIpatool = Self.detectIpatoolBinary()
        let savedIpatool = UserDefaults.standard.string(forKey: "ringodrop.ipatoolPath") ?? detectedIpatool
        let defaultDlDir = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let savedDlDir = UserDefaults.standard.string(forKey: "ringodrop.downloadDir") ?? defaultDlDir
        let savedRegionRaw = UserDefaults.standard.string(forKey: "ringodrop.activeRegion") ?? "CN"

        self.proxyEnabled = savedProxyEnabled
        self.proxyURL = savedProxyURL
        self.ipatoolPath = FileManager.default.isExecutableFile(atPath: savedIpatool) ? savedIpatool : detectedIpatool
        self.downloadDirectory = savedDlDir
        self.activeRegionTag = StoreRegion(rawValue: savedRegionRaw) ?? .cn

        reloadAccountSlots()
        appendLog("🍎 RingoDrop (りんご雫) 已启动 | ipatool: \(self.ipatoolPath)")

        Task {
            await refreshAccountInfo()
            await hydrateIconsAndListings()
        }
    }

    static func detectIpatoolBinary() -> String {
        let candidates = [
            "/opt/homebrew/bin/ipatool",
            "/usr/local/bin/ipatool",
            (NSHomeDirectory() as NSString).appendingPathComponent("bin/ipatool")
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/ipatool"
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logs.append(line)
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    // MARK: - 3-Country Account Slots Management (CN / JP / US)

    private var ipatoolDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".ipatool")
    }

    private func cookieFilePath(for region: StoreRegion? = nil) -> String {
        if let reg = region {
            return (ipatoolDir as NSString).appendingPathComponent("cookies.\(reg.rawValue)")
        }
        return (ipatoolDir as NSString).appendingPathComponent("cookies")
    }

    func reloadAccountSlots() {
        var map: [StoreRegion: RegionAccountSlot] = [:]
        for reg in StoreRegion.allCases {
            let email = UserDefaults.standard.string(forKey: "ringodrop.slot.\(reg.rawValue).email") ?? ""
            let name = UserDefaults.standard.string(forKey: "ringodrop.slot.\(reg.rawValue).name") ?? ""
            let hasPwd = !email.isEmpty && (RingoKeychain.loadPassword(for: "\(reg.rawValue):\(email)") != nil)
            let hasCookie = FileManager.default.fileExists(atPath: cookieFilePath(for: reg))
            map[reg] = RegionAccountSlot(
                region: reg,
                email: email,
                displayName: name,
                hasSavedPassword: hasPwd,
                hasCookieSnapshot: hasCookie
            )
        }
        accountSlots = map
    }

    func saveSlot(region: StoreRegion, email: String, name: String, password: String?) {
        UserDefaults.standard.set(email, forKey: "ringodrop.slot.\(region.rawValue).email")
        UserDefaults.standard.set(name, forKey: "ringodrop.slot.\(region.rawValue).name")
        if let pwd = password, !pwd.isEmpty, savePasswordInKeychain {
            RingoKeychain.savePassword(pwd, for: "\(region.rawValue):\(email)")
        }
        // Snapshot cookies file for 2FA session preservation
        let mainCookies = cookieFilePath(for: nil)
        let regionCookies = cookieFilePath(for: region)
        if FileManager.default.fileExists(atPath: mainCookies) {
            try? FileManager.default.removeItem(atPath: regionCookies)
            try? FileManager.default.copyItem(atPath: mainCookies, toPath: regionCookies)
        }
        reloadAccountSlots()
    }

    func removeSlot(region: StoreRegion) {
        if let email = accountSlots[region]?.email, !email.isEmpty {
            RingoKeychain.deletePassword(for: "\(region.rawValue):\(email)")
        }
        UserDefaults.standard.removeObject(forKey: "ringodrop.slot.\(region.rawValue).email")
        UserDefaults.standard.removeObject(forKey: "ringodrop.slot.\(region.rawValue).name")
        try? FileManager.default.removeItem(atPath: cookieFilePath(for: region))
        reloadAccountSlots()
    }

    func prepareLoginSheet(for region: StoreRegion) {
        editingRegion = region
        let slot = accountSlots[region]
        loginEmail = slot?.email ?? ""
        if let email = slot?.email, !email.isEmpty,
           let savedPwd = RingoKeychain.loadPassword(for: "\(region.rawValue):\(email)")
        {
            loginPassword = savedPwd
        } else {
            loginPassword = ""
        }
        login2FACode = ""
        showAccountSheet = true
    }

    func switchOrOpenAccount(for region: StoreRegion) async {
        guard let slot = accountSlots[region], !slot.email.isEmpty else {
            prepareLoginSheet(for: region)
            return
        }

        // If already active
        if activeAccount.isLoggedIn && activeAccount.email.lowercased() == slot.email.lowercased() {
            activeRegionTag = region
            appendLog("✨ 当前已处于 \(region.cuteLabel) 账号 (\(slot.email))")
            return
        }

        // Check if we have saved password in RingoKeychain for 1-click switch
        if let pwd = RingoKeychain.loadPassword(for: "\(region.rawValue):\(slot.email)"), !pwd.isEmpty {
            isLoggingIn = true
            appendLog("🔄 正在一键切换至 \(region.cuteLabel) 账号: \(slot.email)...")

            // Restore that region's 2FA trusted cookie snapshot first
            let mainCookies = cookieFilePath(for: nil)
            let regionCookies = cookieFilePath(for: region)
            if FileManager.default.fileExists(atPath: regionCookies) {
                try? FileManager.default.removeItem(atPath: mainCookies)
                try? FileManager.default.copyItem(atPath: regionCookies, toPath: mainCookies)
            }

            let res = await runIpatool(args: [
                "auth", "login",
                "-e", slot.email,
                "-p", pwd,
                "--format", "json",
                "--non-interactive"
            ])
            isLoggingIn = false

            if res.exitCode == 0 {
                activeRegionTag = region
                await refreshAccountInfo(assignToRegion: region)
                appendLog("✅ 已成功切换至 \(region.cuteLabel) 账号: \(slot.email)")
                return
            } else {
                appendLog("ℹ️ \(region.cuteLabel) 账号需要刷新验证码，已打开登录窗口")
            }
        }

        prepareLoginSheet(for: region)
    }

    // MARK: - Search Region Toggles & Filtering

    func toggleSearchRegion(_ region: StoreRegion) {
        if selectedSearchRegions.contains(region) {
            if selectedSearchRegions.count > 1 {
                selectedSearchRegions.remove(region)
            }
        } else {
            selectedSearchRegions.insert(region)
        }
    }

    var filteredResults: [StoreAppItem] {
        switch resultFilterRegion {
        case "CN":
            return searchResults.filter { $0.listings[.cn] != nil || $0.isDelistedOrRecovered }
        case "JP":
            return searchResults.filter { $0.listings[.jp] != nil || $0.isDelistedOrRecovered }
        case "US":
            return searchResults.filter { $0.listings[.us] != nil || $0.isDelistedOrRecovered }
        case "DELISTED":
            return searchResults.filter { $0.listings[.cn] == nil || $0.isDelistedOrRecovered }
        default:
            return searchResults
        }
    }

    // MARK: - Network Helper with Configurable Proxy

    private func makeURLSession() -> URLSession {
        guard proxyEnabled,
              let url = URL(string: proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host,
              let port = url.port
        else {
            return URLSession.shared
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port
        ]
        return URLSession(configuration: config)
    }

    private func fetchData(from url: URL) async throws -> Data {
        let session = makeURLSession()
        do {
            let (data, _) = try await session.data(from: url)
            return data
        } catch {
            if proxyEnabled {
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            }
            throw error
        }
    }

    // MARK: - Hydrate Icons & Multi-Region Listings (CN / JP / US)

    func hydrateIconsAndListings() async {
        let allIDs = searchResults.map { String($0.trackId) }
        guard !allIDs.isEmpty else { return }
        let chunk = allIDs.prefix(40).joined(separator: ",")

        for reg in StoreRegion.allCases {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(chunk)&country=\(reg.rawValue)") else { continue }
            do {
                let data = try await fetchData(from: url)
                let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
                var map: [Int64: ITunesRawItem] = [:]
                for item in decoded.results {
                    if let id = item.trackId { map[id] = item }
                }
                for idx in searchResults.indices {
                    let tid = searchResults[idx].trackId
                    if let raw = map[tid] {
                        if searchResults[idx].artworkUrl512.isEmpty {
                            searchResults[idx].artworkUrl512 = raw.artworkUrl512 ?? raw.artworkUrl100 ?? ""
                        }
                        if searchResults[idx].fileSizeBytes == nil {
                            searchResults[idx].fileSizeBytes = raw.fileSizeBytes
                        }
                        let priceVal = raw.price ?? 0
                        let priceStr = raw.formattedPrice ?? (priceVal == 0 ? reg.freeWord : "\(priceVal)")
                        searchResults[idx].listings[reg] = RegionListingInfo(
                            region: reg,
                            version: raw.version ?? "在架",
                            priceText: priceStr,
                            isFree: priceVal == 0
                        )
                    }
                }
            } catch {
                // Ignore individual region hydration error
            }
        }
    }

    // MARK: - Load Account's Purchased Apps (ipatool list-purchases + Presets)

    func loadPurchasedApps() async {
        isSearching = true
        appendLog("📦 正在拉取当前账号 (\(activeAccount.email.isEmpty ? "默认" : activeAccount.email)) 的已购应用列表...")
        let res = await runIpatool(args: [
            "list-purchases",
            "-l", "100",
            "--format", "json",
            "--non-interactive"
        ])

        var items: [StoreAppItem] = kPresetDelistedApps
        var seen: Set<Int64> = Set(items.map(\.trackId))

        if let data = res.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apps = json["apps"] as? [[String: Any]]
        {
            for appDict in apps {
                let rawID = (appDict["id"] as? Int64)
                    ?? (appDict["id"] as? Int).map(Int64.init)
                    ?? 0
                guard rawID > 0, !seen.contains(rawID) else { continue }
                seen.insert(rawID)
                let name = (appDict["name"] as? String) ?? "已购应用 #\(rawID)"
                let bundle = (appDict["bundleID"] as? String) ?? ""
                let ver = (appDict["version"] as? String) ?? "已购"
                items.append(
                    StoreAppItem(
                        trackId: rawID,
                        trackName: name,
                        bundleId: bundle,
                        sellerName: "账号历史已购",
                        artworkUrl512: "",
                        primaryGenreName: "已购",
                        fileSizeBytes: nil,
                        listings: [:],
                        fallbackVersion: ver,
                        isDelistedOrRecovered: true,
                        presetNote: "账号已购项目 · 即使商店已下架也可通过 -i \(rawID) 直连下载"
                    )
                )
            }
            appendLog("✅ 已加载 \(apps.count) 款已购应用（并自动补全中/日/美三区状态）")
        } else {
            let errMsg = Self.extractErrorMessage(from: res.stdout + "\n" + res.stderr)
            appendLog("⚠️ 拉取已购列表: \(errMsg)")
        }

        searchResults = items
        await hydrateIconsAndListings()
        isSearching = false
    }

    // MARK: - Multi-Country Parallel Search + Single-Country Delisted Radar

    func performSearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = kPresetDelistedApps
            await hydrateIconsAndListings()
            return
        }

        isSearching = true
        let activeRegions = StoreRegion.allCases.filter { selectedSearchRegions.contains($0) }
        let regionNames = activeRegions.map(\.cuteLabel).joined(separator: " + ")
        appendLog("🔍 正在搜索 [\(regionNames)]: \"\(trimmed)\"")

        let extractedID = Self.extractNumericAppID(from: trimmed)

        // Fetch all selected regions concurrently
        var perRegionResults: [StoreRegion: [ITunesRawItem]] = [:]
        await withTaskGroup(of: (StoreRegion, [ITunesRawItem]).self) { group in
            for reg in activeRegions {
                group.addTask {
                    let list = await self.fetchStoreItems(query: trimmed, numericID: extractedID, country: reg.rawValue)
                    return (reg, list)
                }
            }
            for await (reg, list) in group {
                perRegionResults[reg] = list
            }
        }

        var mergedMap: [Int64: StoreAppItem] = [:]
        var orderedIDs: [Int64] = []

        for reg in activeRegions {
            let list = perRegionResults[reg] ?? []
            for raw in list {
                guard let tid = raw.trackId else { continue }
                let priceVal = raw.price ?? 0
                let priceStr = raw.formattedPrice ?? (priceVal == 0 ? reg.freeWord : "\(priceVal)")
                let listing = RegionListingInfo(
                    region: reg,
                    version: raw.version ?? "在架",
                    priceText: priceStr,
                    isFree: priceVal == 0
                )

                if var existing = mergedMap[tid] {
                    existing.listings[reg] = listing
                    if existing.artworkUrl512.isEmpty {
                        existing.artworkUrl512 = raw.artworkUrl512 ?? raw.artworkUrl100 ?? ""
                    }
                    if existing.fileSizeBytes == nil {
                        existing.fileSizeBytes = raw.fileSizeBytes
                    }
                    mergedMap[tid] = existing
                } else {
                    orderedIDs.append(tid)
                    mergedMap[tid] = StoreAppItem(
                        trackId: tid,
                        trackName: raw.trackName ?? "App #\(tid)",
                        bundleId: raw.bundleId ?? "",
                        sellerName: raw.sellerName ?? "",
                        artworkUrl512: raw.artworkUrl512 ?? raw.artworkUrl100 ?? "",
                        primaryGenreName: raw.primaryGenreName ?? "App",
                        fileSizeBytes: raw.fileSizeBytes,
                        listings: [reg: listing]
                    )
                }
            }
        }

        // Single-Country Delisted App Radar:
        // When user only selected 1 country (e.g. CN) and searches a delisted app (e.g. Shadowrocket / Telegram),
        // CN returns 0 results. Automatically query global fallback metadata (US/JP) to recover its numeric App ID
        // so the user can download the delisted app right under their single country account!
        if enableDelistedRadar {
            let lower = trimmed.lowercased()
            for preset in kPresetDelistedApps {
                if preset.trackName.lowercased().contains(lower)
                    || preset.bundleId.lowercased().contains(lower)
                    || (lower.contains("小火箭") && preset.trackId == 932747118)
                {
                    if mergedMap[preset.trackId] == nil {
                        orderedIDs.insert(preset.trackId, at: 0)
                        mergedMap[preset.trackId] = preset
                    }
                }
            }

            if mergedMap.isEmpty {
                let fallbackRegions = StoreRegion.allCases.filter { !selectedSearchRegions.contains($0) }
                for fbReg in fallbackRegions {
                    let recovered = await fetchStoreItems(query: trimmed, numericID: extractedID, country: fbReg.rawValue)
                    for raw in recovered.prefix(8) {
                        guard let tid = raw.trackId, mergedMap[tid] == nil else { continue }
                        orderedIDs.append(tid)
                        let priceVal = raw.price ?? 0
                        let priceStr = raw.formattedPrice ?? (priceVal == 0 ? fbReg.freeWord : "\(priceVal)")
                        let listing = RegionListingInfo(
                            region: fbReg,
                            version: raw.version ?? "在架",
                            priceText: priceStr,
                            isFree: priceVal == 0
                        )
                        mergedMap[tid] = StoreAppItem(
                            trackId: tid,
                            trackName: raw.trackName ?? "App #\(tid)",
                            bundleId: raw.bundleId ?? "",
                            sellerName: raw.sellerName ?? "",
                            artworkUrl512: raw.artworkUrl512 ?? raw.artworkUrl100 ?? "",
                            primaryGenreName: raw.primaryGenreName ?? "已下架反查",
                            fileSizeBytes: raw.fileSizeBytes,
                            listings: [fbReg: listing],
                            isDelistedOrRecovered: true,
                            presetNote: "🔮 当前所选区服已下架 · 已通过跨区雷达定位数字 ID \(tid)，支持单国账号穿透下载"
                        )
                    }
                    if !mergedMap.isEmpty {
                        appendLog("🔮 单国下架雷达已从 \(fbReg.cuteLabel) 档案库反查出 \(mergedMap.count) 款下架应用的数字 ID")
                        break
                    }
                }
            }
        }

        // If user entered a pure numeric App ID delisted everywhere, still build a direct-extraction card!
        if let explicitID = extractedID, mergedMap[explicitID] == nil {
            orderedIDs.insert(explicitID, at: 0)
            mergedMap[explicitID] = StoreAppItem(
                trackId: explicitID,
                trackName: "已下架应用 (ID: \(explicitID))",
                bundleId: "纯数字 ID 穿透模式",
                sellerName: "Apple CDN 直连提取",
                artworkUrl512: "",
                primaryGenreName: "下架提取",
                fileSizeBytes: nil,
                listings: [:],
                fallbackVersion: "CDN 最新版",
                isDelistedOrRecovered: true,
                presetNote: "🔮 商店前端已完全隐藏 · 直接传 -i \(explicitID) 从 Apple CDN 提取 IPA"
            )
        }

        searchResults = orderedIDs.compactMap { mergedMap[$0] }
        await hydrateIconsAndListings()
        isSearching = false
        appendLog("✅ 搜索完成: 共找到 \(searchResults.count) 款应用")
    }

    static func extractNumericAppID(from input: String) -> Int64? {
        if let direct = Int64(input), input.count >= 6 {
            return direct
        }
        if let range = input.range(of: #"id(\d{6,15})"#, options: .regularExpression) {
            let digits = input[range].dropFirst(2)
            return Int64(digits)
        }
        return nil
    }

    private func fetchStoreItems(query: String, numericID: Int64?, country: String) async -> [ITunesRawItem] {
        var urls: [URL] = []
        if let nid = numericID,
           let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(nid)&country=\(country)")
        {
            urls.append(lookupURL)
        }
        let isBundleID = query.contains(".") && !query.contains(" ")
        if isBundleID,
           let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let bundleURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&country=\(country)")
        {
            urls.append(bundleURL)
        }
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&country=\(country)&entity=software,iPadSoftware&limit=25")
        {
            urls.append(searchURL)
        }

        var collected: [ITunesRawItem] = []
        var seen: Set<Int64> = []

        for url in urls {
            do {
                let data = try await fetchData(from: url)
                let res = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
                for item in res.results {
                    if let tid = item.trackId, !seen.contains(tid) {
                        seen.insert(tid)
                        collected.append(item)
                    }
                }
            } catch {
                appendLog("⚠️ [\(country)] 目录请求异常: \(error.localizedDescription)")
            }
        }
        return collected
    }

    // MARK: - ipatool Subprocess Runner (with Proxy Injection)

    func runIpatool(args: [String]) async -> (exitCode: Int32, stdout: String, stderr: String) {
        let binary = ipatoolPath
        let useProxy = proxyEnabled
        let proxy = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)

        var displayArgs = args
        if let pIdx = displayArgs.firstIndex(of: "-p"), pIdx + 1 < displayArgs.count {
            displayArgs[pIdx + 1] = "********"
        }
        let cmdSummary = ([binary] + displayArgs).joined(separator: " ")
        appendLog("▶ \(cmdSummary)" + (useProxy && !proxy.isEmpty ? " [代理: \(proxy)]" : " [直连]"))

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            if useProxy && !proxy.isEmpty {
                env["HTTP_PROXY"] = proxy
                env["HTTPS_PROXY"] = proxy
                env["http_proxy"] = proxy
                env["https_proxy"] = proxy
                env["ALL_PROXY"] = proxy
            } else {
                env.removeValue(forKey: "HTTP_PROXY")
                env.removeValue(forKey: "HTTPS_PROXY")
                env.removeValue(forKey: "http_proxy")
                env.removeValue(forKey: "https_proxy")
                env.removeValue(forKey: "ALL_PROXY")
            }
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                return (process.terminationStatus, outStr, errStr)
            } catch {
                return (-1, "", error.localizedDescription)
            }
        }.value
    }

    // MARK: - Account Authentication & Region Binding

    func refreshAccountInfo(assignToRegion: StoreRegion? = nil) async {
        let res = await runIpatool(args: ["auth", "info", "--format", "json", "--non-interactive"])
        let combined = (res.stdout + "\n" + res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if res.exitCode == 0, let data = res.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["success"] as? Bool) == true
        {
            let email = (json["email"] as? String) ?? ""
            let name = (json["name"] as? String) ?? ""

            // Match against saved region slots or assignToRegion
            var matchedRegion: StoreRegion? = assignToRegion
            if matchedRegion == nil {
                for reg in StoreRegion.allCases {
                    if let slotEmail = accountSlots[reg]?.email,
                       !slotEmail.isEmpty,
                       slotEmail.lowercased() == email.lowercased()
                    {
                        matchedRegion = reg
                        break
                    }
                }
            }
            let targetReg = matchedRegion ?? activeRegionTag
            activeRegionTag = targetReg
            activeAccount = ActiveAccountStatus(
                isLoggedIn: true,
                email: email,
                name: name,
                detectedRegion: targetReg,
                rawOutput: combined
            )

            // Auto-bind into targetReg slot if empty or matching
            if let existing = accountSlots[targetReg], existing.email.isEmpty || existing.email.lowercased() == email.lowercased() {
                saveSlot(region: targetReg, email: email, name: name, password: nil)
            }
            appendLog("👤 当前在线 [\(targetReg.cuteLabel)]: \(email) (\(name))")
        } else {
            activeAccount = ActiveAccountStatus(isLoggedIn: false, email: "", name: "", detectedRegion: nil, rawOutput: combined)
            appendLog("ℹ️ 当前尚未登录 Apple ID")
        }
    }

    func performLogin() async {
        let cleanEmail = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !loginPassword.isEmpty else { return }
        isLoggingIn = true

        // Restore region cookies if present
        let mainCookies = cookieFilePath(for: nil)
        let regCookies = cookieFilePath(for: editingRegion)
        if FileManager.default.fileExists(atPath: regCookies) {
            try? FileManager.default.removeItem(atPath: mainCookies)
            try? FileManager.default.copyItem(atPath: regCookies, toPath: mainCookies)
        }

        var args = [
            "auth", "login",
            "-e", cleanEmail,
            "-p", loginPassword,
            "--format", "json",
            "--non-interactive"
        ]
        let code = login2FACode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty {
            args.append(contentsOf: ["--auth-code", code])
        }

        let res = await runIpatool(args: args)
        let combined = (res.stdout + "\n" + res.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        appendLog("🔐 [\(editingRegion.cuteLabel)] 登录响应: \(combined)")

        if res.exitCode == 0 {
            saveSlot(region: editingRegion, email: cleanEmail, name: "", password: loginPassword)
            activeRegionTag = editingRegion
            await refreshAccountInfo(assignToRegion: editingRegion)
            saveSlot(region: editingRegion, email: cleanEmail, name: activeAccount.name, password: loginPassword)
            login2FACode = ""
            showAccountSheet = false
        }
        isLoggingIn = false
    }

    func bindCurrentActiveSession(to region: StoreRegion) {
        guard activeAccount.isLoggedIn else { return }
        saveSlot(region: region, email: activeAccount.email, name: activeAccount.name, password: nil)
        activeRegionTag = region
        activeAccount.detectedRegion = region
        appendLog("📌 已将当前账号 \(activeAccount.email) 绑定至 \(region.cuteLabel) 槽位")
    }

    func revokeAccount() async {
        _ = await runIpatool(args: ["auth", "revoke", "--format", "json", "--non-interactive"])
        await refreshAccountInfo()
    }

    // MARK: - List Historical Versions

    func fetchVersions(for app: StoreAppItem) async {
        loadingVersionsFor.insert(app.trackId)
        let res = await runIpatool(args: [
            "list-versions",
            "-i", String(app.trackId),
            "--format", "json",
            "--non-interactive"
        ])
        loadingVersionsFor.remove(app.trackId)

        if let data = res.stdout.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let versions = json["externalVersionIdentifiers"] as? [String],
           !versions.isEmpty
        {
            let reversed = Array(versions.reversed())
            appVersions[app.trackId] = reversed
            appendLog("📜 [\(app.trackName)] 共获取到 \(reversed.count) 个历史/灰度版本 ID")
        } else {
            let msg = Self.extractErrorMessage(from: res.stdout + "\n" + res.stderr)
            appendLog("⚠️ 获取 [\(app.trackName)] 版本列表失败: \(msg)")
        }
    }

    // MARK: - Single-Country Delisted & Normal IPA Downloader (Purchased / Unpurchased / Free)

    func downloadIPA(
        for app: StoreAppItem,
        explicitVersionID: String? = nil,
        strategyOverride: DelistedDownloadStrategy? = nil
    ) async {
        let tid = app.trackId
        let strategy = strategyOverride ?? downloadStrategy
        try? FileManager.default.createDirectory(atPath: downloadDirectory, withIntermediateDirectories: true)

        let sanitizedName = app.trackName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let versionSuffix = explicitVersionID.map { "_v\($0)" } ?? "_\(app.displayVersion)"
        let targetFile = (downloadDirectory as NSString).appendingPathComponent("\(sanitizedName)_\(tid)\(versionSuffix).ipa")

        downloadStates[tid] = DownloadTaskState(
            isRunning: true,
            statusText: "[\(activeRegionTag.cuteLabel) · \(strategy.shortBadge)] 正在连接 Apple 分发服务器...",
            downloadedFilePath: nil,
            isError: false
        )

        var res: (exitCode: Int32, stdout: String, stderr: String) = (-1, "", "")

        switch strategy {
        case .purchasedDirect:
            // Pure numeric ID direct download (bypasses Lookup & Purchase endpoints completely)
            downloadStates[tid]?.statusText = "🔓 正在以纯已购穿透模式 (-i \(tid)) 直连拉取 IPA..."
            var args = [
                "download",
                "-i", String(tid),
                "-o", targetFile,
                "--format", "json",
                "--non-interactive"
            ]
            if let ver = explicitVersionID, !ver.isEmpty {
                args.append(contentsOf: ["--external-version-id", ver])
            }
            res = await runIpatool(args: args)

        case .freeForceClaim:
            // Step 1: Explicitly call `ipatool purchase -i <tid>` to force claim 0-price license by numeric ID
            downloadStates[tid]?.statusText = "🎁 正在强制为当前账号申领免费许可证 (purchase -i \(tid))..."
            let purRes = await runIpatool(args: [
                "purchase",
                "-i", String(tid),
                "--format", "json",
                "--non-interactive"
            ])
            if purRes.exitCode == 0 {
                appendLog("🎁 [\(app.trackName)] 免费许可证申领成功，开始下载 IPA...")
            } else {
                appendLog("ℹ️ 领券接口返回: \(Self.extractErrorMessage(from: purRes.stdout + "\n" + purRes.stderr))，继续尝试直连下载...")
            }
            // Step 2: Download with `--purchase` and fallback to pure `-i`
            downloadStates[tid]?.statusText = "⬇️ 正在下载 IPA 安装包 (-i \(tid))..."
            var dlArgs = [
                "download",
                "-i", String(tid),
                "--purchase",
                "-o", targetFile,
                "--format", "json",
                "--non-interactive"
            ]
            if let ver = explicitVersionID, !ver.isEmpty {
                dlArgs.append(contentsOf: ["--external-version-id", ver])
            }
            res = await runIpatool(args: dlArgs)
            if res.exitCode != 0 {
                var retryArgs = [
                    "download",
                    "-i", String(tid),
                    "-o", targetFile,
                    "--format", "json",
                    "--non-interactive"
                ]
                if let ver = explicitVersionID, !ver.isEmpty {
                    retryArgs.append(contentsOf: ["--external-version-id", ver])
                }
                res = await runIpatool(args: retryArgs)
            }

        case .smartAuto:
            // Smart Auto:
            // 1. Try download with `--purchase` (covers both unpurchased free apps & normal apps)
            // 2. If `--purchase` fails (e.g. app is delisted in current country so purchase check fails),
            //    immediately fallback to pure numeric ID `-i <tid>` direct download (for purchased delisted apps),
            //    and if license is still missing, try explicit `purchase -i <tid>` once!
            var args = [
                "download",
                "-i", String(tid),
                "--purchase",
                "-o", targetFile,
                "--format", "json",
                "--non-interactive"
            ]
            if let ver = explicitVersionID, !ver.isEmpty {
                args.append(contentsOf: ["--external-version-id", ver])
            }
            res = await runIpatool(args: args)

            if res.exitCode != 0 {
                appendLog("🔄 自动切换至「已购下架穿透模式」(-i \(tid) 跳过商店目录校验)...")
                downloadStates[tid]?.statusText = "🔓 正在以已购下架穿透模式 (-i \(tid)) 直连拉取 IPA..."
                var retryArgs = [
                    "download",
                    "-i", String(tid),
                    "-o", targetFile,
                    "--format", "json",
                    "--non-interactive"
                ]
                if let ver = explicitVersionID, !ver.isEmpty {
                    retryArgs.append(contentsOf: ["--external-version-id", ver])
                }
                res = await runIpatool(args: retryArgs)
            }
        }

        if res.exitCode == 0 {
            var finalPath = targetFile
            if let data = res.stdout.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outPath = json["output"] as? String, !outPath.isEmpty
            {
                finalPath = outPath
            }
            downloadStates[tid] = DownloadTaskState(
                isRunning: false,
                statusText: "✅ IPA 下载完成: \((finalPath as NSString).lastPathComponent)",
                downloadedFilePath: finalPath,
                isError: false
            )
            appendLog("🎉 [\(app.trackName)] 下载成功 -> \(finalPath)")
        } else {
            let errMsg = Self.extractErrorMessage(from: res.stdout + "\n" + res.stderr, app: app, activeRegion: activeRegionTag)
            downloadStates[tid] = DownloadTaskState(
                isRunning: false,
                statusText: "❌ \(errMsg)",
                downloadedFilePath: nil,
                isError: true
            )
            appendLog("❌ [\(app.trackName)] 下载失败: \(errMsg)")
        }
    }

    func claimFreeLicenseOnly(for app: StoreAppItem) async {
        let tid = app.trackId
        downloadStates[tid] = DownloadTaskState(
            isRunning: true,
            statusText: "🎁 正在为当前 [\(activeRegionTag.cuteLabel)] 账号免费领券入库...",
            downloadedFilePath: nil,
            isError: false
        )
        let res = await runIpatool(args: [
            "purchase",
            "-i", String(tid),
            "--format", "json",
            "--non-interactive"
        ])
        if res.exitCode == 0 {
            downloadStates[tid] = DownloadTaskState(
                isRunning: false,
                statusText: "✅ 已成功免费领券入库（已绑定至 \(activeAccount.email)）",
                downloadedFilePath: nil,
                isError: false
            )
            appendLog("✅ [\(app.trackName)] 免费许可证入库成功")
        } else {
            let errMsg = Self.extractErrorMessage(from: res.stdout + "\n" + res.stderr, app: app, activeRegion: activeRegionTag)
            downloadStates[tid] = DownloadTaskState(
                isRunning: false,
                statusText: "❌ 领券失败: \(errMsg)",
                downloadedFilePath: nil,
                isError: true
            )
            appendLog("❌ [\(app.trackName)] 领券失败: \(errMsg)")
        }
    }

    func runDelistedDirectExtractor() async {
        let raw = extractorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // Switch region account first if needed
        if extractorTargetRegion != activeRegionTag,
           let slot = accountSlots[extractorTargetRegion], !slot.email.isEmpty
        {
            await switchOrOpenAccount(for: extractorTargetRegion)
        }

        // Resolve numeric ID from raw input (or cross-region search if keyword/bundleId)
        var targetID = Self.extractNumericAppID(from: raw)
        var resolvedItem: StoreAppItem?

        if targetID == nil {
            for reg in [StoreRegion.jp, .us, .cn] {
                let found = await fetchStoreItems(query: raw, numericID: nil, country: reg.rawValue)
                if let first = found.first, let tid = first.trackId {
                    targetID = tid
                    let priceVal = first.price ?? 0
                    resolvedItem = StoreAppItem(
                        trackId: tid,
                        trackName: extractorName.isEmpty ? (first.trackName ?? "下架提取_\(tid)") : extractorName,
                        bundleId: first.bundleId ?? raw,
                        sellerName: first.sellerName ?? "下架穿透提取",
                        artworkUrl512: first.artworkUrl512 ?? first.artworkUrl100 ?? "",
                        primaryGenreName: "下架穿透提取",
                        fileSizeBytes: first.fileSizeBytes,
                        listings: [
                            reg: RegionListingInfo(
                                region: reg,
                                version: first.version ?? "最新版",
                                priceText: first.formattedPrice ?? (priceVal == 0 ? reg.freeWord : "\(priceVal)"),
                                isFree: priceVal == 0
                            )
                        ],
                        isDelistedOrRecovered: true,
                        presetNote: "🔮 下架穿透提取器定位 ID: \(tid)"
                    )
                    break
                }
            }
        }

        guard let finalID = targetID else {
            appendLog("❌ 未能从输入 \"\(raw)\" 解析出数字 App ID，请输入纯数字 ID (如 932747118)")
            return
        }

        let item = resolvedItem ?? StoreAppItem(
            trackId: finalID,
            trackName: extractorName.isEmpty ? "DelistedApp_\(finalID)" : extractorName,
            bundleId: "直连数字 ID: \(finalID)",
            sellerName: "单国下架穿透提取",
            artworkUrl512: "",
            primaryGenreName: "下架提取",
            fileSizeBytes: nil,
            listings: [:],
            fallbackVersion: "最新版",
            isDelistedOrRecovered: true,
            presetNote: "🔮 单国家下架穿透提取 · 模式: \(extractorStrategy.title)"
        )

        if !searchResults.contains(where: { $0.trackId == finalID }) {
            searchResults.insert(item, at: 0)
            await hydrateIconsAndListings()
        }
        showDelistedExtractorSheet = false
        await downloadIPA(for: item, explicitVersionID: nil, strategyOverride: extractorStrategy)
    }

    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func extractErrorMessage(from raw: String, app: StoreAppItem? = nil, activeRegion: StoreRegion = .cn) -> String {
        for line in raw.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String
            {
                if err.contains("license is required") {
                    if let app = app {
                        let freeRegions = app.listings.values.filter(\.isFree).map(\.region.cuteLabel)
                        if !freeRegions.isEmpty && app.listings[activeRegion] == nil {
                            return "当前 [\(activeRegion.cuteLabel)] 账号历史上未购买过此下架应用；但该应用在 \(freeRegions.joined(separator: "/")) 免费在架，点击顶部切换至对应区服账号即可一键免费领券下载！"
                        }
                    }
                    return "当前 [\(activeRegion.cuteLabel)] 账号无此应用许可证 (license is required)。若为已下架应用，需使用下架前曾入手过它的账号；若在外区免费在架，请点击顶部切换至日区/美区账号免费领券。"
                }
                if err.contains("password token is expired") || err.contains("authentication") {
                    return "Apple ID 会话已过期，请点击顶部对应国家槽位重新登录。"
                }
                return err
            }
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Japanese Aesthetic Liquid Glass Design System

struct WindowVibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tintColor: Color = .cyan
    var tintOpacity: Double = 0.08
    var highlightIntensity: Double = 0.50

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(tintOpacity * 0.95),
                                    tintColor.opacity(tintOpacity * 0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .glassEffect(
                    .regular.tint(tintColor.opacity(tintOpacity * 1.15)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(tintOpacity * 1.8),
                                        tintColor.opacity(tintOpacity * 0.45),
                                        Color.white.opacity(tintOpacity * 0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(highlightIntensity),
                                    tintColor.opacity(highlightIntensity * 0.55),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(highlightIntensity * 0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.15
                        )
                )
                .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 8)
        }
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        tintColor: Color = .cyan,
        tintOpacity: Double = 0.08,
        highlightIntensity: Double = 0.50
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                tintColor: tintColor,
                tintOpacity: tintOpacity,
                highlightIntensity: highlightIntensity
            )
        )
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color = Color(red: 0.96, green: 0.48, blue: 0.68)

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .foregroundColor(.white)
                .glassEffect(
                    prominent
                        ? .regular.tint(tint.opacity(0.68)).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
        } else {
            configuration.label
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                        if prominent {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            tint.opacity(configuration.isPressed ? 0.55 : 0.75),
                                            Color.cyan.opacity(configuration.isPressed ? 0.45 : 0.62)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.09))
                        }
                    }
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(prominent ? 0.75 : 0.45),
                                    tint.opacity(0.35),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .foregroundColor(.white)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject private var vm = RingoDropViewModel()

    private let sakuraPink = Color(red: 0.96, green: 0.48, blue: 0.68)
    private let soraCyan = Color(red: 0.35, green: 0.82, blue: 0.98)

    var body: some View {
        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()

            // Japanese Sakura & Sora Liquid Aurora Backdrop
            GeometryReader { geo in
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.08, blue: 0.19).opacity(0.84),
                            Color(red: 0.10, green: 0.11, blue: 0.24).opacity(0.76),
                            Color(red: 0.05, green: 0.07, blue: 0.16).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Sakura Pink Glow
                    Circle()
                        .fill(sakuraPink.opacity(0.22))
                        .frame(width: 460, height: 460)
                        .blur(radius: 105)
                        .offset(x: -geo.size.width * 0.26, y: -geo.size.height * 0.24)

                    // Sora Cyan Water-Drop Glow
                    Circle()
                        .fill(soraCyan.opacity(0.22))
                        .frame(width: 500, height: 500)
                        .blur(radius: 115)
                        .offset(x: geo.size.width * 0.28, y: -geo.size.height * 0.08)

                    // Sumire Violet Glow
                    Circle()
                        .fill(Color.indigo.opacity(0.24))
                        .frame(width: 440, height: 440)
                        .blur(radius: 105)
                        .offset(x: 0, y: geo.size.height * 0.30)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 14) {
                topBrandAndThreeCountryAccountBar
                multiCountrySearchAndStrategyBar
                mainAppList
                bottomStatusAndConsoleBar
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $vm.showAccountSheet) {
            ThreeCountryAccountSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showSettingsSheet) {
            ProxyAndSettingsSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showDelistedExtractorSheet) {
            DelistedDirectExtractorSheet(vm: vm)
        }
    }

    // MARK: - 1. Top Brand & 3-Country Account Dock (CN / JP / US)

    private var topBrandAndThreeCountryAccountBar: some View {
        HStack(spacing: 12) {
            // Cute RingoDrop Brand Logo
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    sakuraPink.opacity(0.92),
                                    Color(red: 0.72, green: 0.48, blue: 0.96).opacity(0.85),
                                    soraCyan.opacity(0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1.1)
                        )
                        .shadow(color: sakuraPink.opacity(0.38), radius: 8, x: 0, y: 4)

                    VStack(spacing: -2) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 16, weight: .bold))
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.82, green: 0.96, blue: 1.0))
                    }
                    .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("RingoDrop")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)

                        Text("りんご雫")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(sakuraPink.opacity(0.28)))
                            .overlay(Capsule().strokeBorder(sakuraPink.opacity(0.65), lineWidth: 0.9))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.92))
                    }
                    Text("中 🇨🇳 · 日 🇯🇵 · 美 🇺🇸 三国账号切换 · 多国联合搜索 & 下架 IPA 提取")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.70))
                }
            }

            Spacer()

            // 3-Country Account Switcher Dock (CN / JP / US)
            HStack(spacing: 7) {
                ForEach(StoreRegion.allCases) { reg in
                    regionAccountPill(for: reg)
                }

                Button {
                    vm.prepareLoginSheet(for: vm.activeRegionTag)
                } label: {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.88))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .help("管理中/日/美三国 Apple ID 账号")
            }
            .padding(6)
            .liquidGlassCard(cornerRadius: 18, tintColor: sakuraPink, tintOpacity: 0.07, highlightIntensity: 0.45)

            // Proxy Quick Pill
            HStack(spacing: 7) {
                Toggle("", isOn: $vm.proxyEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)

                Button {
                    vm.showSettingsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(vm.proxyEnabled ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(vm.proxyEnabled ? vm.proxyURL.replacingOccurrences(of: "http://", with: "") : "直连")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: 18, tintColor: soraCyan, tintOpacity: 0.06, highlightIntensity: 0.40)
        }
    }

    private func regionAccountPill(for region: StoreRegion) -> some View {
        let slot = vm.accountSlots[region]
        let hasEmail = !(slot?.email.isEmpty ?? true)
        let isActive = vm.activeAccount.isLoggedIn && (
            (hasEmail && vm.activeAccount.email.lowercased() == slot?.email.lowercased())
            || (!hasEmail && vm.activeRegionTag == region)
        )

        return Button {
            Task { await vm.switchOrOpenAccount(for: region) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isActive ? Color.green : (hasEmail ? Color.cyan : Color.white.opacity(0.28)))
                    .frame(width: 7, height: 7)

                Text(region.cuteLabel)
                    .font(.system(size: 12, weight: isActive ? .bold : .semibold))

                if isActive {
                    Text(Self.shortEmail(vm.activeAccount.email))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                } else if let email = slot?.email, !email.isEmpty {
                    Text(Self.shortEmail(email))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.68))
                } else {
                    Text("未登录")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.48))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? region.accentColor.opacity(0.34)
                            : (hasEmail ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.75) : Color.white.opacity(0.15),
                        lineWidth: isActive ? 1.1 : 0.7
                    )
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    private static func shortEmail(_ email: String) -> String {
        guard let atIdx = email.firstIndex(of: "@") else { return email }
        let prefix = String(email[..<atIdx])
        if prefix.count <= 9 { return prefix }
        return String(prefix.prefix(8)) + "…"
    }

    // MARK: - 2. Multi-Country Search Bar & Delisted Controls

    private var multiCountrySearchAndStrategyBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Search Input Box
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(sakuraPink)

                    TextField("搜索 App 名称 / Bundle ID / 纯数字 ID (如 932747118 / Shadowrocket / Telegram / ウマ娘)...", text: $vm.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundColor(.white)
                        .onSubmit {
                            Task { await vm.performSearch() }
                        }

                    if !vm.searchQuery.isEmpty {
                        Button {
                            vm.searchQuery = ""
                            Task { await vm.performSearch() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }

                    // Multi-Country Search Selection Check-Pills (CN / JP / US)
                    HStack(spacing: 5) {
                        Text("搜索区:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.60))

                        ForEach(StoreRegion.allCases) { reg in
                            let isOn = vm.selectedSearchRegions.contains(reg)
                            Button {
                                vm.toggleSearchRegion(reg)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isOn ? reg.accentColor : .white.opacity(0.4))
                                    Text("\(reg.flag)\(reg.shortName)")
                                        .font(.system(size: 11.5, weight: isOn ? .bold : .regular))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isOn ? reg.accentColor.opacity(0.24) : Color.white.opacity(0.05))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(isOn ? reg.accentColor.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        Task { await vm.performSearch() }
                    } label: {
                        HStack(spacing: 5) {
                            if vm.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(vm.selectedSearchRegions.count > 1 ? "多国联搜" : "单国搜索")
                                .font(.system(size: 12.5, weight: .bold))
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: sakuraPink))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .liquidGlassCard(cornerRadius: 18, tintColor: sakuraPink, tintOpacity: 0.08, highlightIntensity: 0.52)

                // Quick Action Buttons: Delisted Extractor & My Purchases
                Button {
                    vm.showDelistedExtractorSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                        Text("下架提取")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: soraCyan))
                .help("单国家下载已下架 App（支持已购直下 / 未购免费强制领券）")

                Button {
                    Task { await vm.loadPurchasedApps() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bag.fill")
                        Text("我的已购")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: soraCyan))
            }

            // Sub-bar: Result Region Filter & Single-Country Delisted Download Mode Picker
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    filterTabPill(title: "全部 (\(vm.searchResults.count))", tag: "ALL")
                    filterTabPill(title: "🇨🇳 国区", tag: "CN")
                    filterTabPill(title: "🇯🇵 日区", tag: "JP")
                    filterTabPill(title: "🇺🇸 美区", tag: "US")
                    filterTabPill(title: "🔮 已下架/跨区", tag: "DELISTED")
                }

                Spacer()

                Toggle("单国搜索自动开启「下架 App 数字 ID 雷达」", isOn: $vm.enableDelistedRadar)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.82))
                    .toggleStyle(.checkbox)

                HStack(spacing: 6) {
                    Text("下载策略:")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))

                    Picker("", selection: $vm.downloadStrategy) {
                        ForEach(DelistedDownloadStrategy.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func filterTabPill(title: String, tag: String) -> some View {
        let isSelected = vm.resultFilterRegion == tag
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                vm.resultFilterRegion = tag
            }
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? sakuraPink.opacity(0.32) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .foregroundColor(isSelected ? .white : .white.opacity(0.72))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Main App List

    private var mainAppList: some View {
        ScrollView {
            LazyVStack(spacing: 13) {
                if vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles.tv.fill")
                            .foregroundColor(sakuraPink)
                        Text("りんご雫 · 精选已下架 / 跨区热门直通车（支持中 🇨🇳 · 日 🇯🇵 · 美 🇺🇸 三国账号已购直下或免费领券下载）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.78))
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                }

                ForEach(vm.filteredResults) { app in
                    AppLiquidGlassRow(app: app, vm: vm)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 4. Bottom Bar & Console

    private var bottomStatusAndConsoleBar: some View {
        VStack(spacing: 10) {
            if vm.showConsole {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("RingoDrop (りんご雫) 实时通信日志", systemImage: "terminal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(sakuraPink)
                        Spacer()
                        Button("清空日志") {
                            vm.logs.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.65))
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(vm.logs.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.88))
                                        .textSelection(.enabled)
                                        .id(idx)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: vm.logs.count) {
                            if let last = vm.logs.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .frame(height: 125)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: 16, tintColor: sakuraPink, tintOpacity: 0.07, highlightIntensity: 0.45)
            }

            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        vm.showConsole.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                        Text(vm.showConsole ? "收起日志" : "展开日志")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: false))

                Text("当前激活区服: \(vm.activeRegionTag.cuteLabel) (\(vm.activeAccount.isLoggedIn ? vm.activeAccount.email : "未登录"))  ·  ⚠️ 免责声明：仅限找回本人已购丢失 App 及个人研究，严禁用于其他任何用途")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(sakuraPink)
                        .font(.system(size: 12))
                    Text("保存至: \(vm.downloadDirectory)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Button("打开目录") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: vm.downloadDirectory))
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false))
                    .font(.system(size: 11.5))
                }
            }
        }
    }
}

// MARK: - App Row Card (Liquid Glass)

struct AppLiquidGlassRow: View {
    let app: StoreAppItem
    @ObservedObject var vm: RingoDropViewModel
    @State private var showVersionsPopover: Bool = false

    private let sakuraPink = Color(red: 0.96, green: 0.48, blue: 0.68)

    var taskState: DownloadTaskState {
        vm.downloadStates[app.trackId] ?? DownloadTaskState()
    }

    var versions: [String] {
        vm.appVersions[app.trackId] ?? []
    }

    var selectedVersion: String {
        vm.selectedVersionForApp[app.trackId] ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // App Icon
                AsyncImage(url: URL(string: app.artworkUrl512)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            LinearGradient(
                                colors: [sakuraPink.opacity(0.55), Color.indigo.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "drop.halffull")
                                .font(.system(size: 25))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.50), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

                // Metadata & 3-Country Storefront Badges
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(app.trackName)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        // CN / JP / US Storefront Badges
                        ForEach(StoreRegion.allCases) { reg in
                            if let info = app.listings[reg] {
                                storefrontBadge(
                                    flag: reg.cuteLabel,
                                    detail: "\(info.priceText) · v\(info.version)",
                                    color: reg.accentColor
                                )
                            } else if reg == .cn {
                                storefrontBadge(
                                    flag: "🇨🇳 国区已下架",
                                    detail: "可穿透直下",
                                    color: .orange
                                )
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Label("ID: \(String(app.trackId))", systemImage: "number")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.86))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)

                        if !app.bundleId.isEmpty {
                            Text(app.bundleId)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.68))
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }

                        if !app.formattedSize.isEmpty {
                            Text(app.formattedSize)
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        if !app.sellerName.isEmpty {
                            Text(app.sellerName)
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }

                    if let note = app.presetNote {
                        Text(note)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color(red: 0.62, green: 0.90, blue: 1.0))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 7) {
                    // Historical Version Selector
                    Button {
                        showVersionsPopover.toggle()
                        if versions.isEmpty {
                            Task { await vm.fetchVersions(for: app) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if vm.loadingVersionsFor.contains(app.trackId) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            Text(selectedVersion.isEmpty ? "选版本" : "vID:\(selectedVersion.suffix(5))")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false))

                    // Free License Claim Button
                    if app.isFreeInAnyRegion || app.isDelistedOrRecovered {
                        Button {
                            Task { await vm.claimFreeLicenseOnly(for: app) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gift.fill")
                                Text("免费领券")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .buttonStyle(LiquidGlassButtonStyle(prominent: false))
                        .disabled(taskState.isRunning)
                        .help("强制按数字 ID 申领 0 元免费许可证 (ipatool purchase -i)")
                    }

                    // Primary One-Click Download IPA Button
                    Button {
                        let ver = selectedVersion.isEmpty ? nil : selectedVersion
                        Task { await vm.downloadIPA(for: app, explicitVersionID: ver) }
                    } label: {
                        HStack(spacing: 6) {
                            if taskState.isRunning {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.75)
                                Text("下载中...")
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("一键下载 IPA")
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: sakuraPink))
                    .disabled(taskState.isRunning)
                }
            }

            // Expandable Version Selector Bar
            if showVersionsPopover {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("📜 Apple 服务器历史与最新灰度版本 ID (点击任意版本后点「一键下载 IPA」即可指定版本下载):")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                        Spacer()
                        Button("刷新列表") {
                            Task { await vm.fetchVersions(for: app) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundColor(sakuraPink)
                    }

                    if versions.isEmpty {
                        Text(vm.loadingVersionsFor.contains(app.trackId) ? "正在从 Apple 服务器拉取历史版本列表..." : "暂未读取到版本列表（需当前激活账号拥有该应用已购权限或先点「免费领券」）")
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                versionChip(label: "最新版 (默认)", versionID: "")
                                ForEach(Array(versions.prefix(35).enumerated()), id: \.element) { idx, verID in
                                    versionChip(
                                        label: idx == 0 ? "最新 #\(verID)" : "#\(verID)",
                                        versionID: verID
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
            }

            // Task Status & Quick Mode Retry / Finder Reveal Banner
            if !taskState.statusText.isEmpty {
                HStack(spacing: 10) {
                    Text(taskState.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(taskState.isError ? Color(red: 1.0, green: 0.52, blue: 0.58) : Color(red: 0.55, green: 0.92, blue: 1.0))
                        .textSelection(.enabled)

                    Spacer()

                    if taskState.isError {
                        Button("已购穿透重试") {
                            let ver = selectedVersion.isEmpty ? nil : selectedVersion
                            Task { await vm.downloadIPA(for: app, explicitVersionID: ver, strategyOverride: .purchasedDirect) }
                        }
                        .buttonStyle(LiquidGlassButtonStyle(prominent: false))
                        .font(.system(size: 11))

                        Button("强制领券重试") {
                            let ver = selectedVersion.isEmpty ? nil : selectedVersion
                            Task { await vm.downloadIPA(for: app, explicitVersionID: ver, strategyOverride: .freeForceClaim) }
                        }
                        .buttonStyle(LiquidGlassButtonStyle(prominent: false))
                        .font(.system(size: 11))
                    }

                    if let path = taskState.downloadedFilePath {
                        Button {
                            vm.revealInFinder(path: path)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("在访达中显示 IPA")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(LiquidGlassButtonStyle(prominent: false))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .liquidGlassCard(cornerRadius: 20, tintColor: sakuraPink, tintOpacity: 0.07, highlightIntensity: 0.48)
    }

    private func storefrontBadge(flag: String, detail: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(flag)
                .font(.system(size: 11, weight: .bold))
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .opacity(0.92)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.22))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.58), lineWidth: 0.8)
        )
        .foregroundColor(.white)
    }

    private func versionChip(label: String, versionID: String) -> some View {
        let isSelected = selectedVersion == versionID
        return Button {
            vm.selectedVersionForApp[app.trackId] = versionID
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? sakuraPink.opacity(0.42) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3-Country Account Manager Sheet (CN 🇨🇳 / JP 🇯🇵 / US 🇺🇸)

struct ThreeCountryAccountSheet: View {
    @ObservedObject var vm: RingoDropViewModel
    @Environment(\.dismiss) private var dismiss

    private let sakuraPink = Color(red: 0.96, green: 0.48, blue: 0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("中 🇨🇳 · 日 🇯🇵 · 美 🇺🇸 三国 Apple ID 账号舱", systemImage: "apple.logo")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false))
            }

            // 3 Region Account Cards
            HStack(spacing: 10) {
                ForEach(StoreRegion.allCases) { reg in
                    let slot = vm.accountSlots[reg]
                    let isEditing = vm.editingRegion == reg
                    let isOnline = vm.activeAccount.isLoggedIn && vm.activeRegionTag == reg

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(reg.cuteLabel)
                                .font(.system(size: 13.5, weight: .bold))
                            Spacer()
                            if isOnline {
                                Text("当前在线")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.28)))
                                    .foregroundColor(.green)
                            }
                        }

                        Text(slot?.email.isEmpty == false ? (slot?.email ?? "") : "尚未绑定 \(reg.shortName) Apple ID")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(slot?.email.isEmpty == false ? .white : .secondary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Button(slot?.email.isEmpty == false ? "切换/编辑" : "添加账号") {
                                vm.prepareLoginSheet(for: reg)
                            }
                            .font(.system(size: 11))

                            if vm.activeAccount.isLoggedIn && (slot?.email.isEmpty ?? true) {
                                Button("绑定当前号") {
                                    vm.bindCurrentActiveSession(to: reg)
                                }
                                .font(.system(size: 11))
                            }

                            if slot?.email.isEmpty == false {
                                Button("移除") {
                                    vm.removeSlot(region: reg)
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.85))
                            }
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(
                        cornerRadius: 14,
                        tintColor: reg.accentColor,
                        tintOpacity: isEditing ? 0.16 : 0.06,
                        highlightIntensity: isEditing ? 0.75 : 0.35
                    )
                    .onTapGesture {
                        vm.prepareLoginSheet(for: reg)
                    }
                }
            }

            // Login Form for Selected Region
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("登录并保存至：\(vm.editingRegion.cuteLabel) (\(vm.editingRegion.jpSubtitle))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(vm.editingRegion.accentColor)
                    Spacer()
                    Picker("目标区服", selection: $vm.editingRegion) {
                        ForEach(StoreRegion.allCases) { reg in
                            Text(reg.cuteLabel).tag(reg)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                TextField("输入 \(vm.editingRegion.shortName) Apple ID 邮箱 (如 example@icloud.com)", text: $vm.loginEmail)
                    .textFieldStyle(.roundedBorder)

                SecureField("输入 Apple ID 密码", text: $vm.loginPassword)
                    .textFieldStyle(.roundedBorder)

                TextField("6 位双重验证码 (推荐在 iPhone 设置 -> Apple 账户 -> 登录与安全性 -> 双重认证 -> 获取验证码)", text: $vm.login2FACode)
                    .textFieldStyle(.roundedBorder)

                Toggle("在 macOS 系统钥匙串中安全记住该区服密码与 2FA 信任 Cookie（下次顶栏一键切号免输验证码）", isOn: $vm.savePasswordInKeychain)
                    .font(.system(size: 12))
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tintColor: vm.editingRegion.accentColor, tintOpacity: 0.08)

            HStack {
                if vm.activeAccount.isLoggedIn {
                    Button("注销当前在线会话") {
                        Task { await vm.revokeAccount() }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false, tint: .red))
                }
                Spacer()
                Button {
                    Task { await vm.performLogin() }
                } label: {
                    HStack(spacing: 6) {
                        if vm.isLoggingIn {
                            ProgressView().controlSize(.small)
                        }
                        Text(vm.isLoggingIn ? "正在认证 \(vm.editingRegion.cuteLabel)..." : "登录并激活 \(vm.editingRegion.cuteLabel) 账号")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: sakuraPink))
                .disabled(vm.isLoggingIn || vm.loginEmail.isEmpty || vm.loginPassword.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 620)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Single-Country Delisted App Direct Extractor Sheet

struct DelistedDirectExtractorSheet: View {
    @ObservedObject var vm: RingoDropViewModel
    @Environment(\.dismiss) private var dismiss

    private let sakuraPink = Color(red: 0.96, green: 0.48, blue: 0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("🔮 单国家已下架 / 隐藏 App 穿透提取器", systemImage: "wand.and.stars")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: false))
            }

            Text("当某个应用在当前国家商店已下架（前端搜索不到、商品页不可用）时，Apple 分发 CDN 上依然保留着它的安装包。只需输入它的数字 App ID、历史链接或关键词，即可在单个国家账号下直接穿透提取 `.ipa`。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目标标识:")
                        .frame(width: 90, alignment: .leading)
                    TextField("纯数字 App ID (如 932747118)、App Store 链接或应用名/Bundle ID", text: $vm.extractorInput)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("自定义名称:")
                        .frame(width: 90, alignment: .leading)
                    TextField("可选，留空自动识别 (如 Shadowrocket)", text: $vm.extractorName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("使用国家账号:")
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $vm.extractorTargetRegion) {
                        ForEach(StoreRegion.allCases) { reg in
                            Text("\(reg.cuteLabel) (\(vm.accountSlots[reg]?.email.isEmpty == false ? vm.accountSlots[reg]!.email : "当前会话"))").tag(reg)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("下架提取模式:")
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $vm.extractorStrategy) {
                        ForEach(DelistedDownloadStrategy.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tintColor: sakuraPink, tintOpacity: 0.08)

            HStack {
                Spacer()
                Button {
                    Task { await vm.runDelistedDirectExtractor() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("立即穿透提取 IPA")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: sakuraPink))
                .disabled(vm.extractorInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Proxy & Download Directory Settings Sheet

struct ProxyAndSettingsSheet: View {
    @ObservedObject var vm: RingoDropViewModel
    @Environment(\.dismiss) private var dismiss

    private let sakuraPink = Color(red: 0.96, green: 0.48, blue: 0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("网络代理与下载路径配置", systemImage: "network")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(LiquidGlassButtonStyle(prominent: true, tint: sakuraPink))
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用 HTTP/HTTPS 代理（同时作用于多国商店搜索与 ipatool FairPlay 签名握手）", isOn: $vm.proxyEnabled)
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    Text("代理地址:")
                        .frame(width: 85, alignment: .leading)
                    TextField("http://127.0.0.1:7890", text: $vm.proxyURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                HStack {
                    Text("ipatool 路径:")
                        .frame(width: 85, alignment: .leading)
                    TextField("/opt/homebrew/bin/ipatool", text: $vm.ipatoolPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }

                HStack {
                    Text("IPA 保存目录:")
                        .frame(width: 85, alignment: .leading)
                    TextField("~/Desktop", text: $vm.downloadDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                    Button("选择...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            vm.downloadDirectory = url.path
                        }
                    }
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tintColor: sakuraPink, tintOpacity: 0.08)
        }
        .padding(22)
        .frame(width: 540)
        .preferredColorScheme(.dark)
    }
}

// MARK: - App Delegate & Main Entry

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL)
        {
            NSApp.applicationIconImage = iconImage
        } else if let pngURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
                  let iconImage = NSImage(contentsOf: pngURL)
        {
            NSApp.applicationIconImage = iconImage
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.isMovableByWindowBackground = true
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct RingoDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
