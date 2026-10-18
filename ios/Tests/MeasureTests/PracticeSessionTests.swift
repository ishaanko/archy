import Testing
@testable import MeasurementCore

struct PracticeSessionTests {
    @Test func heelRaisesRiseThenLowerForTenReps() {
        var session = HeelRaiseSession()
        #expect((session.step, session.round, session.secondsRemaining) == (.hold, 1, 3))
        for _ in 0..<3 { session.tick() }
        #expect((session.step, session.round, session.secondsRemaining) == (.rest, 1, 3))
        for _ in 0..<3 { session.tick() }
        #expect((session.step, session.round) == (.hold, 2))
        for _ in 0..<200 { session.tick() }
        #expect(session.step == .done)
        #expect(session.round == HeelRaiseSession.reps)
        #expect(session.elapsed == HeelRaiseSession.reps * 6)
    }

    @Test func toeYogaAlternatesBigToeAndSmallToes() {
        var session = ToeYogaSession()
        #expect((session.step, session.stepSeconds, session.secondsRemaining) == (.hold, 4, 4))
        for _ in 0..<4 { session.tick() }
        #expect((session.step, session.round) == (.rest, 1))
        for _ in 0..<4 { session.tick() }
        #expect((session.step, session.round) == (.hold, 2))
        for _ in 0..<200 { session.tick() }
        #expect(session.step == .done)
        #expect(session.round == ToeYogaSession.rounds)
        #expect(session.elapsed == ToeYogaSession.rounds * 8)
    }
}
