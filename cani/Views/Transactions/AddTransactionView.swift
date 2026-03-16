//
//  AddTransactionView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

// MARK: - Color hex (local)

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

// MARK: - TransactionType

private enum TransactionType: Int, CaseIterable {
    case expense  = 0
    case income   = 1
    case transfer = 2

    var label: String {
        switch self {
        case .expense:  return "Dépense"
        case .income:   return "Revenu"
        case .transfer: return "Transfert"
        }
    }
}

// MARK: - EndMode

private enum EndMode: String, CaseIterable {
    case never      = "Sans fin"
    case onDate     = "Date de fin"
    case afterCount = "Nombre d'occurrences"
}

// MARK: - AddTransactionView

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    /// Non-nil → mode édition d'une RecurringTransaction existante.
    var editingRecurring: RecurringTransaction? = nil
    /// Non-nil → mode édition d'une occurrence unique.
    var editingOccurrenceRecurring: RecurringTransaction? = nil
    /// Date de l'occurrence à modifier.
    var editingOccurrenceDate: Date? = nil
    /// Non-nil → compte pré-sélectionné à l'ouverture.
    var defaultAccountId: UUID? = nil
    /// true → le toggle "Transaction récurrente" est pré-coché.
    var defaultRecurring: Bool = false
    /// true → le toggle "Abonnement" est pré-coché.
    var defaultSubscription: Bool = false

    @Query(sort: \Account.name)       private var accounts:        [Account]
    @Query(sort: \Category.sortOrder) private var allCategories:   [Category]
    @Query                            private var allTransactions:  [Transaction]

    // MARK: - État formulaire
    @State private var transactionType:              TransactionType = .expense
    @State private var name:                         String          = ""
    @State private var amountText:                   String          = ""
    @State private var selectedAccountId:            UUID?           = nil
    @State private var selectedDestinationAccountId: UUID?           = nil
    @State private var selectedCategoryId:           UUID?           = nil
    @State private var date:                         Date            = Date()
    @State private var isRecurring:                  Bool            = false

    // MARK: - État récurrence
    @State private var frequency:          Frequency = .monthly
    @State private var dayOfWeek:          Int       = 1
    @State private var dayOfMonth:         Int       = 1
    @State private var endMode:            EndMode   = .never
    @State private var endDate:            Date      = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var countOfOccurrences: Int       = 4
    @State private var isSubscription:     Bool      = false
    @State private var selectedLogo:       String    = ""

    @State private var showingDeleteConfirm = false

    private var isEditing:           Bool { editingRecurring != nil }
    private var isEditingOccurrence: Bool { editingOccurrenceRecurring != nil }

    private var selectedCategory: Category? {
        guard let id = selectedCategoryId else { return nil }
        return allCategories.first { $0.id == id }
    }

    private var destinationAccounts: [Account] {
        accounts.filter { $0.id != selectedAccountId }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                detailsSection
                if !isEditingOccurrence {
                    recurringSection
                }
            }
            .navigationTitle(
                isEditing           ? "Modifier la récurrence" :
                isEditingOccurrence ? "Modifier cette occurrence" :
                "Nouvelle transaction"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(!isFormValid)
                }
                if isEditing || isEditingOccurrence {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                deleteConfirmTitle,
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if isEditing { deleteAll() }
                    else if isEditingOccurrence { deleteOccurrence() }
                }
                Button("Annuler", role: .cancel) { }
            } message: {
                Text(deleteConfirmMessage)
            }
            .onAppear { prefillIfEditing() }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $transactionType) {
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .onChange(of: transactionType) { _, _ in
                if transactionType != .transfer {
                    selectedDestinationAccountId = nil
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Détails") {
            TextField("Nom", text: $name)
                .autocorrectionDisabled()

            HStack(spacing: 6) {
                amountSignView
                TextField("0,00", text: $amountText)
                    .keyboardType(.decimalPad)
                Spacer()
                Text("$")
                    .foregroundStyle(.secondary)
            }

            if accounts.isEmpty {
                Text("Aucun compte — créez-en un d'abord")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Picker(transactionType == .transfer ? "Compte source" : "Compte", selection: $selectedAccountId) {
                    Text("Choisir…").tag(Optional<UUID>.none)
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.icon)
                            .tag(Optional(account.id))
                    }
                }

                if transactionType == .transfer {
                    Picker("Compte destination", selection: $selectedDestinationAccountId) {
                        Text("Choisir…").tag(Optional<UUID>.none)
                        ForEach(destinationAccounts) { account in
                            Label(account.name, systemImage: account.icon)
                                .tag(Optional(account.id))
                        }
                    }
                }
            }

            NavigationLink {
                CategoryPickerView(categories: allCategories, selectedId: $selectedCategoryId)
            } label: {
                HStack {
                    Text("Catégorie")
                    Spacer()
                    if let cat = selectedCategory {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                            Text(cat.name)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Aucune")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DatePicker("Date", selection: $date, displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "fr_CA"))
        }
    }

    @ViewBuilder
    private var amountSignView: some View {
        switch transactionType {
        case .expense:
            Text("−")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 14)
        case .income:
            Text("+")
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 14)
        case .transfer:
            Image(systemName: "arrow.left.arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 14)
        }
    }

    private var recurringSection: some View {
        Section {
            Toggle("🔁 Transaction récurrente", isOn: $isRecurring)
                .tint(.indigo)
                .disabled(isEditing)

            if isRecurring {
                Picker("Fréquence", selection: $frequency) {
                    ForEach(Frequency.allCases, id: \.self) { freq in
                        Text(freq.labelFR).tag(freq)
                    }
                }

                if frequency == .biweekly {
                    Picker("Jour de la semaine", selection: $dayOfWeek) {
                        ForEach(weekdayOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                }

                if frequency == .monthly {
                    Picker("Jour du mois", selection: $dayOfMonth) {
                        ForEach(1...31, id: \.self) { d in
                            Text("\(d)").tag(d)
                        }
                    }
                }

                if transactionType != .transfer {
                    Toggle("Abonnement", isOn: $isSubscription)
                        .tint(.indigo)
                        .onChange(of: isSubscription) { _, on in
                            if !on { selectedLogo = "" }
                        }

                    if isSubscription {
                        logoPickerRow
                    }
                }

                Picker("Fin", selection: $endMode) {
                    ForEach(EndMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if endMode == .onDate {
                    DatePicker(
                        "Date de fin",
                        selection: $endDate,
                        in: minEndDate...,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_CA"))
                }

                if endMode == .afterCount {
                    Stepper("^[\(countOfOccurrences) occurrence](inflect: true)", value: $countOfOccurrences, in: 1...999)
                }
            }
        }
    }

    // MARK: - Logo picker

    private var logoPickerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Icône")
                    .foregroundStyle(.primary)
                Spacer()
                if selectedLogo.isEmpty {
                    Text("Aucune")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    SubscriptionLogoImage(logo: selectedLogo, size: 28)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        selectedLogo = ""
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .frame(width: 48, height: 48)
                            Image(systemName: "slash.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedLogo.isEmpty ? Color.indigo : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(allSubscriptionLogos, id: \.self) { logo in
                        Button {
                            selectedLogo = logo
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 48, height: 48)
                                SubscriptionLogoImage(logo: logo, size: 36)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedLogo == logo ? Color.indigo : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var parsedAmount: Decimal? {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let amount = parsedAmount, amount > 0,
              selectedAccountId != nil else { return false }
        if transactionType == .transfer {
            return selectedDestinationAccountId != nil
                && selectedDestinationAccountId != selectedAccountId
        }
        return true
    }

    private var minEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private var resolvedEndDate: Date? {
        endMode == .onDate ? endDate : nil
    }

    private var resolvedCountOfOccurrences: Int? {
        endMode == .afterCount ? countOfOccurrences : nil
    }

    private let weekdayOptions: [(label: String, value: Int)] = [
        ("Lundi",    1),
        ("Mardi",    2),
        ("Mercredi", 3),
        ("Jeudi",    4),
        ("Vendredi", 5),
        ("Samedi",   6),
        ("Dimanche", 0),
    ]

    // MARK: - Suppression

    private var deleteConfirmTitle: String {
        isEditing ? "Supprimer la récurrence" : "Supprimer cette occurrence"
    }

    private var deleteConfirmMessage: String {
        isEditing
            ? "Toutes les occurrences planifiées de \"\(editingRecurring?.name ?? "")\" seront supprimées."
            : "Uniquement cette occurrence sera supprimée. Les occurrences suivantes ne sont pas affectées."
    }

    private func deleteAll() {
        guard let recurring = editingRecurring else { return }
        RecurringTransactionService.deleteFutureOccurrences(
            for: recurring.id,
            existingTransactions: allTransactions,
            context: context
        )
        context.delete(recurring)
        try? context.save()
        dismiss()
    }

    private func deleteOccurrence() {
        guard let occDate   = editingOccurrenceDate,
              let recurring = editingOccurrenceRecurring else { return }

        let cal  = Calendar.current
        let norm = cal.startOfDay(for: occDate)

        if let tx = allTransactions.first(where: {
            $0.recurringTransactionId == recurring.id &&
            cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: norm)
        }) {
            context.delete(tx)
            // Maintenir la fenêtre glissante
            RecurringTransactionService.generateNextOccurrenceIfNeeded(
                for: recurring,
                existingTransactions: allTransactions,
                context: context
            )
        }

        try? context.save()
        dismiss()
    }

    // MARK: - Sauvegarde

    private func save() {
        guard let rawAmount = parsedAmount, let accountId = selectedAccountId else { return }

        if transactionType == .transfer {
            saveTransfer(rawAmount: rawAmount, sourceAccountId: accountId)
        } else {
            let isIncome     = transactionType == .income
            let signedAmount = isIncome ? rawAmount : -rawAmount
            saveRegular(signedAmount: signedAmount, isIncome: isIncome, accountId: accountId)
        }

        dismiss()
    }

    private func saveRegular(signedAmount: Decimal, isIncome: Bool, accountId: UUID) {

        // MARK: Mode édition récurrence complète
        if isEditing, let existing = editingRecurring {
            existing.name               = name.trimmingCharacters(in: .whitespaces)
            existing.amount             = signedAmount
            existing.isIncome           = isIncome
            existing.frequency          = frequency
            existing.startDate          = date
            existing.endDate            = resolvedEndDate
            existing.countOfOccurrences = resolvedCountOfOccurrences
            existing.dayOfWeek          = frequency == .biweekly ? dayOfWeek : nil
            existing.dayOfMonth         = frequency == .monthly  ? dayOfMonth : nil
            existing.categoryId         = selectedCategoryId
            existing.isSubscription     = isSubscription
            existing.logo               = selectedLogo
            existing.accountId          = accountId
            existing.isTransfer         = false
            existing.transferDestinationAccountId = nil
            // Mettre à jour toutes les occurrences futures non payées
            RecurringTransactionService.updateFutureOccurrences(
                for: existing,
                from: Date(),
                existingTransactions: allTransactions,
                context: context
            )

        // MARK: Mode édition occurrence unique
        } else if isEditingOccurrence,
                  let recurring = editingOccurrenceRecurring,
                  let occDate   = editingOccurrenceDate {
            let cal  = Calendar.current
            let norm = cal.startOfDay(for: occDate)
            if let tx = allTransactions.first(where: {
                $0.recurringTransactionId == recurring.id &&
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: norm)
            }) {
                tx.name         = name.trimmingCharacters(in: .whitespaces)
                tx.amount       = signedAmount
                tx.date         = date
                tx.categoryId   = selectedCategoryId
                tx.isCustomized = true
            }

        // MARK: Nouvelle récurrence
        } else if isRecurring {
            let recurring = RecurringTransaction(
                accountId:          accountId,
                name:               name.trimmingCharacters(in: .whitespaces),
                amount:             signedAmount,
                frequency:          frequency,
                startDate:          date,
                endDate:            resolvedEndDate,
                countOfOccurrences: resolvedCountOfOccurrences,
                dayOfWeek:          frequency == .biweekly ? dayOfWeek : nil,
                dayOfMonth:         frequency == .monthly  ? dayOfMonth : nil,
                isIncome:           isIncome,
                categoryId:         selectedCategoryId,
                isSubscription:     isSubscription,
                logo:               selectedLogo
            )
            context.insert(recurring)
            // Générer toutes les occurrences sur 12 mois
            RecurringTransactionService.generateOccurrences(for: recurring, context: context)
            // Si la date de départ est passée, marquer la première comme payée et ajuster le solde
            if date <= Date() {
                let firstTx = allTransactions
                    .filter { $0.recurringTransactionId == recurring.id }
                    .sorted { $0.date < $1.date }
                    .first
                firstTx?.isPaid = true
                applyBalance(accountId: accountId, signedAmount: signedAmount)
            }

        // MARK: Transaction manuelle
        } else {
            let isPaid = date <= Date()
            let tx = Transaction(
                accountId:  accountId,
                name:       name.trimmingCharacters(in: .whitespaces),
                amount:     signedAmount,
                date:       date,
                categoryId: selectedCategoryId,
                isPaid:     isPaid
            )
            context.insert(tx)
            if isPaid { applyBalance(accountId: accountId, signedAmount: signedAmount) }
        }
    }

    private func saveTransfer(rawAmount: Decimal, sourceAccountId: UUID) {
        guard let destAccountId = selectedDestinationAccountId else { return }
        let transferAmount = rawAmount

        // MARK: Mode édition récurrence complète
        if isEditing, let existing = editingRecurring {
            existing.name                         = name.trimmingCharacters(in: .whitespaces)
            existing.amount                       = transferAmount
            existing.isIncome                     = false
            existing.frequency                    = frequency
            existing.startDate                    = date
            existing.endDate                      = resolvedEndDate
            existing.countOfOccurrences           = resolvedCountOfOccurrences
            existing.dayOfWeek                    = frequency == .biweekly ? dayOfWeek : nil
            existing.dayOfMonth                   = frequency == .monthly  ? dayOfMonth : nil
            existing.categoryId                   = selectedCategoryId
            existing.isSubscription               = false
            existing.accountId                    = sourceAccountId
            existing.isTransfer                   = true
            existing.transferDestinationAccountId = destAccountId
            RecurringTransactionService.updateFutureOccurrences(
                for: existing,
                from: Date(),
                existingTransactions: allTransactions,
                context: context
            )

        // MARK: Mode édition occurrence unique
        } else if isEditingOccurrence,
                  let recurring = editingOccurrenceRecurring,
                  let occDate   = editingOccurrenceDate {
            let cal  = Calendar.current
            let norm = cal.startOfDay(for: occDate)
            let occurrenceTxs = allTransactions.filter {
                $0.recurringTransactionId == recurring.id &&
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: norm)
            }
            // Mettre à jour la transaction source (débit)
            if let sourceTx = occurrenceTxs.first(where: { $0.accountId == recurring.accountId }) {
                sourceTx.name         = name.trimmingCharacters(in: .whitespaces)
                sourceTx.amount       = -transferAmount
                sourceTx.date         = date
                sourceTx.categoryId   = selectedCategoryId
                sourceTx.isCustomized = true
            }
            // Mettre à jour la transaction destination (crédit)
            if let destId = recurring.transferDestinationAccountId,
               let destTx = occurrenceTxs.first(where: { $0.accountId == destId }) {
                destTx.name         = name.trimmingCharacters(in: .whitespaces)
                destTx.amount       = transferAmount
                destTx.date         = date
                destTx.categoryId   = selectedCategoryId
                destTx.isCustomized = true
            }

        // MARK: Nouvelle récurrence transfert
        } else if isRecurring {
            let recurring = RecurringTransaction(
                accountId:                    sourceAccountId,
                name:                         name.trimmingCharacters(in: .whitespaces),
                amount:                       transferAmount,
                frequency:                    frequency,
                startDate:                    date,
                endDate:                      resolvedEndDate,
                countOfOccurrences:           resolvedCountOfOccurrences,
                dayOfWeek:                    frequency == .biweekly ? dayOfWeek : nil,
                dayOfMonth:                   frequency == .monthly  ? dayOfMonth : nil,
                isIncome:                     false,
                categoryId:                   selectedCategoryId,
                isSubscription:               false,
                isTransfer:                   true,
                transferDestinationAccountId: destAccountId
            )
            context.insert(recurring)
            RecurringTransactionService.generateOccurrences(for: recurring, context: context)
            if date <= Date() {
                // Marquer les deux côtés de la première occurrence comme payés
                let cal        = Calendar.current
                let targetDay  = cal.startOfDay(for: date)
                allTransactions
                    .filter {
                        $0.recurringTransactionId == recurring.id &&
                        cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: targetDay)
                    }
                    .forEach { $0.isPaid = true }
                applyBalance(accountId: sourceAccountId, signedAmount: -transferAmount)
                applyBalance(accountId: destAccountId,   signedAmount:  transferAmount)
            }

        // MARK: Transfert manuel
        } else {
            let isPaid = date <= Date()
            let sourceTx = Transaction(
                accountId:                    sourceAccountId,
                name:                         name.trimmingCharacters(in: .whitespaces),
                amount:                       -transferAmount,    // source : argent qui sort
                date:                         date,
                categoryId:                   selectedCategoryId,
                isTransfer:                   true,
                transferDestinationAccountId: destAccountId,
                isPaid:                       isPaid
            )
            let destTx = Transaction(
                accountId:  destAccountId,
                name:       name.trimmingCharacters(in: .whitespaces),
                amount:     transferAmount,                         // destination : argent qui entre
                date:       date,
                categoryId: selectedCategoryId,
                isTransfer: true,
                isPaid:     isPaid
            )
            context.insert(sourceTx)
            context.insert(destTx)
            if isPaid {
                applyBalance(accountId: sourceAccountId, signedAmount: -transferAmount)
                applyBalance(accountId: destAccountId,   signedAmount:  transferAmount)
            }
        }
    }

    private func applyBalance(accountId: UUID, signedAmount: Decimal) {
        if let account = accounts.first(where: { $0.id == accountId }) {
            account.currentBalance += signedAmount
        }
    }

    // MARK: - Pré-remplissage

    private func prefillIfEditing() {
        if let tx = editingRecurring {
            if tx.isTransfer {
                transactionType              = .transfer
                selectedDestinationAccountId = tx.transferDestinationAccountId
            } else {
                transactionType = tx.isIncome ? .income : .expense
            }
            name               = tx.name
            amountText         = "\(abs(tx.amount))"
            selectedAccountId  = tx.accountId
            selectedCategoryId = tx.categoryId
            date               = tx.startDate
            isRecurring        = true
            frequency          = tx.frequency
            dayOfWeek          = tx.dayOfWeek  ?? 1
            dayOfMonth         = tx.dayOfMonth ?? 1
            isSubscription     = tx.isSubscription
            selectedLogo       = tx.logo
            // Pré-remplir le mode de fin
            if let count = tx.countOfOccurrences {
                endMode            = .afterCount
                countOfOccurrences = count
            } else if let end = tx.endDate {
                endMode  = .onDate
                endDate  = end
            } else {
                endMode = .never
            }

        } else if let recurring = editingOccurrenceRecurring {
            if recurring.isTransfer {
                transactionType              = .transfer
                selectedDestinationAccountId = recurring.transferDestinationAccountId
            } else {
                transactionType = recurring.isIncome ? .income : .expense
            }
            name               = recurring.name
            amountText         = "\(abs(recurring.amount))"
            selectedAccountId  = recurring.accountId
            selectedCategoryId = recurring.categoryId
            date               = editingOccurrenceDate ?? Date()
            isRecurring        = false

        } else {
            if let id = defaultAccountId {
                selectedAccountId = id
            } else if accounts.count == 1 {
                selectedAccountId = accounts[0].id
            }
            if defaultRecurring || defaultSubscription { isRecurring = true }
            if defaultSubscription { isSubscription = true }
        }
    }
}

// MARK: - CategoryPickerView

private struct CategoryPickerView: View {
    let categories: [Category]
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss

    private var roots: [Category] {
        categories.filter { !$0.isSubcategory }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func children(of parent: Category) -> [Category] {
        categories.filter { $0.parentId == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Button {
                selectedId = nil
                dismiss()
            } label: {
                HStack {
                    Label("Aucune catégorie", systemImage: "square.dashed")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedId == nil {
                        Image(systemName: "checkmark").foregroundStyle(.indigo)
                    }
                }
            }

            ForEach(roots) { root in
                let kids = children(of: root)
                if kids.isEmpty {
                    categoryRow(root)
                } else {
                    Section {
                        ForEach(kids) { child in
                            categoryRow(child)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: root.icon)
                                .foregroundStyle(Color(hex: root.color) ?? .indigo)
                            Text(root.name)
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle("Catégorie")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func categoryRow(_ category: Category) -> some View {
        Button {
            selectedId = category.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryIconBadge(icon: category.icon, color: category.color, size: 32)
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedId == category.id {
                    Image(systemName: "checkmark").foregroundStyle(.indigo)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddTransactionView()
        .modelContainer(
            for: [Account.self, Category.self, Transaction.self, RecurringTransaction.self],
            inMemory: true
        )
}
