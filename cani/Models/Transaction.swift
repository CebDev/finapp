import Foundation
import SwiftData

@Model
class Transaction {
    var id: UUID = UUID()
    var accountId: UUID = UUID()
    var recurringTransactionId: UUID? = nil
    /// Nom affiché — prérempli depuis la récurrence parente, modifiable manuellement.
    var name: String = ""
    var amount: Decimal = Decimal(0)
    var date: Date = Date()
    /// true si cette occurrence a été modifiée individuellement par rapport à la règle récurrente.
    /// Utilisé par le moteur de modification "cette occurrence et les suivantes" :
    /// Option A — une modification de série écrase même les occurrences isCustomized == true.
    var isCustomized: Bool = false
    /// UUID de la Category SwiftData sélectionnée (nil = non catégorisé)
    var categoryId: UUID? = nil
    var notes: String? = nil
    /// Vrai si la transaction est un transfert entre comptes
    var isTransfer: Bool = false
    /// UUID du compte de destination pour un transfert (nil si non-transfert)
    var transferDestinationAccountId: UUID? = nil
    var isPaid: Bool = false
 
    init(
        id: UUID = UUID(),
        accountId: UUID,
        recurringTransactionId: UUID? = nil,
        name: String = "",
        amount: Decimal,
        date: Date,
        isCustomized: Bool = false,
        categoryId: UUID? = nil,
        notes: String? = nil,
        isTransfer: Bool = false,
        transferDestinationAccountId: UUID? = nil,
        isPaid: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.recurringTransactionId = recurringTransactionId
        self.name = name
        self.amount = amount
        self.date = date
        self.isCustomized = isCustomized
        self.categoryId = categoryId
        self.notes = notes
        self.isTransfer = isTransfer
        self.transferDestinationAccountId = transferDestinationAccountId
        self.isPaid = isPaid
    }
}