//
//  MarkAsPaidSheet.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import SwiftData

struct MarkAsPaidSheet: View {
    let transaction:    RecurringTransaction
    let occurrenceDate: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \Account.createdAt) private var accounts:  [Account]
    @Query                           private var overrides: [TransactionOverride]

    @State private var amountString:        String  = ""
    @State private var paymentDate:         Date    = Date()
    @State private var selectedAccountId:   UUID?   = nil
    @State private var notes:               String  = ""
    @State private var showingAccountPicker: Bool   = false

    // MARK: - Computed

    private var isIncome:     Bool  { transaction.isIncome }
    private var amountColor:  Color { isIncome ? .green : .orange }

    private var existingOverride: TransactionOverride? {
        overrides.first {
            $0.recurringTransactionId == transaction.id &&
            Calendar.current.isDate(
                Calendar.current.startOfDay(for: $0.occurrenceDate),
                inSameDayAs: Calendar.current.startOfDay(for: occurrenceDate)
            )
        }
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroAmount
                    generalSection
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(transaction.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                            .font(.title3)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                confirmButton
            }
            .sheet(isPresented: $showingAccountPicker) {
                accountPickerSheet
            }
            .onAppear {
                prefill()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero amount

    private var heroAmount: some View {
        VStack(spacing: 8) {
            Text("MONTANT PAYÉ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("CAD")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                TextField("0,00", text: $amountString)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(amountColor)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .fixedSize()
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }

    // MARK: - General section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GÉNÉRAL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                // Date de paiement
                HStack {
                    Text("Date de paiement")
                        .font(.body)
                    Spacer()
                    DatePicker("", selection: $paymentDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "fr_CA"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                // Compte
                Button {
                    showingAccountPicker = true
                } label: {
                    HStack {
                        Text("Compte")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 5) {
                            if let account = selectedAccount {
                                Image(systemName: account.icon)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(account.type.accentColor)
                                Text(account.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Aucun")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }

                Divider().padding(.leading, 16)

                // Note
                HStack(alignment: .top, spacing: 8) {
                    Text("Note")
                        .font(.body)
                    Spacer()
                    TextField("Optionnelle", text: $notes, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1...3)
                        .frame(maxWidth: 220)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirmer le paiement")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: - Account picker sheet

    private var accountPickerSheet: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    selectedAccountId = account.id
                    showingAccountPicker = false
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(account.type.accentColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: account.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(account.type.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(CurrencyFormatter.shared.format(account.effectiveBalance))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedAccountId == account.id {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }
                }
            }
            .navigationTitle("Choisir un compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showingAccountPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Save

    private func save() {
        let rawString     = amountString
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        let parsed        = Decimal(string: rawString) ?? abs(transaction.amount)
        let signedAmount: Decimal = isIncome ? parsed : -parsed
        let normalizedOcc = Calendar.current.startOfDay(for: occurrenceDate)

        if let existing = existingOverride {
            // Si déjà payé, annuler l'effet précédent sur le compte d'origine avant d'appliquer le nouveau
            if existing.isPaid {
                let prevAccountId = existing.actualAccountId ?? transaction.accountId
                let prevAmount    = existing.actualAmount ?? transaction.amount
                if let prevAccount = accounts.first(where: { $0.id == prevAccountId }) {
                    prevAccount.currentBalance -= prevAmount
                }
            }
            existing.isPaid          = true
            existing.actualAmount    = signedAmount
            existing.actualAccountId = selectedAccountId
            existing.actualDate      = paymentDate
            existing.notes           = notes.isEmpty ? nil : notes
        } else {
            let override = TransactionOverride(
                recurringTransactionId: transaction.id,
                occurrenceDate:         normalizedOcc
            )
            override.isPaid          = true
            override.actualAmount    = signedAmount
            override.actualAccountId = selectedAccountId
            override.actualDate      = paymentDate
            override.notes           = notes.isEmpty ? nil : notes
            context.insert(override)
        }

        // Appliquer le montant au solde du compte sélectionné
        if let account = accounts.first(where: { $0.id == selectedAccountId }) {
            account.currentBalance += signedAmount
        }

        try? context.save()
        dismiss()
    }

    // MARK: - Prefill

    private func prefill() {
        if let override = existingOverride {
            amountString      = formatForInput(abs(override.actualAmount ?? transaction.amount))
            paymentDate       = override.actualDate ?? occurrenceDate
            selectedAccountId = override.actualAccountId ?? transaction.accountId
            notes             = override.notes ?? ""
        } else {
            amountString      = formatForInput(abs(transaction.amount))
            paymentDate       = occurrenceDate
            selectedAccountId = transaction.accountId
        }
    }

    private func formatForInput(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle          = .decimal
        formatter.locale               = Locale(identifier: "fr_CA")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
