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
    /// false → fenêtre J-2 à J+2 (5 périodes), axe Y masqué, hauteur 120 pt.
    /// true  → toutes les périodes, axe Y visible, hauteur 220 pt.
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

    // MARK: - Couleurs d'état

    private var softRedColor: Color { Color(red: 0.85, green: 0.28, blue: 0.28) }
    private var amberColor:   Color { Color(red: 1.0,  green: 0.70, blue: 0.0)  }

    // MARK: - Données graphique

    /// Un point de données = solde à un instant précis dans le temps.
    private struct ChartPoint: Identifiable {
        let id:             Date   // stable — pas de UUID recréé à chaque render
        let date:           Date
        let balance:        Double
        let isTight:        Bool
        let isNegative:     Bool
        let isPeriodEnd:  Bool   // vrai sur le dernier jour de chaque période (pour les dots)
    }

    /// Périodes visibles selon le mode actif.
    private var visiblePeriods: [PayPeriod] {
        // Mode focusé : fenêtre [idx-1, idx, idx+1]
        if let focused = focusedPeriod {
            guard let idx = periods.firstIndex(where: { $0.id == focused.id }) else { return periods }
            let lo = max(0, idx - 1)
            let hi = min(periods.count - 1, idx + 1)
            return Array(periods[lo...hi])
        }
        // Mode mini avec domaine personnalisé (Home): utiliser toutes les périodes passées.
        if miniXDomainOverride != nil { return periods }
        // Mode plein année : tout
        if showFullYear { return periods }
        // Mode mini : J-2 à J+2 centré sur la période courante
        guard let idx = periods.firstIndex(where: \.isCurrentPeriod) else { return periods }
        let lo = max(0, idx - 2)
        let hi = min(periods.count - 1, idx + 2)
        return Array(periods[lo...hi])
    }

    /// Points de la courbe : un point par jour par période, calculé depuis `dailyBalances`.
    /// Le premier jour de chaque période est marqué `isPeriodEnd` pour y placer un dot.
    private var chartPoints: [ChartPoint] {
        let shown = visiblePeriods
        guard !shown.isEmpty else { return [] }

        let thresholdDouble = Double(NSDecimalNumber(decimal: tightThreshold).doubleValue)
        var pts: [ChartPoint] = []

        for period in shown {
            var daily = period.dailyBalances

            // Appliquer l'override de solde d'ouverture sur la période focalisée
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
                    id:            snapshot.date,
                    date:          snapshot.date,
                    balance:       bal,
                    isTight:       bal < thresholdDouble && bal >= 0,
                    isNegative:    bal < 0,
                    isPeriodEnd: idx == daily.count - 1
                ))
            }
        }

        return pts
    }

    /// Domaine X forcé pour le mode mini.
    /// Priorité: `miniXDomainOverride` (si fourni), sinon fenêtre symétrique autour de la période courante.
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
        // Fallback : bornes des données visibles
        if let first = chartPoints.first?.date, let last = chartPoints.last?.date {
            return first...last
        }
        return Date.distantPast...Date.distantFuture
    }

    private var periodStartPoints: [ChartPoint] { chartPoints.filter(\.isPeriodEnd) }

    private var yRange: (min: Double, max: Double) {
        let vals = chartPoints.map(\.balance)
        return (vals.min() ?? 0, vals.max() ?? 1)
    }

    /// Domaine Y serré autour des données pour maximiser la lisibilité des variations.
    /// Ajoute 15 % de marge en haut et en bas.
    private var tightYDomain: ClosedRange<Double> {
        let (lo, hi) = yRange
        let range = max(hi - lo, 1)
        let pad   = range * 0.15
        return (lo - pad)...(hi + pad)
    }

    // MARK: - Body

    var body: some View {
        if focusedPeriod != nil {
            buildChart()
                .chartYAxis(.hidden)
                .frame(height: 100)
        } else if showFullYear {
            buildChart()
                .chartYAxis { yAxisContent }
                .frame(height: 220)
        } else {
            buildChart()
                .chartXScale(domain: miniXDomain)
                .chartYAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.padding(.top, todayBalance != nil ? 44 : 0)
                }
                .frame(height: 120)
        }
    }

    // MARK: - Chart builder

    @ViewBuilder
    private func buildChart() -> some View {
        Chart {
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
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        // Correspondance exacte au jour — données journalières disponibles
        if let pt = chartPoints.first(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            return pt.balance
        }
        // Hors plage : clamp sur les bornes
        let sorted = chartPoints
        guard !sorted.isEmpty else { return nil }
        if day < sorted.first!.date { return sorted.first!.balance }
        return sorted.last!.balance
    }

    // MARK: - Gradient vert / amber / rouge

    /// Calcule les stops du gradient Y mappé sur le domaine des données.
    /// `opaque: true`  → ligne (couleurs pleines)
    /// `opaque: false` → aire (couleurs opaques réduites, fondues vers le bas)
    private func makeGradientStops(opaque: Bool) -> [Gradient.Stop] {
        let (yMin, yMax) = yRange
        let range = yMax - yMin
        let t = Double(NSDecimalNumber(decimal: tightThreshold).doubleValue)

        // Position 0 = haut du graphique (yMax), 1 = bas (yMin)
        func pos(_ v: Double) -> CGFloat { CGFloat(max(0, min(1, (yMax - v) / range))) }
        func stop(_ c: Color, _ alpha: Double, _ loc: CGFloat) -> Gradient.Stop {
            .init(color: opaque ? c : c.opacity(alpha), location: loc)
        }

        guard range > 0.01 else {
            let c: Color = yMax < 0 ? softRedColor : yMax < t ? amberColor : .green
            return [stop(c, 0.30, 0), stop(c, opaque ? 1.0 : 0.04, 1)]
        }

        let tPos    = pos(t)
        let zeroPos = pos(0.0)
        var stops: [Gradient.Stop] = []

        // Haut → seuil tight
        if yMax >= t {
            stops.append(stop(.green,    0.30, 0))
            if tPos > 0.01 {
                stops.append(stop(.green,     0.18, max(0, tPos - 0.005)))
                stops.append(stop(amberColor, 0.28, tPos))
            }
        } else if yMax >= 0 {
            stops.append(stop(amberColor, 0.28, 0))
        } else {
            stops.append(stop(softRedColor, 0.30, 0))
        }

        // Franchissement de zéro
        if yMin < 0 && yMax > 0 && zeroPos > 0.01 && zeroPos < 0.99 {
            stops.append(stop(amberColor,   0.18, max(0, zeroPos - 0.005)))
            stops.append(stop(softRedColor, 0.35, zeroPos))
            stops.append(stop(softRedColor, 0.08, 1.0))
        } else {
            let bot: Color = yMin < 0 ? softRedColor : yMin < t ? amberColor : .green
            stops.append(stop(bot, opaque ? 1.0 : 0.04, 1.0))
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
        ForEach(chartPoints) { pt in
            AreaMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(areaGradient())
        }
    }

    @ChartContentBuilder
    private func lineMarks() -> some ChartContent {
        ForEach(chartPoints) { pt in
            LineMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(lineGradient())
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    @ChartContentBuilder
    private func statusPointMarks() -> some ChartContent {
        ForEach(periodStartPoints) { pt in
            let dotColor: Color = pt.isNegative ? softRedColor : pt.isTight ? amberColor : .green
            PointMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .foregroundStyle(dotColor)
            .symbolSize(45)
            .symbol(.circle)
        }
    }

    /// Ligne verticale « Aujourd'hui » — présente dans tous les graphiques.
    /// Affiche un badge date + solde si `todayBalance` est fourni, sinon « Aujourd'hui » en mode plein.
    /// Le badge est masqué quand le scrubbing est actif.
    @ChartContentBuilder
    private func todayRule() -> some ChartContent {
        RuleMark(x: .value("Aujourd'hui", Date.now))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(Color.secondary.opacity(0.6))
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
            day: Calendar.current.component(.day,   from: .now),
            month: Calendar.current.component(.month, from: .now),
            formattedBalance: CurrencyFormatter.shared.format(balance),
            accentColor: Color.primary.opacity(0.10)
        )
    }

    @ViewBuilder
    private func scrubbingBadge(date: Date, balance: Double) -> some View {
        chartBadge(
            day: Calendar.current.component(.day,   from: date),
            month: Calendar.current.component(.month, from: date),
            formattedBalance: CurrencyFormatter.shared.format(Decimal(balance)),
            accentColor: Color.indigo.opacity(0.25)
        )
    }

    @ViewBuilder
    private func chartBadge(day: Int, month: Int, formattedBalance: String, accentColor: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(day)/\(month)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(formattedBalance)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(accentColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 1)
    }

    // MARK: - Axes

    private var xAxisContent: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: showFullYear ? 6 : 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.primary.opacity(0.08))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(
                        date,
                        format: Date.FormatStyle()
                            .locale(Locale(identifier: "fr_CA"))
                            .month(.abbreviated)
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            BalanceChartView(periods: periods, showFullYear: false)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Pleine année").font(.caption).foregroundStyle(.secondary)
            BalanceChartView(periods: periods, showFullYear: true)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Focalisé (sheet)").font(.caption).foregroundStyle(.secondary)
            BalanceChartView(periods: periods, showFullYear: false, focusedPeriod: periods[1])
        }
    }
    .padding()
}
