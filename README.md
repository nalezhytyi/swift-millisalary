# Millisalary

Your salary, earned in real time: a macOS app that shows what you've made so far this hour, today, this week, this month and this year, ticking in the menu bar. Native Swift and SwiftUI, for macOS 14 and later; it replaces the Electron version.

## Install

Download `Millisalary-<version>.dmg` from the latest [release](https://github.com/nalezhytyi/swift-millisalary/releases/latest). It's one app for Apple Silicon and Intel Macs. Open the dmg and drag Millisalary to Applications.

The app isn't signed with an Apple Developer ID yet, so macOS blocks it the first time. Either of these opens it:

- Right-click (or Control-click) Millisalary in Applications, choose **Open**, then **Open** again in the dialog. On newer macOS versions, if there's no Open button, go to System Settings → Privacy & Security and click **Open Anyway** next to the message about Millisalary. You only do this once.
- Or remove the quarantine flag in Terminal:

  ```bash
  xattr -d com.apple.quarantine /Applications/Millisalary.app
  ```

The app is in English and Ukrainian. It follows the languages of your Mac; to run Millisalary in one of them on its own, choose it under System Settings → General → Language & Region → Applications.

If you used the Electron version, the first launch takes over its settings (salary, schedule, currencies).

"Open at login" may ask you to allow Millisalary under System Settings → General → Login Items.

The app doesn't update itself. It checks the latest release once a day and tells you when there's a newer one (or use **Check for Updates…** in the menu), and you install it the same way.

## Develop

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate                       # Millisalary.xcodeproj from project.yml
open Millisalary.xcodeproj              # or build from the command line:
xcodebuild -project Millisalary.xcodeproj -scheme Millisalary -derivedDataPath build/DerivedData build
swift test --package-path Packages/MillisalaryCore
scripts/build-dmg.sh                    # the universal Release app in build/Millisalary-<version>.dmg
swift scripts/generate-icons.swift      # regenerate the app and menu bar icons
swift scripts/check-localizations.swift # every text in the string catalogs translated
```

A Debug build is called Millisalary Dev and keeps its own settings, so it never touches an installed Millisalary. `CLAUDE.md` describes the code, the decisions behind it and how it's tested.

## Release

Bump `MARKETING_VERSION` in `project.yml`, commit, push, and run:

```bash
scripts/release.sh
```

It builds the dmg and publishes it as a GitHub release (`gh release create`) in the repository named by `MillisalaryReleasesRepo` in `project.yml`, which is also where the app looks for updates. It needs `gh` signed in as that repository's owner and an `origin` remote pointing at it, and it refuses to run with uncommitted or unpushed changes. Run it only when you mean to ship.
