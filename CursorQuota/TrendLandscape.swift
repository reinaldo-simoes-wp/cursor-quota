import SwiftUI

struct TrendLandscape: View {
    @ObservedObject var appState: AppState

    @State private var hoveredBucket: Int?

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
                Text(hoveredLabel ?? "oldest → newest")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(hoveredLabel == nil ? Color.secondary.opacity(0.65) : Color.primary)
                    .lineLimit(1)
            }

            DottedGraphGlyph(
                color: trendColor,
                levels: appState.trendLevels ?? [],
                phase: appState.isRefreshing ? appState.loadingPhase : nil,
                maxRows: landscapeRows,
                dotSize: dotSize,
                highlightFraction: highlightShare
            )
            // Morphing only reads as a trend changing when the buckets line up; a period
            // with a different bucket count is different data, so it swaps outright.
            .id(appState.trendLevels?.count ?? 0)
            .animation(.easeInOut(duration: 0.45), value: appState.trendLevels ?? [])
            .frame(height: gridHeight)
            .frame(maxWidth: .infinity)
            .overlay { hoverReadout }
            .padding(inset)
            .background {
                RoundedRectangle(cornerRadius: PopoverTheme.cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            }
            // A held position belongs to the series it was taken over, not the next one.
            .onChange(of: appState.trendLevels?.count) { _ in hoveredBucket = nil }
        }
        .onDisappear { hoveredBucket = nil }
    }

    /// Vertical rule over the hovered bucket, so the caption's time range is anchored to
    /// a place on the graph rather than left to be guessed.
    private var hoverReadout: some View {
        GeometryReader { proxy in
            let buckets = appState.trendLevels?.count ?? 0
            ZStack(alignment: .leading) {
                if let bucket = activeBucket, buckets > 0 {
                    let step = proxy.size.width / CGFloat(buckets)
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: (CGFloat(bucket) + 0.5) * step)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    guard buckets > 0, proxy.size.width > 0 else {
                        hoveredBucket = nil
                        return
                    }
                    let fraction = min(max(point.x / proxy.size.width, 0), 0.999)
                    hoveredBucket = Int(fraction * CGFloat(buckets))
                case .ended:
                    hoveredBucket = nil
                }
            }
        }
    }

    /// The bucket the marker and caption both describe.
    ///
    /// A refresh redraws the grid as the loading wave and then replaces the buckets, so
    /// the marker has nothing to point at and the caption would name the wrong window.
    private var activeBucket: Int? {
        guard !appState.isRefreshing,
              let hoveredBucket,
              let count = appState.trendLevels?.count,
              hoveredBucket < count
        else { return nil }
        return hoveredBucket
    }

    private var hoveredLabel: String? {
        activeBucket.flatMap(appState.trendBucketLabel)
    }

    /// The trend is only fetched as period totals, so a highlighted model can only be
    /// shown as its share of spend applied evenly across the buckets.
    private var highlightShare: Double? {
        appState.isRefreshing ? nil : appState.selectedModelShare()
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
