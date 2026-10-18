# archy for iPhone

One SwiftUI app, iOS 26+. Tabs: Home, Scan, Insole, Train.

- `Archy/App`: entry point, root view, tab router.
- `Archy/Design`: tokens (colors, type, spacing, motion) and shared components. Mirrors `sim/src/theme.css`.
- One folder per feature: `Onboarding`, `Home`, `Measure`, `Scan`, `Insole`, `Space`, `Train`, `Settings`.

The Xcode project is generated from `project.yml` with sources as synced folders, so adding files needs no regeneration. After editing `project.yml`, run `xcodegen`.

## Run

Open `Archy.xcodeproj`, pick the **Archy** scheme and a device. Scanning needs an iPhone with LiDAR; the Simulator runs everything else. Signing uses team B37KYDJP8C; pick your own team under Signing & Capabilities if needed.

Debug launch arguments (Scheme > Run > Arguments):

- `-ArchyFreshInstall YES`: start at onboarding.
- `-ArchySkipOnboarding YES`: skip onboarding with sample answers.
- `-ArchyTab home|scan|insole|train`: open on a tab.
- `-ArchyRoute <feature.screen>`: open a deep screen; each feature documents its routes in its entry file.
- `-ArchyOpenScan <scan folder>`: open a saved scan in the viewer.

## Verify

```sh
swift test   # model and persistence tests on the Mac
xcodebuild -project Archy.xcodeproj -scheme Archy -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ArchyDD CODE_SIGNING_ALLOWED=NO build
```

## Calculations and measurement limitations

- AHI = dorsum height at 50% of full length / truncated length (heel to first metatarsal head).
- Navicular drop = seated navicular height − standing navicular height, in mm. Negative readings are preserved with remeasurement guidance.
- Width-to-length ratio = maximum forefoot width / full length.

No clinical thresholds, diagnoses or composite score. AHI is not footprint-based Arch Index. Illustrated landmarks are schematic; a home tape/ruler workflow is not a validated substitute for the standardized instruments in published reliability studies. Gravity modes and material concepts do not predict clinical outcomes. No NASA affiliation or medical certification.

## Persistence

`AssessmentStore` is main-actor isolated. Completed records are JSON in Application Support/archy/assessments.json in the app sandbox. Writes are atomic and memory updates only after disk success. A corrupt file is preserved and a visible error is provided. No synthetic records are seeded automatically. Logger records state transitions/errors without logging measurement values.

