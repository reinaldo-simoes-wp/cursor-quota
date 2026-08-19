import Foundation

struct ModelAggregation: Sendable {
    var modelIntent: String
    var totalCents: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheWriteTokens: Int
    var cacheReadTokens: Int
}

struct UsageData: Sendable {
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalCacheWriteTokens: Int
    var totalCacheReadTokens: Int
    var totalCostCents: Int
    var aggregations: [ModelAggregation]

    static let empty = UsageData(
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCacheWriteTokens: 0,
        totalCacheReadTokens: 0,
        totalCostCents: 0,
        aggregations: []
    )

    func ioTokens() -> Int {
        totalInputTokens + totalOutputTokens
    }

    func cacheTokens() -> Int {
        totalCacheReadTokens + totalCacheWriteTokens
    }
}

struct CursorIdentity: Sendable {
    var userID: Int
    var teamID: Int?
    var teamName: String
    var isAdmin: Bool
}

enum CursorAPIError: LocalizedError {
    case http(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let detail):
            if code == 401 {
                return "HTTP 401 — token rejected, re-login in Cursor"
            }
            return "HTTP \(code)\(detail.isEmpty ? "" : " — \(detail)")"
        case .api(let message):
            return message
        }
    }
}

enum CursorAPI {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    static func apiPost(cookie: String, url: URL, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("WorkosCursorSessionToken=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("cursor-quota (native menu bar app)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorAPIError.api("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw CursorAPIError.http(http.statusCode, detail)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorAPIError.api("Invalid JSON response")
        }
        return json
    }

    static func identity(cookie: String) async throws -> CursorIdentity {
        let me: [String: Any]
        do {
            me = try await apiPost(cookie: cookie, url: AppConstants.meURL, payload: [:])
        } catch {
            throw TokenError.message("Could not fetch Cursor identity: \(error.localizedDescription)")
        }

        guard let userID = jsonInt(me["userId"]) else {
            throw TokenError.message("Cursor identity has no user id — API change?")
        }

        var teams: [[String: Any]] = []
        if let teamsResp = try? await apiPost(cookie: cookie, url: AppConstants.teamsURL, payload: [:]),
           let list = teamsResp["teams"] as? [[String: Any]] {
            teams = list
        }

        let teamID = jsonInt(me["teamId"])
        let team = teams.first { jsonInt($0["id"]) == teamID }
        let role = (team?["role"] as? String) ?? ""
        let teamName = (team?["name"] as? String)
            ?? (me["teamName"] as? String)
            ?? "team"

        return CursorIdentity(
            userID: userID,
            teamID: teamID,
            teamName: teamName,
            isAdmin: role.contains("ADMIN") || role.contains("OWNER")
        )
    }

    static func postUsage(
        cookie: String,
        startMs: Int64,
        endMs: Int64,
        extras: [String: Any] = [:]
    ) async throws -> UsageData {
        var payload: [String: Any] = [
            "startDate": String(startMs),
            "endDate": String(endMs),
        ]
        for (key, value) in extras { payload[key] = value }
        let json = try await apiPost(cookie: cookie, url: AppConstants.apiURL, payload: payload)
        return parseUsage(json)
    }

    static func fetchFilteredEvents(
        cookie: String,
        startMs: Int64,
        endMs: Int64,
        extras: [String: Any] = [:]
    ) async throws -> [[String: Any]] {
        var events: [[String: Any]] = []
        var page = 1
        var total: Int?

        while page <= AppConstants.filteredMaxPages {
            var payload: [String: Any] = [
                "startDate": String(startMs),
                "endDate": String(endMs),
                "page": page,
                "pageSize": AppConstants.filteredPageSize,
            ]
            for (key, value) in extras { payload[key] = value }

            let resp = try await apiPost(cookie: cookie, url: AppConstants.filteredURL, payload: payload)
            let batch = resp["usageEventsDisplay"] as? [[String: Any]] ?? []
            events.append(contentsOf: batch)

            if let count = jsonInt(resp["totalUsageEventsCount"]) {
                total = count
            }
            if let total, events.count >= total { break }
            if batch.count < AppConstants.filteredPageSize { break }
            page += 1
        }

        if page > AppConstants.filteredMaxPages {
            if total == nil || events.count < (total ?? 0) {
                let shown = total.map(String.init) ?? "?"
                throw CursorAPIError.api(
                    "usage events truncated at \(AppConstants.filteredMaxPages) pages (\(events.count)/\(shown))"
                )
            }
        }

        return events
    }

    static func fetchRange(
        cookie: String,
        startMs: Int64,
        endMs: Int64,
        extras: [String: Any] = [:],
        depth: Int = 0
    ) async throws -> UsageData {
        do {
            return try await postUsage(cookie: cookie, startMs: startMs, endMs: endMs, extras: extras)
        } catch let error as CursorAPIError {
            guard depth < 3,
                  case .http(400, let detail) = error,
                  let split = splitBoundaryMs(detail: detail, startMs: startMs, endMs: endMs) else {
                throw error
            }
            async let first = fetchRange(
                cookie: cookie,
                startMs: startMs,
                endMs: split - 1,
                extras: extras,
                depth: depth + 1
            )
            async let second = fetchRange(
                cookie: cookie,
                startMs: split,
                endMs: endMs,
                extras: extras,
                depth: depth + 1
            )
            return UsageMerge.mergeUsage(try await first, try await second)
        }
    }

    static func fetchUsage(cookie: String, days: Int, extras: [String: Any] = [:]) async throws -> UsageData {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return try await fetchRange(
            cookie: cookie,
            startMs: now - Int64(days) * AppConstants.dayMs,
            endMs: now,
            extras: extras
        )
    }

    static func fetchAllPeriods(
        cookie: String,
        extras: [String: Any]
    ) async -> (results: [PeriodKey: UsageData], errors: [PeriodKey: String], recentEvents: [[String: Any]], recentError: String?) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var results: [PeriodKey: UsageData] = [:]
        var errors: [PeriodKey: String] = [:]
        var recentEvents: [[String: Any]] = []
        var recentError: String?

        await withTaskGroup(of: FetchResult.self) { group in
            for period in PeriodKey.allCases {
                group.addTask {
                    do {
                        let usage = try await fetchUsage(cookie: cookie, days: period.days, extras: extras)
                        return .period(period, usage: usage, error: nil)
                    } catch {
                        return .period(period, usage: nil, error: error.localizedDescription)
                    }
                }
            }
            group.addTask {
                do {
                    let events = try await fetchFilteredEvents(
                        cookie: cookie,
                        startMs: nowMs - Int64(AppConstants.aggLagDays) * AppConstants.dayMs,
                        endMs: nowMs,
                        extras: extras
                    )
                    return .recent(events: events, error: nil)
                } catch {
                    return .recent(events: nil, error: error.localizedDescription)
                }
            }

            for await result in group {
                switch result {
                case .period(let key, let usage, let error):
                    if let usage {
                        results[key] = usage
                    } else {
                        errors[key] = error ?? "unknown error"
                    }
                case .recent(let events, let error):
                    if let events {
                        recentEvents = events
                    } else {
                        recentError = error
                    }
                }
            }
        }

        for period in PeriodKey.allCases {
            let startMs = nowMs - Int64(period.days) * AppConstants.dayMs
            if let agg = results[period] {
                if UsageMerge.isEmptyUsage(agg) {
                    if let recentError {
                        results.removeValue(forKey: period)
                        errors[period] = recentError
                    } else {
                        results[period] = UsageMerge.combineUsage(
                            agg: agg,
                            events: recentEvents,
                            startMs: startMs,
                            endMs: nowMs,
                            nowMs: nowMs
                        )
                    }
                } else if recentError == nil {
                    results[period] = UsageMerge.combineUsage(
                        agg: agg,
                        events: recentEvents,
                        startMs: startMs,
                        endMs: nowMs,
                        nowMs: nowMs
                    )
                }
            } else if recentError == nil, period.days <= AppConstants.aggLagDays {
                results[period] = UsageMerge.combineUsage(
                    agg: .empty,
                    events: recentEvents,
                    startMs: startMs,
                    endMs: nowMs,
                    nowMs: nowMs
                )
                errors.removeValue(forKey: period)
            }
        }

        return (results, errors, recentEvents, recentError)
    }

    /// Cost per equal-width slice of the selected period, for the menu bar glyph and the
    /// panel's spend trend.
    ///
    /// Every slice is cut at the aggregate-lag boundary rather than merged with
    /// `combineUsage`. That helper overlays the last few days *relative to now*,
    /// which is right for a period total ending at now but wrong for a mid-window
    /// bucket: a weekly bucket ending four days ago would silently drop its
    /// in-lag spend. Here the part older than the lag comes from the aggregate
    /// and the part newer than it comes from the event log, with no overlap.
    ///
    /// Returns nil if any needed source is unavailable, so a fetch error is never
    /// drawn as a dip.
    static func fetchTrend(
        cookie: String,
        period: PeriodKey,
        extras: [String: Any],
        recentEvents: [[String: Any]],
        eventsAvailable: Bool
    ) async -> [Int]? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let windowMs = Int64(period.days) * AppConstants.dayMs
        let startMs = nowMs - windowMs
        let buckets = AppConstants.trendBuckets(for: period)
        let bucketMs = windowMs / Int64(buckets)
        let lagStartMs = nowMs - Int64(AppConstants.aggLagDays) * AppConstants.dayMs

        func range(_ index: Int) -> (start: Int64, end: Int64) {
            let start = startMs + Int64(index) * bucketMs
            let end = index == buckets - 1 ? nowMs : start + bucketMs - 1
            return (start, end)
        }

        var cents = Array(repeating: 0, count: buckets)
        var pending: [Int] = []

        for index in 0..<buckets {
            let bucket = range(index)

            // Newer than the lag: the aggregate has nothing here, events are it.
            let eventsStart = max(bucket.start, lagStartMs)
            if eventsStart <= bucket.end {
                guard eventsAvailable else { return nil }
                let slice = recentEvents.filter {
                    let ts = UsageMerge.eventTimestamp($0)
                    return eventsStart <= ts && ts <= bucket.end
                }
                cents[index] = UsageMerge.usageFromEvents(slice).totalCostCents
            }

            // Older than the lag: needs its own aggregate call.
            if bucket.start < lagStartMs {
                pending.append(index)
            }
        }

        guard !pending.isEmpty else { return cents }

        var failed = false
        await withTaskGroup(of: (Int, Int?).self) { group in
            for index in pending {
                group.addTask {
                    let bucket = range(index)
                    let aggEnd = min(bucket.end, lagStartMs - 1)
                    guard let agg = try? await fetchRange(
                        cookie: cookie,
                        startMs: bucket.start,
                        endMs: aggEnd,
                        extras: extras
                    ) else {
                        return (index, nil)
                    }
                    return (index, agg.totalCostCents)
                }
            }
            for await (index, value) in group {
                if let value {
                    cents[index] += value
                } else {
                    failed = true
                }
            }
        }

        return failed ? nil : cents
    }

    private enum FetchResult {
        case period(PeriodKey, usage: UsageData?, error: String?)
        case recent(events: [[String: Any]]?, error: String?)
    }

    private static func splitBoundaryMs(detail: String, startMs: Int64, endMs: Int64) -> Int64? {
        guard detail.contains("Split the query") else { return nil }
        let pattern = #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?)Z"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(detail.startIndex..<detail.endIndex, in: detail)
        let matches = regex.matches(in: detail, range: range)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        var stamps: [Int64] = []
        for match in matches {
            guard let r = Range(match.range(at: 1), in: detail) else { continue }
            let text = String(detail[r]) + "Z"
            let date = formatter.date(from: text) ?? fallback.date(from: text)
            if let date {
                stamps.append(Int64(date.timeIntervalSince1970 * 1000))
            }
        }
        let inside = stamps.filter { startMs < $0 && $0 < endMs }
        return inside.max()
    }

    private static func parseUsage(_ json: [String: Any]) -> UsageData {
        let aggregations = (json["aggregations"] as? [[String: Any]] ?? []).map { agg in
            ModelAggregation(
                modelIntent: agg["modelIntent"] as? String ?? "unknown",
                totalCents: jsonInt(agg["totalCents"]) ?? 0,
                inputTokens: intValue(agg["inputTokens"]),
                outputTokens: intValue(agg["outputTokens"]),
                cacheWriteTokens: intValue(agg["cacheWriteTokens"]),
                cacheReadTokens: intValue(agg["cacheReadTokens"])
            )
        }
        return UsageData(
            totalInputTokens: intValue(json["totalInputTokens"]),
            totalOutputTokens: intValue(json["totalOutputTokens"]),
            totalCacheWriteTokens: intValue(json["totalCacheWriteTokens"]),
            totalCacheReadTokens: intValue(json["totalCacheReadTokens"]),
            totalCostCents: jsonInt(json["totalCostCents"]) ?? 0,
            aggregations: aggregations
        )
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
