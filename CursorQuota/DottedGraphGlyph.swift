import SwiftUI

/// Interpolatable list of dot heights, so a changing sparkline morphs between
/// shapes instead of snapping. Vectors of unequal length are zero-padded.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: combine(lhs.values, rhs.values, +))
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: combine(lhs.values, rhs.values, -))
    }

    private static func combine(
        _ lhs: [Double],
        _ rhs: [Double],
        _ operation: (Double, Double) -> Double
    ) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            operation(
                index < lhs.count ? lhs[index] : 0,
                index < rhs.count ? rhs[index] : 0
            )
        }
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

/// Dot-matrix glyph echoing the app icon.
///
/// Idle, the columns are a sparkline of `levels` (the selected period's spend trend).
/// While loading, `phase` replaces them with a travelling wave.
///
/// Dots sit on a single square pitch derived from the row count, so horizontal and
/// vertical gaps match at any size. Columns are then filled to the available width
/// and the remainder is split evenly, keeping the margins consistent too.
struct DottedGraphGlyph: View, Animatable {
    var color: Color
    /// Each bucket's spend as a fraction of the busiest one; empty means no trend yet.
    var levels: [Double]
    var phase: Double?
    var maxRows: Int = AppConstants.glyphRows
    var dotSize: CGFloat = 1.7
    /// Portion of each column, measured from the baseline, drawn in `highlightColor`.
    var highlightFraction: Double?
    var highlightColor: Color = .accentColor

    var animatableData: AnimatableVector {
        get { AnimatableVector(values: levels) }
        set { levels = newValue.values }
    }

    var body: some View {
        Canvas { context, size in
            guard maxRows > 1 else { return }

            let pitch = (size.height - dotSize) / CGFloat(maxRows - 1)
            guard pitch > 0 else { return }

            let columns = max(2, Int((size.width - dotSize) / pitch) + 1)
            let gridWidth = CGFloat(columns - 1) * pitch + dotSize
            let originX = (size.width - gridWidth) / 2
            let heights = rowHeights(columns: columns)

            for column in 0..<columns {
                let filled = heights[column]
                let highlighted = highlightFraction.map {
                    Int((Double(filled) * min(max($0, 0), 1)).rounded())
                }

                for row in 0..<filled {
                    let rect = CGRect(
                        x: originX + CGFloat(column) * pitch,
                        y: size.height - dotSize - CGFloat(row) * pitch,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor(row: row, highlighted: highlighted)))
                }
            }
        }
    }

    private func dotColor(row: Int, highlighted: Int?) -> Color {
        guard let highlighted else { return color }
        return row < highlighted ? highlightColor : color.opacity(0.22)
    }

    /// Dot count per column, scaled so the busiest column fills the grid.
    ///
    /// A period can have more buckets than the grid has columns, so each column averages
    /// the buckets it spans. Averaging keeps a narrow glyph reading as spend per slice;
    /// taking the peak instead would saturate every column once spikes are common.
    /// Scaling happens after that, so the tallest column always reaches the top row
    /// whether the grid is wider or narrower than the data.
    private func rowHeights(columns: Int) -> [Int] {
        if let phase {
            return (0..<columns).map { column in
                let position = Double(column) / Double(columns) * AppConstants.loadingWaveSpan
                let wave = sin(phase - position * 0.7)
                return 1 + Int((((wave + 1) / 2) * Double(maxRows - 1)).rounded())
            }
        }

        // No trend yet: a flat baseline, never a ramp that would imply rising spend.
        guard !levels.isEmpty else { return Array(repeating: 1, count: columns) }

        let scale = Double(levels.count) / Double(columns)
        let averages = (0..<columns).map { column -> Double in
            // Half-open spans, so neighbouring columns never share a bucket and smear it.
            let first = min(Int(Double(column) * scale), levels.count - 1)
            let next = min(max(Int(Double(column + 1) * scale), first + 1), levels.count)
            let span = levels[first..<next]
            return span.reduce(0, +) / Double(span.count)
        }

        guard let peak = averages.max(), peak > 0 else {
            return Array(repeating: 1, count: columns)
        }
        return averages.map { 1 + Int(($0 / peak * Double(maxRows - 1)).rounded()) }
    }
}
