// swift-tools-version: 6.0
// Runs the app's pure model and persistence code on the Mac: `cd ios && swift test`.
import PackageDescription

let package = Package(
    name: "MeasurementCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeasurementCore", targets: ["MeasurementCore"])],
    targets: [
        .target(name: "MeasurementCore", path: "Archy", sources: ["Measure/MeasurementModels.swift", "Measure/AssessmentStore.swift", "Insole/PremiumModels.swift", "Train/ExerciseSession.swift"]),
        .target(name: "OnboardingCore", path: "Archy/Onboarding", sources: ["OnboardingModels.swift", "OnboardingStore.swift"]),
        .target(name: "ScanCore", path: "Archy/Scan", sources: ["Support/FootMesh.swift", "Support/Log.swift", "Analysis/FootArchAnalyzer.swift"]),
        .testTarget(name: "ScanCoreTests", dependencies: ["ScanCore"], path: "Tests/ScanTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "MeasurementCoreTests", dependencies: ["MeasurementCore"], path: "Tests/MeasureTests"),
        .testTarget(name: "OnboardingCoreTests", dependencies: ["OnboardingCore"], path: "Tests/OnboardingTests")
    ]
)
