import SwiftUI

// The process starts here rather than at an `@main` on MillisalaryApp, so
// that `--smoke-test` can quit before any of the app runs: no settings, no
// analytics, no NSApplication. dyld has loaded the binary and every
// framework it links by then, which is all scripts/build-dmg.sh wants to
// know (0.1.0 crashed in dyld, before any code of its own ran)
if CommandLine.arguments.dropFirst().contains("--smoke-test") {
    exit(0)
}

MillisalaryApp.main()
