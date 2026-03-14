//
//  AccountTransactionsSheet.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import SwiftData

// MARK: - Modèle d'affichage unifié

/// Représente une entrée dans le relevé, qu'elle vienne d'un Transaction ou d'un TransactionOverride payé.
private struct AccountEntry: Identifiable {
    let id:         UUID
    let date:       Date
    let amount:     Decimal
    let categoryId: UUID?
    let label:      String
    let isPaidOverride: Bool   // true = provient d'une récurrence payée
}

// MARK: - Sheet principale

struct AccountTransactionsSheet: View {
    let account:    Account
    let categories: [Category]

    @Environment(\.dismiss) private var dismiss

    /// Transactions manuelles passées et confirmées sur ce compte (3 derniers mois).
    @Query private var pastTransactions: [Transaction]

    /// Toutes les occurrences marquées payées — filtrage par compte en mémoire.
    @Query(filter: #Predicate<TransactionOverride> { $0.isPaid == true })
    private var paidOverrides: [TransactionOverride]

    /// Récurrences pour résoudre noms et catégories des overrides payés.
    @Query private var allRecurring: [RecurringTransaction]

    private static let amberColor = Color(red: 1.0, green: 0.7, blue: 0.0)

    // MARK: - Init avec @Query filtré

    init(account: Account, categories: [Category]) {
        self.account    = account
        self.categories = categories

        let accountId = account.id
        let cutoff    = Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now

        _pastTransactions = Query(
            filter: #Predicate<Transaction> {
                $0.accountId == accountId &&
                $0.date      >= cutoff    &&
                $0.isPast    == true
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    // MARK: - Entrées unifiées

    private var entries: [AccountEntry] {
        let cal    = Calendar.current
        let cutoff = cal.date(byAdding: .month, value: -3, to: .now) ?? .now

        var result: [AccountEntry] = []

        // 1. Transactions passées manuelles
        for tx in pastTransactions {
            // Si un override payé couvre cette occurrence récurrente, l'afficher via la section 2 uniquement
            if let recurId = tx.recurringTransactionId {
                let hasPaidOverride = paidOverrides.contains { ov in
                    ov.recurringTransactionId == recurId &&
                    cal.isDate(cal.startOfDay(for: ov.occurrenceDate), inSameDayAs: cal.startOfDay(for: tx.date))
                }
                if hasPaidOverride { continue }
            }
            let cat   = tx.categoryId.flatMap { id in categories.first { $0.id == id } }
            let label = entryLabel(notes: tx.notes, categoryName: cat?.name, isIncome: tx.amount > 0)
            result.append(AccountEntry(
                id:             tx.id,
                date:           tx.date,
                amount:         tx.amount,
                categoryId:     tx.categoryId,
                label:          label,
                isPaidOverride: false
            ))
        }

        // 2. Occurrences récurrentes marquées payées sur ce compte
        for override in paidOverrides {
            guard let recurring = allRecurring.first(where: { $0.id == override.recurringTransactionId })
            else { continue }

            // Vérifie que l'override concerne ce compte
            let targetAccountId = override.actualAccountId ?? recurring.accountId
            guard targetAccountId == account.id else { continue }

            // Date effective : actualDate > occurrenceDate
            let entryDate = override.actualDate ?? override.occurrenceDate
            guard entryDate >= cutoff else { continue }

            let amount = override.actualAmount ?? recurring.amount
            let cat    = recurring.categoryId.flatMap { id in categories.first { $0.id == id } }
            let label  = entryLabel(notes: override.notes, categoryName: cat?.name, isIncome: recurring.isIncome, fallback: recurring.name)

            result.append(AccountEntry(
                id:             override.id,
                date:           entryDate,
                amount:         amount,
                categoryId:     recurring.categoryId,
                label:          label,
                isPaidOverride: true
            ))
        }

        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Groupement par mois

    private struct MonthGroup: Identifiable {
        let id:           Date
        let label:        String
        let entries:      [AccountEntry]
        let totalIncome:  Decimal
        let totalExpense: Decimal
    }

    private var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        let fmt: DateFormatter = {
            let f = DateFormatter()
            f.locale     = Locale(identifier: "fr_CA")
            f.dateFormat = "MMMM yyyy"
            return f
        }()

        let grouped = Dictionary(
            grouping: entries,
            by: { cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date }
        )

        return grouped.keys
            .sorted { $0 > $1 }
            .compactMap { key in
                let items   = (grouped[key] ?? []).sorted { $0.date > $1.date }
                let income  = items.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
                let expense = items.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + abs($1.amount) }
                let raw     = fmt.string(from: key)
                let label   = raw.prefix(1).uppercased() + raw.dropFirst()
                return MonthGroup(
                    id:           key,
                    label:        String(label),
                    entries:      items,
                    totalIncome:  income,
                    totalExpense: expense
                )
            }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    if monthGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(monthGroups) { group in
                            monthSection(group)
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header card

    private var headerCard: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            account.type.accentColor.opacity(0.85),
                            account.type.accentColor
                        ],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 130)
                .offset(x: 20, y: 40)
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 70)
                .offset(x: -10, y: 15)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(.white.opacity(0.20))
                            .frame(width: 36, height: 36)
                        Image(systemName: account.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(account.type.labelFR)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }

                Text(CurrencyFormatter.shared.format(account.effectiveBalance))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("3 derniers mois · mouvements réels")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .shadow(
            color: account.type.accentColor.opacity(0.35),
            radius: 16, x: 0, y: 6
        )
    }

    // MARK: - Section par mois

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(group.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    if group.totalIncome > 0 {
                        Text("+" + CurrencyFormatter.shared.format(group.totalIncome))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    if group.totalExpense > 0 {
                        Text("−" + CurrencyFormatter.shared.format(group.totalExpense))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.amberColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Self.amberColor.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    entryRow(entry)
                    if entry.id != group.entries.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Ligne entrée

    private func entryRow(_ entry: AccountEntry) -> some View {
        let isIncome = entry.amount > 0
        let cat      = entry.categoryId.flatMap { id in categories.first { $0.id == id } }

        return HStack(spacing: 12) {
            // Icône : badge catégorie, ou checkmark vert si récurrence payée, sinon flèche
            if entry.isPaidOverride {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            } else if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 38)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: isIncome ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isIncome ? Color.green : Self.amberColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.isPaidOverride {
                        Text("· récurrence")
                            .font(.caption)
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }

            Spacer()

            Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(entry.amount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? Color.green : Self.amberColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 38))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("Aucune transaction")
                .font(.headline)
            Text("Aucun mouvement réel enregistré\nsur les 3 derniers mois.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func entryLabel(
        notes: String?,
        categoryName: String?,
        isIncome: Bool,
        fallback: String? = nil
    ) -> String {
        if let n = notes,        !n.isEmpty { return n }
        if let f = fallback,     !f.isEmpty { return f }
        if let c = categoryName, !c.isEmpty { return c }
        return isIncome ? "Revenu" : "Dépense"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.dayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
