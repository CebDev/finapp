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

// MARK: - AddTransactionView

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    /// Non-nil → mode édition d'une RecurringTransaction existante.
    var editingRecurring: RecurringTransaction? = nil
    /// Non-nil → mode édition d'une occurrence unique (sans modifier la règle récurrente).
    var editingOccurrenceRecurring: RecurringTransaction? = nil
    /// Date de l'occurrence à modifier (utilisée avec editingOccurrenceRecurring).
    var editingOccurrenceDate: Date? = nil
    /// true → le toggle "Transaction récurrente" est pré-coché à l'ouverture.
    var defaultRecurring: Bool = false

    @Query(sort: \Account.name)    private var accounts:       [Account]
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    // MARK: État du formulaire
    @State private var isIncome:           Bool     = false
    @State private var name:               String   = ""
    @State private var amountText:         String   = ""
    @State private var selectedAccountId:  UUID?    = nil
    @State private var selectedCategoryId: UUID?    = nil
    @State private var date:               Date     = Date()
    @State private var isRecurring:        Bool     = false

    // MARK: État récurrence
    @State private var frequency:     Frequency = .monthly
    @State private var dayOfWeek:     Int       = 1   // 1 = Lundi
    @State private var dayOfMonth:    Int       = 1
    @State private var noEndDate:     Bool      = true
    @State private var endDate:       Date      = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var isSubscription: Bool     = false

    private var isEditing: Bool { editingRecurring != nil }
    private var isEditingOccurrence: Bool { editingOccurrenceRecurring != nil }

    private var selectedCategory: Category? {
        guard let id = selectedCategoryId else { return nil }
        return allCategories.first { $0.id == id }
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
                isEditing          ? "Modifier la récurrence" :
                isEditingOccurrence ? "Modifier cette occurrence" :
                "Nouvelle transaction"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isFormValid)
                }
            }
            .onAppear { prefillIfEditing() }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $isIncome) {
                Text("Dépense").tag(false)
                Text("Revenu").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var detailsSection: some View {
        Section("Détails") {
            TextField("Nom", text: $name)
                .autocorrectionDisabled()

            HStack(spacing: 6) {
                Text(isIncome ? "+" : "−")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isIncome ? .green : .orange)
                    .frame(width: 14)
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
                Picker("Compte", selection: $selectedAccountId) {
                    Text("Choisir…").tag(Optional<UUID>.none)
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.icon)
                            .tag(Optional(account.id))
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

                Toggle("Abonnement", isOn: $isSubscription)
                    .tint(.indigo)

                Toggle("Sans date de fin", isOn: $noEndDate)
                    .tint(.indigo)

                if !noEndDate {
                    DatePicker(
                        "Date de fin",
                        selection: $endDate,
                        in: minEndDate...,
                        displayedComponents: .date
                    )
                    .environment(\.locale, Locale(identifier: "fr_CA"))
                }
            }
        }
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedAmount != nil
            && parsedAmount! > 0
            && selectedAccountId != nil
    }

    private var minEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
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

    // MARK: - Sauvegarde

    private func save() {
        guard let rawAmount = parsedAmount, let accountId = selectedAccountId else { return }
        let signedAmount = isIncome ? rawAmount : -rawAmount

        if isEditing, let existing = editingRecurring {
            existing.name          = name.trimmingCharacters(in: .whitespaces)
            existing.amount        = signedAmount
            existing.isIncome      = isIncome
            existing.frequency     = frequency
            existing.startDate     = date
            existing.endDate       = noEndDate ? nil : endDate
            existing.dayOfWeek     = frequency == .biweekly ? dayOfWeek : nil
            existing.dayOfMonth    = frequency == .monthly  ? dayOfMonth : nil
            existing.categoryId    = selectedCategoryId
            existing.isSubscription = isSubscription
            existing.accountId     = accountId

        } else if isEditingOccurrence, let recurring = editingOccurrenceRecurring {
            let isPast = date <= Date()
            let tx = Transaction(
                accountId:              accountId,
                recurringTransactionId: recurring.id,
                amount:                 signedAmount,
                date:                   date,
                isPast:                 isPast,
                isConfirmed:            isPast,
                categoryId:             selectedCategoryId
            )
            context.insert(tx)

        } else if isRecurring {
            let recurring = RecurringTransaction(
                accountId:      accountId,
                name:           name.trimmingCharacters(in: .whitespaces),
                amount:         signedAmount,
                frequency:      frequency,
                startDate:      date,
                endDate:        noEndDate ? nil : endDate,
                dayOfWeek:      frequency == .biweekly ? dayOfWeek : nil,
                dayOfMonth:     frequency == .monthly  ? dayOfMonth : nil,
                isIncome:       isIncome,
                categoryId:     selectedCategoryId,
                isSubscription: isSubscription
            )
            context.insert(recurring)

            // Première occurrence si startDate <= maintenant
            if date <= Date() {
                let tx = Transaction(
                    accountId:              accountId,
                    recurringTransactionId: recurring.id,
                    amount:                 signedAmount,
                    date:                   date,
                    isPast:                 true,
                    isConfirmed:            true,
                    categoryId:             selectedCategoryId
                )
                context.insert(tx)
            }

        } else {
            let isPast = date <= Date()
            let tx = Transaction(
                accountId:   accountId,
                amount:      signedAmount,
                date:        date,
                isPast:      isPast,
                isConfirmed: isPast,
                categoryId:  selectedCategoryId
            )
            context.insert(tx)
        }

        dismiss()
    }

    // MARK: - Pré-remplissage (mode édition)

    private func prefillIfEditing() {
        if let tx = editingRecurring {
            isIncome           = tx.isIncome
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
            noEndDate          = tx.endDate == nil
            if let end = tx.endDate { endDate = end }
        } else if let recurring = editingOccurrenceRecurring {
            isIncome           = recurring.isIncome
            name               = recurring.name
            amountText         = "\(abs(recurring.amount))"
            selectedAccountId  = recurring.accountId
            selectedCategoryId = recurring.categoryId
            date               = editingOccurrenceDate ?? Date()
            isRecurring        = false
        } else {
            // Auto-sélectionner le seul compte s'il n'y en a qu'un
            if accounts.count == 1 { selectedAccountId = accounts[0].id }
            if defaultRecurring { isRecurring = true }
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
            // Option "Aucune"
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

            // Catégories racines + sous-catégories
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
