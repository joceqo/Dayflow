# Dayflow — UI & Design System

Document de référence pour le front de l'app Dayflow (macOS, SwiftUI).
Toutes les références de fichiers pointent vers `Dayflow/Dayflow/`.

---

## 1. Architecture d'écran

### 1.1 Layout racine

- **Entrée principale** : `Views/UI/MainView/MainView.swift`
- **Layout deux colonnes** : `Views/UI/MainView/Layout.swift`
  - Colonne gauche (~100 px) : logo `LogoBadgeView` (36 px) + sidebar
  - Colonne droite (panneau blanc) : `ZStack` qui switch sur l'onglet actif

### 1.2 Sidebar et navigation

Fichier : `Views/UI/MainView/SidebarView.swift`

Énum `SidebarIcon` : `.timeline`, `.daily`, `.weekly`, `.chat`, `.journal`, `.logs`, `.bug`, `.settings`.
Badge dynamique (point orange) sur `.journal` et `.daily` via `NotificationBadgeManager`.
Items : ~61,6 px (1,1 × 56 px de base), badge : 8 px.

### 1.3 Onglets / écrans principaux

| Onglet | Fichier |
|---|---|
| Timeline | `Views/UI/MainView/Layout.swift` (cards + overlays) |
| Daily | `Views/UI/DailyView.swift` |
| Weekly | `Views/UI/Weekly/WeeklyView.swift` + `Sections/` |
| Chat | `Views/UI/ChatView.swift` |
| Journal (bêta) | `Views/UI/JournalView.swift` |
| Logs | `Views/UI/RuntimeConsoleView.swift` |
| Bug report | `Views/UI/BugReportView.swift` |
| Settings | `Views/UI/SettingsView.swift` |

### 1.4 Modals / sheets

- `.sheet(item:)` pour le setup d'un provider (900×650 min)
- `.sheet(isPresented:)` pour l'upgrade modèle local
- Overlays plein écran : `TimelineFeedbackModal`, `TimelineReviewOverlay`, `VideoPlayerModal` (transition hero via `@Namespace`)
- Calendrier inline déployable dans la timeline et l'export Settings

---

## 2. Onboarding

Orchestrateur : `Views/Onboarding/OnboardingFlow.swift`

Machine à états `OnboardingStep` en 10 écrans :

1. `.introVideo` — vidéo d'intro (`VideoLaunchView`)
2. `.roleSelection` — métier / profil (`OnboardingPrototypeFlow`)
3. `.referral` — survey (`ReferralSurveyView`)
4. `.preferences` — préférences générales
5. `.llmSelection` — choix du provider (`OnboardingLLMSelectionView`)
6. `.llmSetup` — configuration + clé API (`LLMProviderSetupView`, `APIKeyInputView`, `TestConnectionView`)
7. `.categories` — création des catégories (`OnboardingCategoryStepView`)
8. `.categoryColors` — couleurs par catégorie
9. `.screen` — permission enregistrement écran (`ScreenRecordingPermissionView`)
10. `.completion` — succès

Cadre commun : `SetupSidebarView` + `SetupContinueButton`, plus `HowItWorksView` / `HowItWorksCard` pour l'éducation.

---

## 3. Design system — primitives

### 3.1 Boutons

| Composant | Fichier | Usage |
|---|---|---|
| `DayflowButton` | `Views/Components/DayflowButton.swift` | CTA principal orange, animation pulse, haptic |
| `DayflowSurfaceButton` | `Views/Components/DayflowSurfaceButton.swift` | Bouton générique très paramétrable (couleur fond/texte/bordure, coin, padding, stroke blanc optionnel) |
| `DayflowCircleButton` | `Views/UI/DayflowUIStyles.swift:29` | Bouton rond (~31 px) |
| `DayflowPillButton` | `Views/UI/DayflowUIStyles.swift:60` | Pill texte, hauteur ~30 px |

Paramètres typiques de `DayflowSurfaceButton` :

```swift
DayflowSurfaceButton(
  action: { … },
  content: { … },
  background: Color.white,
  foreground: Color(red: 0.25, green: 0.17, blue: 0),
  borderColor: Color(hex: "FFE0A5"),
  cornerRadius: 8,
  horizontalPadding: 12,
  verticalPadding: 7,
  showOverlayStroke: true
)
```

Animations communes : hover `scaleEffect(1.02)`, press `scaleEffect(0.985)`, ombre modulée.

### 3.2 Cards

| Composant | Fichier | Usage |
|---|---|---|
| `SettingsCard` | `Views/UI/Settings/SettingsComponents.swift` | Wrapper standard des sections Settings (titre + sous-titre + contenu) |
| `FlexibleProviderCard` | `Views/Components/ProviderCardComponents.swift` | Card provider LLM, avec état sélectionné, badge, checklist |
| `DistractionSummaryCard`, `LongestFocusCard`, `TimelineReviewSummaryCard` | `Views/Components/…` | Cards métriques Daily/Timeline |
| `CardsToReviewBadge` / `CardsToReviewButton` | `Views/Components/…` | Badge nombre d'activités à relire |

Style `SettingsCard` : fond `Color.white.opacity(0.72)`, coin 18 px, padding 28 px, stroke blanc 0,8 px.

### 3.3 View modifiers

- `pointingHandCursor()` — curseur main. `Views/Components/CursorModifiers.swift` (natif macOS 15+, no-op 14)
- `pointingHandCursorOnHover(enabled:, reassertOnPressEnd:)` — compat API
- `hoverScaleEffect(scale:, animation:)` — spring sur hover (défaut 1,02 ; response 0,24 s)
- `pointingHandCursorWithHoverScale(...)` — combo
- `.if(condition:, transform:)` — conditionnel inline. `Views/UI/MainView/Support.swift:41`
- `ScrollTrackingModifier` — suivi de position pour parallaxe / fondus

### 3.4 Autres composants utiles

- `WrappingHStack` — layout flow-wrap
- `CategoryPickerView`, `TimelineCardColorPicker` — pickers catégories
- `ProgressRingView` — anneau de progression
- `LogoBadgeView` — logo + badge pastille

---

## 4. Typographie

Polices embarquées (`Dayflow/Fonts/`) :

| Famille | Usage | Tailles courantes |
|---|---|---|
| **Nunito** (variable) | Texte courant, labels, titres de card | 10 → 18 (jusqu'à 36 pour hero) |
| **Instrument Serif** | Headlines, dates, hero | 18 → 38 |
| **Figtree** (variable) | Secondaire (usage minoritaire) | — |

Poids Nunito couramment appelés : `Regular`, `Medium`, `SemiBold`, `Bold`.

Il n'y a **pas** de helper typographique central : les appels sont inline via `.font(.custom("Nunito", size: 13))`, etc.

Hiérarchie textuelle observée :

- Titre card : `Nunito 18 / semibold`, `Color.black.opacity(0.85)`
- Sous-titre : `Nunito 12`, `Color.black.opacity(0.45)`
- Label de champ : `Nunito 13`, `Color.black.opacity(0.7)`
- Aide / caption : `Nunito 11.5`, `Color.black.opacity(0.5–0.55)`

---

## 5. Palette de couleurs

Pas de fichier `Theme` centralisé. Les couleurs sont inline via `Color(hex:)` (défini dans `Utilities/Color+Luminance.swift`) ou `Color(red:green:blue:)`.

### 5.1 Accent primaire (orange Dayflow)

- `#F96E00` / `#FF7506` / `#FF8904` — CTAs, sélection sidebar, badges
- `#C04A00` — icônes warning
- `#FCF2E3` — fond card sélectionnée
- `#F3D9C2` / `#FFE0A5` — bordures / strokes chaleureux
- `#FFF8F2` — fond toast/alerte douce

### 5.2 Neutres

- `#FFFFFF` — panneaux
- `#F2F2F2` / `#ECECEC` / `#EBE9E6` — séparateurs / états inactifs
- `#2F2A24` / `#1F1B18` / `#1E1B18` — textes sombres

### 5.3 Sémantique

- Succès : `#34C759`, `#2EB67D`
- Erreur : `#E91515`, `Color.red.opacity(0.75)`

### 5.4 Transparences récurrentes

- `Color.black.opacity(0.04 / 0.05 / 0.12 / 0.22 / 0.45 / 0.55 / 0.7 / 0.85)` — couches texte et surfaces
- Ombres : `Color.black.opacity(0.04 → 0.35)` en stack 3–4 couches pour la profondeur

---

## 6. Icônes & assets

### 6.1 SF Symbols

Exemples : `checkmark`, `xmark`, `exclamationmark.triangle.fill`, `chart.pie`, `terminal`, `gearshape`, `sparkles`, `plus`, `square.and.arrow.down`.

### 6.2 Assets custom (`Assets.xcassets`)

- Logo : `DayflowLogoMainApp`, `DayflowLaunch`
- Sidebar : `TimelineIcon`, `DailyIcon`, `ChatIcon`, `JournalIcon`, `IconBackground`
- Navigation calendrier : `CalendarLeftButton`, `CalendarRightButton`
- Journal : `JournalArrow`, `JournalLock`, `JournalPreview`, `JournalReminderIcon`
- Catégories : `CategoriesCheckmark`, `CategoriesDelete`, `CategoriesEdit`, `TimelineCardColorPicker`
- Summaries : `DistractionSummaryIcon`, `LongestFocusCard`, `CardsToReviewBadge`
- Onboarding : `OnboardingBackgroundv2`, `OnboardingTimeline`
- Feedback / social : `ThumbsUp`, `DiscordGlyph`, `GithubIcon`, `Copy`

---

## 7. Organisation des vues

```
Views/
├── Components/           # Primitives réutilisables
│   ├── DayflowButton.swift
│   ├── DayflowSurfaceButton.swift
│   ├── CursorModifiers.swift
│   ├── ProviderCardComponents.swift
│   ├── SettingsCard.swift
│   ├── TimelineCardColorPicker.swift
│   ├── CategoryPickerView.swift
│   ├── WrappingHStack.swift
│   ├── ScrollTrackingModifier.swift
│   └── …
│
├── Onboarding/           # 10 étapes du setup
│   ├── OnboardingFlow.swift
│   ├── OnboardingLLMSelectionView.swift
│   ├── LLMProviderSetupView.swift
│   ├── ScreenRecordingPermissionView.swift
│   └── …
│
└── UI/                   # Écrans app
    ├── MainView/
    │   ├── MainView.swift
    │   ├── Layout.swift
    │   ├── SidebarView.swift
    │   ├── Support.swift
    │   ├── Actions.swift
    │   ├── Lifecycle.swift
    │   └── …
    ├── Settings/
    │   ├── SettingsView.swift
    │   ├── SettingsStorageTabView.swift
    │   ├── SettingsProvidersTabView.swift
    │   ├── SettingsDataTabView.swift
    │   ├── SettingsOtherTabView.swift
    │   ├── SettingsComponents.swift
    │   └── *ViewModel.swift
    ├── Weekly/
    │   ├── WeeklyView.swift
    │   └── Sections/ (Treemap, Sankey, Heatmap, Donut, …)
    ├── DailyView.swift
    ├── JournalView.swift
    ├── ChatView.swift
    ├── BugReportView.swift
    ├── RuntimeConsoleView.swift
    ├── VideoPlayerModal.swift
    ├── ProgressRingView.swift
    └── DayflowUIStyles.swift
```

---

## 8. Patron Settings

`SettingsView.swift` = hub 4 onglets.

```swift
private enum SettingsTab: String, CaseIterable, Identifiable {
  case storage, providers, data, other
}
```

Chaque onglet :

- A son `*TabView` dédié
- A son `*SettingsViewModel` `@StateObject` (sauf `data` et `other` qui partagent `OtherSettingsViewModel`)
- Gère ses propres sheets
- Empile des `SettingsCard` dans un `VStack(spacing: 28)`

Transitions entre onglets : `@State var tabTransitionDirection` (`none`, `leading`, `trailing`) → animation asymétrique opacité + offset.

---

## 9. Animations

- Spring par défaut : `response 0.22–0.35`, `dampingFraction 0.75–0.9`
- Entrées échelonnées avec `.delay()` (0,1 / 0,15 / 0,2 s)
- Transitions combinées fréquentes : `.opacity.combined(with: .move(edge: .top))`, `.scale.combined(with: .opacity)`
- Hero animation vidéo via `@Namespace var videoHeroNamespace` (MainView)

---

## 10. Patrons d'implémentation remarquables

- **PreferenceKeys** pour la synchro de layout : `TimelineHeaderFramesPreferenceKey`, `WeeklyHoursFramePreferenceKey`, `TimelineTimeLabelFramesPreferenceKey`
- **State machines locales** : `TimelineCopyState` (idle/copying/copied), `VideoExpansionState`, `TabTransitionDirection`
- **Analytics** : `AnalyticsService.shared.capture(event, props)` aux points clés (navigation, submit). Sampling via `withSampling(probability:)`. Breadcrumbs Sentry dans les flots critiques.

---

## 11. Bonnes pratiques pour ajouter un écran / un composant

1. **Réutiliser avant de créer** : `SettingsCard`, `DayflowSurfaceButton`, `pointingHandCursor()`.
2. **Typographie** : `Font.custom("Nunito", size: …)` + opacité noire standard (0,85 titre, 0,7 label, 0,55 aide).
3. **Couleurs** : passer par `Color(hex:)` si valeur existante de la palette ; éviter d'inventer un nouvel orange.
4. **Corners** : 8 px (chips / petits CTAs), 12 px (champs), 18 px (cards).
5. **Padding card** : 28 px par défaut (voir `SettingsCard`).
6. **Spacing vertical** inter-card : 28 px (`VStack(spacing: 28)`).
7. **Curseur main** sur tout élément cliquable non-button-standard : `.pointingHandCursor()`.
8. **Animations d'apparition** : spring 0,24 s / 0,88 damping + opacity.
9. **Mode sombre** : l'app force `colorScheme .light` sur les Settings (`SettingsView.body` ligne 56). Vérifier la cohérence si un nouvel écran doit hériter.
10. **Le projet utilise des `PBXFileSystemSynchronizedRootGroup`** : un nouveau `.swift` déposé sous `Dayflow/Dayflow/Views/...` est automatiquement compilé, pas de manipulation pbxproj.
