//
//  ScanPhase.swift
//  FootScan
//

/// The one state machine that drives the UI:
/// `ready → detecting → capturing → finishing → reconstructing → viewing`, plus `failed`.
enum ScanPhase: Equatable {
    /// Ready to scan: the user points the dot at the foot. On the first scan of a launch the tips sheet
    /// shows first and the camera isn't running yet; otherwise it's starting or live.
    case ready
    /// Bounding box is shown; the user trims it at the ankle.
    case detecting
    /// Images are being taken while the user circles the foot.
    case capturing
    /// The session is writing the last images to disk.
    case finishing
    /// Images are on disk; the model is being built.
    case reconstructing
    /// The finished model is on screen.
    case viewing
    case failed(String)
}
