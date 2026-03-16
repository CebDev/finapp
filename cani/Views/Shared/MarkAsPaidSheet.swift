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
    @Query(sort: \Account.sortOrder) private var accounts:        [Account]
    @Query                           private var allTransactions: [Transaction]

    @State private var amountString:        String  = ""
    @State private var paymentDate:         Date    = Date()
    @State private var selectedAccountId:   UUID?   = nil
    @State private var notes:               String  = ""
    @State private var showingAccountPicker: Bool   = false

    // MARK: - Computed

    private var isIncome:     Bool  { transaction.isIncome }
    private var amountColor:  Color {
        transaction.isTransfer ? .indigo : (isIncome ? .green : .orange)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingAccountPicker = false } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Save

    private func save() {
        let rawString       = amountString
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        let parsed          = Decimal(string: rawString) ?? abs(transaction.amount)
        let cal             = Calendar.current
        let normalizedOcc   = cal.startOfDay(for: occurrenceDate)
        let targetAccountId = selectedAccountId ?? transaction.accountId

        if transaction.isTransfer {
            saveTransfer(parsed: parsed, normalizedOcc: normalizedOcc, targetAccountId: targetAccountId, cal: cal)
        } else {
            let signedAmount: Decimal = isIncome ? parsed : -parsed
            saveRegular(signedAmount: signedAmount, normalizedOcc: normalizedOcc, targetAccountId: targetAccountId, cal: cal)
        }

        // Générer la prochaine occurrence pour maintenir la fenêtre glissante
        RecurringTransactionService.generateNextOccurrenceIfNeeded(
            for: transaction,
            existingTransactions: allTransactions,
            context: context
        )

        try? context.save()
        dismiss()
    }

    private func saveRegular(signedAmount: Decimal, normalizedOcc: Date, targetAccountId: UUID, cal: Calendar) {
        guard let tx = allTransactions.first(where: {
            $0.recurringTransactionId == transaction.id &&
            cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: normalizedOcc)
        }) else { return }

        if tx.isPaid, let prev = accounts.first(where: { $0.id == tx.accountId }) {
            prev.currentBalance -= tx.amount
        }

        tx.isPaid    = true
        tx.amount    = signedAmount
        tx.date      = paymentDate
        tx.accountId = targetAccountId
        tx.notes     = notes.isEmpty ? nil : notes

        if let account = accounts.first(where: { $0.id == targetAccountId }) {
            account.currentBalance += signedAmount
        }
    }

    private func saveTransfer(parsed: Decimal, normalizedOcc: Date, targetAccountId: UUID, cal: Calendar) {
        guard let destAccountId = transaction.transferDestinationAccountId else { return }

        let occurrenceTxs = allTransactions.filter {
            $0.recurringTransactionId == transaction.id &&
            cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: normalizedOcc)
        }

        guard let sourceTx = occurrenceTxs.first(where: { $0.accountId == transaction.accountId }),
              let destTx   = occurrenceTxs.first(where: { $0.accountId == destAccountId })
        else { return }

        // Annuler les effets précédents si déjà payés
        if sourceTx.isPaid, let acc = accounts.first(where: { $0.id == sourceTx.accountId }) {
            acc.currentBalance -= sourceTx.amount
        }
        if destTx.isPaid, let acc = accounts.first(where: { $0.id == destTx.accountId }) {
            acc.currentBalance -= destTx.amount
        }

        // Mettre à jour la transaction source (débit)
        sourceTx.isPaid    = true
        sourceTx.amount    = -parsed
        sourceTx.date      = paymentDate
        sourceTx.accountId = targetAccountId
        sourceTx.notes     = notes.isEmpty ? nil : notes

        // Mettre à jour la transaction destination (crédit)
        destTx.isPaid = true
        destTx.amount = parsed
        destTx.date   = paymentDate

        // Appliquer les soldes
        if let acc = accounts.first(where: { $0.id == targetAccountId }) {
            acc.currentBalance -= parsed
        }
        if let acc = accounts.first(where: { $0.id == destAccountId }) {
            acc.currentBalance += parsed
        }
    }

    // MARK: - Prefill

    private func prefill() {
        let cal           = Calendar.current
        let normalizedOcc = cal.startOfDay(for: occurrenceDate)

        // Pour les transferts, toujours pré-remplir depuis la transaction source
        let tx = transaction.isTransfer
            ? allTransactions.first(where: {
                $0.recurringTransactionId == transaction.id &&
                $0.accountId == transaction.accountId &&
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: normalizedOcc)
              })
            : allTransactions.first(where: {
                $0.recurringTransactionId == transaction.id &&
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: normalizedOcc)
              })

        if let tx {
            amountString      = formatForInput(abs(tx.isPaid ? tx.amount : transaction.amount))
            paymentDate       = tx.isPaid ? tx.date : occurrenceDate
            selectedAccountId = tx.accountId
            notes             = tx.notes ?? ""
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