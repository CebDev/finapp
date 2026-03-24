//
//  BalanceChartView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import Charts

// MARK: - BalanceChartView

struct BalanceChartView: View {
    /// Tableau complet de périodes (typiquement 5-13 générées par PeriodEngine).
    let periods: [PayPeriod]
    /// false → fenêtre J-2 à J+2 (5 périodes), axe Y compact trailing, hauteur 180 pt.
    /// true  → toutes les périodes, axe Y leading visible, hauteur 220 pt.
    var showFullYear: Bool = false
    /// Période à mettre en évidence (context de PeriodDetailSheet).
    /// Quand fourni, la fenêtre est réduite à [idx-1 … idx+1] et la hauteur passe à 100 pt.
    var focusedPeriod: PayPeriod? = nil
    /// Quand fourni, remplace le `previousBalance` de la période focalisée dans le premier point
    /// de la courbe — utilisé par PeriodDetailSheet en mode « vue isolée » (carryForwardBalance = false).
    var overridePreviousBalance: Decimal? = nil
    /// Domaine X personnalisé (principalement pour Home) en mode mini.
    var miniXDomainOverride: ClosedRange<Date>? = nil
    /// Seuil en dessous duquel une période est « serrée » (amber). Défaut : 500 $ CAD.
    var tightThreshold: Decimal = 500
    /// Solde actuel des comptes inclus — si fourni, affiché dans l'annotation de la ligne « Aujourd'hui ».
    var todayBalance: Decimal? = nil

    // MARK: - État scrubbing

    @State private var scrubbedDate:    Date?   = nil
    @State private var scrubbedBalance: Double? = nil

    // MARK: - Cache points graphique (évite le recalcul à chaque geste de scrubbing)

    @State private var cachedChartPoints: [ChartPoint]    = []
    @State private var balanceByDate:     [Date: Double]  = [:]

    // MARK: - Couleurs d'état

    private var softRedColor: Color { Color(red: 0.85, green: 0.28, blue: 0.28) }
    private var amberColor:   Color { Color(red: 1.0,  green: 0.70, blue: 0.0)  }

    // MARK: - Données graphique

    /// Un point de données = solde à un instant précis dans le temps.
    private struct ChartPoint: Identifiable {
        let id:          Date
        let date:        Date
        let balance:     Double
        let isTight:     Bool
        let isNegative:  Bool
        let isPeriodEnd: Bool
    }

    /// Périodes visibles selon le mode actif.
    private var visiblePeriods: [PayPeriod] {
        if let focused = focusedPeriod {
            guard let idx = periods.firstIndex(where: { $0.id == focused.id }) else { return periods }
            let lo = max(0, idx - 1)
            let hi = min(periods.count - 1, idx + 1)
            return Array(periods[lo...hi])
        }
        if miniXDomainOverride != nil { return periods }
        if showFullYear { return periods }
        guard let idx = periods.firstIndex(where: \.isCurrentPeriod) else { return periods }
        let lo = max(0, idx - 2)
        let hi = min(periods.count - 1, idx + 2)
        return Array(periods[lo...hi])
    }

    /// Construit les points de la courbe depuis `dailyBalances` (résultat mis en cache dans `cachedChartPoints`).
    private func buildChartPoints() -> [ChartPoint] {
        let shown = visiblePeriods
        guard !shown.isEmpty else { return [] }

        let thresholdDouble = Double(NSDecimalNumber(decimal: tightThreshold).doubleValue)
        var pts: [ChartPoint] = []

        for period in shown {
            var daily = period.dailyBalances

            if let override = overridePreviousBalance,
               let focused  = focusedPeriod,
               period.id    == focused.id,
               !daily.isEmpty {
                let overrideDouble = (override as NSDecimalNumber).doubleValue
                let originalFirst  = (daily[0].balance as NSDecimalNumber).doubleValue
                let shift          = overrideDouble - originalFirst
                daily = daily.map { (date: $0.date, balance: $0.balance + Decimal(shift)) }
            }

            for (idx, snapshot) in daily.enumerated() {
                let bal = (snapshot.balance as NSDecimalNumber).doubleValue
                pts.append(ChartPoint(
                    id:          snapshot.date,
                    date:        snapshot.date,
                    balance:     bal,
                    isTight:     bal < thresholdDouble && bal >= 0,
                    isNegative:  bal < 0,
                    isPeriodEnd: idx == daily.count - 1
                ))
            }
        }

        return pts
    }

    /// Identifiant de cache : change quand les données du graphique changent.
    private var chartHash: Int {
        var h = Hasher()
        h.combine(periods.count)
        h.combine(focusedPeriod?.id)
        h.combine(overridePreviousBalance?.description)
        for p in periods {
            h.combine(p.id)
            h.combine(p.projectedBalance.description)
        }
        return h.finalize()
    }

    /// Reconstruit le cache des points et du lookup de solde par date.
    private func rebuildChartCache() {
        let pts = buildChartPoints()
        cachedChartPoints = pts
        let cal = Calendar.current
        balanceByDate = pts.reduce(into: [Date: Double]()) { dict, pt in
            dict[cal.startOfDay(for: pt.date)] = pt.balance
        }
    }

    /// Domaine X forcé pour le mode mini.
    private var miniXDomain: ClosedRange<Date> {
        if let override = miniXDomainOverride {
            return override
        }
        let cal = Calendar.current
        if let current = periods.first(where: \.isCurrentPeriod) {
            let start = cal.date(byAdding: .day, value: -14, to: current.startDate) ?? current.startDate
            let end   = cal.date(byAdding: .day, value: +14, to: current.endDate)   ?? current.endDate
            return start...end
        }
        if let first = cachedChartPoints.first?.date, let last = cachedChartPoints.last?.date {
            return first...last
        }
        return Date.distantPast...Date.distantFuture
    }

    private var periodEndPoints: [ChartPoint] { cachedChartPoints.filter(\.isPeriodEnd) }

    private var yRange: (min: Double, max: Double) {
        let vals = cachedChartPoints.map(\.balance)
        return (vals.min() ?? 0, vals.max() ?? 1)
    }

    /// Domaine Y serré autour des données. Marge 15 % haut + bas.
    private var tightYDomain: ClosedRange<Double> {
        let (lo, hi) = yRange
        let range = max(hi - lo, 1)
        let pad   = range * 0.15
        return (lo - pad)...(hi + pad)
    }

    private var tightThresholdDouble: Double {
        Double(NSDecimalNumber(decimal: tightThreshold).doubleValue)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if focusedPeriod != nil {
                buildChart()
                    .chartYAxis(.hidden)
                    .frame(height: 100)
            } else if showFullYear {
                buildChart()
                    .chartYAxis { yAxisContent }
                    .frame(height: 220)
                    .clipped()
            } else {
                // Mode mini : hauteur augmentée + axe Y compact à droite
                buildChart()
                    .chartXScale(domain: miniXDomain)
                    .chartYAxis { yAxisContentMini }
                    .chartPlotStyle { plot in
                        plot.padding(.top, todayBalance != nil ? 36 : 8)
                    }
                    .frame(height: 180)
            }
        }
        .onChange(of: chartHash, initial: true) { _, _ in rebuildChartCache() }
    }

    // MARK: - Chart builder

    @ViewBuilder
    private func buildChart() -> some View {
        Chart {
            tightThresholdRule()
            periodSeparators()
            focusedHighlight()
            areaMarks()
            lineMarks()
            statusPointMarks()
            todayRule()
            scrubbingRule()
        }
        .chartYScale(domain: tightYDomain)
        .chartXAxis { xAxisContent }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let date = proxy.value(atX: value.location.x, as: Date.self) else { return }
                                scrubbedDate    = date
                                scrubbedBalance = balance(at: date)
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scrubbedDate    = nil
                                    scrubbedBalance = nil
                                }
                            }
                    )
            }
        }
    }

    // MARK: - Interpolation de solde

    private func balance(at date: Date) -> Double? {
        let day = Calendar.current.startOfDay(for: date)
        // O(1) via dictionnaire précalculé
        if let val = balanceByDate[day] { return val }
        guard !cachedChartPoints.isEmpty else { return nil }
        if day < cachedChartPoints.first!.date { return cachedChartPoints.first!.balance }
        return cachedChartPoints.last!.balance
    }

    // MARK: - Gradient vert / amber / rouge

    /// Calcule les stops du gradient Y mappé sur le domaine des données.
    private func makeGradientStops(opaque: Bool) -> [Gradient.Stop] {
        let (yMin, yMax) = yRange
        let range = yMax - yMin
        let t = tightThresholdDouble

        func pos(_ v: Double) -> CGFloat { CGFloat(max(0, min(1, (yMax - v) / range))) }
        func stop(_ c: Color, _ alpha: Double, _ loc: CGFloat) -> Gradient.Stop {
            .init(color: opaque ? c : c.opacity(alpha), location: loc)
        }

        guard range > 0.01 else {
            let c: Color = yMax < 0 ? softRedColor : yMax < t ? amberColor : .green
            return [stop(c, 0.42, 0), stop(c, opaque ? 1.0 : 0.06, 1)]
        }

        let tPos    = pos(t)
        let zeroPos = pos(0.0)
        var stops: [Gradient.Stop] = []

        if yMax >= t {
            stops.append(stop(.green, 0.42, 0))
            if tPos > 0.01 {
                stops.append(stop(.green,     0.22, max(0, tPos - 0.005)))
                stops.append(stop(amberColor, 0.35, tPos))
            }
        } else if yMax >= 0 {
            stops.append(stop(amberColor, 0.35, 0))
        } else {
            stops.append(stop(softRedColor, 0.40, 0))
        }

        if yMin < 0 && yMax > 0 && zeroPos > 0.01 && zeroPos < 0.99 {
            stops.append(stop(amberColor,   0.22, max(0, zeroPos - 0.005)))
            stops.append(stop(softRedColor, 0.40, zeroPos))
            stops.append(stop(softRedColor, 0.10, 1.0))
        } else {
            let bot: Color = yMin < 0 ? softRedColor : yMin < t ? amberColor : .green
            stops.append(stop(bot, opaque ? 1.0 : 0.06, 1.0))
        }

        return stops
    }

    private func areaGradient() -> LinearGradient {
        LinearGradient(stops: makeGradientStops(opaque: false), startPoint: .top, endPoint: .bottom)
    }

    private func lineGradient() -> LinearGradient {
        LinearGradient(stops: makeGradientStops(opaque: true), startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Chart content builders

    /// Ligne horizontale pointillée au seuil « tight » — visible si le seuil est dans la plage Y.
    @ChartContentBuilder
    private func tightThresholdRule() -> some ChartContent {
        let t = tightThresholdDouble
        let (yMin, yMax) = yRange
        if t > yMin && t < yMax {
            RuleMark(y: .value("Seuil", t))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(amberColor.opacity(0.50))
        }
    }

    /// Règles verticales subtiles aux jonctions de périodes (hors mode focusé).
    @ChartContentBuilder
    private func periodSeparators() -> some ChartContent {
        if focusedPeriod == nil {
            ForEach(visiblePeriods.dropFirst()) { period in
                RuleMark(x: .value("Début", period.startDate))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 5]))
                    .foregroundStyle(Color.primary.opacity(0.13))
            }
        }
    }

    /// Fond indigo sur la plage de la période focalisée.
    @ChartContentBuilder
    private func focusedHighlight() -> some ChartContent {
        if let focused = focusedPeriod {
            let (yMin, yMax) = yRange
            let end = Calendar.current.date(byAdding: .day, value: 1, to: focused.endDate) ?? focused.endDate
            RectangleMark(
                xStart: .value("Début", focused.startDate),
                xEnd:   .value("Fin",   end),
                yStart: .value("", yMin),
                yEnd:   .value("", yMax)
            )
            .foregroundStyle(Color.indigo.opacity(0.07))
        }
    }

    @ChartContentBuilder
    private func areaMarks() -> some ChartContent {
        let yMin = tightYDomain.lowerBound
        ForEach(cachedChartPoints) { pt in
            AreaMark(
                x:      .value("Date",  pt.date),
                yStart: .value("Bas",   yMin),
                yEnd:   .value("Solde", pt.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(areaGradient())
        }
    }

    @ChartContentBuilder
    private func lineMarks() -> some ChartContent {
        ForEach(cachedChartPoints) { pt in
            LineMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(lineGradient())
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Dots de fin de période : halo blanc + point coloré pour ressortir sur la courbe.
    /// Deux ForEach séparés car @ChartContentBuilder n'accepte pas plusieurs marks dans un seul.
    @ChartContentBuilder
    private func statusPointMarks() -> some ChartContent {
        // Halo blanc (arrière-plan)
        ForEach(periodEndPoints) { pt in
            PointMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .foregroundStyle(Color(UIColor.systemBackground))
            .symbolSize(110)
            .symbol(.circle)
        }
        // Point coloré (avant-plan)
        ForEach(periodEndPoints) { pt in
            let dotColor: Color = pt.isNegative ? softRedColor : pt.isTight ? amberColor : .green
            PointMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .foregroundStyle(dotColor)
            .symbolSize(60)
            .symbol(.circle)
        }
    }

    /// Ligne verticale « Aujourd'hui ».
    @ChartContentBuilder
    private func todayRule() -> some ChartContent {
        RuleMark(x: .value("Aujourd'hui", Date.now))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(Color.primary.opacity(0.30))
            .annotation(position: .top, alignment: .center, spacing: 4) {
                if scrubbedDate == nil {
                    if let balance = todayBalance {
                        todayBadge(balance: balance)
                    } else if showFullYear {
                        Text("Aujourd'hui")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    }
                }
            }
    }

    /// Ligne de scrubbing — suit le doigt et affiche la date + solde interpolé.
    @ChartContentBuilder
    private func scrubbingRule() -> some ChartContent {
        if let date = scrubbedDate {
            RuleMark(x: .value("Sélection", date))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(Color.indigo.opacity(0.85))
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    if let bal = scrubbedBalance {
                        scrubbingBadge(date: date, balance: bal)
                    }
                }
        }
    }

    @ViewBuilder
    private func todayBadge(balance: Decimal) -> some View {
        chartBadge(
            label:            formattedShortDate(.now),
            formattedBalance: CurrencyFormatter.shared.format(balance),
            accentColor:      Color.primary.opacity(0.12)
        )
    }

    @ViewBuilder
    private func scrubbingBadge(date: Date, balance: Double) -> some View {
        chartBadge(
            label:            formattedShortDate(date),
            formattedBalance: CurrencyFormatter.shared.format(Decimal(balance)),
            accentColor:      Color.indigo.opacity(0.25)
        )
    }

    @ViewBuilder
    private func chartBadge(label: String, formattedBalance: String, accentColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(formattedBalance)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(accentColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func formattedShortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    // MARK: - Axes

    private var xAxisContent: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: showFullYear ? 6 : 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary.opacity(0.08))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    if showFullYear {
                        Text(
                            date,
                            format: Date.FormatStyle()
                                .locale(Locale(identifier: "fr_CA"))
                                .month(.abbreviated)
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        // Mode mini : jour + mois abrégé pour une meilleure orientation temporelle
                        Text(formattedShortDate(date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Axe Y compact (trailing) pour le mode mini — donne l'échelle sans encombrer.
    private var yAxisContentMini: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary.opacity(0.06))
            AxisValueLabel(anchor: .leading) {
                if let d = value.as(Double.self) {
                    Text(abbreviatedCAD(d))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.75))
                }
            }
        }
    }

    private var yAxisContent: some AxisContent {
        AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary.opacity(0.08))
            AxisValueLabel {
                if let d = value.as(Double.self) {
                    Text(abbreviatedCAD(d))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Ex : 1 500 → "1,5k", 12 000 → "12k", 250 → "250"
    private func abbreviatedCAD(_ value: Double) -> String {
        let abs  = Swift.abs(value)
        let sign = value < 0 ? "−" : ""
        if abs >= 1_000 {
            let k = abs / 1_000
            if k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(sign)\(Int(k))k"
            } else {
                return String(format: "\(sign)%.1fk", k)
            }
        }
        return "\(sign)\(Int(abs))"
    }
}

// MARK: - Preview

#Preview {
    let cal   = Calendar.current
    let today = cal.startOfDay(for: .now)

    func period(offset: Int, balance: Decimal, tight: Bool, current: Bool) -> PayPeriod {
        let start = cal.date(byAdding: .day, value: offset * 14, to: today)!
        let end   = cal.date(byAdding: .day, value: 13, to: start)!
        let prev  = balance - 400
        let daily: [(date: Date, balance: Decimal)] = (0...13).map { d in
            let date = cal.date(byAdding: .day, value: d, to: start)!
            let bal  = prev + Decimal(d) * 400 / 13
            return (date: date, balance: bal)
        }
        return PayPeriod(
            id: UUID(), startDate: start, endDate: end,
            projectedBalance: balance, previousBalance: prev,
            delta: 400, isTight: tight, isCurrentPeriod: current,
            transactions: [], dailyBalances: daily
        )
    }

    let periods: [PayPeriod] = [
        period(offset: -2, balance: 2_400, tight: false, current: false),
        period(offset: -1, balance: 1_800, tight: false, current: false),
        period(offset:  0, balance: 3_200, tight: false, current: true),
        period(offset:  1, balance:   420, tight: true,  current: false),
        period(offset:  2, balance: 2_100, tight: false, current: false),
    ]

    return VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mini (5 périodes)").font(.caption).foregroundStyle(.secondary)
            BalanceChartView(
                periods:             periods,
                showFullYear:        false,
                tightThreshold:      500,
                todayBalance:        3_200
            )
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Pleine année").font(.caption).foregroundStyle(.secondary)
            BalanceChartView(periods: periods, showFullYear: true, tightThreshold: 500)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Focalisé (sheet)").font(.caption).foregroundStyle(.secondary)
            BalanceChartView(periods: periods, showFullYear: false, focusedPeriod: periods[1])
        }
    }
    .padding()
}
