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
    /// Les UUIDs sont déterministes pour garantir la stabilité entre les seeds.
    static func defaultCategories() -> [Category] {
        var result: [Category] = []
        var order = 0

        // Helper pour créer un parent + ses enfants d'un coup
        func makeGroup(
            id: UUID,
            name: String,
            icon: String,
            color: String,
            children: [(name: String, icon: String)]
        ) {
            let parent = Category(
                id: id,
                name: name,
                icon: icon,
                color: color,
                parentId: nil,
                isSystem: true,
                sortOrder: order
            )
            result.append(parent)
            order += 1

            for (childIndex, child) in children.enumerated() {
                result.append(Category(
                    name: child.name,
                    icon: child.icon,
                    color: color,
                    parentId: id,
                    isSystem: true,
                    sortOrder: childIndex
                ))
            }
        }

        // MARK: 🏠 Logement
        makeGroup(
            id: UUID(uuidString: "00000001-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000002-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000003-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000004-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000005-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000006-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000007-0000-0000-0000-000000000000")!,
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
            id: UUID(uuidString: "00000008-0000-0000-0000-000000000000")!,
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

    /// Insère les catégories par défaut si aucune catégorie n'existe encore dans le contexte.
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for category in defaultCategories() {
            context.insert(category)
        }
    }
}
