import SwiftUI

struct TrendLandscape: View {
    @ObservedObject var appState: AppState

    private let landscapeRows = 13
    private let dotSize: CGFloat = 2.6
    private let gridHeight: CGFloat = 50
    /// Equal on all sides so the field sits evenly inside its container.
    private let inset: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spend trend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(caption)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(highlightShare == nil ? .secondary.opacity(0.65) : Color.accentColor)
                    .lineLimit(1)
            }

            DottedGraphGlyph(
                color: trendColor,
                levels: appState.trendLevels?.map(Double.init) ?? [],
                phase: appState.isRefreshing ? appState.loadingPhase : nil,
                buckets: AppConstants.trendBuckets,
                maxRows: landscapeRows,
                dotSize: dotSize,
                highlightFraction: highlightShare
            )
            .animation(.easeInOut(duration: 0.45), value: appState.trendLevels ?? [])
            .frame(height: gridHeight)
            .frame(maxWidth: .infinity)
            .padding(inset)
            .background {
                RoundedRectangle(cornerRadius: PopoverTheme.cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            }
        }
    }

    /// The trend is only fetched as period totals, so a highlighted model can only be
    /// shown as its share of spend applied evenly across the buckets.
    private var highlightShare: Double? {
        appState.isRefreshing ? nil : appState.selectedModelShare()
    }

    private var caption: String {
        if let share = highlightShare, let model = appState.selectedModel {
            return "\(model) · \(Int((share * 100).rounded()))% of spend"
        }
        return "oldest → newest"
    }

    private var trendColor: Color {
        guard appState.display.showsCeiling,
              let data = appState.results[appState.selectedPeriod],
              let limit = appState.limit(for: appState.selectedPeriod) else {
            return .primary
        }
        return appState.limitSwiftUIColor(costCents: data.totalCostCents, limit: limit)
    }
}
