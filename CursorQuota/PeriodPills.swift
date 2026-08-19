import SwiftUI

struct PeriodPills: View {
    @ObservedObject var appState: AppState

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Period")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PeriodKey.allCases) { period in
                    pill(for: period)
                }
            }
        }
    }

    @ViewBuilder
    private func pill(for period: PeriodKey) -> some View {
        let selected = period == appState.selectedPeriod
        Button {
            appState.selectPeriod(period)
        } label: {
            VStack(spacing: 3) {
                Text(period.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(pillSubtitle(for: period))
                    .font(.system(size: 9, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(PopoverTheme.valueAnimation, value: pillSubtitle(for: period))
                    .foregroundStyle(selected ? Color.primary.opacity(0.7) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            // Fixed so switching periods never reflows the panel.
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .foregroundStyle(pillForeground(for: period, selected: selected))
        }
        .buttonStyle(.plain)
        .help(pillHelp(for: period))
    }

    /// Never nil, so a pill keeps its height whether or not the period has data.
    private func pillSubtitle(for period: PeriodKey) -> String {
        if let data = appState.results[period] {
            switch appState.display {
            case .cost: return Formatters.cost(cents: data.totalCostCents)
            case .tokens: return Formatters.tokens(data.ioTokens())
            }
        }
        return appState.errors[period] != nil ? "⚠" : "—"
    }

    private func pillHelp(for period: PeriodKey) -> String {
        if let data = appState.results[period] {
            return "\(period.label): \(Formatters.cost(cents: data.totalCostCents)) · \(Formatters.tokens(data.ioTokens())) tokens"
        }
        if let error = appState.errors[period] {
            return "\(period.label): \(error)"
        }
        return period.label
    }

    private func pillForeground(for period: PeriodKey, selected: Bool) -> Color {
        guard let data = appState.results[period],
              let limit = appState.limit(for: period) else {
            return selected ? .primary : .secondary
        }
        let tint = appState.limitSwiftUIColor(costCents: data.totalCostCents, limit: limit)
        return selected ? tint : tint.opacity(0.85)
    }
}
