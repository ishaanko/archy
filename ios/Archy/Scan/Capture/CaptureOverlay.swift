import SwiftUI

/// Everything drawn over the camera feed. A pure view (state and actions come in) so a DEBUG route can
/// render it without a capture session. Always dark: white type on scrims over the live camera.
@MainActor
struct CaptureOverlay: View {
    struct Actions {
        var cancel: () -> Void = {}
        var help: () -> Void = {}
        var detect: () -> Void = {}
        var resetBox: () -> Void = {}
        var startCapture: () -> Void = {}
        var finish: () -> Void = {}
        var nextLap: () -> Void = {}
    }

    let phase: ScanPhase
    let lap: Int
    let shots: Int
    /// The session's image cap, which the progress ring counts toward.
    let shotLimit: Int
    let instruction: String
    let banner: String?
    /// "?" pauses the session, which is unsafe while it is still initializing.
    let canShowHelp: Bool
    let canFinish: Bool
    let isPassComplete: Bool
    var actions = Actions()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.md) {
            topBar
            bannerView
            Spacer()
            if isPassComplete {
                lapCompleteCard
                    .transition(.scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: 24)))
            } else {
                bottomControls
                    .transition(.opacity)
            }
        }
        .padding(Space.page)
        .animation(Motion.playful.reduced(reduceMotion), value: isPassComplete)
        .sensoryFeedback(.success, trigger: isPassComplete) { _, done in done }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.ink)
        .tint(.ink)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top) {
            if [.ready, .detecting, .capturing].contains(phase) {
                Button("Cancel", action: actions.cancel)
                    .buttonStyle(CameraGlassButtonStyle(minHeight: 44))
                    .fixedSize()
            }
            Spacer()
            switch phase {
            case .ready, .detecting:
                if canShowHelp {
                    Button(action: actions.help) {
                        Image(systemName: "questionmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(CameraGlassButtonStyle(minHeight: 44, circle: true))
                    .accessibilityLabel("How to scan")
                }
            case .capturing, .finishing:
                progressHUD
            default:
                EmptyView()
            }
        }
    }

    /// Lap label with the photo count rolling inside a ring that fills toward the session's image cap.
    private var progressHUD: some View {
        let fraction = min(1, Double(shots) / Double(max(shotLimit, 1)))
        return HStack(spacing: Space.md) {
            ZStack {
                Circle().stroke(Color.line3, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.snappy.reduced(reduceMotion), value: fraction)
                MetricText(value: Double(shots), style: .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(Space.sm)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 0) {
                Text(FootGuidance.lapLabel(lap))
                    .font(.subheadline.weight(.semibold))
                Text("photos")
                    .font(.footnote)
                    .foregroundStyle(.inkSecondary)
            }
        }
        .padding(.vertical, Space.sm)
        .padding(.leading, Space.sm)
        .padding(.trailing, Space.lg)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FootGuidance.lapLabel(lap)), \(shots) photos")
    }

    /// A calm line that springs in and out: the session's top warning, or the lens reminder.
    private var bannerView: some View {
        VStack {
            if let banner {
                Text(banner)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Color.line2))
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: -8)))
            }
        }
        .animation(Motion.smooth.reduced(reduceMotion), value: banner)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bottom

    private var bottomControls: some View {
        VStack(spacing: Space.lg) {
            if phase == .detecting {
                BoxTrimDiagram()
            }
            Text(instruction)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .contentTransition(.opacity)
                .animation(Motion.smooth.reduced(reduceMotion), value: instruction)
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .ready:
            Button("Continue", action: actions.detect)
                .buttonStyle(.archyPrimary)
                .accessibilityIdentifier("scan.continue")
        case .detecting:
            HStack(spacing: Space.md) {
                Button("Reset box", action: actions.resetBox)
                    .buttonStyle(CameraGlassButtonStyle(minHeight: 54))
                Button("Start capture", action: actions.startCapture)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("scan.startCapture")
            }
        case .capturing:
            Button("Finish", action: actions.finish)
                .buttonStyle(.archyPrimary)
                .disabled(!canFinish)
                .accessibilityIdentifier("scan.finish")
        default:
            EmptyView()
        }
    }

    private var lapCompleteCard: some View {
        let text = FootGuidance.lapCompleteText(lap: lap)
        let moreLapsPlanned = lap < FootGuidance.plannedLaps
        return VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(text.title).display(.headline)
                Text(text.body)
                    .font(.subheadline)
                    .foregroundStyle(.inkSecondary)
            }
            VStack(spacing: Space.xs) {
                if moreLapsPlanned {
                    Button("Start lap \(lap + 1)", action: actions.nextLap)
                        .buttonStyle(.archyPrimary)
                    Button("Finish now", action: actions.finish)
                        .buttonStyle(.archyGhost)
                } else {
                    Button("Finish", action: actions.finish)
                        .buttonStyle(.archyPrimary)
                        .accessibilityIdentifier("scan.finish")
                    Button("Another lap", action: actions.nextLap)
                        .buttonStyle(.archyGhost)
                }
            }
        }
        .surface(radius: Radius.xxl, padding: Space.xl)
        .frame(maxWidth: 400)
    }
}

/// Translucent camera button: material fill, white type, hairline edge. For secondary actions over the feed.
private struct CameraGlassButtonStyle: ButtonStyle {
    var minHeight: CGFloat
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: circle ? minHeight / 2 : Radius.lg, style: .continuous)
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: circle ? nil : .infinity, minHeight: minHeight)
            .padding(.horizontal, circle ? 0 : Space.lg)
            .foregroundStyle(.ink)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.line2))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(configuration.isPressed ? Motion.pressIn : Motion.release, value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
