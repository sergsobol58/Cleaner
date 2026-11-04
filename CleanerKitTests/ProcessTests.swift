import XCTest
@testable import CleanerKit

final class ProcessGuardTests: XCTestCase {
    private let me: uid_t = 501
    private let ownPID: pid_t = 4_242
    private var sut: ProcessGuard { ProcessGuard(currentUser: me, ownPID: ownPID) }

    func testAnOrdinaryProcessOfYourOwnPassesThrough() {
        XCTAssertNil(sut.validate(name: "Notion", uid: me, pid: 900))
    }

    /// Signalling another user's process needs privileges this app does not
    /// have and should not want.
    func testAProcessOfAnotherUserIsRefused() {
        XCTAssertEqual(sut.validate(name: "mds_stores", uid: 0, pid: 900), .notYours)
    }

    func testQuittingTheSessionIsRefused() {
        for name in ["launchd", "loginwindow", "WindowServer", "securityd"] {
            XCTAssertEqual(sut.validate(name: name, uid: me, pid: 900), .essential, name)
        }
        XCTAssertEqual(sut.validate(name: "anything", uid: me, pid: 1), .essential)
    }

    /// Relaunched by macOS within seconds: disruptive, not destructive, and
    /// protecting them would cost more than it saves.
    func testTheDockAndFinderAreNotProtected() {
        XCTAssertNil(sut.validate(name: "Dock", uid: me, pid: 900))
        XCTAssertNil(sut.validate(name: "Finder", uid: me, pid: 901))
    }

    func testCleanerWillNotQuitItself() {
        XCTAssertEqual(sut.validate(name: "Cleaner", uid: me, pid: ownPID), .isCleanerItself)
    }
}

final class ProcessTerminatorTests: XCTestCase {
    private let me: uid_t = 501

    private func process(_ name: String, pid: pid_t = 900, uid: uid_t? = nil,
                         protection: ProcessRejection? = nil) -> RunningProcess {
        RunningProcess(pid: pid, name: name, residentBytes: 1_024, cpuPercent: 0,
                       uid: uid ?? me, protection: protection)
    }

    private func terminator(_ spy: SignalSpy) -> ProcessTerminator {
        ProcessTerminator(processGuard: ProcessGuard(currentUser: me, ownPID: 1_111),
                          signal: spy)
    }

    func testAsksTheSelectedProcessesToQuit() async {
        let spy = SignalSpy()
        let report = await terminator(spy).quit([process("Notion"), process("Figma", pid: 901)])

        XCTAssertEqual(spy.signalled, [900, 901])
        XCTAssertEqual(report.asked.count, 2)
        XCTAssertTrue(report.refused.isEmpty)
    }

    /// The list is seconds old and a pid is reused the moment its process
    /// dies, so what the scan said is checked again on the way out.
    func testTheGuardRunsAgainAtQuitTimeNotOnlyWhenListing() async {
        let spy = SignalSpy()
        // Looks harmless in the list, but the guard knows better now.
        let report = await terminator(spy).quit([process("loginwindow", protection: nil)])

        XCTAssertTrue(spy.signalled.isEmpty, "nothing was signalled")
        XCTAssertEqual(report.refused.count, 1)
    }

    func testAProcessOfAnotherUserIsNeverSignalled() async {
        let spy = SignalSpy()
        let report = await terminator(spy).quit([process("mds_stores", uid: 0)])

        XCTAssertTrue(spy.signalled.isEmpty)
        XCTAssertEqual(report.refused.count, 1)
    }

    /// A process that exits between listing and signalling is ordinary, not
    /// an error worth stopping the rest for.
    func testOneFailureDoesNotStopTheRest() async {
        let spy = SignalSpy(failing: [900])
        let report = await terminator(spy).quit([process("Gone"), process("Alive", pid: 901)])

        XCTAssertEqual(report.asked.map(\.process.pid), [901])
        XCTAssertEqual(report.refused.count, 1)
    }
}

private final class SignalSpy: ProcessSignalling, @unchecked Sendable {
    private let lock = NSLock()
    private let failing: Set<pid_t>
    private(set) var signalled: [pid_t] = []

    init(failing: Set<pid_t> = []) { self.failing = failing }

    func terminate(_ pid: pid_t) throws {
        if failing.contains(pid) {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ESRCH))
        }
        lock.lock(); defer { lock.unlock() }
        signalled.append(pid)
    }
}

final class ProcessorSnapshotTests: XCTestCase {
    private func ticks(user: Int64 = 0, system: Int64 = 0,
                       idle: Int64 = 0, nice: Int64 = 0) -> ProcessorTicks {
        ProcessorTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func between(_ previous: ProcessorTicks?, _ current: ProcessorTicks,
                         cores: Int = 8) -> ProcessorSnapshot {
        ProcessorSnapshot.between(previous: previous, current: current,
                                  coreCount: cores, loadAverage: [1, 1, 1])
    }

    /// Ticks are cumulative since boot. A first reading has nothing to
    /// subtract from, and a number invented from the whole uptime would be a
    /// claim about now that nobody measured.
    func testAFirstReadingReportsAnIdleMachine() {
        let snapshot = between(nil, ticks(user: 900, system: 50, idle: 10_000))
        XCTAssertEqual(snapshot.busyPercent, 0)
        XCTAssertEqual(snapshot.idlePercent, 100)
    }

    func testSplitsUserAndSystemAcrossTheInterval() {
        let snapshot = between(ticks(), ticks(user: 30, system: 20, idle: 50))

        XCTAssertEqual(snapshot.userPercent, 30, accuracy: 0.001)
        XCTAssertEqual(snapshot.systemPercent, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot.idlePercent, 50, accuracy: 0.001)
    }

    /// Niced work is still work someone asked for. Dropping it would leave a
    /// machine busy with a background build looking idle.
    func testNicedWorkCountsAsApplicationWork() {
        let snapshot = between(ticks(), ticks(user: 10, idle: 50, nice: 40))
        XCTAssertEqual(snapshot.userPercent, 50, accuracy: 0.001)
    }

    func testNoTicksPassedReportsNothingRatherThanDividingByZero() {
        let same = ticks(user: 100, idle: 100)
        XCTAssertEqual(between(same, same).busyPercent, 0)
    }

    /// More processes wanting a core than there are cores to give.
    func testQueueingIsLoadAboveTheCoreCount() {
        func queueing(load: Double, cores: Int) -> Bool {
            ProcessorSnapshot(userPercent: 0, systemPercent: 0, coreCount: cores,
                              loadAverage: [load, load, load]).isQueueing
        }
        XCTAssertTrue(queueing(load: 9, cores: 8))
        XCTAssertFalse(queueing(load: 7.9, cores: 8))
        XCTAssertFalse(ProcessorSnapshot(userPercent: 0, systemPercent: 0,
                                         coreCount: 8, loadAverage: []).isQueueing)
    }
}
