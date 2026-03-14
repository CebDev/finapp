//
//  TransactionOverride.swift
//  cani
//
//  Created by Sébastien Vermandele on 2026-03-14.
//

import Foundation
import SwiftData

/// Override pour une occurrence spécifique d'une RecurringTransaction.
/// Permet de marquer une occurrence comme payée et/ou d'ajuster son montant, compte ou date.
@Model
final class TransactionOverride {
    var id:                     UUID     = UUID()
    var recurringTransactionId: UUID     = UUID()
    /// Date prévue de l'occurrence originale (heure normalisée à minuit).
    var occurrenceDate:         Date     = Date()
    /// true = occurrence confirmée comme payée.
    var isPaid:                 Bool     = false
    /// Montant réel — signé (négatif = dépense, positif = revenu). nil = montant original.
    var actualAmount:           Decimal? = nil
    /// Compte de débit/crédit réel. nil = compte original de la RecurringTransaction.
    var actualAccountId:        UUID?    = nil
    /// Date de paiement réelle. nil = date d'occurrence prévue.
    var actualDate:             Date?    = nil
    var notes:                  String?  = nil
    var createdAt:              Date     = Date()

    init(recurringTransactionId: UUID, occurrenceDate: Date) {
        self.id                     = UUID()
        self.recurringTransactionId = recurringTransactionId
        self.occurrenceDate         = occurrenceDate
        self.isPaid                 = false
        self.actualAmount           = nil
        self.actualAccountId        = nil
        self.actualDate             = nil
        self.notes                  = nil
        self.createdAt              = Date()
    }
}
