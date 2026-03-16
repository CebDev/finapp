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
/// `period.transactions` contient toutes les Transaction de la période (payées et planifiées).
/// - isPaid == true  → transaction réelle (passée)
/// - isPaid == false → occurrence future planifiée
struct PeriodProgressChart: View {
    let period:              PayPeriod
    let carryForwardBalance: Bool
    let tightThreshold:      Decimal
    var budgetAccountIds:    Set<UUID> = []

    private let greenColor   = Color.green
    private let amberColor   = Color(red: 1.0, green: 0.7, blue: 0.0)
    private let softRedColor = Color(red: 0.85, green: 0.28, blue: 0.28)

    private struct BalanceStep: Identifiable {
        let id      = UUID()
        let date:    Date
        let balance: Decimal
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
        if period.isCurrentPeriod { return period.previousBalance }
        return carryForwardBalance ? period.previousBalance : Decimal(0)
    }

    private var steps: [BalanceStep] {
        let calendar    = Calendar.current
        let periodStart = calendar.startOfDay(for: period.startDate)
        let periodEnd   = calendar.startOfDay(for: period.endDate)

        var deltaByDay: [Date: Decimal] = [:]
        for tx in period.transactions {
            let day = calendar.startOfDay(for: tx.date)
            guard day >= periodStart && day <= periodEnd else { continue }
            deltaByDay[day, default: 0] += budgetDelta(for: tx)
        }

        var result:  [BalanceStep] = []
        var running  = startBalanceAtJMinus1
        var day      = chartStartDay

        while day <= chartEndDay {
            if day >= periodStart && day <= periodEnd {
                running += deltaByDay[day, default: 0]
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

    private func budgetDelta(for tx: Transaction) -> Decimal {
        let sourceInBudget = budgetAccountIds.isEmpty || budgetAccountIds.contains(tx.accountId)
        if tx.isTransfer {
            let destInBudget = tx.transferDestinationAccountId
                .map { budgetAccountIds.isEmpty || budgetAccountIds.contains($0) } ?? false
            var delta: Decimal = 0
            if sourceInBudget { delta -= tx.amount }
            if destInBudget   { delta += tx.amount }
            return delta
        }
        return sourceInBudget ? tx.amount : 0
    }

    private var yMin: Double {
        let minVal = steps.map { ($0.balance as NSDecimalNumber).doubleValue }.min() ?? 0
        return min(minVal, 0) * 1.05
    }

    private var yMax: Double {
        let maxVal = steps.map { ($0.balance as NSDecimalNumber).doubleValue }.max() ?? 1
        return maxVal * 1.10
    }

    private func colorFor(balance: Decimal) -> Color {
        if balance < 0              { return softRedColor }
        if balance < tightThreshold { return amberColor }
        return greenColor
    }

    private func makeGradient(opaque: Bool) -> LinearGradient {
        let range = yMax - yMin
        let t     = (tightThreshold as NSDecimalNumber).doubleValue

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

        if yMax >= t {
            stops.append(stop(greenColor, 0.30, 0))
            if tPos > 0.01 {
                stops.append(stop(greenColor, 0.18, max(0, tPos - 0.005)))
                stops.append(stop(amberColor, 0.28, tPos))
            }
        } else if yMax >= 0 {
            stops.append(stop(amberColor, 0.28, 0))
        } else {
            stops.append(stop(softRedColor, 0.30, 0))
        }

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

    var body: some View {
        Chart {
            ForEach(steps) { step in
                AreaMark(x: .value("Date", step.date), y: .value("Solde", step.balance))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(makeGradient(opaque: false))
            }
            ForEach(steps) { step in
                LineMark(x: .value("Date", step.date), y: .value("Solde", step.balance))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(makeGradient(opaque: true))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let first = steps.first {
                PointMark(x: .value("Date", first.date), y: .value("Solde", first.balance))
                    .foregroundStyle(.white).symbolSize(36)
                PointMark(x: .value("Date", first.date), y: .value("Solde", first.balance))
                    .foregroundStyle(colorFor(balance: first.balance)).symbolSize(16)
            }
            if let last = steps.last, steps.count > 1 {
                PointMark(x: .value("Date", last.date), y: .value("Solde", last.balance))
                    .foregroundStyle(.white).symbolSize(54)
                PointMark(x: .value("Date", last.date), y: .value("Solde", last.balance))
                    .foregroundStyle(colorFor(balance: last.balance)).symbolSize(28)
            }
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
            if yMin < 0 {
                RuleMark(y: .value("Zéro", 0))
                    .foregroundStyle(Color.secondary.opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            RuleMark(x: .value("Début période", period.startDate))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text("Début")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            RuleMark(x: .value("Fin période", period.endDate))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .annotation(position: .top, spacing: 2) {
                    Text("Fin")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            if period.isCurrentPeriod {
                RuleMark(x: .value("Aujourd'hui", Date.now))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .annotation(position: .top, spacing: 2) {
                        Text("Aujourd'hui")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXScale(domain: chartStartDay...chartEndDay)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(dayLabel(date)).font(.caption2).foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let d = value.as(Decimal.self) {
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel {
                        Text(shortAmount(d)).font(.caption2).foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private var xAxisStride: Int {
        let days = Calendar.current.dateComponents([.day], from: period.startDate, to: period.endDate).day ?? 14
        if days <= 14 { return 3 }
        if days <= 31 { return 7 }
        return 14
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func dayLabel(_ date: Date) -> String {
        Self.dayFmt.string(from: date).replacingOccurrences(of: ".", with: "")
    }

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