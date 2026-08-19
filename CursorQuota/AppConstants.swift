import Foundation

enum AppConstants {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static let repoURL = "https://github.com/reinaldo-simoes-wp/cursor-quota"
    static let dashboardURL = "https://cursor.com/dashboard/usage"

    static let apiURL = URL(string: "https://cursor.com/api/dashboard/get-aggregated-usage-events")!
    static let filteredURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!
    static let teamsURL = URL(string: "https://cursor.com/api/dashboard/teams")!
    static let meURL = URL(string: "https://cursor.com/api/dashboard/get-me")!

    static let aggLagDays = 5
    static let fillLagDays = 4
    static let filteredPageSize = 1000
    static let filteredMaxPages = 50
    static let dayMs: Int64 = 86_400_000
    static let refreshInterval: TimeInterval = 300
    static let loadingFrameNanoseconds: UInt64 = 110_000_000
    static let loadingPhaseStep: Double = 0.55
    /// Columns in the menu bar glyph, and therefore buckets in the trend sparkline.
    static let trendBuckets = 5
    /// Dot heights a bucket's spend is scaled onto; the panel stretches this range.
    static let trendLevelSteps = 5

    static let stateDB = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cursor-quota")

    static let periodFile = configDir.appendingPathComponent("period")
    static let scopeFile = configDir.appendingPathComponent("scope")
    static let displayFile = configDir.appendingPathComponent("display")
    static let tokenFile = configDir.appendingPathComponent("token")
    static let limitsFile = configDir.appendingPathComponent("limits")
}

enum PeriodKey: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    case threeMonths = "3months"
    case sixMonths = "6months"
    case oneYear = "1year"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .oneYear: "1 Year"
        }
    }

    var days: Int {
        switch self {
        case .daily: 1
        case .weekly: 7
        case .monthly: 30
        case .threeMonths: 91
        case .sixMonths: 182
        case .oneYear: 365
        }
    }

    static let `default`: PeriodKey = .daily
}

enum ScopeKey: String, CaseIterable, Identifiable {
    case you, team
    var id: String { rawValue }
    static let `default`: ScopeKey = .you
}

/// The single figure the panel and the menu bar lead with.
enum DisplayKey: String, CaseIterable, Identifiable {
    case cost, tokens

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cost: "$"
        case .tokens: "Tokens"
        }
    }

    /// A spend ceiling only applies to the dollar figure.
    var showsCeiling: Bool { self == .cost }

    static let `default`: DisplayKey = .cost

    /// Maps the pre-2.1 display values, which also encoded rate windows.
    static func fromStoredValue(_ raw: String) -> DisplayKey? {
        if let key = DisplayKey(rawValue: raw) { return key }
        switch raw {
        case "total", "cost_hr", "cost_min": return .cost
        case "tok_hr", "tok_min": return .tokens
        default: return nil
        }
    }
}

struct StatusGauge: Equatable, Hashable {
    var title: String
    var limitColor: LimitColor?
}

enum LimitColor: Hashable {
    case orange, red

    static func forPercent(_ pct: Double) -> LimitColor? {
        if pct >= 0.9 { return .red }
        if pct >= 0.7 { return .orange }
        return nil
    }
}

enum LimitPresets {
    static let base: [PeriodKey: [Double]] = [
        .daily: [25, 50, 100, 250, 500, 1000],
        .weekly: [100, 250, 500, 1000, 2500, 5000],
        .monthly: [500, 1000, 2500, 5000, 10000, 25000],
        .threeMonths: [1000, 2500, 5000, 10000, 25000, 50000],
        .sixMonths: [2500, 5000, 10000, 25000, 50000, 75000],
        .oneYear: [5000, 10000, 25000, 50000, 75000, 100000],
    ]

    static func presets(scope: ScopeKey, period: PeriodKey) -> [Double] {
        let values = base[period] ?? []
        return scope == .team ? values.map { $0 * 2 } : values
    }
}

struct LimitKey: Hashable {
    let scope: ScopeKey
    let period: PeriodKey
}
