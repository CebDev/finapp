//
//  PayPeriodCard.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI

struct PayPeriodCard: View {
    let period:              PayPeriod
    /// Valeur max utilisée pour normaliser la barre.
    /// En mode cumulé : max des soldes projetés. En mode isolé : max des deltas absolus.
    let maxBalance:          Decimal
    let onTap:               () -> Void
    /// Quand false : la barre représente le solde de la période (delta), layout inversé.
    var carryForwardBalance: Bool = true

    // MARK: - Computed

    private var deltaIsPositive: Bool { period.delta >= 0 }

    private var barFraction: CGFloat {
        guard maxBalance > 0 else { return 0 }
        let value = carryForwardBalance ? period.projectedBalance : abs(period.delta)
        let clamped = max(Decimal(0.03), min(value / maxBalance, Decimal(1)))
        return CGFloat(NSDecimalNumber(decimal: clamped).doubleValue)
    }

    private var barColor: Color {
        if period.isTight { return amberColor }
        if !carryForwardBalance { return deltaIsPositive ? .green : amberColor }
        return .green
    }

    private var amberColor: Color { Color(red: 1.0, green: 0.7, blue: 0.0) }

    // MARK: - Formatage

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.dayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private var dateRangeLabel: String {
        "\(shortDate(period.startDate)) — \(shortDate(period.endDate))"
    }

    private var deltaLabel: String {
        let prefix = deltaIsPositive ? "↑ +" : "↓ "
        return prefix + CurrencyFormatter.shared.format(abs(period.delta))
    }

    private var balanceLabel: String {
        CurrencyFormatter.shared.format(period.projectedBalance)
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {

                    if carryForwardBalance {
                        // ── Mode cumulé : dates + delta à gauche, solde cumulé à droite ──

                        VStack(alignment: .leading, spacing: 2) {
                            dateRow
                            Text(deltaLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(deltaIsPositive ? Color.green : Color.orange)
                        }
                        .frame(minWidth: 130, alignment: .leading)

                        progressBar

                        HStack(spacing: 5) {
                            Text(balanceLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(period.isTight ? amberColor : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Circle()
                                .fill(period.isTight ? amberColor : Color.clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(minWidth: 80, alignment: .trailing)

                    } else {
                        // ── Mode isolé : dates + solde cumulé (petit) à gauche, delta (grand) à droite ──

                        VStack(alignment: .leading, spacing: 2) {
                            dateRow
                            Text(balanceLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 130, alignment: .leading)

                        progressBar

                        HStack(spacing: 5) {
                            Text(deltaLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(deltaIsPositive ? Color.green : Color.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Circle()
                                .fill(period.isTight ? amberColor : Color.clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(minWidth: 80, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)

                Divider()
                    .padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sous-vues partagées

    private var dateRow: some View {
        HStack(spacing: 5) {
            if period.isCurrentPeriod {
                Text("En cours")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
            }
            Text(dateRangeLabel)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(height: 6)
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * barFraction, height: 6)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Preview

#Preview {
    let cal = Calendar.current
    let periods: [PayPeriod] = [
        PayPeriod(
            id: UUID(),
            startDate: cal.date(byAdding: .day, value: -7,  to: .now)!,
            endDate:   cal.date(byAdding: .day, value:  6,  to: .now)!,
            projectedBalance: 3_955,
            previousBalance:  1_525,
            delta:            2_430,
            isTight:          false,
            isCurrentPeriod:  true,
            transactions:     []
        ),
        PayPeriod(
            id: UUID(),
            startDate: cal.date(byAdding: .day, value:  7,  to: .now)!,
            endDate:   cal.date(byAdding: .day, value: 20,  to: .now)!,
            projectedBalance: 320,
            previousBalance:  640,
            delta:            -320,
            isTight:          true,
            isCurrentPeriod:  false,
            transactions:     []
        ),
        PayPeriod(
            id: UUID(),
            startDate: cal.date(byAdding: .day, value: 21,  to: .now)!,
            endDate:   cal.date(byAdding: .day, value: 34,  to: .now)!,
            projectedBalance: 2_100,
            previousBalance:  320,
            delta:            1_780,
            isTight:          false,
            isCurrentPeriod:  false,
            transactions:     []
        ),
    ]
    let maxBal = periods.map(\.projectedBalance).max() ?? 1

    return VStack(spacing: 0) {
        ForEach(periods) { p in
            PayPeriodCard(period: p, maxBalance: maxBal, onTap: {})
        }
    }
    .background(Color(.systemBackground))
}
