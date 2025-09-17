# Repository Guidelines

## Project Structure & Module Organization
DiskSpaceSwiftUI ships as a Swift Package macOS app. Core code sits in `Sources/`, with `main.swift` wiring the SwiftUI scene, `DashboardView.swift` and `DashboardComponents.swift` composing the UI, `DashboardViewModel.swift` orchestrating state, and `Scanner.swift` providing the concurrent filesystem engine. Shared helpers such as `DateFormatter+HM.swift` live alongside feature files. Build scripts (`build-app.sh`, `sign_notarize.sh`) stay at the repository root; keep any new assets or resources co-located with the code that consumes them.

## Build, Test, and Development Commands
- `swift build` — compile the package in debug mode; use `--product DiskSpaceSwiftUI` to target the app explicitly.
- `swift run DiskSpaceSwiftUI` — launch the app from the command line for quick iteration.
- `swift build -c release` followed by `./build-app.sh` — produce an optimized build and assemble the `.app` bundle.
- `swift test` — execute the XCTest suite; add `--filter ScannerTests` (example) to focus on a target.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines with four-space indentation. Use `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and keep extensions namespaced (e.g., `DateFormatter+HM.swift`). Mirror existing property wrappers (`@Published`, `@AppStorage`) and prefer value types (`struct`) for view models unless reference semantics are required. Document non-obvious logic with concise inline comments and keep public APIs marked `internal` by default.

## Testing Guidelines
Add XCTest targets under `Tests/`, mirroring the module name (e.g., `Tests/DiskSpaceSwiftUITests`). Name test cases after the component under test and the scenario (`ScannerPerformanceTests`, `DashboardViewModelStateTests`). When touching concurrency or caching, include regression tests capturing expected ordering and cache invalidation behavior. Run `swift test` before every PR and monitor console output for async expectations that may hang.

## Commit & Pull Request Guidelines
Adopt Conventional Commits as seen in history (`feat:`, `refactor(scanner):`, `docs:`). Scope commits narrowly and keep messages under 72 characters for the subject. Pull requests should include: concise summary, testing evidence (command output or screenshots), relevant issue links, and UI change captures when the dashboard layout shifts. Confirm scripts remain executable (`chmod +x`) when modified and note any notarization prerequisites.

## Security & Configuration Tips
Scanning system volumes often requires Full Disk Access; remind reviewers to enable it via System Settings > Privacy & Security before testing. Use `sign_notarize.sh` only with temporary API keys or a dedicated account, and scrub credentials from shell history. Avoid committing paths from personal home directories; prefer placeholders like `/Volumes/TestDrive`.
