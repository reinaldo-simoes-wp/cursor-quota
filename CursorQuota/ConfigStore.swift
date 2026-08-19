import Foundation

enum ConfigStore {
    static func readPeriod() -> PeriodKey {
        readKey(from: AppConstants.periodFile, valid: PeriodKey.self, default: .default)
    }

    static func writePeriod(_ key: PeriodKey) {
        writeKey(key.rawValue, to: AppConstants.periodFile)
    }

    static func readScope() -> ScopeKey {
        readKey(from: AppConstants.scopeFile, valid: ScopeKey.self, default: .default)
    }

    static func writeScope(_ key: ScopeKey) {
        writeKey(key.rawValue, to: AppConstants.scopeFile)
    }

    static func readDisplay() -> DisplayKey {
        guard let contents = try? String(contentsOf: AppConstants.displayFile, encoding: .utf8) else {
            return .default
        }
        let raw = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return DisplayKey.fromStoredValue(raw) ?? .default
    }

    static func writeDisplay(_ key: DisplayKey) {
        writeKey(key.rawValue, to: AppConstants.displayFile)
    }

    static func parseDollars(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    static func readLimits() -> [LimitKey: Double] {
        var limits: [LimitKey: Double] = [:]
        guard let text = try? String(contentsOf: AppConstants.limitsFile, encoding: .utf8) else {
            return limits
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = raw.split(separator: "#", maxSplits: 1).first?
                .split(whereSeparator: \.isWhitespace)
                .map(String.init) ?? []
            if parts.count >= 3,
               let scope = ScopeKey(rawValue: parts[0]),
               let period = PeriodKey(rawValue: parts[1]),
               let dollars = parseDollars(parts[2]) {
                limits[LimitKey(scope: scope, period: period)] = dollars
            } else if parts.count >= 2,
                      let period = PeriodKey(rawValue: parts[0]),
                      let dollars = parseDollars(parts[1]) {
                limits[LimitKey(scope: .you, period: period)] = dollars
            }
        }
        return limits
    }

    private static func isLimitLine(_ raw: String) -> Bool {
        let parts = raw.split(separator: "#", maxSplits: 1).first?
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? []
        if parts.count >= 3,
           ScopeKey(rawValue: parts[0]) != nil,
           PeriodKey(rawValue: parts[1]) != nil {
            return true
        }
        if parts.count >= 2, PeriodKey(rawValue: parts[0]) != nil {
            return true
        }
        return false
    }

    static func writeLimits(_ limits: [LimitKey: Double]) {
        try? FileManager.default.createDirectory(
            at: AppConstants.configDir,
            withIntermediateDirectories: true
        )
        var kept: [String] = []
        if let text = try? String(contentsOf: AppConstants.limitsFile, encoding: .utf8) {
            kept = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !isLimitLine($0) }
        }
        let tmp = AppConstants.limitsFile.appendingPathExtension("tmp")
        var lines = kept
        for key in limits.keys.sorted(by: {
            ($0.scope.rawValue, $0.period.rawValue) < ($1.scope.rawValue, $1.period.rawValue)
        }) {
            guard let dollars = limits[key] else { continue }
            lines.append("\(key.scope.rawValue) \(key.period.rawValue) \(formatDollars(dollars))")
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? body.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: AppConstants.limitsFile.path) {
            _ = try? FileManager.default.replaceItemAt(AppConstants.limitsFile, withItemAt: tmp)
        } else {
            _ = try? FileManager.default.moveItem(at: tmp, to: AppConstants.limitsFile)
        }
    }

    static func setLimit(scope: ScopeKey, period: PeriodKey, action: String) {
        var limits = readLimits()
        let key = LimitKey(scope: scope, period: period)
        if action == "off" {
            limits.removeValue(forKey: key)
        } else if let dollars = parseDollars(action) {
            limits[key] = dollars
        }
        writeLimits(limits)
    }

    private static func readKey<T: RawRepresentable>(
        from url: URL,
        valid: T.Type,
        default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return defaultValue
        }
        let raw = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = T(rawValue: raw) else {
            return defaultValue
        }
        return key
    }

    private static func writeKey(_ value: String, to url: URL) {
        try? FileManager.default.createDirectory(
            at: AppConstants.configDir,
            withIntermediateDirectories: true
        )
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func formatDollars(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(value)
    }
}
