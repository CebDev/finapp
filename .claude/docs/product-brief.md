# FinApp — Document Fondateur du Projet Claude

## Contexte développeur

- Développeur indépendant québécois, 7+ ans Ruby on Rails
- Découverte de SwiftUI dans le cadre de ce projet
- Workflow : Cursor + Claude, directives précises qui passent du premier coup
- Préférence : instructions claires et opinionées, pas de code approximatif

-----

## Stack technique

- **UI & logique** : SwiftUI
- **Persistance locale** : SwiftData (SQLite sous le capot)
- **Sync & backup** : CloudKit (iCloud natif, E2E chiffré, zéro backend propriétaire)
- **Plateforme** : iOS first, potentiellement macOS via Catalyst plus tard
- **Backend** : aucun — offline-first total, coût d’hébergement zéro

-----

## Principes produit non négociables

1. **Offline-first** — l’app fonctionne sans connexion, la sync iCloud est transparente
1. **Gamification encourageante, jamais culpabilisante** — célébrer le progrès, pas punir l’échec. Zéro rouge agressif quand un budget est dépassé
1. **Réalité québécoise** — CAD par défaut, concepts locaux supportés (RRQ, CELI, REER, hypothèque, paie bi-hebdomadaire)
1. **Ton encourageant** — l’app est un coach positif, pas un juge
1. **Simplicité d’abord** — chaque feature doit être justifiée par un vrai besoin utilisateur

-----

## Problème central résolu

WalletApp et équivalents ont une projection financière faible ou inexistante. L’utilisateur doit créer manuellement des budgets quinzaine par quinzaine pour avoir une vision à moyen terme.

**Ce produit résout ça avec une timeline financière vivante** : une projection automatique sur 12 mois qui reflète toutes les récurrences, leurs dates de début et de fin, et qui permet de simuler l’impact d’un nouvel engagement financier avant de le prendre.

-----

## Modèle de données — Entités principales

### Account

```
id: UUID
name: String
type: chequing | savings | credit | mortgage | investment
currentBalance: Decimal
includeInBudget: Bool        // défaut: true sauf savings/investment
isShortTermReserve: Bool     // fonds d'urgence, épargne court terme
creditLimit: Decimal?        // si type == credit
icon: String                 // SF Symbol
createdAt: Date
```

### RecurringTransaction

```
id: UUID
accountId: UUID
name: String
amount: Decimal              // négatif = dépense, positif = revenu
frequency: weekly | biweekly | semimonthly | monthly | quarterly | annual
startDate: Date
endDate: Date?               // nil = indéfini (ex: salaire, loyer)
dayOfWeek: Int?              // pour biweekly — ex: jeudi
dayOfMonth: Int?             // pour monthly
isIncome: Bool
category: Category
isSubscription: Bool         // identifie les abonnements récurrents
logo: String                 // nom du service pour affichage logo (ex: "netflix", "spotify")
notes: String?
```

### Transaction (réelle ou planifiée future)

```
id: UUID
accountId: UUID
recurringTransactionId: UUID?  // lien si générée depuis une récurrence
amount: Decimal
date: Date
isPast: Bool                   // passé = réel, futur = projeté
isConfirmed: Bool              // l'utilisateur a validé la transaction réelle
category: Category
notes: String?
```

### Goal

```
id: UUID
name: String
targetAmount: Decimal
currentAmount: Decimal
deadline: Date?
type: shortTerm | longTerm
linkedAccountId: UUID?
emoji: String
```

### Simulation

```
id: UUID
name: String                   // ex: "Achat TV 85$/mois 10 mois"
transactions: [SimulationTransaction]
createdAt: Date
isActive: Bool                 // si true, visible en overlay sur la projection
```

### SimulationTransaction

```
id: UUID
simulationId: UUID
amount: Decimal
frequency: (même enum que RecurringTransaction)
startDate: Date
endDate: Date?
label: String
```

-----

## Scope MVP — Ce qui est dans la v1

### Comptes

- Création de comptes (chèques, épargne, crédit, hypothèque)
- Paramétrage includeInBudget par compte
- Solde actuel saisi manuellement

### Transactions

- Saisie manuelle de transactions passées
- Transactions récurrentes avec toutes les fréquences (hebdo, bi-hebdo, mensuel, etc.)
- Support paie bi-hebdomadaire avec jour de semaine fixe (ex: jeudi sur 2)
- Date de fin sur les récurrences (ex: crédit qui se termine dans 3 mois)

### Projection

- Vue timeline 1 à 12 mois
- Solde projeté automatique basé sur les récurrences actives à chaque période
- Événements ponctuels futurs (one-shots)
- Indicateur visuel des périodes “tight” (solde bas)

### Simulation

- Ajout d’un scénario hypothétique (ex: nouvel achat à payer en X mois)
- Overlay sur la projection pour voir l’impact
- Réponse claire : “ça passe / ça passe pas” sur la période

### Abonnements

- Vue dédiée listant toutes les RecurringTransaction où isSubscription == true
- Total mensuel normalisé (ramener weekly/annual en équivalent mensuel)
- Logo/icône par service pour reconnaissance visuelle rapide
- Prise de conscience : “Tu dépenses X$/mois en abonnements”

### Goals

- Création d’un goal avec montant cible et deadline optionnelle
- Barre de progression visuelle
- Distinction court terme / long terme

### Gamification (v1 — simple)

- Streak de budget respecté (hebdomadaire)
- Célébration visuelle quand un goal est atteint
- Impact visuel quand un crédit se termine (solde qui “se libère”)

### Sync

- CloudKit automatique — multi-device transparent

-----

## Hors scope MVP (v2+)

- Conseils basés sur les habitudes (analyse patterns)
- Import OFX / QIF / bancaire automatique
- Multi-devise
- Rapports et graphiques avancés
- Paiements extra crédit gamifiés (badge remboursement accéléré)
- macOS / iPad optimisé
- Partage budget couple (comptes partagés multi-utilisateur)

-----

## Contexte marché

- App concurrente principale : WalletApp
- Frustrations clés à résoudre : projection multi-mois absente, pas de simulation d’impact, goals basiques
- Modèle business cible : achat unique ou abonnement annuel one-shot, prix accessible
- Différenciation : offline-first + gamification positive + projection vivante
- Marché principal : québécois/canadien, potentiellement francophone international

-----

## Instructions pour Claude dans ce projet

- Toujours générer du code SwiftUI/SwiftData complet et fonctionnel, pas de pseudocode
- Respecter les conventions Swift modernes (Swift 5.9+, iOS 17+)
- Utiliser SwiftData `@Model` pour toutes les entités persistées
- Utiliser `@Query` pour les fetch SwiftData dans les vues
- CloudKit sync via `ModelConfiguration` avec `cloudKitContainerIdentifier`
- Privilégier les composants SwiftUI natifs — pas de librairies tierces sauf si vraiment justifié
- Le ton de l’UI est toujours encourageant — les couleurs d’alerte sont orange/amber, jamais rouge agressif
- Quand une feature touche la projection, toujours considérer l’impact sur le moteur de calcul central
- Poses des questions avant de coder quoi que ce soit afin de valider que nous sommes d'accord sur la stratégie à appliquer