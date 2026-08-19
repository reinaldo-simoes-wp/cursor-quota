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
    /// Heights on the 1...trendLevelSteps scale; empty means no trend yet.
    var levels: [Double]
    var phase: Double?
    var buckets: Int = AppConstants.trendBuckets
    var maxRows: Int = AppConstants.trendLevelSteps
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
            guard maxRows > 1, buckets > 0 else { return }

            let pitch = (size.height - dotSize) / CGFloat(maxRows - 1)
            guard pitch > 0 else { return }

            let columns = max(2, Int((size.width - dotSize) / pitch) + 1)
            let gridWidth = CGFloat(columns - 1) * pitch + dotSize
            let originX = (size.width - gridWidth) / 2

            for column in 0..<columns {
                let position = Double(column) / Double(columns) * Double(buckets)
                let filled = rows(atBucketPosition: position)
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

    private func rows(atBucketPosition position: Double) -> Int {
        if let phase {
            let wave = sin(phase - position * 0.7)
            return 1 + Int((((wave + 1) / 2) * Double(maxRows - 1)).rounded())
        }
        if !levels.isEmpty {
            let index = min(max(Int(position), 0), levels.count - 1)
            return scaledRows(forLevel: levels[index])
        }
        // No trend yet: a flat baseline, never a ramp that would imply rising spend.
        return 1
    }

    /// `levels` are always on the 1...trendLevelSteps scale, so a taller grid has to
    /// stretch them rather than clamp everything into the bottom few rows.
    private func scaledRows(forLevel level: Double) -> Int {
        let steps = Double(AppConstants.trendLevelSteps)
        guard steps > 1 else { return 1 }
        let clamped = min(max(level, 1), steps)
        let fraction = (clamped - 1) / (steps - 1)
        return 1 + Int((fraction * Double(maxRows - 1)).rounded())
    }
}
