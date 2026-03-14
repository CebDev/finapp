//
//  ProfileView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI
import SwiftData

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(\.modelContext) private var context

    @Query private var accounts:              [Account]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var transactions:          [Transaction]
    @Query private var goals:                 [Goal]

    @State private var showDangerDialog = false
    @State private var showErasureSheet = false
    @State private var confirmText      = ""
    @State private var isDeleting       = false
    @State private var showSuccessToast = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    identityCard
                    statsSection
                    appInfoSection
                    dangerSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            if showSuccessToast {
                successToast
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showSuccessToast)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Effacer toutes les données",
            isPresented: $showDangerDialog,
            titleVisibility: .visible
        ) {
            Button("Continuer", role: .destructive) {
                showErasureSheet = true
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous vos comptes, transactions, récurrences, objectifs et simulations seront supprimés. Cette action ne peut pas être annulée.")
        }
        .sheet(isPresented: $showErasureSheet, onDismiss: { confirmText = "" }) {
            ErasureConfirmSheet(
                confirmText: $confirmText,
                isDeleting:  $isDeleting,
                onConfirm:   performReset
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Identity card

    private var identityCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.25, blue: 0.90),
                                Color(red: 0.52, green: 0.18, blue: 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint:   .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Text("C")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(
                color: Color(red: 0.30, green: 0.25, blue: 0.90).opacity(0.35),
                radius: 10, x: 0, y: 4
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("CanI")
                    .font(.title2.weight(.bold))
                Text("Projection financière")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Stats section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Vos données")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard(value: accounts.count,              label: "Comptes",      icon: "creditcard.fill",              color: .indigo)
                statCard(value: recurringTransactions.count, label: "Récurrences",  icon: "repeat",                       color: Color(red: 0.52, green: 0.18, blue: 0.82))
                statCard(value: transactions.count,          label: "Transactions", icon: "list.bullet.rectangle.fill",   color: Color(red: 0.30, green: 0.25, blue: 0.90))
                statCard(value: goals.count,                 label: "Objectifs",    icon: "target",                       color: .teal)
            }
        }
    }

    @ViewBuilder
    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - App info

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Application")

            HStack {
                Text("Version")
                Spacer()
                Text("v\(appVersion)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Zone de danger")

            VStack(spacing: 0) {
                Button {
                    showDangerDialog = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(amberColor.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "trash.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(amberColor)
                        }
                        Text("Effacer toutes mes données")
                            .foregroundStyle(amberColor)
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Text("Supprime définitivement tous vos comptes, transactions, récurrences, objectifs et simulations. Les catégories et préférences seront réinitialisées.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Success toast

    private var successToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Données effacées — nouveau départ !")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(amberColor)
                .shadow(color: amberColor.opacity(0.35), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var amberColor: Color {
        Color(red: 1.0, green: 0.62, blue: 0.0)
    }

    // MARK: - Reset

    @MainActor
    private func performReset() {
        guard !isDeleting else { return }
        isDeleting = true

        deleteAll(Account.self)
        deleteAll(RecurringTransaction.self)
        deleteAll(Transaction.self)
        deleteAll(TransactionOverride.self)
        deleteAll(Goal.self)
        deleteAll(Simulation.self)
        deleteAll(SimulationTransaction.self)
        deleteAll(Category.self)
        deleteAll(UserSettings.self)

        // Persistance locale — SwiftData propage les suppressions vers CloudKit automatiquement
        try? context.save()

        // Réinitialisation des données essentielles
        CategoryService.seedIfNeeded(context: context)
        UserSettings.seedIfNeeded(context: context)

        isDeleting         = false
        showErasureSheet   = false
        confirmText        = ""

        withAnimation { showSuccessToast = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { withAnimation { showSuccessToast = false } }
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        items.forEach { context.delete($0) }
    }
}

// MARK: - ErasureConfirmSheet

private struct ErasureConfirmSheet: View {
    @Binding var confirmText: String
    @Binding var isDeleting:  Bool
    let onConfirm:            () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private let keyword = "Effacer"

    private var isValid: Bool {
        confirmText.trimmingCharacters(in: .whitespaces).lowercased() == keyword.lowercased()
    }

    var body: some View {
        VStack(spacing: 28) {
            // Warning icon + title
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(amberColor.opacity(0.12))
                        .frame(width: 68, height: 68)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(amberColor)
                }

                VStack(spacing: 6) {
                    Text("Dernière confirmation")
                        .font(.title3.weight(.bold))
                    Text("Tapez \(Text("**\(keyword)**")) pour confirmer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // TextField
            VStack(spacing: 8) {
                TextField("", text: $confirmText)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        isValid ? amberColor.opacity(0.5) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: isValid)

                if !confirmText.isEmpty && !isValid {
                    Text("Tapez exactement « \(keyword) »")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Actions
            VStack(spacing: 10) {
                Button {
                    guard isValid, !isDeleting else { return }
                    fieldFocused = false
                    onConfirm()
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Confirmer la suppression")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isValid ? amberColor : Color.secondary.opacity(0.20))
                    )
                    .animation(.easeInOut(duration: 0.2), value: isValid)
                }
                .disabled(!isValid || isDeleting)

                Button("Annuler") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(isDeleting)
            }
        }
        .padding(24)
        .onAppear { fieldFocused = true }
    }

    private var amberColor: Color {
        Color(red: 1.0, green: 0.62, blue: 0.0)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileView()
            .modelContainer(
                for: [Account.self, RecurringTransaction.self, Transaction.self, Goal.self],
                inMemory: true
            )
    }
}
