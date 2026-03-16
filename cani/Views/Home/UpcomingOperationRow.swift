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
            if operation.isPaid {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            } else if let logo = operation.logo, !logo.isEmpty {
                SubscriptionLogoImage(logo: logo, size: 36)
            } else if let cat = operation.category {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(operation.name)
                    .font(operation.isPaid ? .system(size: 15).italic() : .system(size: 15))
                    .foregroundStyle(operation.isPaid ? Color.secondary : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(relativeDateLabel(operation.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let accountName = operation.accountName {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text(accountName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if operation.isPaid {
                        Text("· payée")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Text(amountLabel)
                .font(operation.isPaid
                      ? .subheadline.weight(.semibold).italic()
                      : .subheadline.weight(.semibold))
                .foregroundStyle(operation.isPaid
                                 ? Color.secondary
                                 : (operation.isIncome ? Color.green : Color.orange))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    // MARK: - Helpers

    private var amountLabel: String {
        let prefix = operation.isIncome ? "+" : "−"
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
            f.dateFormat = "EEEE"
            let raw = f.string(from: date)
            return raw.prefix(1).uppercased() + raw.dropFirst()
        default:
            return "Dans \(days) jours"
        }
    }
}