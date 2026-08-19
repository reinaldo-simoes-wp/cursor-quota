import SwiftUI

struct HeroSpendView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let data = appState.results[appState.selectedPeriod] {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryValue(data))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(PopoverTheme.valueAnimation, value: primaryValue(data))
                        .foregroundStyle(heroColor(data))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(secondaryValue(data))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(PopoverTheme.valueAnimation, value: secondaryValue(data))
                        .foregroundStyle(.secondary)
                        // One line always, so the hero block keeps a constant height.
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if appState.display.showsCeiling, let limit = appState.limit(for: appState.selectedPeriod) {
                    limitArc(data: data, limit: limit)
                }
            }
        } else if let error = appState.errors[appState.selectedPeriod] {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }
        } else {
            HStack(spacing: 8) {
                if appState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(appState.isRefreshing ? "Loading usage…" : "No data for this period")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func limitArc(data: UsageData, limit: Double) -> some View {
        let pct = appState.limitPercent(costCents: data.totalCostCents, limit: limit)
        let tint = appState.limitSwiftUIColor(costCents: data.totalCostCents, limit: limit)

        Menu {
            LimitsControl(appState: appState, embedded: true)
        } label: {
            CeilingArc(percent: pct, color: tint)
                .frame(width: 54, height: 54)
                // The arc is a stroke around empty space, which takes no hits of its own.
                .contentShape(Circle())
                .help("Spend ceiling — tap for presets")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func primaryValue(_ data: UsageData) -> String {
        switch appState.display {
        case .cost:
            let cost = Formatters.cost(cents: data.totalCostCents)
            guard let limit = appState.limit(for: appState.selectedPeriod) else { return cost }
            return "\(cost)/\(Formatters.limitDollars(limit))"
        case .tokens:
            return Formatters.tokens(data.ioTokens())
        }
    }

    private func secondaryValue(_ data: UsageData) -> String {
        let rate = Formatters.ratePerHour(
            data: data,
            display: appState.display,
            days: appState.selectedPeriod.days
        )

        switch appState.display {
        case .cost:
            var parts = ["\(Formatters.tokens(data.ioTokens())) tokens", rate]
            if let limit = appState.limit(for: appState.selectedPeriod) {
                let pct = appState.limitPercent(costCents: data.totalCostCents, limit: limit)
                parts.append("\(Int((pct * 100).rounded()))% of ceiling")
            }
            return parts.joined(separator: " · ")
        case .tokens:
            return "\(Formatters.cost(cents: data.totalCostCents)) · \(rate)"
        }
    }

    private func heroColor(_ data: UsageData) -> Color {
        guard appState.display.showsCeiling,
              let limit = appState.limit(for: appState.selectedPeriod) else {
            return .primary
        }
        return appState.limitSwiftUIColor(costCents: data.totalCostCents, limit: limit)
    }
}

struct CeilingArc: View {
    var percent: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: min(max(percent, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(PopoverTheme.valueAnimation, value: percent)
            Text(arcLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
                .animation(PopoverTheme.valueAnimation, value: arcLabel)
                .foregroundStyle(color)
        }
    }

    private var arcLabel: String {
        if percent >= 1 {
            return String(format: "%.0f%%", percent * 100)
        }
        return String(format: "%.0f%%", max(percent, 0) * 100)
    }
}

