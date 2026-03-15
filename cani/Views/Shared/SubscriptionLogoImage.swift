//
//  SubscriptionLogoImage.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import SwiftUI

/// Noms des logos d'abonnement disponibles dans Assets.xcassets.
let allSubscriptionLogos: [String] = [
    "netflix",
    "spotify",
    "apple-music",
    "amazon-prime",
    "crave",
    "claude-ai",
    "youtube",
    "chatgpt"
]

/// Affiche le logo d'un abonnement depuis Assets.xcassets.
/// Si `logo` est vide ou inconnu, affiche un carré générique.
struct SubscriptionLogoImage: View {
    let logo: String
    let size: CGFloat

    private var cornerRadius: CGFloat { size * 0.22 }

    var body: some View {
        Image(logo)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
