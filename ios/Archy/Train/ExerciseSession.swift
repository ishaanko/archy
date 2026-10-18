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

#if DEBUG
extension ShortFootSession {
    /// A session already `elapsed` seconds in, for launching the coach mid-practice.
    init(debugElapsed elapsed: Int) {
        self.init()
        for _ in 0..<elapsed { tick() }
    }
}

extension BalanceSession {
    /// A session already `elapsed` seconds in, for launching the coach mid-practice.
    init(debugElapsed elapsed: Int) {
        self.init()
        for _ in 0..<elapsed { tick() }
    }
}
#endif
