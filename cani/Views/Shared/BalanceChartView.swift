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

    // MARK: - Données graphique

    /// Un point de données = solde à un instant précis dans le temps.
    private struct ChartPoint: Identifiable {
        let id:      Date   // stable — pas de UUID recréé à chaque render
        let date:    Date
        let balance: Double
        let isTight: Bool
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
        // Mode plein année : tout
        if showFullYear { return periods }
        // Mode mini : J-2 à J+2 centré sur la période courante
        guard let idx = periods.firstIndex(where: \.isCurrentPeriod) else { return periods }
        let lo = max(0, idx - 2)
        let hi = min(periods.count - 1, idx + 2)
        return Array(periods[lo...hi])
    }

    /// Points de la courbe : deux points par période — solde de début ET solde de fin.
    /// Cela produit une courbe en escalier réaliste : la ligne monte/descend à l'intérieur
    /// de chaque période selon les flux réels, plutôt qu'une interpolation entre périodes éloignées.
    private var chartPoints: [ChartPoint] {
        let shown = visiblePeriods
        guard !shown.isEmpty else { return [] }

        var pts: [ChartPoint] = []

        for period in shown {
            // Début de période : solde avant les transactions
            // Si overridePreviousBalance est fourni et que c'est la période focalisée, on l'utilise.
            let startBalance: Double
            if let override = overridePreviousBalance,
               let focused = focusedPeriod,
               period.id == focused.id {
                startBalance = (override as NSDecimalNumber).doubleValue
            } else {
                startBalance = (period.previousBalance as NSDecimalNumber).doubleValue
            }
            pts.append(ChartPoint(
                id:      period.startDate,
                date:    period.startDate,
                balance: startBalance,
                isTight: false
            ))
            // Fin de période : solde après les transactions
            pts.append(ChartPoint(
                id:      period.endDate,
                date:    period.endDate,
                balance: (period.projectedBalance as NSDecimalNumber).doubleValue,
                isTight: period.isTight
            ))
        }

        return pts
    }

    /// Domaine X forcé pour le mode mini : fenêtre symétrique autour de la période courante.
    /// [currentPeriod.startDate − 14 j, currentPeriod.endDate + 14 j]
    /// Garantit que la ligne « Aujourd'hui » tombe au centre visuel du graphique.
    private var miniXDomain: ClosedRange<Date> {
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

    private var tightPoints: [ChartPoint] { chartPoints.filter(\.isTight) }

    private var yRange: (min: Double, max: Double) {
        let vals = chartPoints.map(\.balance)
        return (vals.min() ?? 0, vals.max() ?? 1)
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
            tightPointMarks()
            todayRule()
        }
        .chartXAxis { xAxisContent }
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
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.28), Color.indigo.opacity(0.04)],
                    startPoint: .top,
                    endPoint:   .bottom
                )
            )
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
            .foregroundStyle(Color.indigo)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    @ChartContentBuilder
    private func tightPointMarks() -> some ChartContent {
        ForEach(tightPoints) { pt in
            PointMark(
                x: .value("Date",  pt.date),
                y: .value("Solde", pt.balance)
            )
            .foregroundStyle(Color.orange)
            .symbolSize(55)
            .symbol(.circle)
        }
    }

    /// Ligne verticale « Aujourd'hui » — présente dans tous les graphiques.
    /// Le tag texte n'est affiché qu'en mode showFullYear pour ne pas surcharger le mini.
    @ChartContentBuilder
    private func todayRule() -> some ChartContent {
        RuleMark(x: .value("Aujourd'hui", Date.now))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(Color.secondary.opacity(0.6))
            .annotation(position: .top, spacing: 2) {
                if showFullYear {
                    Text("Aujourd'hui")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
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
        return PayPeriod(
            id: UUID(), startDate: start,
            endDate: cal.date(byAdding: .day, value: 13, to: start)!,
            projectedBalance: balance, previousBalance: balance - 400,
            delta: 400, isTight: tight, isCurrentPeriod: current, transactions: []
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
