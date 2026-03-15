//
//  PeriodProgressChart.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import Charts

/// Graphique de l'évolution du solde à l'intérieur d'une seule période.
///
/// - Période courante : départ à `period.previousBalance` (J-1).
/// - Période future : départ à `period.previousBalance` si report actif, sinon 0.
/// - Chaque point correspond au solde journalier (réel pour les jours passés, projeté pour les jours à venir).
struct PeriodProgressChart: View {
    let period:              PayPeriod
    let carryForwardBalance: Bool
    let tightThreshold:      Decimal
    var overrides:           [TransactionOverride] = []
    var realTransactions:    [Transaction] = []
    var budgetAccountIds:    Set<UUID> = []

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

    private struct OccurrenceKey: Hashable {
        let recurringId: UUID
        let day: Date
    }

    private var chartStartDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: period.startDate))
        ?? Calendar.current.startOfDay(for: period.startDate)
    }

    private var chartEndDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: period.endDate))
        ?? Calendar.current.startOfDay(for: period.endDate)
    }

    private var startBalanceAtJMinus1: Decimal {
        if period.isCurrentPeriod {
            return period.previousBalance
        }
        return carryForwardBalance ? period.previousBalance : Decimal(0)
    }

    /// Construit les points journaliers.
    private var steps: [BalanceStep] {
        let calendar = Calendar.current
        let periodStart = calendar.startOfDay(for: period.startDate)
        let periodEnd = calendar.startOfDay(for: period.endDate)
        let today = calendar.startOfDay(for: .now)

        let realByDay = buildRealDailyDelta(calendar: calendar, startDay: periodStart, endDay: periodEnd)
        let projectedByDay = buildProjectedDailyDelta(calendar: calendar, startDay: periodStart, endDay: periodEnd)

        var result: [BalanceStep] = []
        var running = startBalanceAtJMinus1
        var day = chartStartDay

        while day <= chartEndDay {
            if day >= periodStart && day <= periodEnd {
                if day < today {
                    running += realByDay[day, default: 0]
                } else {
                    running += projectedByDay[day, default: 0]
                }
            }
            result.append(BalanceStep(date: day, balance: running))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        if result.isEmpty {
            result.append(BalanceStep(date: chartStartDay, balance: running))
        }

        return result
    }

    private func buildProjectedDailyDelta(calendar: Calendar, startDay: Date, endDay: Date) -> [Date: Decimal] {
        let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        var deltaByDay: [Date: Decimal] = [:]

        for tx in period.transactions {
            let dates = ProjectionEngine.occurrences(of: tx, from: startDay, to: exclusiveEnd, calendar: calendar)
            for date in dates {
                let occurrenceDay = calendar.startOfDay(for: date)
                let ov = overrides.first {
                    $0.recurringTransactionId == tx.id &&
                    calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: occurrenceDay)
                }
                if let ov, ov.isSkipped { continue }
                if ov?.isPaid == true { continue }

                let day = calendar.startOfDay(for: ov?.actualDate ?? occurrenceDay)
                guard day >= startDay && day <= endDay else { continue }

                let amount = ov?.actualAmount ?? tx.amount
                let sourceAccountId = ov?.actualAccountId ?? tx.accountId
                deltaByDay[day, default: 0] += budgetDelta(
                    amount: amount,
                    sourceAccountId: sourceAccountId,
                    isTransfer: tx.isTransfer,
                    destinationAccountId: tx.transferDestinationAccountId
                )
            }
        }

        return deltaByDay
    }

    private func buildRealDailyDelta(calendar: Calendar, startDay: Date, endDay: Date) -> [Date: Decimal] {
        var deltaByDay: [Date: Decimal] = [:]

        for tx in realTransactions where tx.isConfirmed {
            let day = calendar.startOfDay(for: tx.date)
            guard day >= startDay && day <= endDay else { continue }
            deltaByDay[day, default: 0] += budgetDelta(
                amount: tx.amount,
                sourceAccountId: tx.accountId,
                isTransfer: tx.isTransfer,
                destinationAccountId: tx.transferDestinationAccountId
            )
        }

        let paidRealKeys: Set<OccurrenceKey> = Set(
            realTransactions.compactMap { tx in
                guard let recurringId = tx.recurringTransactionId else { return nil }
                return OccurrenceKey(recurringId: recurringId, day: calendar.startOfDay(for: tx.date))
            }
        )

        let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        for tx in period.transactions {
            let dates = ProjectionEngine.occurrences(of: tx, from: startDay, to: exclusiveEnd, calendar: calendar)
            for date in dates {
                let occurrenceDay = calendar.startOfDay(for: date)
                guard let ov = overrides.first(where: {
                    $0.recurringTransactionId == tx.id &&
                    calendar.isDate(calendar.startOfDay(for: $0.occurrenceDate), inSameDayAs: occurrenceDay)
                }) else { continue }
                guard ov.isPaid, !ov.isSkipped else { continue }

                let day = calendar.startOfDay(for: ov.actualDate ?? occurrenceDay)
                guard day >= startDay && day <= endDay else { continue }

                let key = OccurrenceKey(recurringId: tx.id, day: day)
                if paidRealKeys.contains(key) { continue }

                let amount = ov.actualAmount ?? tx.amount
                let sourceAccountId = ov.actualAccountId ?? tx.accountId
                deltaByDay[day, default: 0] += budgetDelta(
                    amount: amount,
                    sourceAccountId: sourceAccountId,
                    isTransfer: tx.isTransfer,
                    destinationAccountId: tx.transferDestinationAccountId
                )
            }
        }

        return deltaByDay
    }

    private func budgetDelta(
        amount: Decimal,
        sourceAccountId: UUID,
        isTransfer: Bool,
        destinationAccountId: UUID?
    ) -> Decimal {
        let sourceInBudget = budgetAccountIds.contains(sourceAccountId)
        if isTransfer {
            let destInBudget = destinationAccountId.map { budgetAccountIds.contains($0) } ?? false
            var delta: Decimal = 0
            if sourceInBudget { delta -= amount }
            if destInBudget { delta += amount }
            return delta
        }
        return sourceInBudget ? amount : 0
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
                .interpolationMethod(.monotone)
                .foregroundStyle(makeGradient(opaque: false))
            }

            // Ligne principale — même gradient, couleurs pleines
            ForEach(steps) { step in
                LineMark(
                    x: .value("Date", step.date),
                    y: .value("Solde", step.balance)
                )
                .interpolationMethod(.monotone)
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

            // Repères de période: jour de début et jour de fin.
            RuleMark(x: .value("Début période", period.startDate))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text("Début")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

            RuleMark(x: .value("Fin période", period.endDate))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text("Fin")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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
        .chartXScale(domain: chartStartDay...chartEndDay)
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
