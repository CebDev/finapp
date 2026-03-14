# CanI — Document de référence Claude Code

> Ce fichier est la source de vérité pour toutes les sessions Claude Code.
> Lire en entier avant de générer du code.

---

## Identité du projet

- **Nom** : CanI
- **Bundle ID** : cebdev.cani
- **Pitch** : App de projection financière vivante — répond à "Est-ce que je peux me permettre ça?"
- **Plateforme** : iOS 17+ first, Swift 5.9+, SwiftUI + SwiftData + CloudKit

---

## Profil développeur

- 7+ ans Ruby on Rails, découverte SwiftUI dans ce projet
- Workflow : Claude Code + Cursor
- Attente : code complet et fonctionnel du premier coup, jamais de pseudocode
- Instructions claires et opinées — pas d'approximation

---

## Stack technique — non négociable

| Couche | Technologie | Notes |
|---|---|---|
| UI & logique | SwiftUI | Composants natifs uniquement |
| Persistance | SwiftData | `@Model`, `@Query`, pas de Core Data |
| Sync | CloudKit | Via `ModelConfiguration(cloudKitContainerIdentifier:)` |
| Backend | Aucun | Offline-first total, zéro serveur propriétaire |
| Librairies tierces | Aucune | Sauf justification explicite et approuvée |

---

## Principes produit — non négociables

1. **Offline-first** — l'app fonctionne sans connexion, iCloud sync est transparente
2. **Gamification encourageante, jamais culpabilisante** — célébrer le progrès, pas punir l'échec
3. **Réalité québécoise** — CAD par défaut, support RRQ/CELI/REER/hypothèque/paie bi-hebdomadaire
4. **Ton encourageant** — coach positif, jamais un juge
5. **Simplicité d'abord** — chaque feature justifiée par un vrai besoin utilisateur

---

## Règles UI/UX absolues

- **Jamais de rouge agressif** pour les alertes budget — utiliser orange/amber uniquement
- Tab bar : TabView natif Apple, 5 onglets (voir Navigation)
- Langue UI : français canadien
- Couleurs d'accentuation : à définir (direction indigo/violet possible)

---

## Navigation — Structure TabView

```
Tab 1 — Accueil       (house.fill)
Tab 2 — Projection    (chart.line.uptrend.xyaxis)
Tab 3 — ＋            (plus.circle.fill) — action rapide centrale
Tab 4 — Abonnements   (rectangle.stack.fill)
Tab 5 — Objectifs     (target)
```

---

## Modèle de données SwiftData

### Account
```swift
@Model class Account {
    var id: UUID
    var name: String
    var type: AccountType           // chequing | savings | credit | mortgage | investment
    var currentBalance: Decimal
    var includeInBudget: Bool       // défaut: true sauf savings/investment
    var isShortTermReserve: Bool    // fonds d'urgence, épargne court terme
    var creditLimit: Decimal?       // si type == credit
    var icon: String                // SF Symbol name
    var createdAt: Date
}
```

### RecurringTransaction
```swift
@Model class RecurringTransaction {
    var id: UUID
    var accountId: UUID
    var name: String
    var amount: Decimal             // négatif = dépense, positif = revenu
    var frequency: Frequency        // weekly | biweekly | semimonthly | monthly | quarterly | annual
    var startDate: Date
    var endDate: Date?              // nil = indéfini
    var dayOfWeek: Int?             // pour biweekly (0=dimanche … 6=samedi)
    var dayOfMonth: Int?            // pour monthly
    var isIncome: Bool
    var category: Category
    var isSubscription: Bool
    var logo: String                // ex: "netflix", "spotify" — pour affichage logo
    var notes: String?
}
```

### Transaction
```swift
@Model class Transaction {
    var id: UUID
    var accountId: UUID
    var recurringTransactionId: UUID?
    var amount: Decimal
    var date: Date
    var isPast: Bool                // passé = réel, futur = projeté
    var isConfirmed: Bool
    var category: Category
    var notes: String?
}
```

### Goal
```swift
@Model class Goal {
    var id: UUID
    var name: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var deadline: Date?
    var type: GoalType              // shortTerm | longTerm
    var linkedAccountId: UUID?
    var emoji: String
}
```

### Simulation
```swift
@Model class Simulation {
    var id: UUID
    var name: String                // ex: "Achat TV 85$/mois 10 mois"
    var createdAt: Date
    var isActive: Bool              // overlay visible sur projection
}
```

### SimulationTransaction
```swift
@Model class SimulationTransaction {
    var id: UUID
    var simulationId: UUID
    var amount: Decimal
    var frequency: Frequency
    var startDate: Date
    var endDate: Date?
    var label: String
}
```

---

## Enums à définir

```swift
enum AccountType: String, Codable { case chequing, savings, credit, mortgage, investment }
enum Frequency: String, Codable { case weekly, biweekly, semimonthly, monthly, quarterly, annual }
enum GoalType: String, Codable { case shortTerm, longTerm }
enum Category: String, Codable { /* à compléter selon les besoins UI */ }
```

---

## Configuration SwiftData + CloudKit

```swift
// Dans l'App entry point — patron à respecter
let schema = Schema([Account.self, RecurringTransaction.self, Transaction.self, Goal.self, Simulation.self, SimulationTransaction.self])
let config = ModelConfiguration(schema: schema, cloudKitContainerIdentifier: "iCloud.cebdev.cani")
let container = try ModelContainer(for: schema, configurations: config)
```

---

## Scope MVP — Features v1

### ✅ Dans le MVP
- Comptes (chèques, épargne, crédit, hypothèque) — CRUD complet
- Transactions manuelles passées
- Transactions récurrentes — toutes fréquences incluant bi-hebdo avec jour fixe
- Date de fin sur récurrences
- Projection timeline 1–12 mois avec solde projeté automatique
- Indicateur visuel périodes "tight" (solde bas) — orange/amber, jamais rouge
- Simulation hypothétique avec overlay sur projection
- Réponse binaire simulation : "ça passe / ça passe pas"
- Vue abonnements (isSubscription == true) avec total mensuel normalisé
- Goals avec barre de progression
- Streak budget respecté + célébration goal atteint
- CloudKit sync automatique

### ❌ Hors MVP (v2+)
- Conseils IA / analyse patterns
- Import OFX/QIF
- Multi-devise
- Rapports avancés
- macOS/iPad optimisé
- Budget couple multi-utilisateur
- Paiements extra crédit gamifiés

---

## Moteur de projection — Règles de calcul

> Toute feature touchant la projection doit respecter ces règles.

- Point de départ : `currentBalance` de chaque compte `includeInBudget == true`
- Générer les occurrences de chaque `RecurringTransaction` active sur la période
- Une récurrence est active si : `startDate <= périodeCourante` ET (`endDate == nil` OR `endDate >= périodeCourante`)
- Fréquence biweekly : calculer à partir de `startDate` + multiples de 14 jours, filtrer par `dayOfWeek`
- Fréquence semimonthly : 1er et 15 du mois
- Agrégation par période (hebdo ou mensuel selon zoom)
- Solde projeté = solde précédent + somme des transactions de la période
- Période "tight" : solde projeté < seuil configurable (défaut: 500$ CAD)
- Simulation : calculer en parallèle avec/sans SimulationTransactions actives

---

## Conventions de code

```swift
// ✅ Toujours
@Model class MonEntité { ... }          // SwiftData pour tout ce qui est persisté
@Query var items: [MonEntité]           // fetch dans les vues
@Environment(\.modelContext) var context // injection contexte
Decimal(string:) ?? 0                   // pour les montants financiers, jamais Double

// ❌ Jamais
import CoreData                          // on est SwiftData
Double pour les montants                 // précision flottante inacceptable pour $$$
UIKit sauf bridging explicitement justifié
```

---

## Conventions monétaire

- Devise par défaut : **CAD**
- Format affichage : `NumberFormatter` avec `locale: Locale(identifier: "fr_CA")`
- Stockage : `Decimal` (jamais `Double` ou `Float`)
- Arrondi : 2 décimales pour l'affichage, précision complète en interne

---

## Processus de travail

1. **Poser des questions avant de coder** si la stratégie n'est pas claire
2. Générer du code complet et fonctionnel — jamais de `// TODO` sans implémentation
3. Un fichier = une responsabilité claire
4. Quand une feature touche la projection : valider l'impact sur le moteur de calcul
5. Tester mentalement le flow offline avant de livrer

---

## Contexte marché

- Concurrent principal : WalletApp
- Frustrations résolues : projection multi-mois, simulation d'impact, goals
- Marché : québécois/canadien, francophone international
- Modèle business : achat unique ou abonnement annuel, prix accessible
- Différenciation : offline-first + gamification positive + projection vivante

---

## Références

- Brief complet : `.claude/docs/product-brief.md`
- Décisions : `.claude/docs/decisions.md`
- UI de référence : `.claude/design/reference-ui.webp`