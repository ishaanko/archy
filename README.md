# Space + Measure — DubHacks ’26

Independent SwiftUI prototype in `SpaceMeasureDemo.xcodeproj`, on `space-and-measure`.

## First-run onboarding

The app starts with a three-question quiz and review: goal, self-reported previous diagnosis/foot focus, and pain (1–10, no pain, or prefer not to say). It saves answers locally and explicitly opens the Add (+) tab. Returning users see Today and can edit the quiz without losing their measurement records.

The native tabs are Today, Add, Space and Premium. Add routes to the existing bilateral measurement workflow or six guided photo slots (three angles per foot). Photos import through the system Photos picker, save progressively as a protected local draft, and can be reopened. There is no photo-analysis pipeline or image-derived classification.

Accessibility settings include reading-friendly typography and spacing, native Dynamic Type, and on-device read-aloud. Optional Grok instruction synthesis can be configured later in Accessibility using an HTTPS narration proxy and a separate Keychain access token. A fixed script ID is sent only after opt-in; personalized quiz narration stays on-device. Live credentials are not configured. No xAI API key or microphone recording is included. See `Services/voice/README.md`.

The questionnaire records self-reports; it does not infer a diagnosis or disease severity. Manual results use AHI (height divided by truncated length); footprint Arch Index uses contact-area measurements, which ordinary photos and tape readings do not supply. See Cavanagh & Rodgers, 1987: https://pubmed.ncbi.nlm.nih.gov/3611129/.

The supplied `/Users/prakhartiwari/Downloads/SKILL.md` was applied for modern Swift value models, explicit enum state, main-actor isolation, observable UI state, and Swift Testing. The existing measurement module was preserved.

Run the shared scheme’s UI tests to verify the quiz, optional answers, local persistence, Plus-tab handoff, Photos picker, Space route and large-text flow. XCTest is used only for UI automation; new pure-model and store tests use Swift Testing.

Requires Xcode with an iOS SDK supporting iOS 18 or later. Minimum deployment target: iOS 18.0. Swift language mode: 6. Apple frameworks only; no packages, backend, accounts, analytics, camera or LiDAR.

## Launch on iPhone 15

1. Open `SpaceMeasureDemo.xcodeproj` in Xcode. Choose the shared **SpaceMeasureDemo** scheme.
2. Connect and unlock the iPhone 15; trust the Mac if prompted. Enable Developer Mode on the phone if Xcode requests it.
3. Select the phone as the run destination. If Xcode reports a signing error, select your own development team in the app target’s Signing & Capabilities panel. No existing signing configuration was present or changed by this implementation.
4. Press Run (Command-R). The device must run iOS 18 or later.

For Simulator, choose an installed iPhone simulator. Install an iOS 18 runtime through Xcode Settings > Components if testing specifically on iOS 18. This implementation was compiled with the installed iOS 27.1 SDK for a minimum target of iOS 18; runtime UI testing on iOS 18.0 passed on iPhone 15 and iPhone 16 Pro simulators.

## Demo route

- Complete the quiz and open **Add → Manual measurements** → Begin assessment: 6 readings for the left foot, then 6 for the right. Choose mm or cm at any step; existing input is converted, with mm stored internally. Back retains entered values.
- Complete the assessment to save a bilateral record and see AHI, navicular drop, width/length ratio, comparisons and raw values. Reopen it from history after relaunch.
- For a quick presentation, **Explore a synthetic example** shows clearly labeled example results without inserting them into personal history.
- **Space tab → Biomechanics Explorer**: adjust dorsum height, select Earth/Moon/Mars/microgravity, load saved geometry and switch feet. Arch deformation is controlled by the slider; gravity changes context and loading arrows only.
- **AstroFit**: switch feet, choose saved proportions, change material, arch-zone intensity and pattern density. Every control changes the native preview. The studio button opens a graceful coming-soon message until an HTTPS URL is configured in `StartupConfiguration.websiteURL` in `SpaceLab/AstroFitView.swift`. No measurements are appended to the URL or uploaded.
- **Space Medicine**: four reading cards open NASA pages and a peer-reviewed journal DOI in the browser.

## Calculations and measurement limitations

- AHI = dorsum height at 50% of full length / truncated length (heel to first metatarsal head).
- Navicular drop = seated navicular height − standing navicular height, in mm. Negative readings are preserved with remeasurement guidance.
- Width-to-length ratio = maximum forefoot width / full length.

No clinical thresholds, diagnoses or composite score. AHI is not footprint-based Arch Index. Illustrated landmarks are schematic; a home tape/ruler workflow is not a validated substitute for the standardized instruments in published reliability studies. Gravity modes and material concepts do not predict clinical outcomes. No NASA affiliation or medical certification.

## Persistence

`AssessmentStore` is main-actor isolated. Completed records are JSON in Application Support/SpaceMeasureDemo/assessments.json in the app sandbox. Writes are atomic and memory updates only after disk success. A corrupt file is preserved and a visible error is provided. No synthetic records are seeded automatically. Logger records state transitions/errors without logging measurement values.

## Verify

```sh
swift test
xcodebuild -project SpaceMeasureDemo.xcodeproj -scheme SpaceMeasureDemo \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SpaceMeasureDerived CODE_SIGNING_ALLOWED=NO build
```

Tests run on the Mac through a small Swift package containing the exact app model and persistence sources. Premium tests additionally cover consent, unchanged gravity-context measurements, scan export round-tripping, attachment rejection and exercise timing. They cover equations, unit conversion, invalid/nonfinite inputs, impossible geometry, signed navicular drop, independent feet, Codable, explorer dimensions and persistence success/failure behavior.

In a nested sandbox, Swift macro subprocesses may require the command-line-only option `'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'` for xcodebuild and `--disable-sandbox` for SwiftPM. These flags do not change app entitlements or saved project configuration.

Verification on October 17, 2026: unsigned Simulator and device compilation, plus successful iOS 18.0 UI tests on iPhone 15 and iPhone 16 Pro. Both devices passed five scenarios covering the 12-step bilateral wizard, save/relaunch/history, synthetic results, gravity modes, AstroFit controls and research navigation. Saved-measurement personalization was additionally verified on iPhone 15. Screenshot review led to fixes for the heel/forefoot legend and mirrored right-foot insole branding; affected UI tests passed again. Physical-device installation remains unverified.

## Research sources

NASA pages retrieved October 17, 2026:

- https://www.nasa.gov/humans-in-space/counteracting-bone-and-muscle-loss-in-microgravity/
- https://www.nasa.gov/glenn/glenn-expertise-space-exploration/human-health-performance/computational-modeling/musculoskeletal/
- https://www.nasa.gov/directorates/esdmd/hhp/exercise-physiology-and-countermeasures/
- Butler RJ et al. *Arch Height Index Measurement System: Establishment of Reliability and Normative Values*. JAPMA. 2008;98(2):102–106. https://doi.org/10.7547/0980102 — publication metadata confirmed; the DOI destination could not be fetched by the browsing tool.
- Gravity context: https://nssdc.gsfc.nasa.gov/planetary/factsheet/moonfact.html and https://www.jpl.nasa.gov/news/press_kits/insight/landing/facts/mars-at-a-glance/

## Premium preview

Premium is open for this demo; subscription billing is not connected. The Movement Studio offers animated short-foot and supported tandem-balance lessons, with pause/resume/reset, phase cues, voice instructions, Dynamic Type and Reduce Motion. These are introductory practices rather than personalized clinical protocols. Each lesson links its small randomized trials and describes their limits:

- [Short foot plus insoles, 40 participants](https://pubmed.ncbi.nlm.nih.gov/36988565/): six-week program; pain and function improvements compared with insoles alone.
- [Short-foot training, 45 participants](https://pubmed.ncbi.nlm.nih.gov/37379736/): six-week programs with changes in dynamic gait function.
- [Balance plus short-foot training, 32 participants](https://pmc.ncbi.nlm.nih.gov/articles/PMC8544541/): an 18-session combined program, not evidence that a one-minute tandem exercise alone treats flat feet.

AstroFit prepares single-foot quote requests from a saved assessment or explicitly labeled synthetic data. All six dimensions, source date, optional reviewed photos, an optional scan-file attachment, material and environment are shown before consent. Native Files import accepts STL, OBJ, PLY, GLB or USDZ up to 20 MiB; scan bytes remain local until explicit sharing. File format, selected foot and size are checked, but geometry/calibration are not validated. Quiz responses and pain ratings are excluded. Requests are protected local JSON files; nothing uploads automatically. A user can explicitly share the reviewed export through the iOS share sheet, and view or delete local drafts in Saved Requests. Deletion cannot recall previously shared copies.

SpaceLab's environment is remembered and offered in Space Insole requests. Gravity alters the illustrative design brief (heel retention/adjustable cushioning), never stored foot measurements or a predicted anatomical change. Ordinary photos are not calibrated scans. Scan files from other components can be attached for specialist review; automated scan analysis, calibration and manufacturing-grade fitting are not connected. Provider, price, manufacturing, fulfillment and checkout remain unconfigured. No cost-saving claim is made before an actual quote. Consent is not a claim of HIPAA compliance; future service obligations must be assessed before accepting health data ([HHS covered entities](https://www.hhs.gov/hipaa/for-professionals/covered-entities/index.html)).

The native UI follows the palette, quiet surfaces and reduced-motion principle in `origin/test/data-sim:sim/src/theme.css`, `sim/src/core/gait.ts` and `sim/README.md`. Short-foot motion is a teaching diagram rather than a port of a gait simulation. The simulator's pressure-to-insole heuristics are not substituted for measured AHI or used as a validated prescription. No browser models or third-party datasets are bundled by this change.

Voice guidance, reading-friendly/dyslexia typography and audio cues remain free settings. Optional Grok speech uses public scripts through the included demo proxy, with on-device fallback. It supports instruction playback, not microphone-based conversation.

## Git workflow

Leave changes uncommitted unless explicitly asked otherwise. Any future commit must be performed through the Cursor headless CLI and verified to carry Cursor Agent coauthorship. The previous onboarding commit was created and pushed through Cursor headless CLI as `Cursor <cursoragent@cursor.com>` with Cursor coauthorship. Premium work remains uncommitted until requested.

Simulator Keychain verification uses a locally signed build (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). An unsigned simulator build may reject Keychain operations; the app reports that failure and does not store tokens elsewhere. These command-line settings do not alter project signing.
