import Foundation

enum Formatters {
    static func tokens(_ n: Int) -> String {
        let value = Double(n)
        for (div, suffix) in [(1_000_000_000.0, "B"), (1_000_000.0, "M"), (1_000.0, "K")] {
            if value >= div {
                let v = value / div
                return v < 100 ? String(format: "%.1f%@", v, suffix) : String(format: "%.0f%@", v, suffix)
            }
        }
        return String(n)
    }

    static func cost(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let grouped = formatter.string(from: NSNumber(value: dollars)) ?? String(format: "%.2f", dollars)
        return "$\(grouped)"
    }

    static func rateCost(dollars: Double) -> String {
        if dollars >= 1 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            formatter.groupingSeparator = ","
            formatter.decimalSeparator = "."
            let grouped = formatter.string(from: NSNumber(value: dollars)) ?? String(format: "%.2f", dollars)
            return "$\(grouped)"
        }
        if dollars >= 0.01 {
            return String(format: "$%.3f", dollars)
        }
        return String(format: "$%.4f", dollars)
    }

    /// Average burn rate over the period, shown alongside the headline figure.
    static func ratePerHour(data: UsageData, display: DisplayKey, days: Int) -> String {
        let hours = Double(days * 24)
        guard hours > 0 else { return "" }
        switch display {
        case .cost:
            return "\(rateCost(dollars: Double(data.totalCostCents) / 100.0 / hours))/hr"
        case .tokens:
            return "\(tokens(Int(Double(data.ioTokens()) / hours)))/hr"
        }
    }

    /// Names a trend bucket by its own width, so an hourly slice reads as an hour and a
    /// multi-month slice as a range. Templates are localized, so 12- or 24-hour clocks
    /// and day/month order follow the user's settings.
    static func trendBucket(start: Date, end: Date) -> String {
        let span = end.timeIntervalSince(start)
        if span <= 2 * 3600 {
            return localized("jm", from: start)
        }
        if span <= 36 * 3600 {
            return localized("EEEd", from: start)
        }
        // Past about three weeks a slice spans months, so naming days stops being useful.
        if span <= 25 * 86_400 {
            return "\(localized("MMMd", from: start)) – \(localized("MMMd", from: end))"
        }
        return "\(localized("MMMy", from: start)) – \(localized("MMMy", from: end))"
    }

    private static func localized(_ template: String, from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    static func limitDollars(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
    }
}

