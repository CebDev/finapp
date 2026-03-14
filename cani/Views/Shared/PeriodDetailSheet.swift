//
//  PeriodDetailSheet.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

struct PeriodDetailSheet: View {
    let period:              PayPeriod
    var allPeriods:          [PayPeriod] = []
    /// Quand false, le header affiche un solde recalculé isolément (revenus − dépenses)
    /// et le graphique démarre à zéro, sans report du solde précédent.
    var carryForwardBalance: Bool = true
    var tightThreshold:     Decimal = 500

    @Query(sort: \Category.sortOrder) private var allCategories:  [Category]
    @Query                            private var allTransactions: [Transaction]
    @Query                            private var allOverrides:    [TransactionOverride]
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditChoice:        Bool                  = false
    @State private var editChoiceTarget:         RecurringTransaction? = nil
    @State private var editChoiceOccurrenceDate: Date                  = Date()
    @State private var editingRecurring:         RecurringTransaction? = nil
    @State private var editingOccurrence:        RecurringTransaction? = nil
    @State private var markingAsPaid:            RecurringTransaction? = nil
    @State private var markingAsPaidDate:        Date                  = Date()

    // MARK: - Computed

    /// Une entrée par occurrence (pas par récurrence) — c'est le fix du bug d'affichage.
    private struct SortedEntry: Identifiable {
        let id:   UUID
        let tx:   RecurringTransaction
        let date: Date
    }

    private var sortedTransactions: [SortedEntry] {
        let cal          = Calendar.current
        let exclusiveEnd = cal.date(byAdding: .day, value: 1, to: period.endDate) ?? period.endDate
        return period.transactions
            .flatMap { tx -> [SortedEntry] in
                ProjectionEngine.occurrences(of: tx, from: period.startDate, to: exclusiveEnd, calendar: cal)
                    .map { SortedEntry(id: UUID(), tx: tx, date: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    private var totalIncome: Decimal {
        sortedTransactions
            .filter { $0.tx.isIncome }
            .reduce(0) { $0 + abs(effectiveAmount(for: $1.tx, at: $1.date)) }
    }

    private var totalExpenses: Decimal {
        sortedTransactions
            .filter { !$0.tx.isIncome }
            .reduce(0) { $0 + abs(effectiveAmount(for: $1.tx, at: $1.date)) }
    }

    private func category(for tx: RecurringTransaction) -> Category? {
        guard let id = tx.categoryId else { return nil }
        return allCategories.first { $0.id == id }
    }

    /// Retourne le Transaction d'override pour une occurrence précise, s'il existe.
    private func occurrenceOverride(for tx: RecurringTransaction, at occDate: Date) -> Transaction? {
        let cal = Calendar.current
        return allTransactions.first {
            $0.recurringTransactionId == tx.id &&
            cal.isDate($0.date, inSameDayAs: occDate)
        }
    }

    /// Montant effectif à afficher : override si présent, sinon la règle récurrente.
    private func effectiveAmount(for tx: RecurringTransaction, at occDate: Date) -> Decimal {
        occurrenceOverride(for: tx, at: occDate)?.amount ?? tx.amount
    }

    /// Catégorie effective : override si présent, sinon la règle récurrente.
    private func effectiveCategory(for tx: RecurringTransaction, at occDate: Date) -> Category? {
        let categoryId = occurrenceOverride(for: tx, at: occDate)?.categoryId ?? tx.categoryId
        guard let id = categoryId else { return nil }
        return allCategories.first { $0.id == id }
    }

    /// Retourne le TransactionOverride marqué payé pour une occurrence précise, s'il existe.
    private func paidOverride(for tx: RecurringTransaction, at occDate: Date) -> TransactionOverride? {
        let cal = Calendar.current
        return allOverrides.first {
            $0.recurringTransactionId == tx.id &&
            $0.isPaid &&
            cal.isDate(cal.startOfDay(for: $0.occurrenceDate), inSameDayAs: cal.startOfDay(for: occDate))
        }
    }

    // MARK: - Mode isolé (carryForwardBalance == false)

    /// Solde recalculé sans report : revenus − dépenses de la période uniquement.
    private var isolatedProjectedBalance: Decimal {
        totalIncome - totalExpenses
    }

    /// Solde affiché dans le header selon le mode actif.
    private var displayedProjectedBalance: Decimal {
        carryForwardBalance ? period.projectedBalance : isolatedProjectedBalance
    }

    /// Version de allPeriods où la période focalisée a son previousBalance remplacé par 0
    /// et son projectedBalance remplacé par isolatedProjectedBalance — pour le graphique en mode isolé.
    private var chartPeriods: [PayPeriod] {
        guard !carryForwardBalance else { return allPeriods }
        let isolated = isolatedProjectedBalance
        return allPeriods.map { p in
            guard p.id == period.id else { return p }
            return PayPeriod(
                id:               p.id,
                startDate:        p.startDate,
                endDate:          p.endDate,
                projectedBalance: isolated,
                previousBalance:  0,
                delta:            isolated,
                isTight:          p.isTight,
                isCurrentPeriod:  p.isCurrentPeriod,
                transactions:     p.transactions
            )
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if !period.transactions.isEmpty {
                        PeriodProgressChart(
                            period:              period,
                            carryForwardBalance: carryForwardBalance,
                            tightThreshold:      tightThreshold,
                            overrides:           allOverrides
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    if period.isTight {
                        tightBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if sortedTransactions.isEmpty {
                        emptyState
                    } else {
                        sectionLabel("Transactions")
                        ForEach(sortedTransactions) { entry in
                            transactionRow(entry.tx, occurrenceDate: entry.date)
                        }
                    }

                    // Espace sous le contenu pour que le footer ne le masque pas
                    Spacer(minLength: 110)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            .navigationTitle(dateRangeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                editChoiceTarget?.name ?? "",
                isPresented: $showingEditChoice,
                titleVisibility: .visible
            ) {
                Button("Modifier toutes les occurrences à venir") {
                    editingRecurring = editChoiceTarget
                    editChoiceTarget = nil
                }
                Button("Modifier uniquement cette occurrence") {
                    editingOccurrence = editChoiceTarget
                    editChoiceTarget  = nil
                }
                Divider()
                Button("Marquer comme payé") {
                    markingAsPaidDate = editChoiceOccurrenceDate
                    markingAsPaid     = editChoiceTarget
                    editChoiceTarget  = nil
                }
                Button("Annuler", role: .cancel) {
                    editChoiceTarget = nil
                }
            }
            .sheet(item: $editingRecurring) { tx in
                AddTransactionView(editingRecurring: tx)
            }
            .sheet(item: $editingOccurrence) { tx in
                AddTransactionView(
                    editingOccurrenceRecurring: tx,
                    editingOccurrenceDate:      editChoiceOccurrenceDate
                )
            }
            .sheet(item: $markingAsPaid) { tx in
                MarkAsPaidSheet(transaction: tx, occurrenceDate: markingAsPaidDate)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CurrencyFormatter.shared.format(displayedProjectedBalance))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if carryForwardBalance {
                HStack(spacing: 4) {
                    let positive = period.delta >= 0
                    Image(systemName: positive ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.bold))
                    Text((period.delta >= 0 ? "+" : "") + CurrencyFormatter.shared.format(abs(period.delta)))
                        .font(.subheadline.weight(.medium))
                    Text("cette période")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(period.delta >= 0 ? Color.green : Color.orange)
            } else {
                Text("Vue isolée")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Tight banner

    private var tightBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Text("Période serrée — solde bas prévu")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(amberColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(amberColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: - Transaction row

    private func transactionRow(_ tx: RecurringTransaction, occurrenceDate occ: Date) -> some View {
        let cat        = effectiveCategory(for: tx, at: occ)
        let amount     = effectiveAmount(for: tx, at: occ)
        let isOverride = occurrenceOverride(for: tx, at: occ) != nil
        let isPaid     = paidOverride(for: tx, at: occ) != nil
        let isIncome   = tx.isIncome
        return HStack(spacing: 12) {
            // Icône : checkmark vert si payé, sinon badge catégorie normal
            if isPaid {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            } else if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 36)
            } else {
                CategoryIconBadge(icon: "square.dashed", color: "#98989D", size: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.name)
                    .font(isPaid ? .body.italic() : .body)
                    .foregroundStyle(isPaid ? Color.secondary : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    // Date d'occurrence — information principale
                    Text(shortDate(occ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isPaid ? Color.secondary.opacity(0.7) : Color.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text(tx.frequency.labelFR)
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    if isPaid {
                        Text("· payée")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else if isOverride {
                        Text("· modifiée")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.indigo)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(amount)))
                    .font(isPaid ? .subheadline.weight(.semibold).italic() : .subheadline.weight(.semibold))
                    .foregroundStyle(isPaid ? Color.secondary : (isIncome ? Color.green : Color.orange))
                if !isPaid {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
        .overlay(
            Divider()
                .padding(.leading, 68),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editChoiceTarget         = tx
            editChoiceOccurrenceDate = occ
            showingEditChoice        = true
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Aucune transaction planifiée")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Sticky footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Text("Revenus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+" + CurrencyFormatter.shared.format(totalIncome))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
                HStack {
                    Text("Dépenses")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("−" + CurrencyFormatter.shared.format(totalExpenses))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }

                Divider()

                HStack {
                    Text("Solde projeté")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(CurrencyFormatter.shared.format(displayedProjectedBalance))
                        .font(.body.weight(.bold))
                        .foregroundStyle(period.isTight ? amberColor : Color.indigo)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.dateFormat = "d MMM"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
    }

    private var dateRangeLabel: String {
        "\(shortDate(period.startDate)) — \(shortDate(period.endDate))"
    }

    /// Amber — jamais rouge pour les alertes budget.
    private var amberColor: Color {
        Color(red: 1.0, green: 0.7, blue: 0.0)
    }
}

// MARK: - Preview

#Preview {
    Text("Ouvrir sheet")
        .sheet(isPresented: .constant(true)) {
            PeriodDetailSheet(
                period: PayPeriod(
                    id: UUID(),
                    startDate: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
                    endDate: Calendar.current.date(byAdding: .day, value: 6, to: .now)!,
                    projectedBalance: 420,
                    previousBalance: 1_990,
                    delta: -1_570,
                    isTight: true,
                    isCurrentPeriod: true,
                    transactions: []
                )
            )
        }
        .modelContainer(for: Category.self, inMemory: true)
}
