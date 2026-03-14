//
//  CategoriesView.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import SwiftUI
import SwiftData

// MARK: - Color ↔ Hex helpers

private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        h = h.hasPrefix("#") ? String(h.dropFirst()) : h
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}

// MARK: - Category icon badge

struct CategoryIconBadge: View {
    let icon: String
    let color: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill((Color(hex: color) ?? .indigo).opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(Color(hex: color) ?? .indigo)
        }
    }
}

// MARK: - Available icons for picker

private let pickerIcons: [String] = [
    "house.fill", "car.fill", "cart.fill", "heart.fill", "tv.fill",
    "arrow.down.circle.fill", "book.fill", "chart.pie.fill", "square.grid.2x2.fill",
    "bolt.fill", "wifi", "shield.fill", "fuelpump.fill", "tram.fill",
    "fork.knife", "cup.and.saucer.fill", "pills.fill", "stethoscope",
    "rectangle.stack.fill", "ticket.fill", "figure.run", "airplane",
    "banknote.fill", "briefcase.fill", "graduationcap.fill", "dollarsign.circle.fill",
    "creditcard.fill", "building.columns.fill", "gift.fill", "leaf.fill",
    "gamecontroller.fill", "music.note", "camera.fill", "wrench.fill",
    "tag.fill", "bag.fill", "bicycle", "bus.fill", "flame.fill", "drop.fill",
]

// MARK: - Category form sheet

private enum CategoryFormMode {
    case add(parent: Category)
    case edit(category: Category)
}

private struct CategoryFormSheet: View {
    let mode: CategoryFormMode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: Color

    init(mode: CategoryFormMode) {
        self.mode = mode
        switch mode {
        case .add(let parent):
            _name = State(initialValue: "")
            _selectedIcon = State(initialValue: parent.icon)
            _selectedColor = State(initialValue: Color(hex: parent.color) ?? .indigo)
        case .edit(let cat):
            _name = State(initialValue: cat.name)
            _selectedIcon = State(initialValue: cat.icon)
            _selectedColor = State(initialValue: Color(hex: cat.color) ?? .indigo)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var titleKey: String {
        switch mode {
        case .add: return "categories.sheet.add.title"
        case .edit: return "categories.sheet.edit.title"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Nom
                Section(String(localized: "categories.form.name.label")) {
                    TextField(
                        String(localized: "categories.form.name.placeholder"),
                        text: $name
                    )
                    .autocorrectionDisabled()
                }

                // MARK: Icône
                Section(String(localized: "categories.form.icon.label")) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                        spacing: 10
                    ) {
                        ForEach(pickerIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            selectedIcon == icon
                                                ? selectedColor
                                                : Color(.secondarySystemBackground)
                                        )
                                        .frame(height: 44)
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(
                                            selectedIcon == icon ? .white : selectedColor
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.12), value: selectedIcon)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Couleur
                Section(String(localized: "categories.form.color.label")) {
                    ColorPicker(
                        String(localized: "categories.form.color.label"),
                        selection: $selectedColor,
                        supportsOpacity: false
                    )
                }
            }
            .navigationTitle(LocalizedStringKey(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let hexColor = selectedColor.toHex()

        switch mode {
        case .add(let parent):
            let sub = Category(
                name: trimmed,
                icon: selectedIcon,
                color: hexColor,
                parentId: parent.id,
                isSystem: false,
                sortOrder: 99
            )
            context.insert(sub)
        case .edit(let cat):
            cat.name = trimmed
            cat.icon = selectedIcon
            cat.color = hexColor
        }
        dismiss()
    }
}

// MARK: - Main view

struct CategoriesView: View {
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @Environment(\.modelContext) private var context

    @State private var expandedIds: Set<UUID> = []
    @State private var addingToParent: Category? = nil
    @State private var editingCategory: Category? = nil

    private var rootCategories: [Category] {
        allCategories.filter { !$0.isSubcategory }
    }

    private func subcategories(of parent: Category) -> [Category] {
        allCategories
            .filter { $0.parentId == parent.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            ForEach(rootCategories) { root in
                DisclosureGroup(isExpanded: expandedBinding(for: root.id)) {
                    ForEach(subcategories(of: root)) { sub in
                        subcategoryRow(sub)
                    }

                    // Bouton ajouter une sous-catégorie
                    Button {
                        addingToParent = root
                    } label: {
                        Label("categories.add_subcategory.button", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.indigo)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                } label: {
                    HStack(spacing: 12) {
                        CategoryIconBadge(icon: root.icon, color: root.color, size: 36)
                        Text(verbatim: root.name)
                            .font(.body.weight(.semibold))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("categories.navigation.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addingToParent) { parent in
            CategoryFormSheet(mode: .add(parent: parent))
        }
        .sheet(item: $editingCategory) { cat in
            CategoryFormSheet(mode: .edit(category: cat))
        }
    }

    @ViewBuilder
    private func subcategoryRow(_ sub: Category) -> some View {
        HStack(spacing: 12) {
            CategoryIconBadge(icon: sub.icon, color: sub.color, size: 28)
            Text(verbatim: sub.name)
                .font(.body)
            Spacer()
            if !sub.isSystem {
                Text("categories.subcategory.custom_badge")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.indigo.opacity(0.10))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingCategory = sub
            } label: {
                Label("common.edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !sub.isSystem {
                Button(role: .destructive) {
                    context.delete(sub)
                } label: {
                    Label("common.delete", systemImage: "trash")
                }
            }
        }
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedIds.insert(id) } else { expandedIds.remove(id) }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CategoriesView()
    }
    .modelContainer(for: Category.self, inMemory: true)
}
