import Foundation

/// Pure aggregation for the cost screen — a single pass over a flat
/// `[TokenEvent]` stream that splits it into today / this-month / rolling-5h /
/// rolling-7d windows, per-model breakdowns, and sparkline buckets.
///
/// Lives as a free `enum` so the detached refresh task in `CostStore` can call
/// it off the main actor without touching `@MainActor` state. `now` is
/// injectable so the window boundaries are testable.
enum CostSummary {
    static func summarize(events: [TokenEvent], now: Date = Date()) -> ProviderCost {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfDay = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfDay
        let currentHour = cal.dateComponents([.hour], from: now).hour ?? 0
        let currentDay = (cal.dateComponents([.day], from: now).day ?? 1) - 1
        let historyDays = yearHistoryDays(now: now)
        let historyStart = cal.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: startOfDay
        ) ?? startOfDay
        let last7Start = cal.date(byAdding: .day, value: -6, to: startOfDay) ?? startOfDay
        // Rolling windows for per-model breakdown — approximate the live
        // tile windows. We don't know the server's exact window alignment
        // for either, so "last N hours from now" is the practical proxy.
        // 5h matches Anthropic's rate-limit window; 7d matches both
        // providers' weekly tile.
        let recentStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)

        var todayDollars = 0.0, todayTokens = 0, todayBillable = 0
        var monthDollars = 0.0, monthTokens = 0, monthBillable = 0
        var totalDollars = 0.0, totalTokens = 0, totalBillable = 0
        var hourlyBuckets = Array(repeating: 0.0, count: currentHour + 1)
        var dailyBuckets = Array(repeating: 0.0, count: currentDay + 1)
        var historyTokenBuckets = Array(repeating: 0, count: historyDays)
        var historyBillableBuckets = Array(repeating: 0, count: historyDays)
        var last7DailyDollars = Array(repeating: 0.0, count: 7)
        // Filtered to non-zero token events so handshake/stub rows don't
        // show up as "unpriced" warnings — the user only cares about
        // models that actually moved tokens.
        var todayUnknown: Set<String> = []
        var monthUnknown: Set<String> = []
        var totalUnknown: Set<String> = []
        var totalMonthlyBuckets: [Date: Double] = [:]
        // Per-canonical-model billable tokens + dollars for calendar cost
        // windows. These drive the cost page's 今天 / 当月 / 历史 bar view.
        // Cache reads excluded from `tokens` (they don't pressure the
        // rate-limit counter), included in `dollars` (they cost real money).
        var todayTokensByModel: [String: Int] = [:]
        var todayDollarsByModel: [String: Double] = [:]
        var monthTokensByModel: [String: Int] = [:]
        var monthDollarsByModel: [String: Double] = [:]
        var totalTokensByModel: [String: Int] = [:]
        var totalDollarsByModel: [String: Double] = [:]

        // Rolling per-model windows retained for the usage page's 5h/week
        // breakdown.
        var recentTokensByModel: [String: Int] = [:]
        var recentDollarsByModel: [String: Double] = [:]
        var weekTokensByModel: [String: Int] = [:]
        var weekDollarsByModel: [String: Double] = [:]

        // Walk every event handed to us. CostStore now scans a long local-log
        // window so this pass can also compute all parsed history, while the
        // month/today/week/year views keep their own date gates below.
        for event in events {
            let cost = Pricing.cost(for: event)
            // Two parallel running totals: `tokens` is the wire-level sum
            // (ccusage parity); `billable` is input + output only, matching
            // Anthropic's claude.ai stats panel which excludes cache tokens.
            // Persisting both lets the Settings toggle flip the displayed
            // figure instantly without re-scanning session logs.
            let billable = event.inputTokens + event.outputTokens
            let tokens = billable + event.cacheCreationTokens + event.cacheReadTokens
            let isUnpriced = tokens > 0 && !Pricing.isKnown(event.model)
            let canon = Pricing.canonicalModelName(event.model)

            totalDollars += cost
            totalTokens += tokens
            totalBillable += billable
            if billable > 0 {
                totalTokensByModel[canon, default: 0] += billable
            }
            if cost > 0 {
                totalDollarsByModel[canon, default: 0] += cost
            }
            if isUnpriced { totalUnknown.insert(event.model) }
            if tokens > 0 {
                let eventMonth = cal.date(
                    from: cal.dateComponents([.year, .month], from: event.timestamp)
                ) ?? cal.startOfDay(for: event.timestamp)
                totalMonthlyBuckets[eventMonth, default: 0] += cost
            }

            if event.timestamp >= historyStart {
                let eventDay = cal.startOfDay(for: event.timestamp)
                let dayOffset = cal.dateComponents([.day], from: historyStart, to: eventDay).day ?? -1
                if historyTokenBuckets.indices.contains(dayOffset) {
                    historyTokenBuckets[dayOffset] += tokens
                    historyBillableBuckets[dayOffset] += billable
                }
            }

            if event.timestamp >= last7Start {
                let eventDay = cal.startOfDay(for: event.timestamp)
                let dayOffset = cal.dateComponents([.day], from: last7Start, to: eventDay).day ?? -1
                if last7DailyDollars.indices.contains(dayOffset) {
                    last7DailyDollars[dayOffset] += cost
                }
            }

            // Month aggregation gated separately now that the outer guard
            // is `min(monthStart, weekStart)` (so previous-month events
            // can reach the weekly slice).
            if event.timestamp >= monthStart {
                monthDollars += cost
                monthTokens += tokens
                monthBillable += billable
                let day = (cal.dateComponents([.day], from: event.timestamp).day ?? 1) - 1
                if day < dailyBuckets.count { dailyBuckets[day] += cost }
                if billable > 0 {
                    monthTokensByModel[canon, default: 0] += billable
                }
                if cost > 0 {
                    monthDollarsByModel[canon, default: 0] += cost
                }
                if isUnpriced { monthUnknown.insert(event.model) }
            }

            // Today is a strict subset of month
            if event.timestamp >= startOfDay {
                todayDollars += cost
                todayTokens += tokens
                todayBillable += billable
                let hour = cal.dateComponents([.hour], from: event.timestamp).hour ?? 0
                if hour < hourlyBuckets.count { hourlyBuckets[hour] += cost }
                if billable > 0 {
                    todayTokensByModel[canon, default: 0] += billable
                }
                if cost > 0 {
                    todayDollarsByModel[canon, default: 0] += cost
                }
                if isUnpriced { todayUnknown.insert(event.model) }
            }

            // Weekly rolling window slice — superset of recent, subset of
            // month (when month is short).
            if event.timestamp >= weekStart {
                if billable > 0 {
                    weekTokensByModel[canon, default: 0] += billable
                }
                if cost > 0 {
                    weekDollarsByModel[canon, default: 0] += cost
                }

                // 5h rolling window slice — strict subset of weekly.
                if event.timestamp >= recentStart {
                    if billable > 0 {
                        recentTokensByModel[canon, default: 0] += billable
                    }
                    if cost > 0 {
                        recentDollarsByModel[canon, default: 0] += cost
                    }
                }
            }
        }

        let totalSeries = runningSum(
            totalMonthlyBuckets.keys.sorted().map { totalMonthlyBuckets[$0] ?? 0 }
        )

        let todayRows = modelRows(
            tokensByModel: todayTokensByModel,
            dollarsByModel: todayDollarsByModel
        )
        let monthRows = modelRows(
            tokensByModel: monthTokensByModel,
            dollarsByModel: monthDollarsByModel
        )
        let totalRows = modelRows(
            tokensByModel: totalTokensByModel,
            dollarsByModel: totalDollarsByModel
        )
        let recentRows = modelRows(
            tokensByModel: recentTokensByModel,
            dollarsByModel: recentDollarsByModel
        )
        let weekRows = modelRows(
            tokensByModel: weekTokensByModel,
            dollarsByModel: weekDollarsByModel
        )

        return ProviderCost(
            today: CostWindow(
                dollars: todayDollars,
                tokens: todayTokens,
                billableTokens: todayBillable,
                series: runningSum(hourlyBuckets),
                label: "Today",
                error: nil,
                unknownModels: todayUnknown.sorted()
            ),
            month: CostWindow(
                dollars: monthDollars,
                tokens: monthTokens,
                billableTokens: monthBillable,
                series: runningSum(dailyBuckets),
                label: CostBucketing.currentMonthLabel(),
                error: nil,
                unknownModels: monthUnknown.sorted()
            ),
            total: CostWindow(
                dollars: totalDollars,
                tokens: totalTokens,
                billableTokens: totalBillable,
                series: totalSeries,
                label: "History",
                error: nil,
                unknownModels: totalUnknown.sorted()
            ),
            todayByModel: todayRows,
            monthByModel: monthRows,
            totalByModel: totalRows,
            recentByModel: recentRows,
            weekByModel: weekRows,
            last7DailyDollars: last7DailyDollars,
            dailyTokens: dailyTokenBuckets(
                start: historyStart,
                tokens: historyTokenBuckets,
                billableTokens: historyBillableBuckets,
                calendar: cal
            )
        )
    }

    static func yearHistoryDays(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        let yearStart = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        let yearDays = (cal.dateComponents([.day], from: yearStart, to: today).day ?? 0) + 1
        return max(1, yearDays)
    }

    private static func dailyTokenBuckets(
        start: Date,
        tokens: [Int],
        billableTokens: [Int],
        calendar: Calendar
    ) -> [DailyTokenBucket] {
        tokens.indices.map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
            return DailyTokenBucket(
                dayStart: day,
                tokens: tokens[index],
                billableTokens: billableTokens[index]
            )
        }
    }

    /// Build sorted `ModelUsageRow`s from the two parallel per-model maps
    /// for a given window. Shared between the 5h and weekly slices so
    /// both stay perfectly consistent in shape, sorting, and percent-share
    /// computation.
    private static func modelRows(
        tokensByModel: [String: Int],
        dollarsByModel: [String: Double]
    ) -> [ModelUsageRow] {
        let totalTokens = tokensByModel.values.reduce(0, +)
        let totalDollars = dollarsByModel.values.reduce(0, +)
        let canonicals = Set(tokensByModel.keys).union(dollarsByModel.keys)
        return canonicals.map { canon in
            let tokens = tokensByModel[canon] ?? 0
            let dollars = dollarsByModel[canon] ?? 0
            return ModelUsageRow(
                model: canon,
                displayName: prettyModelName(canon),
                tokens: tokens,
                dollars: dollars,
                percent: totalTokens > 0 ? Double(tokens) / Double(totalTokens) : 0,
                dollarPercent: totalDollars > 0 ? dollars / totalDollars : 0
            )
        }
        .sorted {
            // Tokens primary, dollars secondary — handles cache-read-only
            // rows (zero billable tokens, non-zero dollars) by sinking
            // them to the bottom but not disappearing.
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.dollars > $1.dollars
        }
    }

    /// Pretty-print the canonical model id for UI rows. Falls back to the
    /// raw id if no friendlier name is wired up yet — better than a blank.
    private static func prettyModelName(_ canonical: String) -> String {
        // Anthropic: "claude-opus-4-7" → "Opus 4.7"
        if canonical.hasPrefix("claude-") {
            let trimmed = String(canonical.dropFirst("claude-".count))
            // Split at first dash, then collapse remaining dashes into dots
            // so "opus-4-7" → "opus.4.7" → "Opus 4.7".
            guard let dash = trimmed.firstIndex(of: "-") else {
                return trimmed.capitalized
            }
            let family = String(trimmed[..<dash]).capitalized
            let version = trimmed[trimmed.index(after: dash)...]
                .replacingOccurrences(of: "-", with: ".")
            return "\(family) \(version)"
        }
        // OpenAI: keep as-is, just uppercase the GPT prefix.
        if canonical.hasPrefix("gpt-") {
            return canonical.replacingOccurrences(of: "gpt-", with: "GPT-")
        }
        // OpenAI reasoning family ("o3-pro", "o4-mini-high", etc.) — already
        // short and conventional, capitalize only the leading letter so it
        // matches the typographic weight of "GPT-..." / "Opus 4.7".
        if let first = canonical.first, first == "o", canonical.count > 1,
           canonical.dropFirst().first?.isNumber == true {
            return canonical.prefix(1).uppercased() + canonical.dropFirst()
        }
        return canonical
    }

    private static func runningSum(_ values: [Double]) -> [Double] {
        var out = [Double]()
        out.reserveCapacity(values.count)
        var sum = 0.0
        for v in values { sum += v; out.append(sum) }
        return out
    }
}
