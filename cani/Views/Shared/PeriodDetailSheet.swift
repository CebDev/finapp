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
    var carryForwardBalance: Bool = true
    var tightThreshold:      Decimal = 500

    @Query(sort: \Category.sortOrder)        private var allCategories:   [Category]
    @Query                                   private var allTransactions: [Transaction]
    @Query                                   private var allAccounts:     [Account]
    @Query(sort: \RecurringTransaction.name) private var allRecurring:    [RecurringTransaction]
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    // MARK: - State

    /// Transaction planifiée tappée → menu d'actions
    @State private var tappedPlannedTx:      Transaction?  = nil
    @State private var showingPlannedMenu:   Bool          = false
    /// Transaction payée tappée → menu modifier/supprimer
    @State private var tappedPaidTx:         Transaction?  = nil
    @State private var showingPaidMenu:      Bool          = false
    /// Sheets
    @State private var editingRealTx:        Transaction?  = nil
    @State private var markingAsPaidTx:      Transaction?  = nil
    @State private var editingRecurring:     RecurringTransaction? = nil
    @State private var editingOccurrenceTx:  Transaction?  = nil

    // MARK: - Computed

    /// Transactions de la période triées par date.
    private var sortedTransactions: [Transaction] {
        period.transactions.sorted { $0.date < $1.date }
    }

    private var totalIncome: Decimal {
        period.transactions
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalExpenses: Decimal {
        period.transactions
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + abs($1.amount) }
    }

    private var isolatedProjectedBalance: Decimal { totalIncome - totalExpenses }

    private var displayedProjectedBalance: Decimal {
        carryForwardBalance ? period.projectedBalance : isolatedProjectedBalance
    }

    private var budgetAccountIds: Set<UUID> {
        Set(allAccounts.filter(\.includeInBudget).map(\.id))
    }

    /// Récurrence parente d'une Transaction, si elle existe.
    private func recurring(for tx: Transaction) -> RecurringTransaction? {
        guard let rid = tx.recurringTransactionId else { return nil }
        return allRecurring.first { $0.id == rid }
    }

    /// Nom d'affichage d'une transaction.
    private func label(for tx: Transaction) -> String {
        if !tx.name.isEmpty { return tx.name }
        if let notes = tx.notes, !notes.isEmpty { return notes }
        if let cat = tx.categoryId.flatMap({ id in allCategories.first { $0.id == id } }) { return cat.name }
        return tx.amount > 0 ? "Revenu" : "Dépense"
    }

    /// État d'une transaction planifiée dans la période courante.
    private enum PlannedState {
        case overdue   // date ≤ aujourd'hui, non payée
        case upcoming  // date > aujourd'hui, non payée
        case future    // période future (pas de distinction)
    }

    private func plannedState(for tx: Transaction) -> PlannedState {
        guard period.isCurrentPeriod else { return .future }
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.startOfDay(for: tx.date) <= today ? .overdue : .upcoming
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    if !period.transactions.isEmpty {
                        PeriodProgressChart(
                            period:           period,
                            carryForwardBalance: carryForwardBalance,
                            tightThreshold:   tightThreshold,
                            budgetAccountIds: budgetAccountIds
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
                        sectionLabel(period.isCurrentPeriod ? "Période en cours" : "Transactions")
                        ForEach(sortedTransactions) { tx in
                            transactionRow(tx)
                        }
                    }

                    Spacer(minLength: 110)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle(dateRangeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            // Menu transaction planifiée
            .confirmationDialog(
                tappedPlannedTx.map { label(for: $0) } ?? "",
                isPresented: $showingPlannedMenu,
                titleVisibility: .visible
            ) {
                Button("Payer") {
                    markingAsPaidTx  = tappedPlannedTx
                    tappedPlannedTx  = nil
                }
                Button("Modifier cette occurrence") {
                    editingOccurrenceTx = tappedPlannedTx
                    tappedPlannedTx     = nil
                }
                if let tx = tappedPlannedTx,
                   let rt = recurring(for: tx) {
                    Button("Modifier toutes les occurrences à venir") {
                        editingRecurring = rt
                        tappedPlannedTx  = nil
                    }
                }
                Button("Supprimer cette occurrence", role: .destructive) {
                    if let tx = tappedPlannedTx { deletePlannedTx(tx) }
                    tappedPlannedTx = nil
                }
                Button("Annuler", role: .cancel) { tappedPlannedTx = nil }
            }
            // Menu transaction payée
            .confirmationDialog(
                tappedPaidTx.map { label(for: $0) } ?? "",
                isPresented: $showingPaidMenu,
                titleVisibility: .visible
            ) {
                Button("Modifier") {
                    editingRealTx = tappedPaidTx
                    tappedPaidTx  = nil
                }
                Button("Supprimer", role: .destructive) {
                    if let tx = tappedPaidTx { deleteRealTx(tx) }
                    tappedPaidTx = nil
                }
                Button("Annuler", role: .cancel) { tappedPaidTx = nil }
            }
            .sheet(item: $markingAsPaidTx) { tx in
                if let rt = recurring(for: tx) {
                    // Récurrence : MarkAsPaidSheet gère le montant réel + génération suivante
                    MarkAsPaidSheet(transaction: rt, occurrenceDate: tx.date)
                } else {
                    // Transaction ponctuelle planifiée : on marque isPaid directement
                    Color.clear.onAppear {
                        tx.isPaid = true
                        if let account = allAccounts.first(where: { $0.id == tx.accountId }) {
                            account.currentBalance += tx.amount
                        }
                    }
                }
            }
            .sheet(item: $editingRecurring) { rt in
                AddTransactionView(editingRecurring: rt)
            }
            .sheet(item: $editingOccurrenceTx) { tx in
                if let rt = recurring(for: tx) {
                    AddTransactionView(
                        editingOccurrenceRecurring: rt,
                        editingOccurrenceDate:      tx.date
                    )
                }
            }
            .sheet(item: $editingRealTx) { tx in
                RealTransactionEditSheet(
                    transaction: tx,
                    allAccounts: allAccounts
                ) { newAmount, newDate, newNotes, newAccountId in
                    updateRealTx(tx, newSignedAmount: newAmount, newDate: newDate, newNotes: newNotes, newAccountId: newAccountId)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Row

    @ViewBuilder
    private func transactionRow(_ tx: Transaction) -> some View {
        if tx.isPaid {
            paidRow(tx)
        } else {
            plannedRow(tx)
        }
    }

    private func paidRow(_ tx: Transaction) -> some View {
        let isIncome = tx.amount > 0
        let cat      = tx.categoryId.flatMap { id in allCategories.first { $0.id == id } }
        let logo     = recurring(for: tx)?.logo ?? ""

        return HStack(spacing: 12) {
            if tx.isTransfer {
                CategoryIconBadge(icon: "arrow.left.arrow.right", color: "#5856D6", size: 36)
            } else if !logo.isEmpty {
                SubscriptionLogoImage(logo: logo, size: 38)
            } else if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 36)
            } else {
                CategoryIconBadge(
                    icon:  isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                    color: isIncome ? "#34C759" : "#FF9500",
                    size:  36
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label(for: tx))
                    .font(.body).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(tx.date))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary.opacity(0.4))
                    Text("Payée")
                        .font(.caption).foregroundStyle(.secondary.opacity(0.7))
                }
            }
            Spacer()
            Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(tx.amount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tx.isTransfer ? Color.indigo : (isIncome ? Color.green : Color.orange))
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(Color(.systemBackground))
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            tappedPaidTx     = tx
            showingPaidMenu  = true
        }
    }

    private func plannedRow(_ tx: Transaction) -> some View {
        let isIncome  = tx.amount > 0
        let cat       = tx.categoryId.flatMap { id in allCategories.first { $0.id == id } }
        let rt        = recurring(for: tx)
        let state     = plannedState(for: tx)
        let isOverdue = state == .overdue
        let logo      = rt?.logo ?? ""

        return HStack(spacing: 12) {
            if !logo.isEmpty {
                SubscriptionLogoImage(logo: logo, size: 36)
            } else if tx.isTransfer {
                CategoryIconBadge(icon: "arrow.left.arrow.right", color: "#5856D6", size: 36)
            } else if let cat {
                CategoryIconBadge(icon: cat.icon, color: cat.color, size: 36)
            } else {
                CategoryIconBadge(icon: "square.dashed", color: "#98989D", size: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label(for: tx))
                    .font(.body).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(shortDate(tx.date))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if let rt {
                        Text("·").font(.caption).foregroundStyle(.secondary.opacity(0.4))
                        Text(rt.frequency.labelFR)
                            .font(.caption).foregroundStyle(.secondary.opacity(0.7))
                    }
                    if isOverdue {
                        Text("EN RETARD")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if tx.isCustomized {
                        Text("· modifiée")
                            .font(.caption.weight(.medium)).foregroundStyle(.indigo)
                    }
                }
            }
            Spacer()
            Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(tx.amount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tx.isTransfer ? Color.indigo : (isIncome ? Color.green : Color.orange))
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(Color(.systemBackground))
        .overlay(Divider().padding(.leading, 68), alignment: .bottom)
        .opacity(state == .upcoming ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            tappedPlannedTx   = tx
            showingPlannedMenu = true
        }
    }

    // MARK: - Actions

    private func deletePlannedTx(_ tx: Transaction) {
        if let rt = recurring(for: tx) {
            RecurringTransactionService.generateNextOccurrenceIfNeeded(
                for: rt,
                existingTransactions: allTransactions,
                context: context
            )
            if rt.isTransfer {
                deleteTransferPartner(of: tx)
            }
        }
        context.delete(tx)
    }

    private func deleteRealTx(_ tx: Transaction) {
        if tx.isPaid, let account = allAccounts.first(where: { $0.id == tx.accountId }) {
            account.currentBalance -= tx.amount
        }
        if tx.isTransfer, let rid = tx.recurringTransactionId {
            let cal   = Calendar.current
            let txDay = cal.startOfDay(for: tx.date)
            if let partner = allTransactions.first(where: {
                $0.recurringTransactionId == rid &&
                $0.id != tx.id &&
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: txDay)
            }) {
                if partner.isPaid, let acc = allAccounts.first(where: { $0.id == partner.accountId }) {
                    acc.currentBalance -= partner.amount
                }
                context.delete(partner)
            }
        }
        context.delete(tx)
    }

    /// Supprime la transaction partenaire d'un transfert (l'autre côté de la même occurrence).
    private func deleteTransferPartner(of tx: Transaction) {
        guard let rid = tx.recurringTransactionId else { return }
        let cal   = Calendar.current
        let txDay = cal.startOfDay(for: tx.date)
        if let partner = allTransactions.first(where: {
            $0.recurringTransactionId == rid &&
            $0.id != tx.id &&
            cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: txDay)
        }) {
            context.delete(partner)
        }
    }

    private func updateRealTx(_ tx: Transaction, newSignedAmount: Decimal, newDate: Date, newNotes: String?, newAccountId: UUID) {
        let delta          = newSignedAmount - tx.amount
        let accountChanged = newAccountId != tx.accountId

        if tx.isPaid {
            if accountChanged {
                allAccounts.first(where: { $0.id == tx.accountId })?.currentBalance -= tx.amount
                allAccounts.first(where: { $0.id == newAccountId })?.currentBalance += newSignedAmount
            } else {
                allAccounts.first(where: { $0.id == tx.accountId })?.currentBalance += delta
            }
        }
        tx.amount    = newSignedAmount
        tx.date      = newDate
        tx.notes     = newNotes
        tx.accountId = newAccountId
    }

    // MARK: - Subviews

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
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(period.delta >= 0 ? Color.green : Color.orange)
            } else {
                Text("Vue isolée").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tightBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.subheadline)
            Text("Période serrée — solde bas prévu").font(.subheadline.weight(.medium))
        }
        .foregroundStyle(amberColor)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(amberColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 36)).foregroundStyle(.secondary.opacity(0.5))
            Text("Aucune transaction planifiée")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Text("Revenus").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("+" + CurrencyFormatter.shared.format(totalIncome))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                }
                HStack {
                    Text("Dépenses").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("−" + CurrencyFormatter.shared.format(totalExpenses))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                }
                Divider()
                HStack {
                    Text("Solde projeté").font(.body.weight(.semibold))
                    Spacer()
                    Text(CurrencyFormatter.shared.format(displayedProjectedBalance))
                        .font(.body.weight(.bold))
                        .foregroundStyle(period.isTight ? amberColor : Color.indigo)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
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
        Self.dayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private var dateRangeLabel: String {
        "\(shortDate(period.startDate)) — \(shortDate(period.endDate))"
    }

    private var amberColor: Color { Color(red: 1.0, green: 0.7, blue: 0.0) }
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
                            .keyboardType(.decimalPad).focused($amountFocused)
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
                        .environment(\.locale, Locale(identifier: "fr_CA")).labelsHidden()
                }
                Section("Notes") {
                    TextField("Facultatif", text: $notes, axis: .vertical)
                        .lineLimit(3).autocorrectionDisabled()
                }
            }
            .navigationTitle("Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let raw = parsedAmount else { return }
                        onSave(isIncome ? raw : -raw, date, notes.isEmpty ? nil : notes, selectedAccountId)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear { amountFocused = true }
        }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
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
                    endDate:   Calendar.current.date(byAdding: .day, value:  6, to: .now)!,
                    projectedBalance: 420,
                    previousBalance:  1_990,
                    delta:            -1_570,
                    isTight:          true,
                    isCurrentPeriod:  true,
                    transactions:     [],
                    dailyBalances:    []
                )
            )
        }
        .modelContainer(for: Category.self, inMemory: true)
}