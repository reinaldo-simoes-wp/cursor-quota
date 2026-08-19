import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var gauge = StatusGauge(title: "…", limitColor: nil)
    @Published private(set) var tokenError: String?
    @Published private(set) var header = ""
    @Published private(set) var results: [PeriodKey: UsageData] = [:]
    @Published private(set) var errors: [PeriodKey: String] = [:]
    @Published private(set) var identity: CursorIdentity?

    @Published private(set) var isRefreshing = false {
        didSet {
            guard isRefreshing != oldValue else { return }
            isRefreshing ? startLoadingAnimation() : stopLoadingAnimation()
        }
    }

    /// Frame counter for the menu bar glyph wave; only advances while busy.
    @Published private(set) var loadingFrame = 0

    /// Per-column dot heights (1...5) for the selected period's spend trend.
    @Published private(set) var trendLevels: [Int]?

    @Published var selectedPeriod: PeriodKey {
        didSet {
            if persistConfig { ConfigStore.writePeriod(selectedPeriod) }
            updateGauge()
        }
    }

    @Published var scope: ScopeKey {
        didSet {
            if persistConfig { ConfigStore.writeScope(scope) }
        }
    }

    @Published var display: DisplayKey {
        didSet {
            if persistConfig { ConfigStore.writeDisplay(display) }
            updateGauge()
        }
    }

    @Published private(set) var limits: [LimitKey: Double] = [:]

    /// Model highlighted in the breakdown, which tints its share of the trend.
    @Published var selectedModel: String?

    /// In-memory scope for API calls; does not persist an admin fallback to `you`.
    private(set) var effectiveScope: ScopeKey = .you

    var loadingPhase: Double {
        Double(loadingFrame) * AppConstants.loadingPhaseStep
    }

    private var refreshTask: Task<Void, Never>?
    private var trendTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var refreshGeneration = 0

    /// Reused by trend-only refetches so switching periods costs at most five calls.
    private var lastCookie: String?
    private var lastExtras: [String: Any] = [:]
    private var lastRecentEvents: [[String: Any]] = []
    /// False when the event-log fetch failed, so an empty log is not read as zero spend.
    private var lastEventsAvailable = false
    private var trendCache: [LimitKey: [Int]] = [:]

    /// Nested loads (full refresh plus a trend refetch) share one animation.
    private var busyCount = 0 {
        didSet { isRefreshing = busyCount > 0 }
    }

    /// When false, menu actions update in-memory state only (preview harness).
    private var persistConfig = true

    init(preview: Bool = false) {
        persistConfig = !preview
        selectedPeriod = ConfigStore.readPeriod()
        scope = ConfigStore.readScope()
        display = ConfigStore.readDisplay()
        limits = ConfigStore.readLimits()
        guard !preview else { return }
        startAutoRefresh()
        refreshNow()
    }

    /// Sample data for offline UI previews (`scripts/preview-popover.sh`).
    static func previewSample() -> AppState {
        let state = AppState(preview: true)
        state.applyPreviewFixture()
        return state
    }

    func applyPreviewFixture() {
        header = "Cursor usage (yours)"
        identity = CursorIdentity(userID: 1, teamID: 42, teamName: "Acme", isAdmin: true)
        effectiveScope = .you
        selectedPeriod = .weekly
        display = .cost
        limits = [LimitKey(scope: .you, period: .weekly): 1000]
        results = [
            .daily: UsageData(
                totalInputTokens: 120_000,
                totalOutputTokens: 80_000,
                totalCacheWriteTokens: 10_000,
                totalCacheReadTokens: 50_000,
                totalCostCents: 412,
                aggregations: [
                    ModelAggregation(
                        modelIntent: "claude-sonnet",
                        totalCents: 280,
                        inputTokens: 90_000,
                        outputTokens: 60_000,
                        cacheWriteTokens: 5_000,
                        cacheReadTokens: 30_000
                    ),
                    ModelAggregation(
                        modelIntent: "gpt-4",
                        totalCents: 132,
                        inputTokens: 30_000,
                        outputTokens: 20_000,
                        cacheWriteTokens: 5_000,
                        cacheReadTokens: 20_000
                    ),
                ]
            ),
            .weekly: UsageData(
                totalInputTokens: 2_400_000,
                totalOutputTokens: 1_600_000,
                totalCacheWriteTokens: 200_000,
                totalCacheReadTokens: 900_000,
                totalCostCents: 18_740,
                aggregations: [
                    ModelAggregation(
                        modelIntent: "claude-sonnet",
                        totalCents: 12_400,
                        inputTokens: 1_500_000,
                        outputTokens: 1_000_000,
                        cacheWriteTokens: 120_000,
                        cacheReadTokens: 600_000
                    ),
                    ModelAggregation(
                        modelIntent: "gpt-4",
                        totalCents: 6_340,
                        inputTokens: 900_000,
                        outputTokens: 600_000,
                        cacheWriteTokens: 80_000,
                        cacheReadTokens: 300_000
                    ),
                ]
            ),
            .monthly: UsageData(
                totalInputTokens: 8_000_000,
                totalOutputTokens: 5_000_000,
                totalCacheWriteTokens: 500_000,
                totalCacheReadTokens: 2_000_000,
                totalCostCents: 48_300,
                aggregations: []
            ),
            .threeMonths: UsageData(
                totalInputTokens: 14_000_000,
                totalOutputTokens: 8_000_000,
                totalCacheWriteTokens: 700_000,
                totalCacheReadTokens: 3_000_000,
                totalCostCents: 82_000,
                aggregations: []
            ),
            .sixMonths: UsageData(
                totalInputTokens: 20_000_000,
                totalOutputTokens: 12_000_000,
                totalCacheWriteTokens: 1_000_000,
                totalCacheReadTokens: 4_000_000,
                totalCostCents: 120_000,
                aggregations: []
            ),
            .oneYear: UsageData(
                totalInputTokens: 40_000_000,
                totalOutputTokens: 24_000_000,
                totalCacheWriteTokens: 2_000_000,
                totalCacheReadTokens: 8_000_000,
                totalCostCents: 237_000,
                aggregations: []
            ),
        ]
        trendLevels = [1, 2, 3, 4, 5]
        gauge = StatusGauge(title: "$187.40/$1,000 · 4.0M", limitColor: .orange)
    }

    deinit {
        refreshTask?.cancel()
        trendTask?.cancel()
        timerTask?.cancel()
        animationTask?.cancel()
    }

    // MARK: - Loading animation

    private func beginBusy() { busyCount += 1 }
    private func endBusy() { busyCount = max(0, busyCount - 1) }

    private func startLoadingAnimation() {
        animationTask?.cancel()
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: AppConstants.loadingFrameNanoseconds)
                guard let self, !Task.isCancelled else { return }
                // Bounded so the sine argument cannot drift over a long uptime.
                self.loadingFrame = (self.loadingFrame + 1) % 100_000
            }
        }
    }

    private func stopLoadingAnimation() {
        animationTask?.cancel()
        animationTask = nil
        loadingFrame = 0
    }

    // MARK: - Refresh

    func startAutoRefresh() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.refreshInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                // Goes through refreshNow so there is a single owning task and generation.
                self.refreshNow()
            }
        }
    }

    func refreshNow() {
        refreshTask?.cancel()
        trendTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        // Marked busy synchronously so the glyph never shows a stale idle frame.
        beginBusy()
        refreshTask = Task { [weak self] in
            await self?.refresh(generation: generation)
            self?.endBusy()
        }
    }

    private func refresh(generation: Int) async {
        limits = ConfigStore.readLimits()

        do {
            if Task.isCancelled { return }
            let cookie = try Auth.sessionCookie()
            if Task.isCancelled { return }
            let who = try await CursorAPI.identity(cookie: cookie)
            if Task.isCancelled || generation != refreshGeneration { return }

            identity = who
            effectiveScope = resolvedScope(for: who)

            let extras = apiExtras(for: who, scope: effectiveScope)
            let fetched = await CursorAPI.fetchAllPeriods(cookie: cookie, extras: extras)
            if Task.isCancelled || generation != refreshGeneration { return }

            if fetched.errors.values.contains(where: { $0.contains("401") }) {
                throw TokenError.message("HTTP 401 — token rejected, re-login in Cursor")
            }

            tokenError = nil
            results = fetched.results
            errors = fetched.errors
            header = headerText(for: who, scope: effectiveScope)
            updateGauge()

            lastCookie = cookie
            lastExtras = extras
            lastRecentEvents = fetched.recentEvents
            lastEventsAvailable = fetched.recentError == nil
            trendCache.removeAll()

            let period = selectedPeriod
            let cents = await CursorAPI.fetchTrend(
                cookie: cookie,
                period: period,
                extras: extras,
                recentEvents: fetched.recentEvents,
                eventsAvailable: lastEventsAvailable
            )
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            applyTrend(cents, scope: effectiveScope, period: period)
        } catch is CancellationError {
            return
        } catch let error as TokenError {
            guard generation == refreshGeneration else { return }
            failClosed(message: error.localizedDescription)
        } catch {
            guard generation == refreshGeneration else { return }
            failClosed(message: error.localizedDescription)
        }
    }

    private func failClosed(message: String) {
        tokenError = message
        identity = nil
        results = [:]
        errors = [:]
        header = ""
        trendLevels = nil
        trendCache.removeAll()
        lastCookie = nil
        lastEventsAvailable = false
        gauge = StatusGauge(title: "⚠ Cursor", limitColor: nil)
    }

    // MARK: - Trend

    private func applyTrend(_ cents: [Int]?, scope: ScopeKey, period: PeriodKey) {
        if let cents {
            trendCache[LimitKey(scope: scope, period: period)] = Self.levels(from: cents)
        }
        // A late result must never overwrite whatever period is on screen now.
        guard period == selectedPeriod, scope == effectiveScope else { return }
        // A failed bucket must not read as a dip, so show no sparkline at all.
        trendLevels = cents.map(Self.levels(from:))
    }

    /// Refetches only the sparkline, reusing the last refresh's cookie and event log.
    private func refreshTrend() {
        guard let cookie = lastCookie else {
            refreshNow()
            return
        }
        trendTask?.cancel()
        let period = selectedPeriod
        let scope = effectiveScope
        let extras = lastExtras
        let events = lastRecentEvents
        let eventsAvailable = lastEventsAvailable
        let generation = refreshGeneration

        beginBusy()
        trendTask = Task { [weak self] in
            let cents = await CursorAPI.fetchTrend(
                cookie: cookie,
                period: period,
                extras: extras,
                recentEvents: events,
                eventsAvailable: eventsAvailable
            )
            guard let self, !Task.isCancelled, generation == self.refreshGeneration else {
                self?.endBusy()
                return
            }
            self.applyTrend(cents, scope: scope, period: period)
            self.endBusy()
        }
    }

    /// Scales bucket costs onto the glyph's dot heights.
    static func levels(from cents: [Int]) -> [Int] {
        guard let peak = cents.max(), peak > 0 else {
            return Array(repeating: 1, count: cents.count)
        }
        let span = Double(AppConstants.trendLevelSteps - 1)
        return cents.map { 1 + Int((Double($0) / Double(peak) * span).rounded()) }
    }

    // MARK: - Scope helpers

    func resolvedScope(for identity: CursorIdentity?) -> ScopeKey {
        guard let identity else { return .you }
        if scope == .team, identity.isAdmin, identity.teamID != nil {
            return .team
        }
        return .you
    }

    func headerText(for identity: CursorIdentity, scope: ScopeKey) -> String {
        if scope == .team {
            return "Cursor team usage (\(identity.teamName))"
        }
        return "Cursor usage (yours)"
    }

    func apiExtras(for identity: CursorIdentity, scope: ScopeKey) -> [String: Any] {
        if scope == .team, let teamID = identity.teamID {
            return ["teamId": teamID]
        }
        return ["userId": identity.userID]
    }

    // MARK: - Gauge

    private func updateGauge() {
        guard tokenError == nil, let data = results[selectedPeriod] else {
            gauge = StatusGauge(title: "⚠ Cursor", limitColor: nil)
            return
        }

        switch display {
        case .cost:
            let costCents = data.totalCostCents
            var title = Formatters.cost(cents: costCents)
            var color: LimitColor?
            if let limit = limits[LimitKey(scope: effectiveScope, period: selectedPeriod)] {
                title = "\(title)/\(Formatters.limitDollars(limit))"
                color = LimitColor.forPercent(Double(costCents) / 100.0 / limit)
            }
            gauge = StatusGauge(title: title, limitColor: color)
        case .tokens:
            gauge = StatusGauge(title: Formatters.tokens(data.ioTokens()), limitColor: nil)
        }
    }

    // MARK: - Menu actions

    func setLimit(scope: ScopeKey, period: PeriodKey, action: String) {
        ConfigStore.setLimit(scope: scope, period: period, action: action)
        limits = ConfigStore.readLimits()
        updateGauge()
    }

    func toggleModel(_ modelIntent: String) {
        selectedModel = selectedModel == modelIntent ? nil : modelIntent
    }

    /// Share of the period's spend attributable to the highlighted model.
    func selectedModelShare() -> Double? {
        guard let selectedModel,
              let data = results[selectedPeriod],
              data.totalCostCents > 0,
              let agg = data.aggregations.first(where: { $0.modelIntent == selectedModel })
        else { return nil }
        return Double(agg.totalCents) / Double(data.totalCostCents)
    }

    func selectPeriod(_ period: PeriodKey) {
        guard period != selectedPeriod else { return }
        // The next period has its own model list, so a stale highlight would mislead.
        selectedModel = nil
        selectedPeriod = period
        // Totals for every period are already cached; only the sparkline is period-specific.
        if let cached = trendCache[LimitKey(scope: effectiveScope, period: period)] {
            trendLevels = cached
        } else {
            trendLevels = nil
            refreshTrend()
        }
    }

    func selectScope(_ newScope: ScopeKey) {
        guard newScope != scope else { return }
        selectedModel = nil
        scope = newScope
        trendLevels = nil
        trendCache.removeAll()
        refreshNow()
    }

    func selectDisplay(_ newDisplay: DisplayKey) {
        display = newDisplay
    }
}
