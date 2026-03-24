//
//  CategoryService.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation
import SwiftData

enum CategoryService {

    // MARK: - Default categories

    /// Retourne l'ensemble des catégories système (racines + sous-catégories).
    /// Tous les UUIDs sont déterministes : seed idempotent garanti.
    static func defaultCategories() -> [Category] {
        var result: [Category] = []
        var order = 0

        /// Crée un parent + ses enfants avec UUIDs déterministes.
        /// UUID parent : `{ns}-0000-0000-0000-000000000000`
        /// UUID enfant i : `{ns}-{i+1:04X}-0000-0000-000000000000`
        func makeGroup(
            ns: String,         // ex: "00000001"
            name: String,
            icon: String,
            color: String,
            children: [(name: String, icon: String)]
        ) {
            let parentId = UUID(uuidString: "\(ns)-0000-0000-0000-000000000000")!
            result.append(Category(
                id: parentId,
                name: name,
                icon: icon,
                color: color,
                parentId: nil,
                isSystem: true,
                sortOrder: order
            ))
            order += 1

            for (i, child) in children.enumerated() {
                let childId = UUID(uuidString: "\(ns)-\(String(format: "%04X", i + 1))-0000-0000-000000000000")!
                result.append(Category(
                    id: childId,
                    name: child.name,
                    icon: child.icon,
                    color: color,
                    parentId: parentId,
                    isSystem: true,
                    sortOrder: i
                ))
            }
        }

                // MARK: 🛒 Alimentation
        makeGroup(
            ns: "00000001",
            name: "Alimentation",
            icon: "cart.fill",
            color: "#d13030",
            children: [
                (name: "Épicerie",    icon: "cart.fill"),
                (name: "Restaurants", icon: "fork.knife"),
                (name: "Cafés",       icon: "cup.and.saucer.fill"),
            ]
        )

        // MARK: Achat
        makeGroup(
            ns: "00000002",
            name: "Achats",
            icon: "img:shoppingmall",
            color: "#1b79e4",
            children: [
                (name: "Animaux de compagnie",      icon: "img:pet"),
                (name: "Beauté",                    icon: "img:beauty"),
                (name: "Cadeaux, plaisirs",         icon: "img:gift"),
                (name: "Electronique, accessoires", icon: "img:electronics"),
                (name: "Livres, magazines",         icon: "img:book"),
                (name: "Maison, jardin",            icon: "house.fill"),
                (name: "Vêtements et chaussures",   icon: "img:clothes"),
            ]
        )

        // MARK: 🎬 Loisirs
        makeGroup(
            ns: "00000003",
            name: "Loisirs",
            icon: "tv.fill",
            color: "#b55af2",
            children: [
                (name: "Abonnements", icon: "rectangle.stack.fill"),
                (name: "Sorties",     icon: "ticket.fill"),
                (name: "Sport",       icon: "figure.run"),
                (name: "Voyages",     icon: "airplane"),
                (name: "Internet",            icon: "wifi"),
            ]
        )

        // MARK: 🚗 Transport
        makeGroup(
            ns: "00000004",
            name: "Transport",
            icon: "car.fill",
            color: "#656565",
            children: [
                (name: "Essence",            icon: "fuelpump.fill"),
                (name: "Assurance auto",     icon: "car.fill"),
                (name: "Transport en commun",icon: "tram.fill"),
                (name: "Stationnement",      icon: "parkingsign"),
            ]
        )

        // MARK: 💊 Santé
        makeGroup(
            ns: "00000005",
            name: "Santé",
            icon: "heart.fill",
            color: "#7ec528",
            children: [
                (name: "Pharmacie", icon: "pills.fill"),
                (name: "Médecin",   icon: "stethoscope"),
            ]
        )

        // MARK: 🏠 Logement
        makeGroup(
            ns: "00000006",
            name: "Logement",
            icon: "house.fill",
            color: "#ffa332",
            children: [
                (name: "Loyer / Hypothèque", icon: "house.fill"),
                (name: "Électricité",         icon: "bolt.fill"),
                (name: "Assurance habitation",icon: "shield.fill"),
                (name: "Taxes",icon: "dollarsign.circle.fill"),
            ]
        )

        // MARK: 💼 Revenus
        makeGroup(
            ns: "00000007",
            name: "Revenus",
            icon: "arrow.down.circle.fill",
            color: "#c3c60f",
            children: [
                (name: "Salaire",               icon: "banknote.fill"),
                (name: "Freelance",             icon: "briefcase.fill"),
                (name: "Intérêts, dividendes",  icon: "chart.line.uptrend.xyaxis"),
                (name: "Remboursements",        icon: "arrow.uturn.left.circle.fill"),
            ]
        )

        // MARK: 🎓 Éducation
        makeGroup(
            ns: "00000008",
            name: "Éducation",
            icon: "book.fill",
            color: "#0A84FF",
            children: [
                (name: "Prêt étudiant", icon: "graduationcap.fill"),
                (name: "Formations",    icon: "play.rectangle.fill"),
                (name: "Fournitures",   icon: "pencil.and.ruler.fill"),
            ]
        )

        // MARK: 🏦 Finances
        makeGroup(
            ns: "00000009",
            name: "Finances",
            icon: "chart.pie.fill",
            color: "#0aff8d",
            children: [
                (name: "CELI",              icon: "dollarsign.circle.fill"),
                (name: "REER",              icon: "chart.line.uptrend.xyaxis"),
                (name: "Remboursement dette",icon: "creditcard.fill"),
                (name: "Épargne",           icon: "building.columns.fill"),
            ]
        )

        // MARK: 📦 Autre
        result.append(Category(
            id: UUID(uuidString: "0000000A-0000-0000-0000-000000000000")!,
            name: "Autre",
            icon: "square.grid.2x2.fill",
            color: "#98989D",
            parentId: nil,
            isSystem: true,
            sortOrder: order
        ))

        return result
    }

    // MARK: - Seed

    /// Insère les catégories par défaut si elles ne sont pas encore présentes.
    /// La garde est basée sur l'UUID pivot de "Logement" (déterministe) — insensible
    /// aux races CloudKit et aux relances multiples.
    static func seedIfNeeded(context: ModelContext) {
        let pivotId = UUID(uuidString: "00000001-0000-0000-0000-000000000000")!
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == pivotId }
        )
        let alreadySeeded = (try? context.fetchCount(descriptor)) ?? 0
        guard alreadySeeded == 0 else { return }

        for category in defaultCategories() {
            context.insert(category)
        }
        try? context.save()
    }

    /// Synchronise les catégories système par défaut avec la base existante.
    /// Insère uniquement les catégories manquantes pour permettre l'ajout
    /// progressif de nouvelles racines ou sous-catégories après le premier seed.
    static func syncDefaultCategories(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isSystem }
        )
        let existingCategories = (try? context.fetch(descriptor)) ?? []
        let existingIds = Set(existingCategories.map(\.id))

        var didInsert = false
        for category in defaultCategories() where !existingIds.contains(category.id) {
            context.insert(category)
            didInsert = true
        }

        if didInsert {
            try? context.save()
        }
    }

    // MARK: - Déduplication CloudKit

    /// Supprime les catégories système dupliquées après une sync CloudKit.
    /// Appelé sur `NSPersistentStoreRemoteChange` — garde le premier enregistrement
    /// trouvé pour chaque UUID et supprime les copies.
    static func deduplicateIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.isSystem }
        )
        guard let systemCategories = try? context.fetch(descriptor) else { return }

        var seen: [UUID: Bool] = [:]
        var didDelete = false
        for category in systemCategories {
            if seen[category.id] != nil {
                context.delete(category)
                didDelete = true
            } else {
                seen[category.id] = true
            }
        }
        if didDelete {
            try? context.save()
        }
    }
}
