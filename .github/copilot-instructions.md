# Copilot Instructions

## Project Overview

Donots is a macOS notification monitor that takes screenshots when notifications appear and emails them via Apple Mail. It consists of:

- **`donots.py`** — Standalone Python script (original prototype)
- **`donots-app/`** — Native SwiftUI macOS app (main application)

## Build, Test & Run

All commands run from `donots-app/`:

```bash
# Build release .app bundle
./scripts/build.sh

# Run the app (builds first if needed)
./scripts/run.sh

# Run all tests (native + Docker)
./scripts/test.sh

# Run native tests only
swift test

# Run a single test file
swift test --filter MonitorViewModelTests

# Run a single test
swift test --filter "MonitorViewModelTests/initialState"

# Run Docker-based pure-logic tests only
docker-compose run --rm test
```

## Architecture

### Swift App Structure (`donots-app/Sources/Donots/`)

```
App/           → Entry point (DonotsApp.swift)
Models/        → Data types (CaptureOptions, LogEntry)
Services/      → Core logic (AppleScript, Screenshot, Permissions, MonitoringActor)
ViewModels/    → UI state (MonitorViewModel)
Views/         → SwiftUI views
Utilities/     → Helpers (DateFormatting)
```

### Key Patterns

- **MVVM with Swift Observation** — ViewModels use `@Observable` macro
- **Actor isolation** — `MonitoringActor` handles polling in background; `MonitorViewModel` is `@MainActor`
- **AppleScript integration** — Notification detection and email sending via `NSAppleScript`
- **Settings persistence** — `UserDefaults` with `@AppStorage` in views

### Testing Strategy

Tests use Swift Testing framework (`@Suite`, `@Test`, `#expect`):
- **Native tests** — Full macOS tests requiring system APIs
- **Docker tests** — Pure logic tests that can run in Linux containers (LogEntry, DateFormatting, CaptureOptions, RegionSelector)

### macOS Permissions Required

The app needs Accessibility, Screen Recording, and Automation (AppleEvents) permissions. The build script resets TCC permissions to allow fresh testing.

## Conventions

- Swift 5.9+ with SwiftUI for macOS 14+
- Configuration via constants at file top (Python) or `UserDefaults` (Swift)
- Error handling via Swift `throws` and Result types in services
