// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeasurementCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeasurementCore", targets: ["MeasurementCore"])],
    targets: [
        .target(name: "MeasurementCore", path: "SpaceMeasureDemo/Measurements", exclude: ["MeasurementViews.swift"], sources: ["MeasurementModels.swift", "AssessmentStore.swift", "PremiumModels.swift", "ExerciseSession.swift"]),
        .target(name: "OnboardingCore", path: "SpaceMeasureDemo/Onboarding", exclude: ["OnboardingView.swift", "GuidanceVoice.swift"], sources: ["OnboardingModels.swift", "OnboardingStore.swift"]),
        .testTarget(name: "MeasurementCoreTests", dependencies: ["MeasurementCore"], path: "Tests"),
        .testTarget(name: "OnboardingCoreTests", dependencies: ["OnboardingCore"], path: "OnboardingTests")
    ]
)
