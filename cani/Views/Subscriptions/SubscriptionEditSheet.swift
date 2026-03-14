//
//  SubscriptionEditSheet.swift
//  cani
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Color(hex:) extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - SubscriptionEditSheet

struct SubscriptionEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subscription: Subscription?

    // MARK: - Form state

    @State private var name: String
    @State private var amountText: String
    @State private var frequency: SubscriptionFrequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var dayOfMonth: Int
    @State private var dayOfWeek: Int
    @State private var renewalMonth: Int
    @State private var category: String
    @State private var colorHex: String
    @State private var iconInitials: String
    @State private var notes: String
    @State private var isActive: Bool

    @State private var reminderEnabled: Bool
    @State private var reminderDays: Int

    // MARK: - UI state

    @State private var showingPermissionAlert = false

    // MARK: - Init

    init(subscription: Subscription?) {
        self.subscription = subscription

        let sub = subscription
        let today = Date()
        let cal = Calendar.current

        _name             = State(initialValue: sub?.name ?? "")
        _amountText       = State(initialValue: sub != nil ? "\(sub!.amount)" : "")
        _frequency        = State(initialValue: sub?.frequency ?? .monthly)
        _startDate        = State(initialValue: sub?.startDate ?? today)
        _hasEndDate       = State(initialValue: sub?.endDate != nil)
        _endDate          = State(initialValue: sub?.endDate ?? cal.date(byAdding: .year, value: 1, to: today) ?? today)
        _dayOfMonth       = State(initialValue: sub?.dayOfMonth ?? cal.component(.day, from: today))
        _dayOfWeek        = State(initialValue: sub?.dayOfWeek ?? cal.component(.weekday, from: today))
        _renewalMonth     = State(initialValue: sub?.renewalMonth ?? cal.component(.month, from: today))
        _category         = State(initialValue: sub?.category ?? "")
        _colorHex         = State(initialValue: sub?.colorHex ?? "#6366F1")
        _iconInitials     = State(initialValue: sub?.iconInitials ?? "")
        _notes            = State(initialValue: sub?.notes ?? "")
        _isActive         = State(initialValue: sub?.isActive ?? true)
        _reminderEnabled  = State(initialValue: sub?.reminderDaysBefore != nil)
        _reminderDays     = State(initialValue: sub?.reminderDaysBefore ?? 1)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                informationsSection
                datePaiementSection
                rappelSection
                notesSection
                if subscription != nil {
                    deleteSection
                }
            }
            .navigationTitle(subscription == nil ? "Nouvel abonnement" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sauvegarder") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Notifications désactivées", isPresented: $showingPermissionAlert) {
                Button("Ouvrir Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {
                    reminderEnabled = false
                }
            } message: {
                Text("CanI a besoin de la permission d'envoyer des notifications. Activez-la dans Réglages.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var informationsSection: some View {
        Section("Informations") {
            TextField("Nom", text: $name)

            HStack {
                Text("CAD $")
                    .foregroundStyle(.secondary)
                TextField("0,00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Fréquence", selection: $frequency) {
                ForEach(SubscriptionFrequency.allCases, id: \.self) { freq in
                    Text(freq.localizedLabel).tag(freq)
                }
            }

            Picker("Catégorie", selection: $category) {
                Text("Divertissement").tag("divertissement")
                Text("Musique").tag("musique")
                Text("Productivité").tag("productivite")
                Text("Santé").tag("sante")
                Text("Stockage").tag("stockage")
                Text("Jeux").tag("jeux")
                Text("Autre").tag("autre")
            }

            HStack {
                Text("Initiales / icône")
                Spacer()
                TextField("AB", text: $iconInitials)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onChange(of: iconInitials) { _, new in
                        if new.count > 3 { iconInitials = String(new.prefix(3)) }
                    }
            }

            ColorPickerRow(selection: $colorHex)

            Toggle("Actif", isOn: $isActive)
        }
    }

    @ViewBuilder
    private var datePaiementSection: some View {
        Section("Date de paiement") {
            switch frequency {
            case .weekly:
                weekdayPicker

            case .biweekly:
                weekdayPicker
                DatePicker("Date de départ", selection: $startDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "fr_CA"))

            case .monthly:
                dayOfMonthPicker(label: "Jour du mois")

            case .quarterly:
                dayOfMonthPicker(label: "Jour du mois")
                DatePicker("Date de départ", selection: $startDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "fr_CA"))

            case .annual:
                monthPicker
                dayOfMonthPicker(label: "Jour du mois")
            }

            if frequency != .biweekly && frequency != .quarterly {
                DatePicker("Début le", selection: $startDate, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "fr_CA"))
            }

            Toggle("Date de fin", isOn: $hasEndDate.animation())
            if hasEndDate {
                DatePicker("Fin le", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "fr_CA"))
            }
        }
    }

    @ViewBuilder
    private var rappelSection: some View {
        Section {
            HStack {
                Label("M'avertir avant le renouvellement", systemImage: "bell")
                Spacer()
                Toggle("", isOn: $reminderEnabled)
                    .labelsHidden()
            }
            .onChange(of: reminderEnabled) { _, newValue in
                guard newValue else { return }
                Task { await handleReminderToggle() }
            }

            if reminderEnabled {
                Picker("Délai", selection: $reminderDays) {
                    Text("1 jour").tag(1)
                    Text("3 jours").tag(3)
                    Text("1 semaine").tag(7)
                    Text("1 mois").tag(30)
                }
                .pickerStyle(.segmented)

                Text(notificationPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if reminderEnabled {
                Text("La notification sera envoyée à 9 h 00 le matin du rappel.")
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes optionnelles", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                Task { await delete() }
            } label: {
                HStack {
                    Spacer()
                    Text("Supprimer l'abonnement")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helper views

    private var weekdayPicker: some View {
        Picker("Jour de la semaine", selection: $dayOfWeek) {
            Text("Dimanche").tag(1)
            Text("Lundi").tag(2)
            Text("Mardi").tag(3)
            Text("Mercredi").tag(4)
            Text("Jeudi").tag(5)
            Text("Vendredi").tag(6)
            Text("Samedi").tag(7)
        }
    }

    private func dayOfMonthPicker(label: String) -> some View {
        Picker(label, selection: $dayOfMonth) {
            ForEach(1...28, id: \.self) { day in
                Text("\(day)").tag(day)
            }
        }
    }

    private var monthPicker: some View {
        Picker("Mois", selection: $renewalMonth) {
            Text("Janvier").tag(1)
            Text("Février").tag(2)
            Text("Mars").tag(3)
            Text("Avril").tag(4)
            Text("Mai").tag(5)
            Text("Juin").tag(6)
            Text("Juillet").tag(7)
            Text("Août").tag(8)
            Text("Septembre").tag(9)
            Text("Octobre").tag(10)
            Text("Novembre").tag(11)
            Text("Décembre").tag(12)
        }
    }

    // MARK: - Notification preview

    private var notificationPreview: String {
        let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "ce service" : name
        let label = NotificationManager.dayLabel(reminderDays)
        return "Renouvellement à venir — \(displayName) sera prélevé \(label)."
    }

    // MARK: - Actions

    private func handleReminderToggle() async {
        let status = await NotificationManager.shared.permissionStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let granted = await NotificationManager.shared.requestPermission()
            if !granted { reminderEnabled = false }
        case .denied:
            reminderEnabled = false
            showingPermissionAlert = true
        @unknown default:
            reminderEnabled = false
        }
    }

    private func save() async {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        let parsedAmount = Decimal(string: cleaned) ?? .zero

        let initials = iconInitials.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(name.prefix(2)).uppercased()
            : iconInitials

        if let existing = subscription {
            existing.name = name
            existing.amount = parsedAmount
            existing.frequency = frequency
            existing.startDate = startDate
            existing.endDate = hasEndDate ? endDate : nil
            existing.dayOfMonth = dayOfMonth
            existing.dayOfWeek = [.weekly, .biweekly].contains(frequency) ? dayOfWeek : nil
            existing.renewalMonth = frequency == .annual ? renewalMonth : nil
            existing.category = category
            existing.colorHex = colorHex
            existing.iconInitials = initials
            existing.notes = notes.isEmpty ? nil : notes
            existing.isActive = isActive
            existing.reminderDaysBefore = reminderEnabled ? reminderDays : nil

            await NotificationManager.shared.scheduleNotifications(for: existing)
        } else {
            let newSub = Subscription(
                name: name,
                amount: parsedAmount,
                frequency: frequency,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                dayOfMonth: dayOfMonth,
                dayOfWeek: [.weekly, .biweekly].contains(frequency) ? dayOfWeek : nil,
                renewalMonth: frequency == .annual ? renewalMonth : nil,
                category: category,
                colorHex: colorHex,
                iconInitials: initials,
                notes: notes.isEmpty ? nil : notes,
                reminderDaysBefore: reminderEnabled ? reminderDays : nil,
                isActive: isActive
            )
            context.insert(newSub)
            await NotificationManager.shared.scheduleNotifications(for: newSub)
        }

        dismiss()
    }

    private func delete() async {
        guard let existing = subscription else { return }
        await NotificationManager.shared.cancelNotifications(for: existing)
        context.delete(existing)
        dismiss()
    }
}

// MARK: - ColorPickerRow

private struct ColorPickerRow: View {
    @Binding var selection: String

    private let presets: [String] = [
        "#E50914", // Netflix rouge
        "#1DB954", // Spotify vert
        "#FC3C44", // Apple Music
        "#FF9900", // Amazon orange
        "#6366F1", // Indigo
        "#8B5CF6", // Violet
        "#EC4899", // Rose
        "#14B8A6", // Teal
        "#F59E0B", // Amber
        "#6B7280", // Gris
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couleur")
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(selection == hex ? Color.primary : Color.clear, lineWidth: 2.5)
                            )
                            .onTapGesture { selection = hex }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
