//
//  ScanPhase.swift
//  archy
//

/// The one state machine that drives the UI:
/// `ready → detecting → capturing → finishing → reconstructing → viewing`, plus `failed`.
enum ScanPhase: Equatable {
    /// Idle (no session: the intro screen), or the camera is starting or live and the user points the dot at the foot.
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
