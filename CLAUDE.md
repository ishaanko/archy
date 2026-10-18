# FootScan — DubHacks '26 demo

## Goal
iOS app that scans a person's foot into a 3D model (the default feature).
Later phase: detect flat feet from that model. **Right now we only build scanning.**

## Hard constraints
- SwiftUI app, iOS 17+ deployment target. Mark UI and capture-session code `@MainActor`.
- Apple frameworks only (RealityKit Object Capture, ARKit, ModelIO, QuickLook). No third-party packages unless I approve.
- Runs only on a physical LiDAR iPhone/iPad. The simulator can't run `ObjectCaptureSession`:
  check `ObjectCaptureSession.isSupported` and show a clear message instead of crashing.
- This is a hackathon demo, not production: simplest code that works reliably on stage.
  No accounts, no backend, no persistence beyond local files.
- Never change signing settings, the team, or the bundle identifier.
- Never run `git commit`, `git push`, or create branches. Leave changes uncommitted;
  Cursor's agent handles all git operations. Work happens on the `ios-demo` branch.

## Scanning architecture
- One state machine drives the UI:
  `ready → detecting → capturing → finishing → reconstructing → viewing` (+ `failed(message)`).
- **Detecting:** user frames the foot and adjusts the bounding box so it cuts off at the ankle.
- **Capturing:** `ObjectCaptureSession` + `ObjectCaptureView`. Save to
  `Documents/Scans/<timestamp>/Images/` and `.../Checkpoint/`.
- **Reconstructing:** `PhotogrammetrySession` on device → `.modelFile` USDZ at
  `Documents/Scans/<timestamp>/foot.usdz`. Show progress and surface errors in the UI.
- **Viewing:** display the USDZ (RealityView or QuickLook) with a Share button that can
  AirDrop both the USDZ and the image folder.
- Keep the image folder after reconstruction (we may reprocess on a Mac at higher detail).
- Preserve real-world scale (meters). The next phase measures arch height from the mesh.

## Source layout
All Swift code lives in `FootScan/`, the folder next to `FootScan.xcodeproj` in this project
root. Never create another nested `FootScan/` folder. New Xcode projects pick up files added to
that folder automatically, so don't edit `project.pbxproj` unless a build setting truly needs it
(ask me first).
- `FootScanApp.swift`: app entry point
- `ScanFlow/`: the state machine (`ScanFlowModel.swift`) and the root view that switches screens
- `Capture/`: ObjectCaptureSession + ObjectCaptureView screens
- `Reconstruction/`: PhotogrammetrySession wrapper and progress screen
- `Viewer/`: USDZ viewer and share sheet
- `Support/`: logging, scan folder paths, small helpers
- `Analysis/`: flat-foot phase only; don't create it yet

## Next phase (don't build yet, but don't block it)
- Load the USDZ mesh with ModelIO, find the floor plane, measure medial arch height and
  foot length, classify flat vs. normal arch.

## How we work
- After every change, build with XcodeBuildMCP and fix all errors before saying you're done.
- I test on the phone and paste logs back. Add `Logger(subsystem: "FootScan", ...)` calls at
  every state transition and every error so the logs tell us what happened.
- Apple's Object Capture sample is in `reference/`. Read it for correct API usage;
  don't copy whole files into the app.
- One milestone per task. When you finish, tell me exactly what to test on the device.
