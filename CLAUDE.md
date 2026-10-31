# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Millisalary, the app that shows your salary being earned in real time, rewritten natively in Swift for macOS. It replaces the Electron + React app in `../electron-millisalary` (~273 MB, most of it the Electron framework, and most of its UI work went into faking macOS controls in CSS). That app's `CLAUDE.md` is the behaviour spec: what isn't ported yet is described there. Treat `../electron-millisalary` as a read-only reference: never edit, build or commit there (reading it, or bundling its TypeScript into a temporary folder as the parity script does, is fine).

The user writes in Ukrainian: answer in Ukrainian. Code, comments, commit messages and this file stay in English.

## Commands

```bash
xcodegen generate                       # (re)generate Millisalary.xcodeproj from project.yml; after adding files too
xcodebuild -project Millisalary.xcodeproj -scheme Millisalary -derivedDataPath build/DerivedData build
xcodebuild -project Millisalary.xcodeproj -scheme Millisalary -derivedDataPath build/DerivedData test
swift test --package-path Packages/MillisalaryCore   # the same tests without Xcode, in seconds
open build/DerivedData/Build/Products/Debug/Millisalary.app
scripts/parity/generate-fixtures.sh     # regenerate the parity fixture from the Electron app's TypeScript
```

- XcodeGen (`brew install xcodegen`, 2.46) is required: `Millisalary.xcodeproj` and `Millisalary/Info.plist` are generated and gitignored, `project.yml` is the source of truth (build settings, Info.plist keys, the package dependency, the scheme). Files in `Millisalary/` are picked up by folder, but only after `xcodegen generate`.
- Release: `-configuration Release`; the app is in `build/DerivedData/Build/Products/Release/` (~0.6 MB). There is no packaging or release script yet.
- Commit with the repo-local git identity (`nalezhytyi`, set in `.git/config`), not the global work identity. Conventional Commits with a lowercase scope, e.g. `feat(tray): …`, `fix(core): …`.
- There is no remote. Never create a GitHub repository, add a remote or push without the user's explicit approval for that specific action.

## Structure

- `Packages/MillisalaryCore/` — a local Swift package with everything that doesn't need AppKit: the earnings model, settings schema and validation, money formatting, the menu bar's text. Pure and unit-tested; the app depends on it (`packages:` in `project.yml`), and the scheme's test action runs its tests.
  - `Earnings.swift` — `EarningsModel` (`calculations.ts`): `earnings(at:_:)`, `workingWindow(on:_:)`, `isScheduledDay(_:workingDays:)`, `paydayInMonth(of:payday:)`, `nextPayday(from:payday:)`, plus `Period`, `EarningsSettings`, `WorkdaySettings`, `EarningsSnapshot`.
  - `Settings.swift` — `Settings` (`settings.ts`): the same 15 keys, values and defaults as the Electron app's `settings.json`; `Settings(sanitizing:)` / `applying(_:)` / `apply(_:for:)` are `sanitizeSettings` / `sanitizePatch` / one validator, `propertyList` is the way back, `workday` / `earningsSettings(exchangeRate:)` feed the model.
  - `SalaryForm.swift` — `normalizeWorkingDays`, `normalizePayday`, `normalizeWorkingHoursPerDay` and the defaults (8 hours, 22 days), from `salaryForm.ts`. Its coupled Start/End/hours helpers (`getEndHourFromStart`, `getNext*`, `calculateWorkingHoursPerDayValue`) and `settingsDraft.ts` are not ported yet: they belong with the settings pane.
  - `TimeOfDay.swift` — a wall-clock time; `TimeOfDay(parsing:)` / `formatted` are `parseTimeInputValue` / `formatTimeInputValue` for the `"HH:mm"` strings the settings keep.
  - `CurrencyFormat.swift` — `formatCurrency` (`uk_UA`, narrow symbol, plain spaces: `54 321,00 ₴`). `formatCurrencyParts` (the dial) is not ported yet.
  - `MenuBarContent.swift` — the menu bar title and amount rows (`getTitle` / `getAmountLabels` in `tray.ts`).
- `Millisalary/` — the app target (Swift 6, default actor isolation `MainActor`).
  - `MillisalaryApp.swift` — the SwiftUI `App` (an empty `Settings` scene for now) and `AppDelegate`, which creates the store and the status item.
  - `SettingsStore.swift` — `@Observable`, reads `UserDefaults.standard`, one value per settings key, always through `Settings(sanitizing:)`; KVO on the keys picks up changes from anywhere, `defaults write` in Terminal included. Nothing writes settings yet.
  - `StatusItemController.swift` — the menu bar item, see below.
  - `Clock.swift` — `Clock.now`, which Debug builds can shift (Testing).
- `scripts/parity/` — `fixtures.ts` and `generate-fixtures.sh`, which write `Packages/MillisalaryCore/Tests/MillisalaryCoreTests/Fixtures/parity.json`.

## The port and its parity

The Swift model must give the Electron app's numbers, so the TypeScript is the oracle. `generate-fixtures.sh` bundles `fixtures.ts` with the esbuild in `../electron-millisalary/node_modules/.pnpm/esbuild@*/` (aliasing `@ref` to its `src/shared`, resolving `dayjs` from its `node_modules`) into a temporary folder and runs it with node. The fixture holds 2610 `calculateEarnings` / `getWorkingWindow` / `isScheduledDay` results (15 schedules: overnight, no end time, same start and end, fractional hours and days, 24-hour days, a rate, no salary; at edge instants plus 20 seeded random ones over 2026–2028; in Europe/Kyiv, America/New_York and Asia/Kolkata), every payday 1–31 for 13 months, 256 `formatCurrency` results (8 currencies, 2 and 4 digits, half-way amounts), the normalizers (NaN and the infinities included), time strings and 22 raw settings objects through `sanitizeSettings`. `ParityTests.swift` compares money **exactly**, not with a tolerance. The fixture is committed, so the tests don't need node; regenerate it only when the reference changes, and keep the edge cases.

What makes the results equal to the bit, keep it when changing the model:

- Times are whole milliseconds as `Double`, like a JS `Date` (`epochMilliseconds`); `earnings(at:)` rounds `now` to a millisecond first. The arithmetic runs in the TypeScript's order (`millisecondSalary * 3600 * 1000`, not `* 3_600_000`).
- Each dayjs call maps to a `Calendar` call in the model's calendar (its time zone stands in for the local one): `startOf('day' | 'month' | 'hour')`, `add(n, 'day')` keeps the wall-clock time, `day()` is 0 for Sunday, `diff(…, 'day')` corrects for a change of UTC offset and truncates.
- `atMinutes` mirrors `startOf('day').hour(h).minute(m)`: the hour can run past 23 into the next day (a missing end time is start + hours/day, e.g. 20:00 + 9.5 h is 05:30 next morning) and fractional minutes are truncated (09:00 + 8.33 h ends at 17:19, not 17:19:48). When the end isn't after the start, the end is start + hours/day in milliseconds, truncated like a JS `Date`.
- `workingDays` is a `Double` and stays fractional (the Electron validator doesn't round it); `payday` is an `Int` (it does).
- `formatCurrency` rounds half away from zero (`.toNearestOrAwayFromZero`), as `Intl.NumberFormat` does; Foundation's default is half-even. Both format the shortest decimal of the double, so `1.005` gives `1,01`.
- The validators treat an `NSNumber` boolean as not a number and a number as not a boolean (`CFBooleanGetTypeID`), like `typeof`.
- Read JSON numbers with `JSONDecoder`, not `JSONSerialization`: the latter returns long decimals as `NSDecimalNumber`, whose `doubleValue` is off in the last bits (it broke the first test run). That matters for a future import of the Electron app's `settings.json` too.
- Not covered: a start or end time inside a DST gap or overlap (03:00–04:00 in Kyiv on the last Sundays of March and October). JS moves a missing local time forward and picks the first of a repeated one; `Calendar` may differ. Those are Sundays, which aren't paid, so only `rates` could differ.

## Decisions

All taken on 2026-10-31.

- **XcodeGen** over a hand-made `.xcodeproj` or SwiftPM with a bundling script (the user's choice): a readable, diffable spec that `xcodebuild` builds, with asset catalogs, Info.plist keys and SPM dependencies (Sparkle later) handled by Xcode.
- **macOS 14** deployment target (the user's choice): `@Observable`, `SettingsLink`, `SMAppService`, `MenuBarExtra`. Newer APIs (Liquid Glass, `glassEffect`, macOS 26) go behind `if #available`; on newer systems the native look comes by itself. Built with Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.
- **Swift Testing** for tests. Swift 6 language mode; the app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so app code is main-actor by default (`DefaultsObserver` opts out with `nonisolated`).
- **Bundle IDs**: Release is `com.nalezhytyi.millisalary`, the Electron app's, so the native app is its successor (same login item and notification identity, installs over it). Debug is `com.nalezhytyi.millisalary.debug`, so a dev build never shares settings, notifications or the login item with an installed copy.
- **Signing**: ad hoc (`CODE_SIGN_IDENTITY = -`) with the hardened runtime, not notarized; there is no Developer ID. Not sandboxed, like the Electron app (no App Store; a sandbox would keep the app from reading the Electron app's `settings.json` for an import).
- **Settings in UserDefaults**, one value per key under the `settings.json` names, rather than a JSON file: native, inspectable with `defaults read`, editable with `defaults write`, and SwiftUI can bind to it later. Everything read goes through the ported validator.
- **NSStatusItem**, not SwiftUI's `MenuBarExtra`: the title needs `monospacedDigitSystemFont` (like Electron's `fontType: 'monospacedDigit'`), and an AppKit menu can update its rows while open (the timer runs in the run loop's common modes, so the amounts tick inside the open menu, which the Electron app couldn't do: it only rebuilt its menu while closed).
- **Menu bar only for now** (`LSUIElement`): there is no window yet. When the main window arrives, drop `LSUIElement` (the Electron app has a Dock icon and its window) and honour `showInMenuBar`, which is ignored until then since hiding the item would leave nothing on screen.
- **No exchange rate yet**: amounts are shown in the salary's own currency (rate 1), so a USD salary shows `$` even though `earningsCurrency` defaults to UAH. The Electron app falls back to rate 1 too, but labelled in the earnings currency, and only until its first fetch.

## Menu bar item

`StatusItemController` shows the template icon (`MenuBarIcon` in `Assets.xcassets`, the Electron app's `trayTemplate.png` / `@2x`, 16 pt) with the amount as the button title in monospaced digits, refreshed by a 1 s timer (0.1 s tolerance) and immediately when the settings change (`withObservationTracking`). Before a salary is set it shows the icon alone. The menu lists This hour / Today / This week / This month / This year with their amounts (rows without an action: the Electron app's open its Breakdown, which doesn't exist yet), a separator and Quit Millisalary (⌘Q); with no salary a disabled "No salary set" row stands in for the amounts. Titles and rows are only touched when their text changed, the menu is only rebuilt when the number of rows changes. The Electron app's Open Millisalary, Settings… and Check for Updates… items come with those features.

## Testing

- `swift test --package-path Packages/MillisalaryCore` runs the parity and unit tests (14, under a second); `xcodebuild … test` runs the same through the scheme.
- The dev build keeps its settings in the `com.nalezhytyi.millisalary.debug` domain: `defaults write com.nalezhytyi.millisalary.debug monthlySalary -float 54321` (and `monthlySalaryCurrency UAH`, `menuBarAmount selected`, `selectedPeriod year`, …) changes a running app within a second; `defaults delete com.nalezhytyi.millisalary.debug` resets it. Delete what you wrote when you're done testing.
- Debug-only launch arguments (read through the UserDefaults argument domain, compiled out of Release): `-debugNow "2026-10-29 13:30"` starts the clock at that local time and lets it run, so a weekend can show a weekday ticking (weekends earn nothing). It's a date and not an offset because a negative offset (`-debugTimeShift -205200`, tried first) was ignored: a value starting with `-` reads as another flag. `-debugStatusItemSnapshot <path.png>` draws the status button into a PNG on every title change.
- Why the snapshot: on a Mac with a notch, macOS 27 hides status items that don't fit right of the notch behind a `«` overflow, and this Mac's menu bar is full, so a new item is hidden as soon as it has a title (even a high `NSStatusItem Preferred Position` didn't bring it out). Reading it otherwise needs Accessibility (System Events) or the item to be visible for `screencapture`, which does work without a prompt here. The PNG is white text on transparent in a dark menu bar: composite it on a dark colour to look at it. The menu itself can only be checked by clicking it.
- E.g. `open -n build/DerivedData/Build/Products/Debug/Millisalary.app --args -debugNow "2026-10-29 13:30" -debugStatusItemSnapshot /tmp/item.png`, then copy the PNG twice a few seconds apart: the amount must grow (54 321 a month over 22 days of 8 h is 0.0857 a second) while the comma and the symbol stay put.

## Not ported yet

In the Electron app's `CLAUDE.md`: the main window with its sidebar (Earnings periods with the animated dial, Breakdown, Settings), the settings pane and its coupled Start/End/hours fields, the end-of-day and payday notifications (`shared/notifications.ts`; natively UserNotifications scheduled ahead), the login item (`SMAppService`) with the start-at-login detection, the exchange rate (exchangerate-api.com, cached per pair, retried with backoff, refreshed every 6 h and on wake; natively `URLSession`), the update check (GitHub releases; Sparkle is the usual native updater), Amplitude analytics (a native Swift SDK exists; whether Session Replay works for native macOS apps is unverified, and every amount on screen must be masked if it's used), the app icon and the animated money face (`public/images/money-face.webp`, 150 frames at 20 ms, and the static `money-face.png` that is the icon master), and packaging (dmg, release script).
