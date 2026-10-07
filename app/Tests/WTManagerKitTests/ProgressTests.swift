import XCTest
@testable import WTManagerKit

/// The line format two programs have to agree on. The engine writes it in
/// Python and the app reads it in Swift, so nothing type-checks across the
/// boundary — which makes this the only place the agreement is enforced.
final class ProgressTests: XCTestCase {
    func testReadsTheEnginesLine() throws {
        let p = try XCTUnwrap(
            EngineProgress(line: "wt-progress 23 57 3 3 removing ec-website/feat/cards"[...]))
        XCTAssertEqual(p.done, 23)
        XCTAssertEqual(p.total, 57)
        XCTAssertEqual(p.step, 3)
        XCTAssertEqual(p.steps, 3)
        XCTAssertEqual(p.label, "removing ec-website/feat/cards")
        XCTAssertEqual(try XCTUnwrap(p.fraction), 23.0 / 57.0, accuracy: 0.0001)
    }

    func testALabelMayBeEmptyOrHaveSpacesInIt() throws {
        // The spinner's label is prose — "measuring 57 worktrees" — and the
        // delete loops' is a path. Splitting on every space would truncate one
        // and mangle the other.
        XCTAssertEqual(EngineProgress(line: "wt-progress 4 9 1 2 "[...])?.label, "")
        XCTAssertEqual(EngineProgress(line: "wt-progress 4 9 1 2 reading 27 repos"[...])?.label,
                       "reading 27 repos")
    }

    func testAnUnknownTotalIsNotZeroPercent() {
        // A bar at 0% reads as stuck; an indeterminate one reads as working.
        // Only one of those is true when the engine has not said how many.
        XCTAssertNil(EngineProgress(line: "wt-progress 12 0 1 1 scanning"[...])?.fraction)
        XCTAssertEqual(EngineProgress(line: "wt-progress 60 57 1 1 x"[...])?.fraction, 1,
                       "an overshoot must not run past the end of the bar")
    }

    /// The reason the step is on the wire at all.
    ///
    /// One run draws several bars — reading the repos, measuring them, then
    /// doing the approved work — and the second cannot be counted until the
    /// first has finished, so they cannot share a scale. Measured on a real
    /// run: 27 repos read in about four seconds, 56 worktrees measured in
    /// about eighty. Any single bar weighted by item count sprints to a third
    /// and then appears to hang, which is worse than starting again.
    ///
    /// So the bar restarts, and the caption is what makes a restart legible
    /// rather than a fault.
    func testTheStepCaptionAppearsOnlyWhenThereIsMoreThanOne() throws {
        XCTAssertEqual(EngineProgress(line: "wt-progress 3 56 2 3 measuring"[...])?.stepCaption,
                       "Step 2 of 3")
        XCTAssertNil(EngineProgress(line: "wt-progress 3 56 1 1 measuring"[...])?.stepCaption,
                     "one pass has no steps worth naming")
    }

    func testEverythingElseOnThatStreamIsLeftAlone() {
        // stderr also carries warnings and tracebacks, and the whole of it is
        // the error message when the engine fails.
        for line in ["", "wt-manager: could not remove /x: permission denied",
                     "wt-progress", "wt-progress 4", "wt-progress four nine x",
                     "wt-progress 1 2 x",            // the old three-field form
                     "wt-progress 1 2 0 3 x",        // a step is 1-based
                     "wt-progress 1 2 1 0 x",
                     "wt-progress 1 2 4 3 x",        // an impossible phase
                     "Traceback (most recent call last):", " wt-progress 1 2 1 1 x"] {
            XCTAssertNil(EngineProgress(line: line[...]), line)
        }
    }
}
