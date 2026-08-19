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
        didSet { ConfigStore.writePeriod(selectedPeriod); updateGauge() }
    }

    @Published var scope: ScopeKey {
        didSet { ConfigStore.writeScope(scope) }
    }

    @Published var display: DisplayKey {
        didSet { ConfigStore.writeDisplay(display); updateGauge() }
    }

    @Published private(set) var limits: [LimitKey: Double] = [:]

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

    init() {
        selectedPeriod = ConfigStore.readPeriod()
        scope = ConfigStore.readScope()
        display = ConfigStore.readDisplay()
        limits = ConfigStore.readLimits()
        startAutoRefresh()
        refreshNow()
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

    /// Scales bucket costs onto the glyph's five dot heights.
    static func levels(from cents: [Int]) -> [Int] {
        guard let peak = cents.max(), peak > 0 else {
            return Array(repeating: 1, count: cents.count)
        }
        return cents.map { 1 + Int((Double($0) / Double(peak) * 4).rounded()) }
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

        if display == .total {
            let costCents = data.totalCostCents
            var cost = Formatters.cost(cents: costCents)
            var color: LimitColor?
            if let limit = limits[LimitKey(scope: effectiveScope, period: selectedPeriod)] {
                cost = "\(cost)/\(Formatters.limitDollars(limit))"
                color = LimitColor.forPercent(Double(costCents) / 100.0 / limit)
            }
            gauge = StatusGauge(
                title: "\(cost) · \(Formatters.tokens(data.ioTokens()))",
                limitColor: color
            )
        } else {
            gauge = StatusGauge(
                title: Formatters.rateValue(data: data, display: display, days: selectedPeriod.days),
                limitColor: nil
            )
        }
    }

    // MARK: - Menu actions

    func setLimit(scope: ScopeKey, period: PeriodKey, action: String) {
        ConfigStore.setLimit(scope: scope, period: period, action: action)
        limits = ConfigStore.readLimits()
        updateGauge()
    }

    func selectPeriod(_ period: PeriodKey) {
        guard period != selectedPeriod else { return }
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
        scope = newScope
        trendLevels = nil
        trendCache.removeAll()
        refreshNow()
    }

    func selectDisplay(_ newDisplay: DisplayKey) {
        display = newDisplay
    }
}
