//
//  UpcomingOperationRow.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI

struct UpcomingOperationRow: View {
    let operation: UpcomingOperation

    var body: some View {
        HStack(spacing: 12) {
            // Icône catégorie — fallback gris si non catégorisée
            if let cat = operation.category {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 36)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Nom + date relative
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.name)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(relativeDateLabel(operation.date))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Montant
            Text(amountLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(operation.recurringTransaction.isIncome ? Color.green : Color.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    // MARK: - Helpers

    private var amountLabel: String {
        let prefix = operation.recurringTransaction.isIncome ? "+" : "−"
        return prefix + CurrencyFormatter.shared.format(Swift.abs(operation.amount))
    }

    private func relativeDateLabel(_ date: Date) -> String {
        let cal  = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: .now),
            to:   cal.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case 0:
            return "Aujourd'hui"
        case 1:
            return "Demain"
        case 2...7:
            let f = DateFormatter()
            f.locale     = Locale(identifier: "fr_CA")
            f.dateFormat = "EEE"
            // "mar." → capitalize first letter only
            let raw = f.string(from: date)
            return raw.prefix(1).uppercased() + raw.dropFirst() + "."
        default:
            return "Dans \(days) jours"
        }
    }
}
