//
//  CategoryIconRegistry.swift
//  cani
//
//  Registre des icônes PNG (ou SVG) disponibles pour les catégories.
//  Ajouter un fichier PNG dans Assets.xcassets puis l'inscrire ici.
//
//  Convention de stockage : "img:nomAsset" dans Category.icon
//

import Foundation

/// Noms des assets PNG présents dans Assets.xcassets.
/// Chaque entrée correspond à un fichier image ajouté au catalogue d'assets.
let customCategoryIcons: [String] = [
    // Exemples — remplacer par les vrais noms d'assets ajoutés dans Xcode :
    // "netflix",
    // "spotify",
    // "apple_tv",
    // "disney_plus",
    // "amazon_prime",
    // "youtube",
    // "crave",
    // "tva_plus",
    // "desjardins",
    // "rbc",
    // "td",
]

// MARK: - Helpers

extension String {
    /// Vrai si cette icône est un asset PNG/image (préfixe "img:").
    var isCustomCategoryIcon: Bool { hasPrefix("img:") }

    /// Nom de l'asset sans le préfixe "img:".
    var customAssetName: String {
        isCustomCategoryIcon ? String(dropFirst(4)) : self
    }

    /// Construit une valeur icon à stocker depuis un nom d'asset.
    static func customIcon(_ assetName: String) -> String { "img:\(assetName)" }
}
