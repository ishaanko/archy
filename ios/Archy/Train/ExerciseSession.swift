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

