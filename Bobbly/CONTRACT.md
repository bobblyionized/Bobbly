# Bobbly UI ↔ Core contract

This is for the UI agent. Core owns every `*ViewModel.swift`, `Bobbly/App/` (except
`RootView.swift`), `Engine/`, `Data/`, `Intents/`, `Chat/ChatEngine.swift`,
`Chat/ChatModels.swift`, `Chat/ChatPhrases.swift`, the extension logic files and
`Shared/`. UI owns `Bobbly/UI/` (create it), every `*View.swift`, `RootView.swift`,
`BobblyShieldConfig/ShieldStyle.swift` and the report views in `BobblyReport/`.
The phase 1 views are stubs; replace them completely. Keep the type names and
initializers listed here, because RootView and the extensions call them.

If a signature here is wrong or something is missing, ask Core. Don't add logic to
views.

---

## 0. Ground rules

- **Environment.** `AppEnvironment` (`@Observable @MainActor`) is injected at the
  root with `.environment(env)`. Read it with `@Environment(AppEnvironment.self) private var env`.
  Previews use `AppEnvironment.preview()`: in-memory SwiftData with sample usage,
  plus a separate SharedStore.
- **Tab ViewModels are long-lived.** `env.home`, `env.chat`, `env.study`,
  `env.stats` and `env.settings` are never nil after init. Pass one into its view
  as `@Bindable var model: XViewModel`.
- **Modal ViewModels come from factories:**
  - `env.makeGateViewModel(target:)`
  - `env.makeEmergencyViewModel()`
  - `env.makeSearchViewModel()`
  - `env.makeTutorialViewModel()`
  - `env.makeBlockedAppsViewModel()`
  - `env.makeCompanionViewModel()`

  The presented view owns its model like this:
  ```swift
  @State private var model: GateViewModel
  init(model: GateViewModel) { _model = State(initialValue: model) }
  // for bindings inside body: @Bindable var model = model
  ```
- **ViewModel inits have no side effects.** Call `model.onAppear()` from
  `.onAppear` (it's `async` only on the tutorial; use `.task` there).
- **Observation.** Every model is `@Observable`. Computed properties such as
  `companion` read observable services (`env.companion`, `env.engines`), so views
  update automatically. Don't cache them.
- **Time-based UI.** Countdowns for unlocks, cooldowns, study and emergency
  should use `TimelineView(.periodic(from: .now, by: 1))` with the `Date`s the
  models expose. Models don't tick every second, except the Emergency hold
  progress.
- **Tokens and names.** Under FamilyControls the app often has an opaque
  `ApplicationToken` instead of a name. Whenever `UnlockSubject` is
  `.application(token)`, render the app with FamilyControls' `Label(token)`,
  which shows the real icon and name. Use `displayName` only as a fallback
  ("this app").
- **Pickers.** Apps are chosen with FamilyControls'
  `.familyActivityPicker(isPresented:selection:)` bound to the model properties
  named below. The picker only works when `env.engines.state == .familyControls`.
- **Haptics and motion are UI concerns.** Respect `env.preferences.hapticsEnabled`.

---

## 1. Routing (`Bobbly/App/AppRouter.swift`)

`env.router: AppRouter` (`@Observable`):

| Property | Type | Bind with |
|---|---|---|
| `selectedTab` | `AppTab` | `TabView(selection: $router.selectedTab)` |
| `sheet` | `SheetRoute?` | `.sheet(item: $router.sheet)` |
| `cover` | `CoverRoute?` | `.fullScreenCover(item: $router.cover)` |

`AppTab` cases (display order): `.home`, `.chat`, `.study`, `.stats`, `.settings`.
Each has `.title` and `.systemImage`.

| Route | Present | ViewModel |
|---|---|---|
| `SheetRoute.emergency` | `EmergencyView(model:)` | `env.makeEmergencyViewModel()` |
| `SheetRoute.search` | `SearchView(model:)` | `env.makeSearchViewModel()` |
| `SheetRoute.blockedApps` | `BlockedAppsView(model:)` | `env.makeBlockedAppsViewModel()` |
| `SheetRoute.companion` | `CompanionView(model:)` | `env.makeCompanionViewModel()` |
| `SheetRoute.whitelistEditor(whitelistID: UUID?)` | `WhitelistEditorView(model:whitelistID:)` | `env.study` (shared) |
| `CoverRoute.gate(ChatTarget)` | `GateView(model:)` | `env.makeGateViewModel(target:)` |
| `CoverRoute.tutorial` | `PermissionsTutorialView(model:)` | `env.makeTutorialViewModel()` |

Router methods are `select(_:)`, `present(_:)`, `presentGate(_:)`,
`presentTutorial()`, `dismissSheet()`, `dismissCover()` and `showTab(_:)`.
`showTab` closes every modal before switching. Inside a modal, closing with
`@Environment(\.dismiss)` is fine too.

Deep links are already handled in `BobblyApp` and `AppEnvironment.handle(url:)`:

| Link | Effect |
|---|---|
| `bobbly://gate?app=Instagram` | Gate cover |
| `bobbly://chat?source=shield` | Chat tab, started about the shielded app |
| `bobbly://emergency` | Emergency sheet |
| `bobbly://tutorial` | Tutorial cover |

The phase 1 `RootView.swift` already wires all of this. Restyle it, but keep
the mapping.

---

## 2. Shared domain types

| Type | Where | Fields / cases |
|---|---|---|
| `CompanionSnapshot` | Engine/Companion/CompanionService.swift | `mood: Int` (0–100), `lives: Int`, `maxLives: Int` (3), `tier: CompanionMood`, `focusMinutesToday: Int`, `livesLostToday: Int`, `currentStreak: Int`, `bestStreak: Int`, `resetsAt: Date` (next midnight), `line: String` (what Bobbly says), `moodFraction: Double` (0–1) |
| `CompanionMood` | CompanionRules.swift | `.thriving`, `.happy`, `.okay`, `.sad`, `.exhausted` (0 lives). Drives Bobbly's face. |
| `EngineKind` | Shared/Core/SharedModels.swift | `.familyControls`, `.shortcuts`; `displayName` |
| `EngineSelectionState` | EngineSelector.swift | `.undetermined`, `.familyControls`, `.shortcutsFallback(reason:)`, `.detached`; `label` |
| `EngineStatus` | BlockingEngine.swift | `kind`, `isReady`, `isDetached`, `emergencyUntil: Date?`, `activeUnlocks: [ActiveUnlock]`, `study: StudySnapshot?`, `blockedAppCount`, `blockedCategoryCount`, `blockedWebDomainCount`, `hasAnythingBlocked` |
| `ActiveUnlock` | BlockingEngine.swift | `id: UUID`, `subject: UnlockSubject`, `displayName`, `grantedAt`, `expiresAt`, `remaining(at:) -> TimeInterval` |
| `UnlockSubject` | BlockingEngine.swift | `.appName(String)`, `.application(ApplicationToken)` (render with `Label(token)`), `.studySession` |
| `StatsPoint` | Data/UsageAggregator.swift | `day: Date` (start of day), `appName: String?` (nil = all apps), `minutes: Double`, `id` |
| `AppUsageSummary` | UsageAggregator.swift | `appName`, `appKey`, `totalMinutes: Double`, `opens: Int` |
| `AppUsageSearchResult` | UsageAggregator.swift | `appName`, `range: DateInterval`, `totalMinutes`, `averageMinutesPerDay`, `longestSessionMinutes`, `longestSessionStart: Date?`, `totalOpens`, `opensPerDay`, `daily: [StatsPoint]` (zero-filled, oldest first) |
| `CatalogApp` | Engine/AppCatalog.swift | `id`, `name`, `urlScheme`, `symbol` (an SF Symbol placeholder icon) |
| `TrackedAppRow` | Features/BlockedApps/BlockedAppsViewModel.swift | `id`, `name`, `appKey`, `urlScheme?`, `dailyLimitMinutes` (0 means none), `isBlocked` |

---

## 3. Screens

Each screen lists its state (read-only unless marked **rw**, meaning bindable)
and its actions.

### 3.1 Home: `HomeView(model: HomeViewModel)` (tab)

**State**

| Property | Type | Notes |
|---|---|---|
| `protection` | `ProtectionState` | `.setupNeeded`, `.protecting(blockedCount:)`, `.unlocked(appName:until:)`, `.studying(name:until: Date?)`, `.emergency(until:)`, `.detached`. Drives the big status card. |
| `companion` | `CompanionSnapshot` | The Bobbly header. |
| `activeUnlocks` | `[ActiveUnlock]` | Soonest first. Show countdowns and a "Lock again" button. |
| `unlocksToday` | `Int` | |
| `freeUnlocksLeft` | `Int` | Unlocks left before one costs a life. |
| `interruptionsToday` | `Int` | Blocked attempts today. |
| `screenMinutesToday` | `Double?` | Shortcuts engine only. When `nil`, embed the report (below). |
| `quickActions` | `[HomeQuickAction]` | `.talkToBobbly`, `.startStudy`, `.editBlockedApps`, `.search`, `.emergency`. Each has `title` and `systemImage`. |
| `engineKind` / `engineLabel` | `EngineKind` / `String` | |
| `greeting` | `String` | "Good morning", etc. |
| `showsTodayReport` | `Bool` | When true, embed `DeviceActivityReport(model.todayReportContext, filter: model.todayReportFilter)`, which renders `TodaySummaryView` (§5). |

**Actions:** `onAppear()`, `refresh()`, `perform(_ action: HomeQuickAction)`,
`relock(_ unlock: ActiveUnlock)`, `openCompanion()`, and `openSetup()` (for the
`.setupNeeded` card).

### 3.2 Chat: `ChatView(model: ChatViewModel)` (tab)

**State**

| Property | Type | Notes |
|---|---|---|
| `messages` | `[ChatMessage]` | Oldest first. A `ChatMessage` has `id`, `sender: ChatSender` (`.bobbly`, `.user`, `.system`), `text`, `style: ChatMessageStyle` (`.normal`, `.decision`, `.warning`, `.commitment` for the sentence to copy), and `timestamp`. |
| `quickReplies` | `[QuickReply]` | Chips under the last message. Each has `id`, `title`, `kind`. Send the tap to `select(_:)`. |
| `isBobblyTyping` | `Bool` | Show the typing-indicator bubble. |
| `draft` | `String` **rw** | Text field. |
| `acceptsFreeText` | `Bool` | When false, hide or disable the input bar. |
| `inputPlaceholder` | `String` | |
| `canSend` | `Bool` | Enables the send button. |
| `cooldown` | `ChatCooldown?` | `startedAt`, `endsAt`, `totalSeconds`, `remainingSeconds(at:)`, `progress(at:)` (0–1). Draw a countdown ring with `TimelineView`. The model finishes the cooldown by itself. |
| `commitmentPhrase` | `String?` | The sentence to type. It's also posted as a `.commitment` bubble. |
| `outcome` | `ChatOutcome?` | See the cases below. |
| `target` | `ChatTarget?` | `subject`, `displayName`, `origin` (`.chatTab`, `.gate`, `.shield`, `.studyEnd`), `reopenURL`. Header: use `Label(token)` for `.application`. |
| `phase` | `ChatPhase` | Informational. |
| `companion` | `CompanionSnapshot` | Bobbly's avatar mood in the header. |
| `needsAppSelection` | `Bool` **rw** | FamilyControls only. Bind `.familyActivityPicker(isPresented: $model.needsAppSelection, selection: $model.appSelection)` and offer a confirm/cancel bar that calls `confirmAppSelection()` or `cancelAppSelection()`. |
| `appSelection` | `FamilyActivitySelection` **rw** | |
| `hasConversation` | `Bool` | |

`ChatOutcome` cases. Show each as a result card:

- `.granted(appName:minutes:until:costLife:reopenURL:)`: offer "Open <app>" via
  `openURL(reopenURL)` when it's non-nil.
- `.studyEnded(name:)`
- `.declined`: celebrate.
- `.emergency`: the model has already opened the Emergency sheet.
- `.failed(message:)`

**Actions:** `onAppear()` (starts a conversation if the transcript is empty),
`start(target:)`, `send()`, `select(_ reply: QuickReply)`, `reset()`,
`confirmAppSelection()`, `cancelAppSelection()`, `openEmergency()`.

### 3.3 Gate: `GateView(model: GateViewModel)` (full-screen cover)

This is the block screen opened by `bobbly://gate?app=…` (Shortcuts engine).
Show Bobbly's face, a "Talk to Bobbly" button and a "Go back" button.

**State**

| Property | Type | Notes |
|---|---|---|
| `target` | `ChatTarget` | |
| `appName` | `String` | |
| `headline` | `String` | e.g. "Instagram is blocked" |
| `message` | `String` | The supporting line. |
| `decision` | `AccessDecision` | `.allowed(reason)` or `.blocked(.blockedApp / .studySession(whitelistName:))`. |
| `isAllowedNow` | `Bool` | When true, show "Open <app>" using `reopenURL` instead of "Talk to Bobbly". |
| `unlockedUntil` | `Date?` | |
| `unlocksToday` | `Int` | |
| `companion` | `CompanionSnapshot` | |
| `reopenURL` | `URL?` | |

**Actions:** `onAppear()` (logs one interruption), `refresh()`, `talkToBobbly()`,
`goBack()`, `openEmergency()`.

### 3.4 Emergency: `EmergencyView(model: EmergencyViewModel)` (sheet)

There are two hold-to-confirm buttons, each held for 10 seconds.

**State**

| Property | Type | Notes |
|---|---|---|
| `durationOptions` | `[Int]` | Minutes: 15, 30, 60, 120, 240. |
| `selectedMinutes` | `Int` **rw** | |
| `holdDuration` | `TimeInterval` | 10. |
| `holdingAction` | `EmergencyAction?` | `.unblock` or `.detach`, whichever is being held. |
| `holdProgress` | `Double` | 0–1, updated every 50 ms while holding. Fill the button with it. |
| `isEmergencyActive` / `emergencyUntil` | `Bool` / `Date?` | When active, show a countdown and "End now". |
| `isDetached` | `Bool` | When true, show "Turn Bobbly back on". |
| `detachPhase` | `DetachPhase` | `.idle`, `.working`, `.finished(DetachReport)`. Show `report.manualSteps` as a numbered list. |
| `detachExplanation` | `[String]` | What detach does under the current engine. Show it before the user holds. |
| `engineKind` | `EngineKind` | |
| `errorMessage` / `confirmation` | `String?` | |
| `siriPhrases` | `[String]` | |
| `deepLink` | `String` | `bobbly://emergency` |

**Actions:** `onAppear()`, `beginHold(_ action: EmergencyAction)` (on finger
down), `cancelHold()` (on finger up before it completes), `endEmergencyNow()`,
`reattach() async`.

Implement the press with
`DragGesture(minimumDistance: 0).onChanged { … beginHold }.onEnded { … cancelHold }`
or `onLongPressGesture(minimumDuration: 10, pressing:)`. Let the model do the
timing either way. `beginHold` is idempotent while a hold is running.

### 3.5 Stats: `StatsView(model: StatsViewModel)` (tab)

**State**

| Property | Type | Notes |
|---|---|---|
| `range` | `StatsRange` **rw** | `.week` or `.month`, each with `title` and `days`. Changing it refreshes. |
| `dataSource` | `StatsDataSource` | `.screenTimeReport` (FamilyControls) or `.shortcutsLog`. |
| `reportContext` / `reportFilter` | | With `.screenTimeReport`, embed `DeviceActivityReport(model.reportContext, filter: model.reportFilter)` for the usage charts. It renders `TotalActivityView` (§5). |
| `dailyTotals` | `[StatsPoint]` | Shortcuts only. All apps, one point per day. |
| `dailyPerApp` | `[StatsPoint]` | Shortcuts only. Stacked bars, series = `appName`. |
| `topApps` | `[AppUsageSummary]` | Shortcuts only. |
| `totalMinutes`, `averageMinutesPerDay`, `timeSavedMinutes` | `Double` | Shortcuts only. Zero under FamilyControls. |
| `blockedInterruptions` | `Int` | Both engines. |
| `dailyInterruptions` | `[StatsPoint]` | `minutes` holds the count here. |
| `unlocksGranted`, `unlocksDeclined`, `emergencyUnlocks` | `Int` | |
| `focusMinutes` | `Int` | Study time in the range. |
| `currentStreak`, `bestStreak` | `Int` | |
| `dateInterval` | `DateInterval` | |
| `isEmpty` | `Bool` | Show the empty state. |

**Actions:** `onAppear()`, `refresh()`, `openSearch()`.

### 3.6 Search: `SearchView(model: SearchViewModel)` (sheet)

**State**

| Property | Type | Notes |
|---|---|---|
| `query` | `String` **rw** | Updates `suggestions` live. |
| `suggestions` | `[String]` | Shortcuts only. |
| `preset` | `SearchDatePreset` **rw** | `.today`, `.last7Days`, `.last30Days`, `.custom`; each has `title`. |
| `startDate`, `endDate` | `Date` **rw** | Call `datesChanged()` after the user edits a DatePicker. |
| `dateInterval` | `DateInterval` | |
| `dataSource` | `StatsDataSource` | |
| `result` | `AppUsageSearchResult?` | Shortcuts. Show total, average per day, longest session, opens per day, and a per-day bar chart from `result.daily`. |
| `hasSearched` | `Bool` | Use it to tell "no results" apart from "not searched yet". |
| `pickerSelection` | `FamilyActivitySelection` **rw** | FamilyControls. Bind `.familyActivityPicker(isPresented: $model.isPickerPresented, selection: $model.pickerSelection)`, then call `applyPickerSelection()` when it closes (e.g. `.onChange(of: model.isPickerPresented)`). |
| `isPickerPresented` | `Bool` **rw** | |
| `pickedAppCount` | `Int` | |
| `reportFilter` | `DeviceActivityFilter?` | When non-nil, embed `DeviceActivityReport(model.reportContext, filter: filter)`. It renders `AppSearchReportView` (§5). |

**Actions:** `onAppear()`, `search()`, `select(suggestion:)`, `datesChanged()`,
`presentPicker()`, `applyPickerSelection()`, `clear()`.

### 3.7 Study: `StudyView(model: StudyViewModel)` (tab) and `WhitelistEditorView(model: StudyViewModel, whitelistID: UUID?)` (sheet)

**State**

| Property | Type | Notes |
|---|---|---|
| `whitelists` | `[WhitelistSummary]` | `id`, `name`, `appCount`, `categoryCount`, `webDomainCount`, `allowedAppNames` (Shortcuts), `updatedAt` |
| `selectedWhitelistID` | `UUID?` **rw** | |
| `durationOptions` | `[StudyDuration]` | `.minutes(25/50/90)` or `.untilStopped`; each has `title`, `id`, `minutes?`. |
| `selectedDuration` | `StudyDuration` **rw** | |
| `activeSession` | `ActiveStudySession?` | `whitelistName`, `startedAt`, `endsAt?`, `remaining(at:)`, `elapsed(at:)`, `progress(at:)` |
| `isSessionRunning`, `canStart` | `Bool` | |
| `draft` | `WhitelistDraft?` **rw** | The editor binds to it: `name`, `selection` (FamilyActivityPicker), `allowedAppKeys: Set<String>` (Shortcuts), `isValid`. |
| `isPickerPresented` | `Bool` **rw** | Bind to `.familyActivityPicker(isPresented:selection: <binding to draft.selection>)`. |
| `trackedApps` | `[TrackedAppRow]` | Shortcuts editor. Toggle rows with `toggleAllowed(appKey:)`. |
| `engineKind` | `EngineKind` | |
| `errorMessage` | `String?` | |
| `alwaysAllowedNote` | `String` | |

**Actions:**

- Whitelists: `onAppear()`, `refresh()`, `newWhitelist()`, `edit(_ id:)`,
  `toggleAllowed(appKey:)`, `saveDraft() -> Bool` (true means close the
  editor), `cancelDraft()`, `delete(_ id:)`.
- Sessions: `startSession()`, and `requestEndEarly()`, which opens the Chat tab
  so Bobbly decides.

Open the editor with `env.router.present(.whitelistEditor(whitelistID:))`. Its
`onAppear` calls `edit(id)` or `newWhitelist()` when `draft == nil`.

### 3.8 Companion: `CompanionView(model: CompanionViewModel)` (sheet)

This sheet shows a large Bobbly drawn with SwiftUI shapes in `Bobbly/UI/`, with
no image assets.

**State:**

- `snapshot: CompanionSnapshot`
- `speech: String` (the speech bubble)
- `petCount: Int` (bounce when it changes)
- `rules: [String]`
- `freeUnlocksPerDay: Int`
- `timeUntilReset(at:)`

**Actions:** `onAppear()`, `pet()`.

Reuse the same Bobbly character component everywhere: Home header, Chat
avatar, Gate, Companion and Tutorial. Its expression comes from
`CompanionMood`, plus `mood` for subtle variations.

### 3.9 Blocked apps: `BlockedAppsView(model: BlockedAppsViewModel)` (sheet; also opened from the tutorial)

**State**

| Property | Type | Notes |
|---|---|---|
| `engineKind` | `EngineKind` | FamilyControls shows the picker UI; Shortcuts shows tracked apps and the catalog. |
| `canUsePicker` | `Bool` | |
| `selection` | `FamilyActivitySelection` **rw** | Bind `.familyActivityPicker(isPresented: $model.isPickerPresented, selection: $model.selection)`. |
| `isPickerPresented` | `Bool` **rw** | |
| `selectionSummary` | `String` | e.g. "4 apps · 1 category". Show the picked apps with `ForEach(Array(model.selection.applicationTokens), id: \.self) { Label($0) }`. |
| `hasUnsavedChanges` | `Bool` | Enables Save. |
| `trackedApps` | `[TrackedAppRow]` | Shortcuts. |
| `catalogQuery` | `String` **rw** | |
| `filteredCatalog` | `[CatalogApp]` | Check `isTracked(_:)` for each. |
| `customName`, `customScheme` | `String` **rw** | The custom-app form. |
| `limitOptions` | `[Int]` | Minutes; 0 means none. |
| `errorMessage`, `savedMessage` | `String?` | |

**Actions:** `onAppear()`, `presentPicker()`, `saveSelection()`, `add(_ app: CatalogApp)`,
`addCustomApp()`, `remove(_ row:)`, `setBlocked(_ row:, _ blocked: Bool)`,
`setLimit(_ row:, minutes:)`.

### 3.10 Permissions tutorial: `PermissionsTutorialView(model: PermissionsTutorialViewModel)` (full-screen cover)

This is a paged view with one step per page. Each step shows its live status
(✅ or ❌), with no surveys.

**State**

| Property | Type | Notes |
|---|---|---|
| `steps` | `[TutorialStep]` | Only the visible steps. See the field list below. |
| `currentIndex` | `Int` **rw** | Bind it to a paged `TabView(selection:)`. Steps are tagged by index. |
| `currentStep` | `TutorialStep?` | |
| `isFirstStep`, `isLastStep` | `Bool` | |
| `progress` | `Double` | |
| `completedCount` | `Int` | |
| `isWorking` | `Bool` | Disable buttons and show a spinner. |
| `isBlockedAppsPresented` | `Bool` **rw** | Present `BlockedAppsView(model: env.makeBlockedAppsViewModel())` from inside the cover. |
| `isWhitelistEditorPresented` | `Bool` **rw** | Present `WhitelistEditorView(model: env.study, whitelistID: nil)`. |
| `isEmergencyPresented` | `Bool` **rw** | Present `EmergencyView(model: env.makeEmergencyViewModel())`. |
| `catalogQuery` | `String` **rw** | Shortcuts step. |
| `catalog` | `[CatalogApp]` | Shortcuts step. Check `isTracked(_:)` for each. |
| `expandedCatalogAppID` | `String?` **rw** | Shortcuts step. |
| `automationSteps(for: CatalogApp)` | `[String]` | Shortcuts step. |
| `automationRunCount` | `Int` | Shortcuts step. |

`TutorialStep` fields:

- `id: TutorialStepID`: `.trustDeveloper`, `.screenTime`, `.notifications`,
  `.pickApps`, `.shortcutsFallback` (shown only on the fallback engine),
  `.emergency`
- `number`, `title`, `body`, `systemImage`
- `instructions: [String]`
- `status: StepStatus`: `.complete` ✅, `.incomplete` ❌, `.optional`,
  `.checking`
- `statusText`
- `primary`, `secondary: TutorialButton?`, where each button has `title`,
  `systemImage`, `action: TutorialAction`

**Actions:** `onAppear() async` (use `.task`), `refreshStatuses() async` (also
call it when `scenePhase` returns to `.active`, since the user may come back
from Settings), `next()`, `back()`, `goTo(_ id:)`,
`perform(_ action: TutorialAction) async`, `toggleTracked(_ app: CatalogApp)`,
`finish()`. `finish()` marks the tutorial done and dismisses the cover.

### 3.11 Settings: `SettingsView(model: SettingsViewModel)` (tab)

**State**

| Property | Type | Notes |
|---|---|---|
| `dailyFreeUnlocks` | `Int` **rw** | Options: `freeUnlockOptions`. |
| `defaultEmergencyMinutes` | `Int` **rw** | Options: `emergencyMinuteOptions`. |
| `hapticsEnabled` | `Bool` **rw** | |
| `diagnostics` | `EngineDiagnostics` | `activeEngine`, `selectionState`, `authorizationStatus`, `lastAuthorizationError?`, `lastMonitoringError?`, `appGroupAvailable`, `usingFallbackDataStore`, `monitoredActivities: [String]`, `recentLog: [String]`. Show a warning row when `appGroupAvailable == false`. |
| `engineState` | `EngineSelectionState` | |
| `engineExplanation` | `String` | |
| `canRetryScreenTime` | `Bool` | |
| `isRequestingAuthorization` | `Bool` | |
| `notificationsAuthorized` | `Bool` | |
| `appVersion` | `String` | |
| `didCopyDiagnostics` | `Bool` | |

**Actions:**

- `onAppear()`, `refresh()`
- `openTutorial()` (the "Permission tutorial" row), `openEmergency()`,
  `openBlockedApps()`, `openCompanion()`
- `retryScreenTimeAccess() async`, `switchToShortcutsFallback()`
- `diagnosticsReport() -> String`, `copyDiagnostics()`

---

## 4. Shield (BobblyShieldConfig): the look is yours

`ShieldConfigurationExtension` (Core) builds a `ShieldContent` and calls your
`ShieldStyle.configuration(for: ShieldContent) -> ShieldConfiguration` in
`BobblyShieldConfig/ShieldStyle.swift`.

`ShieldContent` fields:

| Field | Type | Notes |
|---|---|---|
| `kind` | `ShieldContent.Kind` | `.blockedApp`, `.studySession(name:)`, `.website` |
| `appName` | `String?` | |
| `title` | `String` | e.g. "Instagram is blocked" or "Study time!" |
| `subtitle` | `String` | |
| `primaryButton` | `String` | "Talk to Bobbly", or "Tap the notification ↑" right after it was pressed. |
| `secondaryButton` | `String?` | "Go back" |
| `mood` | `ShieldMood` | `.thriving`, `.happy`, `.okay`, `.sad`, `.exhausted` |
| `lives` | `Int` | |
| `unlocksToday` | `Int` | |
| `freeUnlocksLeft` | `Int` | |
| `notificationRecentlySent` | `Bool` | |

Constraints:

- `ShieldConfiguration` takes UIKit values only: `backgroundBlurStyle`,
  `backgroundColor`, `icon: UIImage?`, `title`/`subtitle`/button labels as
  `ShieldConfiguration.Label(text:color:)`, `primaryButtonBackgroundColor`.
- No SwiftUI and no custom layout.
- Draw the Bobbly icon per `mood` with `UIGraphicsImageRenderer`. Keep it cheap
  and pure: the extension is short-lived and memory-limited (about 6 MB).
- Support dark mode with dynamic `UIColor`s.

---

## 5. Report extension (BobblyReport): views and inputs

These views are rendered inside the sandboxed extension. The host app embeds
`DeviceActivityReport(context, filter:)`. Swift Charts and `Label(token)` work
here. You can't use buttons that call back into the app, network, or App Group
writes.

| Context (Shared/Report) | Embedded by | Your view | Input (BobblyReport/ReportModels.swift) |
|---|---|---|---|
| `.bobblyTotalActivity` | StatsView | `TotalActivityView(configuration: TotalActivityConfiguration)` | `totalDuration`, `averagePerDay` (TimeInterval), `totalPickups`, `days: [ReportDay]` (`date`, `duration`, `pickups`; oldest first), `topApps: [ReportAppUsage]` (top 10, each with `id`, `name`, `token: ApplicationToken?`, `duration`, `pickups`, `notifications`) |
| `.bobblyAppSearch` | SearchView | `AppSearchReportView(configuration: AppSearchConfiguration)` | `query`, `dayCount`, `results: [AppSearchResultItem]` (each with `name`, `token?`, `totalDuration`, `averagePerDay`, `totalPickups`, `pickupsPerDay`, `busiestDay?`, `busiestDayDuration`, `daily: [ReportDay]`). DeviceActivity has no per-session data, so show the busiest day in place of "longest session". |
| `.bobblyTodaySummary` | HomeView | `TodaySummaryView(configuration: TodaySummaryConfiguration)` | `totalDuration`, `pickups`, `topApps` (3) |

Use `ReportFormat.duration(_:)` for "2h 05m" style strings. The report view's
height is set by the host's `.frame`. Pick sensible fixed heights in the host
views.

---

## 6. Implementation status (phase 2)

Core's notes. Everything from the phase 1 "Stubbed" list is now implemented.
What remains can only be confirmed on a real device or by the first CI run.

**Done in phase 2**

- **Re-locking (FamilyControls).** Every timed state (unlock, emergency, timed
  study) registers a one-shot DeviceActivity *trigger* whose interval **starts**
  when the state ends. This follows the developer-forum pattern for windows
  under 15 minutes: start/end use time-only components, which are the ones
  reported to fire reliably. The monitor finishes the state in
  `intervalDidStart` (`MonitorLogic`, unit-tested), then re-applies shields with
  `ShieldPolicy.reconcile`. The app also reconciles and re-creates missing
  triggers on every foreground.
- **Shortcuts engine.** Unlocks expire lazily at the next `CheckAccessIntent`.
  Local notifications fire "1 minute left" and "locked again" for unlocks, and
  when an emergency or a timed study session ends.
- **Multi-app unlocks** (chat-tab picker under FamilyControls) count as one
  unlock: one counter increment, one UnlockEvent, one life check.
- **Passive focus.** Protected time with no unlock running raises mood by 1 per
  15 minutes, up to +16 a day. It's credited on launch and on every foreground.
- **Gate and chat "said no" bonus** is rate-limited: once per 10 minutes, at
  most 6 times a day.
- **Daily limits (Shortcuts engine).** If the app is already past its daily
  limit, the grant is halved, Bobbly warns, and the unlock costs a life even
  within the free unlocks.
- **Emergency modal stacking.** `env.presentSheet(_:)` dismisses any cover first.
  Gate, Chat and the `bobbly://emergency` link use it.
- **Study sessions.** Timed sessions that ended while Bobbly was closed are
  closed in SwiftData and credited on the next foreground.
- **Manual engine choice.** Settings › "Use Shortcuts" persists until "Retry
  Screen Time access".
- **Review fixes:**
  - **Unreadable shared state:** extensions never unshield on an unreadable
    App Group (`ShieldPolicy.action`).
  - **Revoked access:** revoking Screen Time voids the saved tokens. The block
    list is cleared and whitelists are flagged `needsRepick`.
  - **Interruption counting:** each blocked attempt counts once (Check Access
    plus Gate, or both shield buttons), and shield counts are kept per day.
  - **Detach:** both the in-app and the Siri detach use one rule
    (`DetachRule`) and clear every Bobbly notification. A study session
    closed by a detach ends early with no bonus.
  - **Triggers:** each emergency and study trigger has a unique name.
  - **SwiftData store:** pinned to the app container (`groupContainer: .none`).
  - **Study whitelists:** whitelisted apps stay usable even if they're also
    on the block list.

**Still unverified (device / CI)**

- **Shield hand-off on device.** It's unknown whether the shield-config
  extension can write the app's name to the App Group (`lastShieldedApp`). If it
  can't, names fall back to "this app"; the hand-off works either way.
- **Report search query.** The name query in `reportSearchQuery` is best effort.
  The token filter is the reliable path.
- **Whitelist categories.** These are exempted because of
  `FamilyActivitySelection(includeEntireCategory: true)`, an API confirmed in
  Apple's docs. Whether that expansion includes apps installed later is
  unknown.
- **Daily limits under FamilyControls.** Time limits aren't wired to
  `DeviceActivityEvent` thresholds. FamilyControls blocks apps outright;
  per-app limits apply to the Shortcuts engine.
- **Intents** take a plain `String` app name. That's the most robust option for
  Shortcuts automations.
- **CI** has not run yet.

---

## Contract changes

- **2026-10-21: additive only, no breaking changes.**
  - `AppEnvironment.presentSheet(_ route: SheetRoute)` is new. Use it instead of
    `router.present(_:)` when a full-screen cover might be showing; it dismisses
    the cover, then presents.
  - `ChatViewModel.needsAppSelection`: when the picker closes (`false`), the
    pending grant is confirmed automatically if apps were picked and cancelled
    otherwise. `appSelection` now starts empty, never pre-filled with the
    block list. Calling `confirmAppSelection()` or `cancelAppSelection()` still
    works.
  - Settings › `switchToShortcutsFallback()` now persists across launches until
    `retryScreenTimeAccess()`.

- **2026-10-21 (review fixes): additive only, no breaking changes.**
  - `HomeViewModel` has new separate counts: `blockedAppCount`,
    `blockedCategoryCount` and `blockedWebsiteCount`. `.protecting(blockedCount:)`
    still carries the total.
  - `HomeViewModel.needsAppRepick: Bool` is true after Screen Time access was
    revoked (detach, or turned off in iOS Settings). The saved app picks are
    void, so show a "Pick your apps again" call to action that calls
    `perform(.editBlockedApps)`. `protection` is `.setupNeeded` in that state.
  - `StatsViewModel.openTutorial()` and `BlockedAppsViewModel.openTutorial()` are
    new. Use them instead of calling `env.router.presentTutorial()` from views.
  - `WhitelistSummary.needsRepick: Bool` is new and defaults to `false`. When
    it's true, show "Pick apps again", which calls `edit(id)`. Under
    FamilyControls, `startSession()` refuses such a whitelist and sets
    `errorMessage`.
  - **Router:**
    - `router.present(_:)` now dismisses a full-screen cover first and shows
      the sheet after `AppRouter.modalHandoffDelay` (450 ms).
    - `presentGate(_:)` and `presentTutorial()` likewise dismiss an open sheet
      first.
    - `showTab(_:)`, `dismissSheet()` and `dismissCover()` cancel a pending
      hand-off.
    - In tests or previews, a modal requested while another is open appears
      only after the delay.
  - `EmergencyViewModel.cancelHold()` is now a no-op once the hold has
    completed. Releasing the finger can no longer cancel a running unblock or
    detach.
  - `ChatViewModel.onAppear()` only starts a new conversation when
    `phase == .idle`, so it no longer wipes a gate- or shield-targeted chat.
