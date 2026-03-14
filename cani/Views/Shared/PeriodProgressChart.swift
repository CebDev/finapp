//
//  PeriodProgressChart.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import Charts

/// Graphique en escalier de l'évolution du solde à l'intérieur d'une seule période.
///
/// - `carryForwardBalance == true`  → démarre à `period.previousBalance`
/// - `carryForwardBalance == false` → démarre à 0, représente revenus − dépenses cumulés
struct PeriodProgressChart: View {
    let period:              PayPeriod
    let carryForwardBalance: Bool
    let tightThreshold:      Decimal
    var overrides:           [TransactionOverride] = []
    /// Transactions réelles de la période (utilisées pour la phase "passé" de la période courante).
    var realTransactions:    [Transaction]         = []

    // MARK: - Colours

    private let greenColor   = Color.green
    private let amberColor   = Color(red: 1.0, green: 0.7, blue: 0.0)
    private let softRedColor = Color(red: 0.85, green: 0.28, blue: 0.28)

    // MARK: - Chart data

    private struct BalanceStep: Identifiable {
        let id    = UUID()
        let date:    Date
        let balance: Decimal
    }

    /// Construit les points du graphique en escalier.
    /// Pour la période courante : phase réelle (transactions confirmées) + phase projetée (occurrences futures).
    /// Pour les autres périodes : uniquement la projection des récurrences.
    private var steps: [BalanceStep] {
        let cal          = Calendar.current
        let startBalance = carryForwardBalance ? period.previousBalance : Decimal(0)
        let exclusiveEnd = cal.date(byAdding: .day, value: 1, to: period.endDate) ?? period.endDate

        if period.isCurrentPeriod {
            return stepsCurrentPeriod(startBalance: startBalance, exclusiveEnd: exclusiveEnd, calendar: cal)
        } else {
            return stepsProjected(startBalance: startBalance, exclusiveEnd: exclusiveEnd, calendar: cal)
        }
    }

    /// Période courante : transactions réelles jusqu'à aujourd'hui, occurrences planifiées ensuite.
    private func stepsCurrentPeriod(startBalance: Decimal, exclusiveEnd: Date, calendar: Calendar) -> [BalanceStep] {
        let today    = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // Phase 1 — transactions réelles groupées par jour (du début à aujourd'hui inclus)
        var realByDay: [Date: Decimal] = [:]
        for tx in realTransactions {
            let day = calendar.startOfDay(for: tx.date)
            guard day >= calendar.startOfDay(for: period.startDate), day <= today else { continue }
            realByDay[day, default: 0] += tx.amount
        }

        // Phase 2 — occurrences planifiées de demain à la fin de période (hors overrides payés)
        var projectedByDay: [Date: Decimal] = [:]
        for tx in period.transactions {
            let dates = ProjectionEngine.occurrences(of: tx, from: tomorrow, to: exclusiveEnd, calendar: calendar)
            for date in dates {
                let day = calendar.startOfDay(for: date)
                let ov = overrides.first {
                    $0.recurringTransactionId == tx.id &&
                    calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: day)
                }
                if let ov, ov.isPaid { continue }
                projectedByDay[day, default: 0] += ov?.actualAmount ?? tx.amount
            }
        }

        var result: [BalanceStep] = []
        var running = startBalance
        result.append(BalanceStep(date: period.startDate, balance: running))

        // Paliers réels (passé)
        for day in realByDay.keys.sorted() {
            running += realByDay[day]!
            result.append(BalanceStep(date: day, balance: running))
        }

        // Point pivot "aujourd'hui" explicite si dans la période
        let periodStart = calendar.startOfDay(for: period.startDate)
        let periodEnd   = calendar.startOfDay(for: period.endDate)
        if today > periodStart, today <= periodEnd, result.last.map({ calendar.startOfDay(for: $0.date) }) != today {
            result.append(BalanceStep(date: today, balance: running))
        }

        // Paliers projetés (futur)
        for day in projectedByDay.keys.sorted() {
            running += projectedByDay[day]!
            result.append(BalanceStep(date: day, balance: running))
        }

        // Point final
        let lastDay = result.last.map { calendar.startOfDay(for: $0.date) } ?? periodStart
        if lastDay < periodEnd {
            result.append(BalanceStep(date: period.endDate, balance: running))
        }

        return result
    }

    /// Périodes passées ou futures : projection pure des récurrences.
    private func stepsProjected(startBalance: Decimal, exclusiveEnd: Date, calendar: Calendar) -> [BalanceStep] {
        var occurrences: [(date: Date, amount: Decimal)] = []
        for tx in period.transactions {
            let dates = ProjectionEngine.occurrences(of: tx, from: period.startDate, to: exclusiveEnd)
            for date in dates {
                let day = calendar.startOfDay(for: date)
                let ov = overrides.first {
                    $0.recurringTransactionId == tx.id &&
                    calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: day)
                }
                occurrences.append((date: day, amount: ov?.actualAmount ?? tx.amount))
            }
        }

        let grouped     = Dictionary(grouping: occurrences, by: { $0.date })
        let sortedDates = grouped.keys.sorted()

        var result: [BalanceStep] = []
        var running = startBalance
        result.append(BalanceStep(date: period.startDate, balance: running))

        for day in sortedDates {
            running += grouped[day]!.reduce(Decimal(0)) { $0 + $1.amount }
            result.append(BalanceStep(date: day, balance: running))
        }

        let lastDay = calendar.startOfDay(for: result.last?.date ?? period.startDate)
        let endDay  = calendar.startOfDay(for: period.endDate)
        if lastDay < endDay {
            result.append(BalanceStep(date: period.endDate, balance: running))
        }

        return result
    }

    // MARK: - Visual helpers

    private var yMin: Double {
        let minVal = steps.map { ($0.balance as NSDecimalNumber).doubleValue }.min() ?? 0
        return min(minVal, 0) * 1.05
    }

    private var yMax: Double {
        let maxVal = steps.map { ($0.balance as NSDecimalNumber).doubleValue }.max() ?? 1
        return maxVal * 1.10
    }

    /// Couleur pour un solde précis (utilisée sur les points).
    private func colorFor(balance: Decimal) -> Color {
        if balance < 0              { return softRedColor }
        if balance < tightThreshold { return amberColor }
        return greenColor
    }

    /// Gradient vertical vert → amber → rouge selon les seuils sur le domaine Y du graphique.
    /// `opaque: true`  → ligne (couleurs pleines)
    /// `opaque: false` → aire (couleurs atténuées, fondues vers le bas)
    private func makeGradient(opaque: Bool) -> LinearGradient {
        let range = yMax - yMin
        let t = (tightThreshold as NSDecimalNumber).doubleValue

        func pos(_ v: Double) -> CGFloat { CGFloat(max(0, min(1, (yMax - v) / range))) }
        func stop(_ c: Color, _ alpha: Double, _ loc: CGFloat) -> Gradient.Stop {
            .init(color: opaque ? c : c.opacity(alpha), location: loc)
        }

        guard range > 0.01 else {
            let c: Color = yMax < 0 ? softRedColor : yMax < t ? amberColor : greenColor
            return LinearGradient(
                stops: [stop(c, 0.30, 0), stop(c, opaque ? 1.0 : 0.04, 1)],
                startPoint: .top, endPoint: .bottom
            )
        }

        let tPos    = pos(t)
        let zeroPos = pos(0.0)
        var stops: [Gradient.Stop] = []

        // Haut du graphique → seuil tight
        if yMax >= t {
            stops.append(stop(greenColor, 0.30, 0))
            if tPos > 0.01 {
                stops.append(stop(greenColor,  0.18, max(0, tPos - 0.005)))
                stops.append(stop(amberColor,  0.28, tPos))
            }
        } else if yMax >= 0 {
            stops.append(stop(amberColor, 0.28, 0))
        } else {
            stops.append(stop(softRedColor, 0.30, 0))
        }

        // Franchissement de zéro (solde qui passe en négatif)
        if yMin < 0 && yMax > 0 && zeroPos > 0.01 && zeroPos < 0.99 {
            stops.append(stop(amberColor,   0.18, max(0, zeroPos - 0.005)))
            stops.append(stop(softRedColor, 0.35, zeroPos))
            stops.append(stop(softRedColor, 0.08, 1.0))
        } else {
            let bot: Color = yMin < 0 ? softRedColor : yMin < t ? amberColor : greenColor
            stops.append(stop(bot, opaque ? 1.0 : 0.04, 1.0))
        }

        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Body

    var body: some View {
        Chart {
            // Zone remplie — gradient vert/amber/rouge selon seuils Y
            ForEach(steps) { step in
                AreaMark(
                    x: .value("Date", step.date),
                    y: .value("Solde", step.balance)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(makeGradient(opaque: false))
            }

            // Ligne principale — même gradient, couleurs pleines
            ForEach(steps) { step in
                LineMark(
                    x: .value("Date", step.date),
                    y: .value("Solde", step.balance)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(makeGradient(opaque: true))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Point de départ — couleur selon son propre solde
            if let first = steps.first {
                PointMark(
                    x: .value("Date", first.date),
                    y: .value("Solde", first.balance)
                )
                .foregroundStyle(.white)
                .symbolSize(36)

                PointMark(
                    x: .value("Date", first.date),
                    y: .value("Solde", first.balance)
                )
                .foregroundStyle(colorFor(balance: first.balance))
                .symbolSize(16)
            }

            // Point final — couleur selon son propre solde
            if let last = steps.last, steps.count > 1 {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Solde", last.balance)
                )
                .foregroundStyle(.white)
                .symbolSize(54)

                PointMark(
                    x: .value("Date", last.date),
                    y: .value("Solde", last.balance)
                )
                .foregroundStyle(colorFor(balance: last.balance))
                .symbolSize(28)
            }

            // Ligne de seuil (si visible dans la plage)
            let threshold = (tightThreshold as NSDecimalNumber).doubleValue
            if threshold > yMin && threshold < yMax {
                RuleMark(y: .value("Seuil", tightThreshold))
                    .foregroundStyle(amberColor.opacity(0.50))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .annotation(position: .trailing, alignment: .center) {
                        Text(CurrencyFormatter.shared.format(tightThreshold))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(amberColor.opacity(0.75))
                    }
            }

            // Ligne de zéro si le solde peut être négatif
            if yMin < 0 {
                RuleMark(y: .value("Zéro", 0))
                    .foregroundStyle(Color.secondary.opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Ligne "Aujourd'hui" — pivot réel / projeté (période courante uniquement)
            if period.isCurrentPeriod {
                RuleMark(x: .value("Aujourd'hui", Date.now))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .annotation(position: .top, spacing: 2) {
                        Text("Aujourd'hui")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXScale(domain: period.startDate...period.endDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(dayLabel(date))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let d = value.as(Decimal.self) {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel {
                        Text(shortAmount(d))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    // MARK: - Helpers

    /// Nombre de jours entre deux marques sur l'axe X selon la durée de la période.
    private var xAxisStride: Int {
        let days = Calendar.current.dateComponents([.day], from: period.startDate, to: period.endDate).day ?? 14
        if days <= 14 { return 3 }
        if days <= 31 { return 7 }
        return 14
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func dayLabel(_ date: Date) -> String {
        Self.dayFmt.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// Montant court pour l'axe Y : "1,2k" ou "−500".
    private func shortAmount(_ value: Decimal) -> String {
        let abs = Swift.abs(value)
        if abs >= 1000 {
            let k   = value / 1000
            let fmt = NumberFormatter()
            fmt.maximumFractionDigits = 1
            fmt.minimumFractionDigits = 0
            fmt.locale = Locale(identifier: "fr_CA")
            return (fmt.string(from: k as NSDecimalNumber) ?? "\(k)") + "k"
        }
        return CurrencyFormatter.shared.format(value)
    }
}
