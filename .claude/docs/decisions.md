# CanI — Log des décisions

> Ce fichier trace toutes les décisions importantes prises durant le projet.
> Format : date + contexte + décision + raison + alternatives rejetées.
> Mettre à jour à chaque décision significative.

---

## 2025-03-12

### Nom de l'app : CanI

**Contexte** : Choix du nom avant démarrage du projet.

**Décision** : `CanI`

**Raison** :
- Répond directement à la question centrale de l'app : "Est-ce que je peux me permettre ça ?"
- Bilingue naturel — compréhensible FR et EN sans traduction
- Le nom = la feature différenciatrice (bouton Simulation)
- Court, mémorable, App Store-friendly

**Alternatives rejetées** :
- `Runway` — trop anglosphère, incompris du marché francophone
- `Float` — même problème
- `Afford` — même problème
- `Horizon` — trop générique
- `Floe` — original mais sans ancrage dans la question produit

---

### Stack technique : SwiftData over Core Data

**Contexte** : Choix de la couche de persistance au démarrage du projet Xcode.

**Décision** : SwiftData (`@Model`, `@Query`) — Storage réglé à "None" dans Xcode, pas de Core Data

**Raison** :
- SwiftData est le standard Apple pour iOS 17+
- API moderne, intégration SwiftUI native
- Moins de boilerplate que Core Data
- Support CloudKit via `ModelConfiguration(cloudKitContainerIdentifier:)`

**Alternatives rejetées** :
- Core Data + NSPersistentCloudKitContainer — ancien, verbeux, généré par Xcode mais à supprimer
- SQLite manuel — complexité injustifiée
- Realm — librairie tierce, contre le principe no-dependencies

**Note** : La checkbox "Host in CloudKit" dans Xcode a été décochée — elle est liée à Core Data, pas SwiftData. La config CloudKit se fait manuellement via `ModelConfiguration`.

---

### Sync : CloudKit natif, zéro backend propriétaire

**Contexte** : Choix de la stratégie de synchronisation multi-device.

**Décision** : CloudKit via SwiftData `ModelConfiguration`

**Raison** :
- E2E chiffré par défaut (données financières sensibles)
- Zéro coût d'hébergement
- Zéro backend à maintenir
- Transparent pour l'utilisateur (iCloud natif)
- Offline-first automatique

**Alternatives rejetées** :
- Firebase — backend propriétaire, coût variable, données hors Canada
- Supabase — même problème
- Sync manuel custom — complexité injustifiée pour un dev solo

---

### Architecture fichiers contexte : `.claude/`

**Contexte** : Organisation du contexte projet pour Claude Code.

**Décision** : Dossier `.claude/` à la racine avec sous-dossiers `docs/` et `design/`

**Structure** :
```
.claude/
├── docs/
│   ├── product-brief.md
│   └── decisions.md        ← ce fichier
└── design/
    └── reference-ui.png
```

**Raison** :
- Convention officielle Claude Code — lu automatiquement
- Séparation claire docs / assets design
- `CLAUDE.md` à la racine pointe vers ces fichiers

---

### Monnaie : Decimal, jamais Double

**Contexte** : Choix du type Swift pour stocker les montants financiers.

**Décision** : `Decimal` partout pour les montants

**Raison** :
- `Double` et `Float` ont des erreurs de précision flottante inacceptables pour des montants en dollars
- Ex: `0.1 + 0.2 == 0.30000000000000004` en Double
- `Decimal` est exact pour l'arithmétique décimale
- SwiftData supporte `Decimal` nativement

**Convention** :
```swift
// ✅
var amount: Decimal
Decimal(string: "19.99") ?? 0

// ❌
var amount: Double
```

---

### Locale affichage : fr_CA

**Contexte** : Format d'affichage des montants et dates.

**Décision** : `Locale(identifier: "fr_CA")` pour tous les formatters

**Raison** :
- Marché principal : québécois/canadien
- Affiche CAD correctement : `1 234,56 $`
- Dates en français canadien
- Cohérent avec le positionnement produit

---

### Couleurs d'alerte : orange/amber, jamais rouge

**Contexte** : Principe de gamification encourageante.

**Décision** : Aucune couleur rouge agressive dans l'UI, même quand un budget est dépassé

**Raison** :
- Principe produit fondamental : coach positif, pas un juge
- Rouge = stress, culpabilité — contre le ton de l'app
- Orange/amber = attention bienveillante

**Application** :
- Solde "tight" : amber
- Budget dépassé : orange
- Erreur critique système (seulement) : rouge système Apple, jamais custom

---

### Plateforme : iOS first, Catalyst plus tard

**Contexte** : Scope de développement MVP.

**Décision** : iOS 17+ uniquement pour le MVP

**Raison** :
- Focus et vélocité de développement
- SwiftUI iOS est plus mature que Catalyst
- Marché principal est mobile

**Futur** : macOS via Catalyst envisagé en v2+ si traction suffisante

---

## Template — Nouvelle décision

```markdown
### [Titre de la décision]

**Contexte** : Pourquoi cette décision s'est posée.

**Décision** : Ce qui a été choisi.

**Raison** :
- Point 1
- Point 2

**Alternatives rejetées** :
- Option A — pourquoi non
- Option B — pourquoi non

**Note** : Informations complémentaires si pertinent.
```
