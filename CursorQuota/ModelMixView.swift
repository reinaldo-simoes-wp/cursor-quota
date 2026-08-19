import SwiftUI

struct ModelMixView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if let data = appState.results[appState.selectedPeriod] {
            let aggs = data.aggregations.sorted { $0.totalCents > $1.totalCents }

            VStack(alignment: .leading, spacing: 8) {
                Text("Models · \(appState.selectedPeriod.label.lowercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if aggs.isEmpty {
                    Text("No per-model breakdown for this period")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    let shown = Array(aggs.prefix(PopoverTheme.maxModelRows))
                    ForEach(shown, id: \.modelIntent) { agg in
                        ModelRow(
                            appState: appState,
                            agg: agg,
                            totalCents: max(data.totalCostCents, 1)
                        )
                    }

                    if aggs.count > shown.count {
                        let hidden = aggs.dropFirst(shown.count)
                        let hiddenCents = hidden.reduce(0) { $0 + $1.totalCents }
                        Text("+\(hidden.count) more · \(Formatters.cost(cents: hiddenCents))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Cache tokens: \(Formatters.tokens(data.cacheTokens()))")
                    .font(.system(size: 10, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(PopoverTheme.valueAnimation, value: data.cacheTokens())
                    .foregroundStyle(.secondary.opacity(0.65))
            }
        }
    }
}

private struct ModelRow: View {
    @ObservedObject var appState: AppState
    let agg: ModelAggregation
    let totalCents: Int

    @State private var isHovering = false

    var body: some View {
        let io = agg.inputTokens + agg.outputTokens
        let cache = agg.cacheReadTokens + agg.cacheWriteTokens
        let fraction = Double(agg.totalCents) / Double(totalCents)
        let selected = appState.selectedModel == agg.modelIntent

        Button {
            appState.toggleModel(agg.modelIntent)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agg.modelIntent)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Formatters.cost(cents: agg.totalCents))
                        .font(.system(size: 11, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(PopoverTheme.valueAnimation, value: agg.totalCents)
                        .layoutPriority(1)
                }
                .foregroundStyle(selected ? Color.accentColor : .primary)

                DottedBar(
                    fraction: fraction,
                    color: selected ? .accentColor : .primary
                )
                .animation(PopoverTheme.valueAnimation, value: fraction)

                // Share replaces nothing, so the row height is the same either way.
                Text(
                    selected
                        ? "\(Int((fraction * 100).rounded()))% of spend · \(Formatters.tokens(io)) io · \(Formatters.tokens(cache)) cache"
                        : "\(Formatters.tokens(io)) io · \(Formatters.tokens(cache)) cache"
                )
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.accentColor.opacity(0.9) : .secondary.opacity(0.65))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill(selected: selected))
            }
            // Text and Canvas only take hits on their glyphs, so the row needs its own shape.
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(PopoverTheme.valueAnimation, value: isHovering)
        .help(selected ? "Clear highlight" : "Highlight \(agg.modelIntent) in the trend")
    }

    /// Rows are otherwise indistinguishable from copy, so hover marks them as controls.
    private func rowFill(selected: Bool) -> Color {
        if selected { return Color.accentColor.opacity(isHovering ? 0.16 : 0.1) }
        return isHovering ? Color.secondary.opacity(0.12) : .clear
    }
}

struct DottedBar: View, Animatable {
    var fraction: Double
    var color: Color
    var maxDots: Int = 24
    var dotSize: CGFloat = 3
    var gap: CGFloat = 2

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let filled = Int((min(max(fraction, 0), 1) * Double(maxDots)).rounded())
            for index in 0..<maxDots {
                let x = CGFloat(index) * (dotSize + gap)
                guard x + dotSize <= size.width else { break }
                let rect = CGRect(
                    x: x,
                    y: (size.height - dotSize) / 2,
                    width: dotSize,
                    height: dotSize
                )
                let fill = index < filled ? color : color.opacity(0.14)
                context.fill(Path(ellipseIn: rect), with: .color(fill))
            }
        }
        .frame(height: dotSize + 2)
    }
}
