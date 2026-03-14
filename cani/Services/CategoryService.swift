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

        // MARK: 🏠 Logement
        makeGroup(
            ns: "00000001",
            name: "Logement",
            icon: "house.fill",
            color: "#5E5CE6",
            children: [
                (name: "Loyer / Hypothèque", icon: "house.fill"),
                (name: "Électricité",         icon: "bolt.fill"),
                (name: "Internet",            icon: "wifi"),
                (name: "Assurance habitation",icon: "shield.fill"),
            ]
        )

        // MARK: 🚗 Transport
        makeGroup(
            ns: "00000002",
            name: "Transport",
            icon: "car.fill",
            color: "#FF9F0A",
            children: [
                (name: "Essence",            icon: "fuelpump.fill"),
                (name: "Assurance auto",     icon: "car.fill"),
                (name: "Transport en commun",icon: "tram.fill"),
                (name: "Stationnement",      icon: "parkingsign"),
            ]
        )

        // MARK: 🛒 Alimentation
        makeGroup(
            ns: "00000003",
            name: "Alimentation",
            icon: "cart.fill",
            color: "#30D158",
            children: [
                (name: "Épicerie",    icon: "cart.fill"),
                (name: "Restaurants", icon: "fork.knife"),
                (name: "Cafés",       icon: "cup.and.saucer.fill"),
            ]
        )

        // MARK: 💊 Santé
        makeGroup(
            ns: "00000004",
            name: "Santé",
            icon: "heart.fill",
            color: "#FF375F",
            children: [
                (name: "Pharmacie", icon: "pills.fill"),
                (name: "Médecin",   icon: "stethoscope"),
            ]
        )

        // MARK: 🎬 Loisirs
        makeGroup(
            ns: "00000005",
            name: "Loisirs",
            icon: "tv.fill",
            color: "#BF5AF2",
            children: [
                (name: "Abonnements", icon: "rectangle.stack.fill"),
                (name: "Sorties",     icon: "ticket.fill"),
                (name: "Sport",       icon: "figure.run"),
                (name: "Voyages",     icon: "airplane"),
            ]
        )

        // MARK: 💼 Revenus
        makeGroup(
            ns: "00000006",
            name: "Revenus",
            icon: "arrow.down.circle.fill",
            color: "#32D74B",
            children: [
                (name: "Salaire",        icon: "banknote.fill"),
                (name: "Freelance",      icon: "briefcase.fill"),
                (name: "REER",           icon: "chart.line.uptrend.xyaxis"),
                (name: "Remboursements", icon: "arrow.uturn.left.circle.fill"),
            ]
        )

        // MARK: 🎓 Éducation
        makeGroup(
            ns: "00000007",
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
            ns: "00000008",
            name: "Finances",
            icon: "chart.pie.fill",
            color: "#FFD60A",
            children: [
                (name: "CELI",              icon: "dollarsign.circle.fill"),
                (name: "REER",              icon: "chart.line.uptrend.xyaxis"),
                (name: "Remboursement dette",icon: "creditcard.fill"),
                (name: "Épargne",           icon: "building.columns.fill"),
            ]
        )

        // MARK: 📦 Autre
        result.append(Category(
            id: UUID(uuidString: "00000009-0000-0000-0000-000000000000")!,
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
}
