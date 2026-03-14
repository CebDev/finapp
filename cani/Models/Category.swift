//
//  Category.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-13.
//

import Foundation
import SwiftData

@Model
class Category {
    var id: UUID = UUID()
    /// Nom affiché dans l'UI (ex: "Logement", "Épicerie")
    var name: String = ""
    /// SF Symbol name (ex: "house.fill")
    var icon: String = "square.grid.2x2.fill"
    /// Couleur hex sans alpha (ex: "#5E5CE6")
    var color: String = "#98989D"
    /// nil = catégorie racine ; non-nil = sous-catégorie de parentId
    var parentId: UUID? = nil
    /// true = catégorie système, non supprimable
    var isSystem: Bool = true
    /// Ordre d'affichage dans les listes
    var sortOrder: Int = 0

    var isSubcategory: Bool { parentId != nil }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        color: String,
        parentId: UUID? = nil,
        isSystem: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.parentId = parentId
        self.isSystem = isSystem
        self.sortOrder = sortOrder
    }
}
