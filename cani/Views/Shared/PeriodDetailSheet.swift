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

    @Query(sort: \Category.sortOrder)          private var allCategories:  [Category]
    @Query                                     private var allTransactions: [Transaction]
    @Query                                     private var allOverrides:    [TransactionOverride]
    @Query(sort: \RecurringTransaction.name)   private var allRecurring:    [RecurringTransaction]
    @Query                                     private var allAccounts:     [Account]
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showingEditChoice:        Bool                    = false
    @State private var editChoiceTarget:         RecurringTransaction?   = nil
    @State private var editChoiceOccurrenceDate: Date                    = Date()
    @State private var editChoicePlannedState:   PlannedTransactionState? = nil
    @State private var editingRecurring:         RecurringTransaction?   = nil
    @State private var editingOccurrence:        RecurringTransaction?   = nil
    @State private var markingAsPaid:            RecurringTransaction?   = nil
    @State private var markingAsPaidDate:        Date                    = Date()
    // Transactions réelles (confirmées)
    @State private var tappedRealTx:             Transaction?            = nil
    @State private var showingRealTxMenu:        Bool                    = false
    @State private var editingRealTx:            Transaction?            = nil

    // MARK: - Computed

    /// État d'une occurrence dans la période courante.
    private enum PlannedTransactionState: Equatable {
        case upcoming   // date > now, non confirmée → opacité réduite
        case overdue    // date ≤ now, non confirmée → tag rouge "EN RETARD"
    }

    /// Discriminant : opération réelle confirmée vs occurrence planifiée.
    private enum SortedEntryKind {
        case real(Transaction)
        case planned(RecurringTransaction, PlannedTransactionState?)
    }

    /// Une entrée par opération ou occurrence, triée par date.
    private struct SortedEntry: Identifiable {
        let id:   UUID
        let date: Date
        let kind: SortedEntryKind
    }

    private var sortedTransactions: [SortedEntry] {
        let cal          = Calendar.current
        let now          = Date()
        let todayStart   = cal.startOfDay(for: now)
        let exclusiveEnd = cal.date(byAdding: .day, value: 1, to: period.endDate) ?? period.endDate

        var entries: [SortedEntry] = []

        // 1. Transactions réelles confirmées dans la période courante uniquement.
        if period.isCurrentPeriod {
            for tx in allTransactions
            where tx.date >= period.startDate && tx.date < exclusiveEnd {
                entries.append(SortedEntry(id: tx.id, date: tx.date, kind: .real(tx)))
            }
        }

        // 2. Occurrences planifiées (récurrences) — exclut celles déjà payées (visible en .real)
        for tx in period.transactions {
            let occs = ProjectionEngine.occurrences(
                of: tx, from: period.startDate, to: exclusiveEnd, calendar: cal
            )
            for occDate in occs {
                // Occurrence supprimée manuellement → toujours ignorer
                if skippedOverride(for: tx, at: occDate) != nil { continue }

                let state: PlannedTransactionState?
                if period.isCurrentPeriod {
                    if paidOverride(for: tx, at: occDate) != nil { continue }
                    state = cal.startOfDay(for: occDate) <= todayStart ? .overdue : .upcoming
                } else {
                    state = nil
                }
                entries.append(SortedEntry(id: UUID(), date: occDate, kind: .planned(tx, state)))
            }
        }

        return entries.sorted { $0.date < $1.date }
    }

    private var totalIncome: Decimal {
        sortedTransactions.reduce(0) { total, entry in
            switch entry.kind {
            case .real(let tx):
                return tx.amount > 0 ? total + tx.amount : total
            case .planned(let tx, _):
                return tx.isIncome ? total + abs(effectiveAmount(for: tx, at: entry.date)) : total
            }
        }
    }

    private var totalExpenses: Decimal {
        sortedTransactions.reduce(0) { total, entry in
            switch entry.kind {
            case .real(let tx):
                return tx.amount < 0 ? total + abs(tx.amount) : total
            case .planned(let tx, _):
                return !tx.isIncome ? total + abs(effectiveAmount(for: tx, at: entry.date)) : total
            }
        }
    }

    private func category(for tx: RecurringTransaction) -> Category? {
        guard let id = tx.categoryId else { return nil }
        return allCategories.first { $0.id == id }
    }

    /// Nom à afficher pour une Transaction réelle : nom de la récurrence liée, ou notes, ou fallback.
    private func name(forReal tx: Transaction) -> String {
        if let rid = tx.recurringTransactionId,
           let recurring = allRecurring.first(where: { $0.id == rid }) {
            return recurring.name
        }
        return tx.notes ?? "Opération"
    }

    /// Catégorie à afficher pour une Transaction réelle.
    private func category(forReal tx: Transaction) -> Category? {
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

    /// Retourne le TransactionOverride marqué supprimé pour une occurrence précise, s'il existe.
    private func skippedOverride(for tx: RecurringTransaction, at occDate: Date) -> TransactionOverride? {
        let cal = Calendar.current
        return allOverrides.first {
            $0.recurringTransactionId == tx.id &&
            $0.isSkipped &&
            cal.isDate(cal.startOfDay(for: $0.occurrenceDate), inSameDayAs: cal.startOfDay(for: occDate))
        }
    }

    /// Vrai si la transaction sélectionnée a au moins une occurrence après la date de l'occurrence en cours.
    private var editChoiceHasFutureOccurrences: Bool {
        guard let tx = editChoiceTarget else { return false }
        return DateUtils.nextOccurrence(from: tx, after: editChoiceOccurrenceDate) != nil
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
                transactions:     p.transactions,
                dailyBalances:    p.dailyBalances
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

                    PeriodProgressChart(
                        period:              period,
                        carryForwardBalance: carryForwardBalance,
                        tightThreshold:      tightThreshold,
                        overrides:           allOverrides,
                        realTransactions:    allTransactions,
                        budgetAccountIds:    Set(allAccounts.filter(\.includeInBudget).map(\.id))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    if period.isTight {
                        tightBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if sortedTransactions.isEmpty {
                        emptyState
                    } else {
                        sectionLabel(period.isCurrentPeriod ? "Période en cours" : "Transactions")
                        ForEach(sortedTransactions) { entry in
                            transactionRow(entry)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                editChoiceTarget?.name ?? "",
                isPresented: $showingEditChoice,
                titleVisibility: .visible
            ) {
                // "Valider" = libellé prioritaire pour overdue/upcoming dans la période courante
                if editChoicePlannedState == .overdue || editChoicePlannedState == .upcoming {
                    Button("Valider le paiement") {
                        markingAsPaidDate = editChoiceOccurrenceDate
                        markingAsPaid     = editChoiceTarget
                        editChoiceTarget  = nil
                    }
                }
                if editChoiceHasFutureOccurrences {
                    Button("Modifier toutes les occurrences à venir") {
                        editingRecurring = editChoiceTarget
                        editChoiceTarget = nil
                    }
                }
                Button("Modifier uniquement cette occurrence") {
                    editingOccurrence = editChoiceTarget
                    editChoiceTarget  = nil
                }
                if editChoicePlannedState == nil {
                    // Périodes futures — conserver l'option de marquer comme payé
                    Button("Marquer comme payé") {
                        markingAsPaidDate = editChoiceOccurrenceDate
                        markingAsPaid     = editChoiceTarget
                        editChoiceTarget  = nil
                    }
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
            .confirmationDialog(
                tappedRealTx.map { name(forReal: $0) } ?? "",
                isPresented: $showingRealTxMenu,
                titleVisibility: .visible
            ) {
                Button("Modifier") {
                    editingRealTx = tappedRealTx
                    tappedRealTx  = nil
                }
                Button("Supprimer", role: .destructive) {
                    if let tx = tappedRealTx { deleteRealTx(tx) }
                    tappedRealTx = nil
                }
                Button("Annuler", role: .cancel) { tappedRealTx = nil }
            }
            .sheet(item: $editingRealTx) { tx in
                RealTransactionEditSheet(transaction: tx, allAccounts: allAccounts) { newAmount, newDate, newNotes, newAccountId in
                    updateRealTx(tx, newSignedAmount: newAmount, newDate: newDate, newNotes: newNotes, newAccountId: newAccountId)
                }
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

    // MARK: - Transaction row (dispatch)

    @ViewBuilder
    private func transactionRow(_ entry: SortedEntry) -> some View {
        switch entry.kind {
        case .real(let tx):
            realRow(tx)
        case .planned(let tx, let state):
            plannedRow(
                logo:          tx.logo,
                category:      effectiveCategory(for: tx, at: entry.date),
                name:          tx.name,
                occurrenceDate: entry.date,
                subtitleLabel: tx.frequency.labelFR,
                isModified:    occurrenceOverride(for: tx, at: entry.date) != nil,
                amount:        effectiveAmount(for: tx, at: entry.date),
                isIncome:      tx.isIncome,
                plannedState:  state,
                onTap: {
                    editChoiceTarget         = tx
                    editChoiceOccurrenceDate = entry.date
                    editChoicePlannedState   = state
                    showingEditChoice        = true
                }
            )
        }
    }

    // MARK: - Opération réelle (confirmée)

    private func realRow(_ tx: Transaction) -> some View {
        let cat      = category(forReal: tx)
        let isIncome = tx.amount > 0

        return HStack(spacing: 12) {
            if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 36)
            } else {
                CategoryIconBadge(
                    icon:  isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                    color: isIncome ? "#34C759" : "#FF9500",
                    size:  36
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name(forReal: tx))
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(tx.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text("Confirmée")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }

            Spacer()

            Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(tx.amount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? Color.green : Color.orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            tappedRealTx      = tx
            showingRealTxMenu = true
        }
    }

    // MARK: - Occurrence planifiée (récurrente ou ponctuelle)

    private func plannedRow(
        logo:          String,
        category:      Category?,
        name:          String,
        occurrenceDate occ: Date,
        subtitleLabel: String,
        isModified:    Bool,
        amount:        Decimal,
        isIncome:      Bool,
        plannedState:  PlannedTransactionState?,
        onTap:         @escaping () -> Void
    ) -> some View {
        let isOverdue  = plannedState == .overdue
        let isUpcoming = plannedState == .upcoming

        return HStack(spacing: 12) {
            if !logo.isEmpty {
                SubscriptionLogoImage(logo: logo, size: 36)
            } else if let category {
                CategoryIconBadge(icon: category.icon, color: category.color, size: 36)
            } else {
                CategoryIconBadge(icon: "square.dashed", color: "#98989D", size: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(occ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text(subtitleLabel)
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    if isOverdue {
                        Text("EN RETARD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if isModified && !isUpcoming {
                        Text("· modifiée")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.indigo)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(amount)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isIncome ? Color.green : Color.orange)
                if plannedState == nil {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(.systemBackground))
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
        .opacity(isUpcoming ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - Suppression / édition transactions réelles

    private func deleteRealTx(_ tx: Transaction) {
        // Annuler l'effet sur le solde si la transaction est passée
        if tx.isPast, let account = allAccounts.first(where: { $0.id == tx.accountId }) {
            account.currentBalance -= tx.amount
        }
        // Si liée à une récurrence, supprimer le marqueur isPaid pour que l'occurrence redevienne planifiée
        if let recurId = tx.recurringTransactionId {
            let cal = Calendar.current
            if let ov = allOverrides.first(where: {
                $0.recurringTransactionId == recurId &&
                $0.isPaid &&
                cal.isDate(cal.startOfDay(for: $0.occurrenceDate), inSameDayAs: cal.startOfDay(for: tx.date))
            }) {
                context.delete(ov)
            }
        }
        context.delete(tx)
    }

    private func updateRealTx(_ tx: Transaction, newSignedAmount: Decimal, newDate: Date, newNotes: String?, newAccountId: UUID) {
        let delta          = newSignedAmount - tx.amount
        let accountChanged = newAccountId != tx.accountId

        if tx.isPast {
            if accountChanged {
                if let oldAccount = allAccounts.first(where: { $0.id == tx.accountId }) {
                    oldAccount.currentBalance -= tx.amount
                }
                if let newAccount = allAccounts.first(where: { $0.id == newAccountId }) {
                    newAccount.currentBalance += newSignedAmount
                }
            } else if let account = allAccounts.first(where: { $0.id == tx.accountId }) {
                account.currentBalance += delta
            }
        }
        tx.amount    = newSignedAmount
        tx.date      = newDate
        tx.notes     = newNotes
        tx.accountId = newAccountId
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

// MARK: - RealTransactionEditSheet

private struct RealTransactionEditSheet: View {
    let transaction: Transaction
    let allAccounts: [Account]
    let onSave:      (Decimal, Date, String?, UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    @State private var amountText:        String
    @State private var date:              Date
    @State private var notes:             String
    @State private var selectedAccountId: UUID

    private var isIncome: Bool { transaction.amount > 0 }

    init(transaction: Transaction, allAccounts: [Account], onSave: @escaping (Decimal, Date, String?, UUID) -> Void) {
        self.transaction = transaction
        self.allAccounts = allAccounts
        self.onSave      = onSave
        _amountText        = State(initialValue: "\(Swift.abs(transaction.amount))")
        _date              = State(initialValue: transaction.date)
        _notes             = State(initialValue: transaction.notes ?? "")
        _selectedAccountId = State(initialValue: transaction.accountId)
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private var isValid: Bool { parsedAmount != nil && parsedAmount! > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Montant") {
                    HStack(spacing: 6) {
                        Text(isIncome ? "+" : "−")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isIncome ? .green : .orange)
                            .frame(width: 16)
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                    }
                }

                if allAccounts.count > 1 {
                    Section("Compte") {
                        Picker("Compte", selection: $selectedAccountId) {
                            ForEach(allAccounts) { acc in
                                Label(acc.name, systemImage: acc.icon).tag(acc.id)
                            }
                        }
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "fr_CA"))
                        .labelsHidden()
                }

                Section("Notes") {
                    TextField("Facultatif", text: $notes, axis: .vertical)
                        .lineLimit(3)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let raw = parsedAmount else { return }
                        let signed = isIncome ? raw : -raw
                        onSave(signed, date, notes.isEmpty ? nil : notes, selectedAccountId)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear { amountFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
                    transactions: [],
                    dailyBalances: []
                )
            )
        }
        .modelContainer(for: Category.self, inMemory: true)
}
