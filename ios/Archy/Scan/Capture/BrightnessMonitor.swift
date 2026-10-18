//
//  BrightnessMonitor.swift
//  archy
//

import AVFoundation
import CoreMedia
import Observation
import os

/// A rough "too bright" check from the back camera's exposure.
/// ObjectCaptureSession only warns about darkness, so this reads AVCaptureDevice directly.
@MainActor
@Observable
final class BrightnessMonitor {
    private(set) var isTooBright = false

    private let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    @ObservationIgnored private var lastLoggedEV: Double?
    @ObservationIgnored private var samplesPastThreshold = 0
    @ObservationIgnored private var hasLoggedUnreadable = false

    /// Harsh light (direct sun is about EV 15) blows out skin and casts hard shadows.
    /// A first guess; tune it from the "Brightness EV" log lines.
    private static let tooBrightEV = 13.0
    /// The wide gap and hold time keep the banner from flickering as the helper turns toward and away from the light.
    private static let notTooBrightEV = 12.0
    private static let samplesToSwitch = 3

    /// Re-reads the exposure. Called about once a second while the camera runs.
    func sample() {
        guard let camera else {
            logUnreadable("no back wide camera found")
            return
        }
        let seconds = camera.exposureDuration.seconds
        let iso = Double(camera.iso)
        let aperture = Double(camera.lensAperture)
        // Scene brightness as EV at ISO 100: about 6 indoors, 12 overcast outside, 15 in direct sun.
        let ev = log2(aperture * aperture / seconds) - log2(iso / 100)
        guard seconds > 0, iso > 0, aperture > 0, ev.isFinite else {
            logUnreadable("exposure \(seconds) s, ISO \(iso), f/\(aperture)")
            return
        }

        if lastLoggedEV.map({ abs(ev - $0) >= 1 }) ?? true {
            lastLoggedEV = ev
            Log.capture.info("Brightness EV \(ev, format: .fixed(precision: 1)) (ISO \(iso, format: .fixed(precision: 0)), \(seconds * 1000, format: .fixed(precision: 2)) ms, f/\(aperture, format: .fixed(precision: 2)))")
        }

        // Switch only after the reading stays past the threshold for a few samples in a row.
        let pastThreshold = isTooBright ? ev < Self.notTooBrightEV : ev > Self.tooBrightEV
        samplesPastThreshold = pastThreshold ? samplesPastThreshold + 1 : 0
        if samplesPastThreshold >= Self.samplesToSwitch {
            samplesPastThreshold = 0
            isTooBright.toggle()
            Log.capture.notice("Too bright: \(self.isTooBright) at EV \(ev, format: .fixed(precision: 1))")
        }
    }

    /// Clears readings when the camera stops.
    func reset() {
        isTooBright = false
        lastLoggedEV = nil
        samplesPastThreshold = 0
    }

    private func logUnreadable(_ reason: String) {
        guard !hasLoggedUnreadable else { return }
        hasLoggedUnreadable = true
        Log.capture.error("Brightness check off: \(reason, privacy: .public)")
    }
}
