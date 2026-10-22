# Bobbly

A screen-time companion for iOS 17+. Pick distracting apps; when you open one,
Bobbly (a little SwiftUI character) asks why. Good reasons get a short unlock.
Boredom gets some pushback. Emergency unblock is always free. No paywall, no
coins, no surveys.

## Features

- **Blocking.** The primary engine uses Screen Time (FamilyControls/ManagedSettings
  shields). The fallback uses Shortcuts automations, picked automatically if
  Screen Time access fails.
- **Chat to unlock.** A scripted chatbot classifies your reason:
  - work, school or messaging someone gets 5–15 minutes;
  - boredom or habit gets pushback, then a typed commitment or a 30–60 s
    cooldown;
  - each unlock that day makes it stricter.
- **Study whitelists.** Block everything except a named set of apps for a
  timed session.
- **Companion.** Mood from 0 to 100 and 3 lives a day. Unlocking past your free
  allowance costs a life. Lives come back daily.
- **Stats and search.** Daily totals, a 7- or 30-day trend, streak, time saved,
  and blocked interruptions. Search usage per app over a date range.
- **Emergency.** Unblock everything for a chosen time, or detach Bobbly
  completely. Both are behind a 10-second hold, and both are also available
  through Siri and a deep link.

## Install (sideloading)

1. Download `Bobbly.ipa` from the latest GitHub Actions run (artifact
   **Bobbly-ipa**) or from a Release.
2. Sign and install it with your sideloading tool. **Keep the entitlements,
   App Group and app extensions intact.** The IPA declares these on the app
   and on all four extensions:
   - `com.apple.developer.family-controls`
   - App Group `group.com.bobbly.shared`
3. If iOS says "Untrusted Developer", go to Settings › General › VPN & Device
   Management and trust the profile. Turn on Developer Mode if iOS asks.
4. Open Bobbly. The permission tutorial walks you through every step and
   checks each one live.

The IPA contains:

- `Payload/Bobbly.app/PlugIns/`:
  - `BobblyShieldConfig.appex`
  - `BobblyShieldAction.appex`
  - `BobblyMonitor.appex`
- `Payload/Bobbly.app/Extensions/BobblyReport.appex` (DeviceActivity reports are
  ExtensionKit-based)

### If Screen Time access fails

Some signers (for example free Apple IDs) can't keep the FamilyControls
entitlement. Bobbly detects this at launch, switches to the **Shortcuts
engine**, and shows it in Settings › Diagnostics. Nothing crashes.

## Shortcuts quick setup (iOS 26+, recommended)

One automation covers every distracting app. It has one action and needs no
typing.

1. Shortcuts › Automation › **+** › **App** › **Choose** › select every
   distracting app at once › Done.
2. Tick **Is Opened** (only) › **Run Immediately** › Next › **New Blank
   Automation**.
3. Search "Bobbly", add **Bobbly Gate**, leave App empty, and tap Done.

When one of those apps opens:

- If Bobbly allows it (an unlock is running, an emergency unblock is on, or
  Bobbly is detached), the app just opens.
- Otherwise Bobbly comes to the front with its Gate. If iOS won't allow that,
  you get a notification to tap instead.

The automation can't tell Bobbly which app opened, so your apps are treated
as one group. An unlock covers all of them. Afterwards, swipe back to your app.

Optional, for usage time in Stats and Search: add a second automation for
the same apps with **Is Closed** › **Bobbly: App Closed**. Without it, Bobbly
still counts how often you open them, under the name "Blocked apps".

You can turn quick-setup blocking off in Settings. The automation then only
tracks.

## Shortcuts per-app setup (advanced / iOS < 26)

iOS doesn't let apps create automations, so you add two personal automations
per app in the Shortcuts app. The tutorial shows these steps for each app you
pick.

1. Shortcuts › Automation › **+** › App › choose the app › **Is Opened** ›
   **Run Immediately**.
   - Add **Log App Event** (Bobbly): App = the app's name, Event = Opened.
   - Add **Check Access** (Bobbly): App = the app's name.
   - Add **If** *Check Access* is false → **Open URLs**
     `bobbly://gate?app=<AppName>`.
2. A second automation: App › same app › **Is Closed** › **Run Immediately** ›
   **Log App Event** with Event = Closed.

This is a soft block: deleting the automation bypasses it.

## Emergency procedures

| Need | How |
|---|---|
| Unblock everything for a while (free) | Home or Settings › Emergency › hold **Unblock** for 10 s, or "Hey Siri, Bobbly emergency", or open `bobbly://emergency` |
| Turn Bobbly off completely | Emergency › hold **Detach** for 10 s, or "Hey Siri, detach Bobbly" |
| Detach didn't remove Screen Time access | Settings › Screen Time › Apps with Screen Time Access › turn Bobbly off |
| Shortcuts engine leftovers | Shortcuts › Automation › delete the Bobbly automations |

Under Screen Time, detach clears every shield, stops all monitoring and revokes
authorization. Under Shortcuts, it sets a "Bobbly off" flag so every check
passes.

## How re-locking works

- **Screen Time engine.** Every unlock, emergency unblock and timed study
  session schedules a one-shot DeviceActivity trigger that starts the moment it
  ends. `BobblyMonitor` then re-applies the shields, even if Bobbly is closed.
  Bobbly also re-checks every time it comes to the foreground. Expect up to
  about a minute of delay, because DeviceActivity works in whole minutes.
- **Shortcuts engine.** An unlock simply expires. The next time the app opens,
  **Check Access** returns false. Bobbly also sends a "locked again"
  notification.
- **Study sessions.** If Bobbly itself gets shielded during a study session,
  use "Hey Siri, Bobbly emergency" or the `bobbly://emergency` link.

## Building

Nothing here builds on Windows. CI is the compiler:
`.github/workflows/build.yml` runs on `macos-latest` and does the following:

1. `xcodegen generate`
2. Unit tests on an iPhone simulator
3. Unsigned `xcodebuild archive`
4. `ldid -S<entitlements>` on every binary
5. Packages `Bobbly.ipa`
6. Verifies the extensions, the URL scheme and the entitlements

To build locally on a Mac:

```sh
brew install xcodegen
xcodegen generate
open Bobbly.xcodeproj
```

## Project layout

```
project.yml              XcodeGen spec (app + 4 extensions + tests)
Shared/Core/             App Group store, access/shield policy, activity names (all targets)
Shared/Report/           DeviceActivityReport contexts (app + report extension)
Bobbly/App/              App entry, environment, router, deep links
Bobbly/Engine/           BlockingEngine protocol, FamilyControls + Shortcuts engines, companion rules
Bobbly/Data/             SwiftData models, usage tracker + aggregation
Bobbly/Intents/          App Intents (Check Access, Log App Event, Emergency, Detach)
Bobbly/Chat/             ChatEngine (rules), ChatViewModel, ChatView
Bobbly/Features/         One folder per screen: <Name>ViewModel.swift + <Name>View.swift
Bobbly/UI/               Design system (theme, components, Bobbly drawing)
BobblyShieldConfig/      Shield look (ShieldContent + ShieldStyle)
BobblyShieldAction/      Shield buttons → notification hand-off
BobblyMonitor/           Re-lock when unlocks/emergency/study intervals end
BobblyReport/            Screen-time report scenes + views
BobblyTests/             ChatEngine, ShortcutsEngine/AccessPolicy, aggregation, companion, deep links
```

For the ViewModel and UI contract, see `Bobbly/CONTRACT.md`.
