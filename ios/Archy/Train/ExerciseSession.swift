import Foundation

/// A short educational practice; the timing is not a prescribed clinical protocol.
struct ShortFootSession: Equatable {
    enum Phase: String { case hold, relax, complete }
    private(set) var elapsed = 0
    static let repetitions = 5
    static let phaseSeconds = 5
    var phase: Phase {
        if elapsed >= 50 { return .complete }
        return elapsed % 10 < 5 ? .hold : .relax
    }
    var repetition: Int { min(elapsed / 10 + 1, Self.repetitions) }
    var secondsRemaining: Int { Self.phaseSeconds - elapsed % Self.phaseSeconds }
    mutating func tick() { elapsed = min(elapsed + 1, 50) }
}

/// Two supported tandem holds of 20 seconds, each followed by 10 seconds of rest.
struct BalanceSession: Equatable {
    private(set) var elapsed = 0
    static let holds = 2
    static let holdSeconds = 20
    static let restSeconds = 10
    private static let cycle = holdSeconds + restSeconds
    private static let total = cycle * holds
    var isComplete: Bool { elapsed >= Self.total }
    var isResting: Bool { !isComplete && elapsed % Self.cycle >= Self.holdSeconds }
    var hold: Int { min(elapsed / Self.cycle + 1, Self.holds) }
    var secondsRemaining: Int {
        isComplete ? 0 : (isResting ? Self.cycle : Self.holdSeconds) - elapsed % Self.cycle
    }
    mutating func tick() { elapsed = min(elapsed + 1, Self.total) }
}

/// Ten slow heel raises at a counter: 3 seconds rising (with a pause at the top), 3 seconds lowering.
struct HeelRaiseSession: Equatable {
    private(set) var elapsed = 0
    static let reps = 10
    static let riseSeconds = 3
    static let lowerSeconds = 3
    private static let cycle = riseSeconds + lowerSeconds
    private static let total = cycle * reps
    var isComplete: Bool { elapsed >= Self.total }
    var isLowering: Bool { !isComplete && elapsed % Self.cycle >= Self.riseSeconds }
    var rep: Int { min(elapsed / Self.cycle + 1, Self.reps) }
    var secondsRemaining: Int {
        isComplete ? 0 : (isLowering ? Self.cycle : Self.riseSeconds) - elapsed % Self.cycle
    }
    mutating func tick() { elapsed = min(elapsed + 1, Self.total) }
}

/// Seated toe yoga: five rounds of lifting the big toe alone for 4 seconds, then the four small toes alone for 4.
struct ToeYogaSession: Equatable {
    private(set) var elapsed = 0
    static let rounds = 5
    static let liftSeconds = 4
    private static let cycle = liftSeconds * 2
    private static let total = cycle * rounds
    var isComplete: Bool { elapsed >= Self.total }
    /// True while the four small toes are up (the big toe is up the rest of the time).
    var isSmallToes: Bool { !isComplete && elapsed % Self.cycle >= Self.liftSeconds }
    var round: Int { min(elapsed / Self.cycle + 1, Self.rounds) }
    var secondsRemaining: Int { isComplete ? 0 : Self.liftSeconds - elapsed % Self.liftSeconds }
    mutating func tick() { elapsed = min(elapsed + 1, Self.total) }
}

enum PracticeStep { case hold, rest, done }

/// What the shared coach screen needs from a timed practice (hold and rest rounds, ticked once a second).
protocol PracticeTimeline {
    init()
    static var rounds: Int { get }
    var step: PracticeStep { get }
    var round: Int { get }
    var secondsRemaining: Int { get }
    /// Length of the current hold or rest, for the countdown ring.
    var stepSeconds: Int { get }
    mutating func tick()
}

extension ShortFootSession: PracticeTimeline {
    static var rounds: Int { repetitions }
    var step: PracticeStep {
        switch phase {
        case .hold: .hold
        case .relax: .rest
        case .complete: .done
        }
    }
    var round: Int { repetition }
    var stepSeconds: Int { Self.phaseSeconds }
}

extension BalanceSession: PracticeTimeline {
    static var rounds: Int { holds }
    var step: PracticeStep { isComplete ? .done : isResting ? .rest : .hold }
    var round: Int { hold }
    var stepSeconds: Int { isResting ? Self.restSeconds : Self.holdSeconds }
}

extension HeelRaiseSession: PracticeTimeline {
    static var rounds: Int { reps }
    /// Rising is the "hold" step; lowering is the "rest" step.
    var step: PracticeStep { isComplete ? .done : isLowering ? .rest : .hold }
    var round: Int { rep }
    var stepSeconds: Int { isLowering ? Self.lowerSeconds : Self.riseSeconds }
}

extension ToeYogaSession: PracticeTimeline {
    /// Big toe up is the "hold" step; small toes up is the "rest" step.
    var step: PracticeStep { isComplete ? .done : isSmallToes ? .rest : .hold }
    var stepSeconds: Int { Self.liftSeconds }
}

#if DEBUG
extension PracticeTimeline {
    /// A session already `elapsed` seconds in, for launching the coach mid-practice.
    init(debugElapsed elapsed: Int) {
        self.init()
        for _ in 0..<elapsed { tick() }
    }
}
#endif
