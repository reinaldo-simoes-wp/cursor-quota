import Foundation

enum UsageMerge {
    static func mergeUsage(_ a: UsageData, _ b: UsageData) -> UsageData {
        var byModel: [String: ModelAggregation] = [:]
        for agg in a.aggregations + b.aggregations {
            var cur = byModel[agg.modelIntent] ?? ModelAggregation(
                modelIntent: agg.modelIntent,
                totalCents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheWriteTokens: 0,
                cacheReadTokens: 0
            )
            cur.totalCents += agg.totalCents
            cur.inputTokens += agg.inputTokens
            cur.outputTokens += agg.outputTokens
            cur.cacheWriteTokens += agg.cacheWriteTokens
            cur.cacheReadTokens += agg.cacheReadTokens
            byModel[agg.modelIntent] = cur
        }

        return UsageData(
            totalInputTokens: a.totalInputTokens + b.totalInputTokens,
            totalOutputTokens: a.totalOutputTokens + b.totalOutputTokens,
            totalCacheWriteTokens: a.totalCacheWriteTokens + b.totalCacheWriteTokens,
            totalCacheReadTokens: a.totalCacheReadTokens + b.totalCacheReadTokens,
            totalCostCents: a.totalCostCents + b.totalCostCents,
            aggregations: Array(byModel.values)
        )
    }

    static func isEmptyUsage(_ data: UsageData) -> Bool {
        if !data.aggregations.isEmpty { return false }
        if data.totalCostCents != 0 { return false }
        if data.totalInputTokens != 0 { return false }
        if data.totalOutputTokens != 0 { return false }
        if data.totalCacheWriteTokens != 0 { return false }
        if data.totalCacheReadTokens != 0 { return false }
        return true
    }

    static func eventTimestamp(_ event: [String: Any]) -> Int64 {
        if let n = jsonInt(event["timestamp"]) { return Int64(n) }
        return 0
    }

    static func usageFromEvents(_ events: [[String: Any]]) -> UsageData {
        var totals = UsageData.empty
        var byModel: [String: ModelAggregation] = [:]

        for event in events {
            let tokenUsage = event["tokenUsage"] as? [String: Any] ?? [:]
            let model = event["model"] as? String ?? "unknown"
            var cur = byModel[model] ?? ModelAggregation(
                modelIntent: model,
                totalCents: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheWriteTokens: 0,
                cacheReadTokens: 0
            )

            let cents = jsonInt(tokenUsage["totalCents"]) ?? 0
            cur.totalCents += cents
            totals.totalCostCents += cents

            let fields: [(String, WritableKeyPath<UsageData, Int>, WritableKeyPath<ModelAggregation, Int>)] = [
                ("inputTokens", \.totalInputTokens, \.inputTokens),
                ("outputTokens", \.totalOutputTokens, \.outputTokens),
                ("cacheWriteTokens", \.totalCacheWriteTokens, \.cacheWriteTokens),
                ("cacheReadTokens", \.totalCacheReadTokens, \.cacheReadTokens),
            ]

            for (field, totalKey, modelKey) in fields {
                let n = intValue(tokenUsage[field])
                cur[keyPath: modelKey] += n
                totals[keyPath: totalKey] += n
            }
            byModel[model] = cur
        }

        totals.aggregations = Array(byModel.values)
        return totals
    }

    static func combineUsage(
        agg: UsageData,
        events: [[String: Any]],
        startMs: Int64,
        endMs: Int64,
        nowMs: Int64
    ) -> UsageData {
        let inWindow = events.filter {
            let ts = eventTimestamp($0)
            return startMs <= ts && ts <= endMs
        }

        if isEmptyUsage(agg) {
            return usageFromEvents(inWindow)
        }

        let fillStart = nowMs - Int64(AppConstants.fillLagDays) * AppConstants.dayMs
        let fill = inWindow.filter { eventTimestamp($0) >= fillStart }
        if fill.isEmpty { return agg }

        // The fill window is shorter than the aggregate lag, so these events cannot
        // also be in `agg` — the event log's own model names merge into the
        // aggregate's rows without double counting.
        return mergeUsage(agg, usageFromEvents(fill))
    }

    private static func intValue(_ value: Any?) -> Int {
        jsonInt(value) ?? 0
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let n = Int(s) { return n }
        return nil
    }
}
