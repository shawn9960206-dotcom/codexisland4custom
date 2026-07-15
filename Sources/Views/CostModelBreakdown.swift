import SwiftUI

// MARK: - Cost page model breakdown

/// Cost-specific per-model view. It replaces the old 5h/week cost split with
/// the calendar windows the user actually asked for: today, current month,
/// and all parsed local history. The layout is intentionally table-like with
/// compact horizontal bars so it reads like the existing bar-chart language
/// without cramming three oversized dollar tiles into one half of the panel.
struct CostModelBreakdown: View {
    let provider: AlertEngine.Provider

    @ObservedObject private var costStore = CostStore.shared
    @ObservedObject private var stylePref = CostStylePref.shared
    @ObservedObject private var tokenMode = TokenCountModeStore.shared
    @ObservedObject private var agentConfig = AgentConfigurationStore.shared

    private var color: Color {
        switch provider {
        case .claude: return IslandColor.claude
        case .codex:  return IslandColor.codex
        }
    }
    private var providerName: String {
        agentConfig.displayName(for: provider)
    }

    private var cost: ProviderCost {
        switch provider {
        case .claude: return costStore.claude
        case .codex:  return costStore.codex
        }
    }

    private var rows: [CostModelJoinedRow] {
        let today = Dictionary(uniqueKeysWithValues: cost.todayByModel.map { ($0.model, $0) })
        let month = Dictionary(uniqueKeysWithValues: cost.monthByModel.map { ($0.model, $0) })
        let total = Dictionary(uniqueKeysWithValues: cost.totalByModel.map { ($0.model, $0) })
        let keys = Set(today.keys).union(month.keys).union(total.keys)
        let joined = keys.map { key in
            CostModelJoinedRow(
                model: key,
                displayName: total[key]?.displayName ?? month[key]?.displayName ?? today[key]?.displayName ?? key,
                today: today[key],
                month: month[key],
                total: total[key]
            )
        }
        let sorted: [CostModelJoinedRow]
        switch stylePref.style {
        case .tokens:
            sorted = joined.sorted { lhs, rhs in
                if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens > rhs.totalTokens }
                return lhs.totalDollars > rhs.totalDollars
            }
        default:
            sorted = joined.sorted { lhs, rhs in
                if lhs.totalDollars != rhs.totalDollars { return lhs.totalDollars > rhs.totalDollars }
                return lhs.totalTokens > rhs.totalTokens
            }
        }
        return Array(sorted.prefix(costModelRowLimit))
    }

    private var maxima: CostModelJoinedRow.Amounts {
        rows.reduce(.zero) { partial, row in
            .init(
                today: max(partial.today, row.amount(.today, metric: metric)),
                month: max(partial.month, row.amount(.month, metric: metric)),
                total: max(partial.total, row.amount(.total, metric: metric))
            )
        }
    }

    private var metric: CostModelMetric {
        stylePref.style == .tokens ? .tokens(tokenMode.mode) : .dollars
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if rows.isEmpty {
                Spacer(minLength: 0)
                Text(L10n.tr("no %@ cost history yet", providerName))
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 5) {
                    columnHeader
                    ForEach(Array(rows.enumerated()), id: \.element.model) { idx, row in
                        CostModelBreakdownRow(
                            row: row,
                            metric: metric,
                            maxima: maxima,
                            color: color,
                            weight: costModelRowWeights[min(idx, costModelRowWeights.count - 1)]
                        )
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(L10n.tr("BY MODEL"))
                .font(Typography.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.58))
            Text(metric.headerCaption)
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
            warningBadge(for: cost.today.unknownModels.count + cost.month.unknownModels.count + cost.total.unknownModels.count)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CostModelBreakdownRow.nameWidth)
            Text(L10n.tr("Today"))
                .costColumnHeader(width: CostModelBreakdownRow.valueWidth)
            Text(L10n.tr("This month"))
                .costColumnHeader(width: CostModelBreakdownRow.valueWidth)
            Text(L10n.tr("History"))
                .costColumnHeader(width: CostModelBreakdownRow.valueWidth)
        }
    }

    @ViewBuilder
    private func warningBadge(for count: Int) -> some View {
        if count > 0 {
            Text(L10n.tr("⚠ unpriced"))
                .font(Typography.micro)
                .foregroundStyle(.orange.opacity(0.8))
        }
    }
}

private let costModelRowLimit = 5
private let costModelRowWeights: [Double] = [0.90, 0.68, 0.52, 0.40, 0.32]

private enum CostModelWindow { case today, month, total }

private enum CostModelMetric {
    case dollars
    case tokens(TokenCountMode)

    var headerCaption: String {
        switch self {
        case .dollars: return L10n.tr("USD")
        case .tokens: return L10n.tr("TOKENS")
        }
    }
}

private struct CostModelJoinedRow {
    struct Amounts {
        let today: Double
        let month: Double
        let total: Double
        static let zero = Amounts(today: 0, month: 0, total: 0)
    }

    let model: String
    let displayName: String
    let today: ModelUsageRow?
    let month: ModelUsageRow?
    let total: ModelUsageRow?

    var totalDollars: Double { total?.dollars ?? month?.dollars ?? today?.dollars ?? 0 }
    var totalTokens: Int { total?.tokens ?? month?.tokens ?? today?.tokens ?? 0 }

    func amount(_ window: CostModelWindow, metric: CostModelMetric) -> Double {
        let row: ModelUsageRow? = {
            switch window {
            case .today: return today
            case .month: return month
            case .total: return total
            }
        }()
        guard let row else { return 0 }
        switch metric {
        case .dollars:
            return row.dollars
        case .tokens:
            return Double(row.tokens)
        }
    }

    func formatted(_ window: CostModelWindow, metric: CostModelMetric) -> String {
        let value = amount(window, metric: metric)
        switch metric {
        case .dollars:
            return Self.formatDollars(value)
        case .tokens:
            return Self.formatTokens(Int(value))
        }
    }

    private static func formatDollars(_ amount: Double) -> String {
        if amount <= 0 { return "$0" }
        if amount < 1 { return String(format: "$%.2f", amount) }
        if amount < 100 { return String(format: "$%.1f", amount) }
        if amount < 10_000 { return String(format: "$%.0f", amount) }
        return String(format: "$%.1fk", amount / 1_000)
    }

    private static func formatTokens(_ n: Int) -> String {
        let v = Double(n)
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 { return String(format: "%.0fK", v / 1_000) }
        if n < 1_000_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        return String(format: "%.1fB", v / 1_000_000_000)
    }
}

private struct CostModelBreakdownRow: View {
    let row: CostModelJoinedRow
    let metric: CostModelMetric
    let maxima: CostModelJoinedRow.Amounts
    let color: Color
    let weight: Double

    static let nameWidth: CGFloat = 144
    static let valueWidth: CGFloat = 68

    var body: some View {
        HStack(spacing: 8) {
            Text(row.displayName)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.80))
                .frame(width: Self.nameWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            CostMiniBarCell(
                valueText: row.formatted(.today, metric: metric),
                amount: row.amount(.today, metric: metric),
                maxAmount: maxima.today,
                color: color,
                opacity: weight
            )
            .frame(width: Self.valueWidth)

            CostMiniBarCell(
                valueText: row.formatted(.month, metric: metric),
                amount: row.amount(.month, metric: metric),
                maxAmount: maxima.month,
                color: color,
                opacity: weight
            )
            .frame(width: Self.valueWidth)

            CostMiniBarCell(
                valueText: row.formatted(.total, metric: metric),
                amount: row.amount(.total, metric: metric),
                maxAmount: maxima.total,
                color: color,
                opacity: weight
            )
            .frame(width: Self.valueWidth)
        }
    }
}

private struct CostMiniBarCell: View {
    let valueText: String
    let amount: Double
    let maxAmount: Double
    let color: Color
    let opacity: Double

    private var fraction: CGFloat {
        guard maxAmount > 0 else { return 0 }
        return CGFloat(min(1, max(0, amount / maxAmount)))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(valueText)
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(amount > 0 ? 0.74 : 0.28))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.055))
                    if amount > 0 {
                        Capsule()
                            .fill(color.opacity(max(0.18, opacity)))
                            .frame(width: max(3, geo.size.width * fraction))
                            .shadow(color: color.opacity(opacity * 0.45), radius: 4)
                            .animation(.strongEaseOut, value: fraction)
                    }
                }
            }
            .frame(height: 5)
        }
    }
}


// MARK: - 7-day total-cost trend

struct CostWeeklyTrendPanel: View {
    let provider: AlertEngine.Provider

    @ObservedObject private var costStore = CostStore.shared

    private var color: Color {
        switch provider {
        case .claude: return IslandColor.claude
        case .codex:  return IslandColor.codex
        }
    }

    private var providerName: String {
        AgentConfigurationStore.shared.displayName(for: provider)
    }

    private var cost: ProviderCost {
        switch provider {
        case .claude: return costStore.claude
        case .codex:  return costStore.codex
        }
    }

    private var values: [Double] {
        let raw = cost.last7DailyDollars
        if raw.count == 7 { return raw }
        if raw.count > 7 { return Array(raw.suffix(7)) }
        return Array(repeating: 0, count: max(0, 7 - raw.count)) + raw
    }

    private var total: Double { values.reduce(0, +) }
    private var average: Double { values.isEmpty ? 0 : total / Double(values.count) }
    private var peak: Double { values.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            SevenDayCostLine(values: values, color: color)
                .frame(height: 92)
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                stat(label: L10n.tr("7d total"), value: formatDollars(total), highlighted: true)
                stat(label: L10n.tr("avg/day"), value: formatDollars(average), highlighted: false)
                stat(label: L10n.tr("peak"), value: formatDollars(peak), highlighted: false)
            }

            dayLabels
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.6)
                )
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(L10n.tr("7-DAY TREND"))
                .font(Typography.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.58))
            Text(L10n.tr("all models"))
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.35))
            Spacer(minLength: 0)
            Text(providerName)
                .font(Typography.micro)
                .foregroundStyle(color.opacity(0.78))
        }
    }

    private func stat(label: String, value: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typography.bodyNumber)
                .monospacedDigit()
                .foregroundStyle(highlighted ? color : .white.opacity(0.72))
                .lineLimit(1)
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.36))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayLabels: some View {
        HStack {
            ForEach(Self.dayNames.indices, id: \.self) { index in
                Text(Self.dayNames[index])
                    .font(Typography.micro)
                    .foregroundStyle(index == Self.dayNames.count - 1 ? color.opacity(0.75) : .white.opacity(0.32))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private static var dayNames: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("E")
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset - 6, to: today) ?? today
            if offset == 6 { return L10n.tr("Today") }
            return formatter.string(from: day)
        }
    }

    private func formatDollars(_ amount: Double) -> String {
        if amount <= 0 { return "$0" }
        if amount < 10 { return String(format: "$%.2f", amount) }
        if amount < 100 { return String(format: "$%.1f", amount) }
        if amount < 10_000 { return String(format: "$%.0f", amount) }
        return String(format: "$%.1fk", amount / 1_000)
    }
}

private struct SevenDayCostLine: View {
    let values: [Double]
    let color: Color

    private var paddedValues: [Double] {
        if values.count >= 2 { return values }
        return values + Array(repeating: 0, count: 2 - values.count)
    }

    var body: some View {
        GeometryReader { geo in
            let vals = paddedValues
            let maxV = max(vals.max() ?? 0, 0.0001)
            let minV = vals.min() ?? 0
            let span = max(maxV - minV, maxV * 0.35, 0.0001)
            let stepX = vals.count > 1 ? geo.size.width / CGFloat(vals.count - 1) : geo.size.width
            let points = vals.enumerated().map { index, value in
                let normalized = (value - minV) / span
                let x = CGFloat(index) * stepX
                let y = geo.size.height * (0.88 - CGFloat(normalized) * 0.72)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                trendGrid

                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    if let last = points.last {
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    }
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [color.opacity(0.24), color.opacity(0.02), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.55), radius: 5)

                ForEach(points.indices, id: \.self) { idx in
                    let point = points[idx]
                    Circle()
                        .fill(idx == points.count - 1 ? color : color.opacity(0.72))
                        .frame(width: idx == points.count - 1 ? 5.5 : 3.5, height: idx == points.count - 1 ? 5.5 : 3.5)
                        .position(point)
                        .shadow(color: color.opacity(idx == points.count - 1 ? 0.75 : 0.35), radius: 3)
                }
            }
        }
    }

    private var trendGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(.white.opacity(0.045))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(height: 1)
        }
    }
}

private extension Text {
    func costColumnHeader(width: CGFloat) -> some View {
        self
            .font(Typography.micro)
            .foregroundStyle(.white.opacity(0.40))
            .frame(width: width, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}
