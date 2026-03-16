//
//  AccountTransactionsSheet.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import SwiftData

// MARK: - Modèle d'affichage unifié

/// Représente une entrée dans le relevé — toujours une Transaction réelle.
private struct AccountEntry: Identifiable {
    let id:                           UUID
    let date:                         Date
    let amount:                       Decimal
    let categoryId:                   UUID?
    let label:                        String
    let isTransfer:                   Bool
    let transferDestinationAccountId: UUID?
    let accountId:                    UUID
}

// MARK: - Sheet principale

struct AccountTransactionsSheet: View {
    let account:    Account
    let categories: [Category]

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    /// Transactions manuelles passées et confirmées sur ce compte (3 derniers mois).
    @Query private var pastTransactions: [Transaction]

    /// Toutes les occurrences marquées payées — filtrage par compte en mémoire.
    @Query(filter: #Predicate<TransactionOverride> { $0.isPaid == true })
    private var paidOverrides: [TransactionOverride]

    /// Récurrences pour résoudre noms et catégories des overrides payés.
    @Query private var allRecurring: [RecurringTransaction]

    /// Tous les comptes — nécessaire pour reverser les transferts.
    @Query private var allAccounts: [Account]

    @State private var tappedEntry:      AccountEntry? = nil
    @State private var showingEntryMenu: Bool          = false
    @State private var editingEntry:     AccountEntry? = nil

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
                $0.isPaid    == true
            },
            sort: \Transaction.date,
            order: .reverse
        )
    }

    // MARK: - Entrées unifiées

    private var entries: [AccountEntry] {
        var result: [AccountEntry] = []

        for tx in pastTransactions {
            let cat           = tx.categoryId.flatMap { id in categories.first { $0.id == id } }
            // Résoudre le nom de la récurrence liée (transactions validées depuis PeriodDetailSheet)
            let recurringName = tx.recurringTransactionId.flatMap { rid in allRecurring.first { $0.id == rid } }?.name
            let label         = entryLabel(notes: tx.notes, categoryName: cat?.name, isIncome: tx.amount > 0, fallback: recurringName)
            result.append(AccountEntry(
                id:                           tx.id,
                date:                         tx.date,
                amount:                       tx.amount,
                categoryId:                   tx.categoryId,
                label:                        label,
                isTransfer:                   tx.isTransfer,
                transferDestinationAccountId: tx.transferDestinationAccountId,
                accountId:                    tx.accountId
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                tappedEntry?.label ?? "",
                isPresented: $showingEntryMenu,
                titleVisibility: .visible
            ) {
                Button("Modifier") {
                    editingEntry = tappedEntry
                    tappedEntry  = nil
                }
                Button("Supprimer", role: .destructive) {
                    if let entry = tappedEntry { deleteEntry(entry) }
                    tappedEntry = nil
                }
                Button("Annuler", role: .cancel) { tappedEntry = nil }
            }
            .sheet(item: $editingEntry) { entry in
                EditEntrySheet(entry: entry, accounts: allAccounts, categories: categories) { newSignedAmount, newDate, newNotes, newAccountId, newCategoryId in
                    updateEntry(entry, newSignedAmount: newSignedAmount, newDate: newDate, newNotes: newNotes, newAccountId: newAccountId, newCategoryId: newCategoryId)
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
            // Icône : badge catégorie si disponible, sinon flèche directionnelle
            if let cat {
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
                Text(shortDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text((isIncome ? "+" : "−") + CurrencyFormatter.shared.format(abs(entry.amount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? Color.green : Self.amberColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            tappedEntry      = entry
            showingEntryMenu = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteEntry(entry)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    // MARK: - Suppression

    private func deleteEntry(_ entry: AccountEntry) {
        if entry.isTransfer {
            // Transfert : annuler le débit source et le crédit destination
            account.currentBalance += entry.amount
            if let destId = entry.transferDestinationAccountId,
               let destAccount = allAccounts.first(where: { $0.id == destId }) {
                destAccount.currentBalance -= entry.amount
            }
            if let tx = pastTransactions.first(where: { $0.id == entry.id }) {
                context.delete(tx)
            }
        } else {
            // Transaction simple ou occurrence validée
            account.currentBalance -= entry.amount
            if let tx = pastTransactions.first(where: { $0.id == entry.id }) {
                // Si liée à une récurrence, supprimer le marqueur de saut (TransactionOverride)
                // pour que l'occurrence redevienne "planifiée" dans PeriodDetailSheet.
                if let recurId = tx.recurringTransactionId,
                   let skipOverride = paidOverrides.first(where: { $0.recurringTransactionId == recurId && $0.isPaid }) {
                    context.delete(skipOverride)
                }
                context.delete(tx)
            }
        }
    }

    // MARK: - Édition

    private func updateEntry(_ entry: AccountEntry, newSignedAmount: Decimal, newDate: Date, newNotes: String?, newAccountId: UUID, newCategoryId: UUID?) {
        let delta          = newSignedAmount - entry.amount
        let accountChanged = newAccountId != entry.accountId

        if entry.isTransfer {
            // Transfert : ajuster le delta sur source et destination (pas de déplacement de compte)
            account.currentBalance -= delta
            if let destId = entry.transferDestinationAccountId,
               let destAccount = allAccounts.first(where: { $0.id == destId }) {
                destAccount.currentBalance += delta
            }
            if let tx = pastTransactions.first(where: { $0.id == entry.id }) {
                tx.amount     = newSignedAmount
                tx.date       = newDate
                tx.notes      = newNotes
                tx.categoryId = newCategoryId
            }
        } else {
            // Transaction simple ou occurrence validée — supporte le déplacement de compte
            let sourceAccount = allAccounts.first(where: { $0.id == entry.accountId }) ?? account
            if accountChanged, let newAccount = allAccounts.first(where: { $0.id == newAccountId }) {
                sourceAccount.currentBalance -= entry.amount
                newAccount.currentBalance    += newSignedAmount
            } else {
                sourceAccount.currentBalance += delta
            }
            if let tx = pastTransactions.first(where: { $0.id == entry.id }) {
                tx.amount     = newSignedAmount
                tx.date       = newDate
                tx.notes      = newNotes
                tx.accountId  = newAccountId
                tx.categoryId = newCategoryId
            }
        }
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

// MARK: - EditEntrySheet

private struct EditEntrySheet: View {
    let entry:      AccountEntry
    let accounts:   [Account]
    let categories: [Category]
    let onSave:     (Decimal, Date, String?, UUID, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    @State private var amountText:          String
    @State private var date:                Date
    @State private var notes:               String
    @State private var selectedAccountId:   UUID
    @State private var selectedCategoryId:  UUID?

    init(entry: AccountEntry, accounts: [Account], categories: [Category], onSave: @escaping (Decimal, Date, String?, UUID, UUID?) -> Void) {
        self.entry      = entry
        self.accounts   = accounts
        self.categories = categories
        self.onSave     = onSave
        _amountText          = State(initialValue: "\(abs(entry.amount))")
        _date                = State(initialValue: entry.date)
        _notes               = State(initialValue: "")
        _selectedAccountId   = State(initialValue: entry.accountId)
        _selectedCategoryId  = State(initialValue: entry.categoryId)
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private var isIncome: Bool { entry.amount > 0 }

    private var isValid: Bool {
        parsedAmount != nil && parsedAmount! > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Montant") {
                    HStack(spacing: 6) {
                        if entry.isTransfer {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.indigo)
                                .frame(width: 16)
                        } else {
                            Text(isIncome ? "+" : "−")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(isIncome ? .green : .orange)
                                .frame(width: 16)
                        }
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                        Spacer()
                        Text("$")
                            .foregroundStyle(.secondary)
                    }
                }

                if !entry.isTransfer && accounts.count > 1 {
                    Section("Compte") {
                        Picker("Compte", selection: $selectedAccountId) {
                            ForEach(accounts) { acc in
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

                if !entry.isTransfer && !categories.isEmpty {
                    Section("Catégorie") {
                        Picker("Catégorie", selection: $selectedCategoryId) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.icon).tag(UUID?.some(cat.id))
                            }
                        }
                    }
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
                        let signed = entry.isTransfer ? raw : (isIncome ? raw : -raw)
                        onSave(signed, date, notes.isEmpty ? nil : notes, selectedAccountId, selectedCategoryId)
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