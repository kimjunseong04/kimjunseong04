import Foundation
import Testing
@testable import MulgilCore

// 기준 시각: 2026-11-25(수) 15:00 KST
private let now: Date = {
    var c = DateComponents()
    c.year = 2026; c.month = 11; c.day = 25; c.hour = 15
    return Seoul.calendar.date(from: c)!
}()
private func h(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
private func kst(_ d: Int, _ hh: Int, _ mm: Int = 0) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 11; c.day = d; c.hour = hh; c.minute = mm
    return Seoul.calendar.date(from: c)!
}

/// 모든 것이 정상인 G1 스냅샷.
private func healthy() -> HealthSnapshot {
    HealthSnapshot(
        phonePathEstablishedAt: h(24 * 10),
        phonePath: .syncthing,
        macSyncthingRunning: true,
        inboxPhoneExists: true,
        phoneConnected: true,
        phoneLastConnectedAt: h(0.1),
        phoneLastSeen: h(0.1),
        folderState: "idle",
        folderError: nil,
        phoneFolderCompletion: 100,
        phoneFolderCompletionSince: h(5),
        phoneFolderFileCount: 40,
        phoneFolderFileCountPrevious: 40,
        lastRecordingArrivalAt: h(3),
        recentRecordings: [h(3.5)],
        baselineRecordingsPerWeek: 6,
        endedMeetings: [h(4)],
        googleToken: .ok,
        lastSuccessfulGoogleSyncAt: h(0.05),
        diskFreeBytes: 200_000_000_000,
        speechAsset: .installed
    )
}

private let monitor = HealthMonitor()
private func codes(_ s: HealthSnapshot, _ m: HealthMonitor = monitor) -> [HealthCode] { m.evaluate(s, now: now).map(\.code) }

// MARK: - HealthMonitor

@Suite struct HealthMonitorTests {
    @Test func healthyIsSilent() {
        #expect(monitor.evaluate(healthy(), now: now).isEmpty)
    }

    @Test func defaultSnapshotIsSilent() {
        // 아무것도 모르면 아무 말도 하지 않는다.
        #expect(monitor.evaluate(HealthSnapshot(), now: now).isEmpty)
    }

    @Test func zeroRecordingsAloneDoesNotAlarm() {
        var s = healthy()
        s.lastRecordingAt(nil)
        s.endedMeetings = []
        #expect(monitor.evaluate(s, now: now).isEmpty)
    }

    @Test func zeroRecordingsWithTwoMeetingsIsSilent() {
        var s = healthy()
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(10), h(5)]
        #expect(codes(s).isEmpty)
    }

    @Test func connectedPlusThreeMeetingsWithoutRecordingIsYellow() {
        var s = healthy()
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(20), h(10), h(5)]
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.count == 1)
        #expect(issues[0].level == .yellow)
        #expect(issues[0].code == .recordingsMissing)
        #expect(issues[0].message == "최근 수업·회의 3개에 녹음이 없어요. 녹음했다면 확인해 주세요 ›")
        #expect(issues[0].level.notifies == false)
    }

    @Test func meetingWithinArrivalGraceIsNotCounted() {
        var s = healthy()
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(20), h(10), h(0.5)] // 마지막 회의는 30분 전에 끝나 아직 도착 대기
        #expect(codes(s).isEmpty)
    }

    @Test func comboRequiresConnectedPhone() {
        var s = healthy()
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(20), h(10), h(5)]
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(2) // 미연결이지만 아직 24h 안
        #expect(codes(s).isEmpty)
    }

    @Test func comboOffForPersonWithoutRecordingHabit() {
        var s = healthy()
        s.lastRecordingAt(nil)
        s.baselineRecordingsPerWeek = 0
        s.endedMeetings = [h(20), h(10), h(5)]
        #expect(codes(s).isEmpty)
    }

    @Test func meetingsBeforePathEstablishedDoNotCount() {
        var s = healthy()
        s.phonePathEstablishedAt = h(12)
        s.lastRecordingAt(nil)
        s.endedMeetings = [h(30), h(20), h(5)]
        #expect(codes(s).isEmpty)
    }

    @Test func phoneDisconnectedOver24hIsRed() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(25)
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.phoneDisconnected])
        #expect(issues[0].level == .red)
        #expect(issues[0].message == "폰과 하루 넘게 연결되지 않았어요 · 확인 방법 ›")
        #expect(issues[0].action == .showGuide)
    }

    @Test func phoneDisconnectedUnder24hIsSilent() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(23)
        #expect(codes(s).isEmpty)
    }

    @Test func homeWifiOnlyUses48h() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(30)
        var t = HealthThresholds(); t.homeWifiOnly = true
        let m = HealthMonitor(thresholds: t)
        #expect(codes(s, m).isEmpty)
        s.phoneLastConnectedAt = h(49)
        #expect(codes(s, m) == [.phoneDisconnected])
    }

    @Test func lastSeenIsFallbackWhenNoConnectedRecord() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = nil
        s.phoneLastSeen = h(26)
        #expect(codes(s) == [.phoneDisconnected])
    }

    @Test func neverConnectedCountsFromPathEstablished() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = nil
        s.phoneLastSeen = nil
        s.phonePathEstablishedAt = h(10)
        #expect(codes(s).isEmpty)
        s.phonePathEstablishedAt = h(25)
        #expect(codes(s) == [.phoneDisconnected])
    }

    @Test func noPhonePathMeansNoPhoneChecks() {
        var s = healthy()
        s.phonePathEstablishedAt = nil
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(100)
        s.macSyncthingRunning = false
        #expect(codes(s).isEmpty)
    }

    @Test(arguments: ["error", "stopped", "ERROR"])
    func brokenFolderStateWhileConnectedIsRed(state: String) {
        var s = healthy()
        s.folderState = state
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.phoneFolderBroken])
        #expect(issues[0].message == "폰은 연결됐는데 녹음 폴더를 못 읽고 있어요 · 폰 권한 확인 ›")
    }

    @Test func folderErrorStringIsRed() {
        var s = healthy()
        s.folderError = "folder path missing"
        #expect(codes(s) == [.phoneFolderBroken])
    }

    @Test func folderCompletionStallIsRed() {
        var s = healthy()
        s.phoneFolderCompletion = 62
        s.phoneFolderCompletionSince = h(5)
        #expect(codes(s).isEmpty)
        s.phoneFolderCompletionSince = h(7)
        #expect(codes(s) == [.phoneFolderBroken])
    }

    @Test func advertisedFileCountCollapseIsRed() {
        var s = healthy()
        s.phoneFolderFileCountPrevious = 40
        s.phoneFolderFileCount = 0
        #expect(codes(s) == [.phoneFolderBroken])
    }

    @Test func smallFileCountDropIsUserDeletionNotAlarm() {
        var s = healthy()
        s.phoneFolderFileCountPrevious = 40
        s.phoneFolderFileCount = 38
        #expect(codes(s).isEmpty)
    }

    @Test func folderBrokenSupersedesRecordingCombo() {
        var s = healthy()
        s.folderState = "error"
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(20), h(10), h(5)]
        #expect(codes(s) == [.phoneFolderBroken])
    }

    @Test func macSyncthingDownIsRootCause() {
        var s = healthy()
        s.macSyncthingRunning = false
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(50)
        s.folderState = "error"
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.macSyncthingDown])
        #expect(issues[0].message == "맥에서 폰 녹음 받기가 멈췄어요 · 다시 켜기 ›")
    }

    @Test func inboxMissingIsRed() {
        var s = healthy()
        s.inboxPhoneExists = false
        #expect(codes(s) == [.inboxMissing])
    }

    @Test func invalidGrantIsRed() {
        var s = healthy()
        s.googleToken = .invalidGrant
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.googleInvalidGrant])
        #expect(issues[0].message == "Google 연결이 끊겼어요 · 다시 로그인 ›")
        #expect(issues[0].action == .signInAgain)
    }

    @Test func briefNetworkErrorIsSilent() {
        var s = healthy()
        s.googleToken = .networkError
        s.lastSuccessfulGoogleSyncAt = h(2)
        #expect(codes(s).isEmpty)
        s.lastSuccessfulGoogleSyncAt = h(25)
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.googleSyncStale])
        #expect(issues[0].level == .yellow)
    }

    @Test func diskBelow10GBIsRed() {
        var s = healthy()
        s.diskFreeBytes = 9_999_999_999
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.code) == [.diskLow])
        #expect(issues[0].message == "맥 저장 공간이 부족해 녹음을 받지 못할 수 있어요 ›")
        s.diskFreeBytes = 10_000_000_000
        #expect(codes(s).isEmpty)
    }

    @Test func speechAssetMissingIsRed() {
        var s = healthy()
        s.speechAsset = .missing
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.code) == [.speechAssetMissing])
        #expect(i[0].message == "한국어 음성 인식 파일이 사라졌어요 · 다시 받기 ›")
        s.speechAsset = .notUsed
        #expect(codes(s).isEmpty)
    }

    @Test func transcriptionFailuresArePerRecordingInfo() {
        var s = healthy()
        s.failedTranscriptions = ["b", "a", "a"]
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.subject) == ["a", "b"])
        #expect(i.allSatisfy { $0.level == .info && $0.action == .playRecording })
        #expect(i[0].message == "이 녹음은 글로 바꾸지 못했어요 · 녹음은 그대로 있어요 ‹재생›")
    }

    @Test func notInCalendarTwiceAWeek() {
        var s = healthy()
        s.notInCalendarThisWeek = 1
        #expect(codes(s).isEmpty)
        s.notInCalendarThisWeek = 2
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.code) == [.notInCalendar])
        #expect(i[0].message == "이 시각 일정이 Google에 없어요 · 폰 캘린더 저장 계정 확인 ›")
    }

    @Test func g2NoArrivalOver24h() {
        var s = healthy()
        s.phonePath = .folderSync
        s.phoneConnected = nil
        s.macSyncthingRunning = false // G2에서는 맥 Syncthing을 보지 않는다
        s.lastRecordingAt(h(25))
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.code) == [.phoneNoArrival])
        #expect(i[0].message == "폰에서 마지막으로 받은 지 하루가 넘었어요 · 확인 방법 ›")
        s.lastRecordingAt(h(20))
        #expect(codes(s).isEmpty)
    }

    @Test func yesterdayInfoLine() {
        var s = healthy()
        // 어제(11/24) 끝난 수업 3개, 어제 녹음 0, 오늘 아침 녹음은 있음 → 조합(연속)은 아니고 정보 줄만.
        s.endedMeetings = [kst(24, 10), kst(24, 13), kst(24, 17)]
        s.recentRecordings = [kst(25, 9)]
        s.lastRecordingArrivalAt = kst(25, 9, 5)
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.code) == [.yesterdayNoRecordings])
        #expect(i[0].level == .info)
        #expect(i[0].message == "어제 끝난 수업·회의 3개 · 녹음 0")
    }

    @Test func yesterdayInfoSilentIfYesterdayHadRecording() {
        var s = healthy()
        s.endedMeetings = [kst(24, 10), kst(24, 13), kst(24, 17)]
        s.recentRecordings = [kst(24, 12), kst(25, 9)]
        s.lastRecordingArrivalAt = kst(25, 9, 5)
        #expect(codes(s).isEmpty)
    }

    @Test func multipleIssuesSortedRedFirst() {
        var s = healthy()
        s.notInCalendarThisWeek = 3
        s.googleToken = .invalidGrant
        s.diskFreeBytes = 1
        s.lostFolderAccess = ["~/Downloads"]
        let i = monitor.evaluate(s, now: now)
        #expect(i.map(\.code) == [.googleInvalidGrant, .diskLow, .folderAccessLost, .notInCalendar])
        #expect(i.map(\.level) == i.map(\.level).sorted())
    }

    @Test func evaluationIsDeterministic() {
        var s = healthy()
        s.missingSourcePaths = ["/b", "/a"]
        s.googleToken = .invalidGrant
        #expect(monitor.evaluate(s, now: now) == monitor.evaluate(s, now: now))
    }

    @Test func normalizeKeepsHigherLevelOfSameKey() {
        let a = HealthIssue(level: .info, code: .diskLow, message: "x", action: .none)
        let b = HealthIssue(level: .red, code: .diskLow, message: "y", action: .openStorage)
        let out = HealthMonitor.normalize([a, b, a])
        #expect(out == [b])
    }

    @Test func notificationsOnlyNewRedOnce() {
        var s = healthy()
        s.googleToken = .invalidGrant
        s.notInCalendarThisWeek = 5
        let issues = monitor.evaluate(s, now: now)
        let first = HealthMonitor.notifications(for: issues, alreadyNotified: [])
        #expect(first.new.map(\.code) == [.googleInvalidGrant])
        let second = HealthMonitor.notifications(for: issues, alreadyNotified: first.active)
        #expect(second.new.isEmpty)
        // 해결되면 active에서 빠져 재발 시 다시 알린다.
        let resolved = HealthMonitor.notifications(for: [], alreadyNotified: second.active)
        #expect(resolved.active.isEmpty)
        #expect(HealthMonitor.notifications(for: issues, alreadyNotified: resolved.active).new.count == 1)
    }
}

private extension HealthSnapshot {
    /// 마지막 녹음 도착·녹음 시각을 함께 맞춘다.
    mutating func lastRecordingAt(_ d: Date?) {
        lastRecordingArrivalAt = d
        recentRecordings = d.map { [$0] } ?? []
    }
}

// MARK: - TasksReconciler

private let reconciler = TasksReconciler()

@Suite struct TasksReconcilerTests {
    @Test func decodesTasksListPage() throws {
        let json = """
        {"kind":"tasks#tasks","items":[
          {"id":"t1","title":"데이터셋 올리기","status":"completed","updated":"2026-11-25T03:00:00.123Z",
           "due":"2026-11-27T00:00:00.000Z","notes":"mulgil:m1","completed":"2026-11-25T03:00:00.000Z","hidden":true},
          {"id":"t2","title":"연사 리스트","status":"needsAction","deleted":true,"updated":"2026-11-25T04:00:00Z"},
          {"id":"t3","title":"","status":"weird"}
        ],"nextPageToken":"p2"}
        """
        let page = try JSONDecoder().decode(TasksListPage.self, from: Data(json.utf8))
        #expect(page.items.count == 3)
        #expect(page.nextPageToken == "p2")
        #expect(page.items[0].status == .completed)
        #expect(page.items[0].hidden)
        #expect(page.items[0].deleted == false)
        #expect(page.items[0].due == Date(timeIntervalSince1970: 1_795_737_600))
        #expect(page.items[1].deleted)
        #expect(page.items[1].notes == nil)
        #expect(page.items[2].status == .unknown("weird"))
        #expect(page.items[2].updated == nil)
    }

    @Test func decodesEmptyListWithoutItemsKey() throws {
        let page = try JSONDecoder().decode(TasksListPage.self, from: Data(#"{"kind":"tasks#tasks"}"#.utf8))
        #expect(page.items.isEmpty)
    }

    @Test func badDateFailsDecoding() {
        let json = #"{"id":"x","due":"내일"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TasksItem.self, from: Data(json.utf8)) }
    }

    @Test func completedBecomesDone() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", status: .completed)],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges == [TasksMarkStateChange(markId: "m1", taskId: "t1", from: .open, to: .done, reason: .completedInTasks)])
        #expect(r.inserts.isEmpty)
    }

    @Test func deletedBecomesDropped() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", deleted: true)],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.map(\.to) == [.dropped])
        #expect(r.stateChanges.first?.reason == .deletedInTasks)
        #expect(r.inserts.isEmpty) // 버린 것을 다시 만들지 않는다
    }

    @Test func completedThenDeletedIsDone() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", status: .completed, deleted: true)],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.map(\.to) == [.done])
    }

    @Test func titleAndDueEditsAreNotRecovered() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", title: "폰에서 고친 제목", status: .needsAction, due: kst(30, 9))],
            marks: [TasksMarkSnapshot(id: "m1", text: "원래 제목", due: Due(date: kst(27, 0), hasTime: false),
                                      taskId: "t1", exportedDue: "2026-11-27T00:00:00.000Z")])
        #expect(r.stateChanges.isEmpty)
        #expect(r.inserts.isEmpty) // 폰에서 옮긴 날짜를 되돌리지도 않는다
        #expect(r.adoptions.isEmpty)
    }

    @Test func hiddenAloneChangesNothing() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", hidden: true)],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.isEmpty)
    }

    @Test func unknownStatusChangesNothing() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", status: .unknown("archived"))],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.isEmpty)
    }

    @Test func alreadyFinalMarksAreNotReopenedOrChanged() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", status: .needsAction), TasksItem(id: "t2", deleted: true)],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", state: .done, taskId: "t1"),
                    TasksMarkSnapshot(id: "m2", text: "b", state: .dropped, taskId: "t2")])
        #expect(r.stateChanges.isEmpty)
        #expect(r.inserts.isEmpty)
    }

    @Test func insertForConfirmedOweWithoutTask() {
        let r = reconciler.reconcile(remote: [], marks: [
            TasksMarkSnapshot(id: "m1", text: "  데이터셋 정리해서 올리기 ", due: Due(date: kst(27, 0), hasTime: false)),
        ])
        #expect(r.inserts.count == 1)
        let b = r.inserts[0].body
        #expect(b.title == "데이터셋 정리해서 올리기")
        #expect(b.due == "2026-11-27T00:00:00.000Z")
        #expect(b.notes == "mulgil:m1")
        #expect(b.status == "needsAction")
        #expect(r.inserts[0].replacesTaskId == nil)
    }

    @Test func dueUsesSeoulDateNotUTCDate() {
        // 11/27 00:30 KST = 11/26 15:30 UTC. 서울 날짜(27일)가 나와야 한다.
        let r = reconciler.reconcile(remote: [], marks: [
            TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(27, 0, 30), hasTime: true)),
            TasksMarkSnapshot(id: "m2", text: "b", due: Due(date: kst(27, 23, 50), hasTime: true)),
        ])
        #expect(r.inserts.map(\.body.due) == ["2026-11-27T00:00:00.000Z", "2026-11-27T00:00:00.000Z"])
    }

    @Test func insertWithoutDueOmitsDueField() throws {
        let r = reconciler.reconcile(remote: [], marks: [TasksMarkSnapshot(id: "m1", text: "a")])
        #expect(r.inserts.first?.body.due == nil)
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let s = String(decoding: try enc.encode(r.inserts[0].body), as: UTF8.self)
        #expect(s == #"{"notes":"mulgil:m1","status":"needsAction","title":"a"}"#)
    }

    @Test(arguments: [MarkKind.wait, .decision, .question])
    func onlyOweIsExported(kind: MarkKind) {
        let r = reconciler.reconcile(remote: [], marks: [TasksMarkSnapshot(id: "m1", kind: kind, text: "a")])
        #expect(r.inserts.isEmpty)
    }

    @Test func candidateIsNeverExported() {
        let r = reconciler.reconcile(remote: [], marks: [TasksMarkSnapshot(id: "m1", text: "a", state: .candidate)])
        #expect(r.inserts.isEmpty)
    }

    @Test func existingTaskIsNotInsertedAgain() {
        let r = reconciler.reconcile(remote: [], marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.inserts.isEmpty)
    }

    @Test func orphanWithNotesMarkerIsAdoptedNotDuplicated() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t9", notes: "폰에서 쓴 메모\nmulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a")])
        #expect(r.adoptions == [TasksAdoption(markId: "m1", taskId: "t9")])
        #expect(r.inserts.isEmpty)
    }

    @Test func adoptedAndCompletedInSameRun() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t9", status: .completed, notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a")])
        #expect(r.adoptions.count == 1)
        #expect(r.stateChanges.map(\.to) == [.done])
    }

    @Test func deletedOrphanIsNotAdoptedSoMarkIsReexported() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t9", deleted: true, notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a")])
        #expect(r.adoptions.isEmpty)
        #expect(r.stateChanges.isEmpty)
        #expect(r.inserts.map(\.markId) == ["m1"])
    }

    @Test func ourOwnDeletionOfOldTaskDoesNotDropMark() {
        // 기한 변경으로 t1을 지우고 t2를 만든 뒤: t1(deleted)도 같은 표식을 갖고 있다.
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", deleted: true, notes: "mulgil:m1"),
                     TasksItem(id: "t2", notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(28, 0), hasTime: false),
                                      taskId: "t2", exportedDue: "2026-11-28T00:00:00.000Z")])
        #expect(r.stateChanges.isEmpty)
        #expect(r.inserts.isEmpty)
    }

    @Test func localDueChangeRecreatesInsteadOfPatch() {
        let r = reconciler.reconcile(remote: [], marks: [
            TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(28, 0), hasTime: false),
                              taskId: "t1", exportedDue: "2026-11-27T00:00:00.000Z"),
        ])
        #expect(r.inserts.count == 1)
        #expect(r.inserts[0].replacesTaskId == "t1")
        #expect(r.inserts[0].body.due == "2026-11-28T00:00:00.000Z")
    }

    @Test func dueTimeChangeOnSameDayDoesNotRecreate() {
        let r = reconciler.reconcile(remote: [], marks: [
            TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(27, 18), hasTime: true),
                              taskId: "t1", exportedDue: "2026-11-27T00:00:00.000Z"),
        ])
        #expect(r.inserts.isEmpty)
    }

    @Test func duplicateIdsUseLatestUpdated() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", status: .completed, updated: kst(25, 10)),
                     TasksItem(id: "t1", status: .needsAction, updated: kst(25, 9))],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.map(\.to) == [.done])
        #expect(r.latestUpdated == kst(25, 10))
    }

    @Test func unrelatedRemoteItemsAreIgnored() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "x", status: .completed, notes: "내가 손으로 만든 할 일")],
            marks: [])
        #expect(r.stateChanges.isEmpty && r.inserts.isEmpty && r.adoptions.isEmpty)
    }

    @Test func notesMarkerParsing() {
        #expect(TasksReconciler.markId(fromNotes: "mulgil:abc") == "abc")
        #expect(TasksReconciler.markId(fromNotes: "메모\n  mulgil: abc \n") == "abc")
        #expect(TasksReconciler.markId(fromNotes: "mulgil:") == nil)
        #expect(TasksReconciler.markId(fromNotes: "그냥 메모") == nil)
        #expect(TasksReconciler.markId(fromNotes: nil) == nil)
    }

    @Test func outputOrderIsDeterministic() {
        let marks = ["m3", "m1", "m2"].map { TasksMarkSnapshot(id: $0, text: $0) }
        let r = reconciler.reconcile(remote: [], marks: marks)
        #expect(r.inserts.map(\.markId) == ["m1", "m2", "m3"])
    }

    @Test func rfc3339UpdatedMinRoundTrip() {
        let d = Date(timeIntervalSince1970: 1_795_737_600.5)
        let s = TasksRFC3339.string(from: d)
        #expect(s == "2026-11-27T00:00:00.500Z")
        #expect(TasksRFC3339.parse(s) == d)
    }
}

// MARK: - 적대적 리뷰: 경계 사례

private func seoul(_ y: Int, _ mo: Int, _ d: Int, _ hh: Int, _ mm: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = hh; c.minute = mm
    return Seoul.calendar.date(from: c)!
}

@Suite struct HealthEdgeTests {
    @Test func futureRecordingTimestampDoesNotSilenceCombo() {
        // 1904 기본값 오해석·시계 어긋남으로 미래 시각이 들어와도 경보가 영영 꺼지면 안 된다.
        var s = healthy()
        s.lastRecordingArrivalAt = nil
        s.recentRecordings = [now.addingTimeInterval(48 * 3600)]
        s.endedMeetings = [h(20), h(10), h(5)]
        #expect(codes(s) == [.recordingsMissing])
    }

    @Test func futureArrivalDoesNotSilenceG2() {
        var s = healthy()
        s.phonePath = .folderSync
        s.lastRecordingArrivalAt = now.addingTimeInterval(5 * 3600)
        s.recentRecordings = []
        #expect(codes(s) == [.phoneNoArrival])
    }

    @Test func futureLastConnectedFallsBackToLastSeen() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = now.addingTimeInterval(3600)
        s.phoneLastSeen = h(30)
        #expect(codes(s) == [.phoneDisconnected])
    }

    @Test func connectionRecordFromBeforePathEstablishedIsIgnored() {
        // 폰을 새로 짝지은 지 2시간: 옛 기기의 사흘 전 연결 기록으로 첫날부터 빨강을 띄우지 않는다.
        var s = healthy()
        s.phonePathEstablishedAt = h(2)
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(72)
        s.phoneLastSeen = h(72)
        #expect(codes(s).isEmpty)
    }

    @Test func disconnectedExactly24hIsNotYetRed() {
        var s = healthy()
        s.phoneConnected = false
        s.phoneLastConnectedAt = h(24)
        #expect(codes(s).isEmpty)
        s.phoneLastConnectedAt = h(24.01)
        #expect(codes(s) == [.phoneDisconnected])
    }

    @Test func duplicatedMeetingEndIsCountedOnce() {
        // 같은 회차가 개인·수업 캘린더 양쪽에 걸린 경우. 실제 회의는 2개다.
        var s = healthy()
        s.lastRecordingAt(h(30))
        s.endedMeetings = [h(10), h(5), h(5)]
        #expect(codes(s).isEmpty)
    }

    @Test func yesterdayInfoWaitsForGraceAcrossMidnight() {
        // 11/25 23:50에 끝난 수업의 녹음이 아직 오는 중인 11/26 00:10에는 "어제 3개 · 녹음 0"을 띄우지 않는다.
        var s = healthy()
        s.lastRecordingAt(kst(24, 9))
        s.endedMeetings = [kst(25, 10), kst(25, 14), kst(25, 23, 50)]
        let justAfterMidnight = kst(26, 0, 10)
        #expect(monitor.evaluate(s, now: justAfterMidnight).isEmpty)
        // 유예가 지나면 3개 연속 + 녹음 0 조합으로 노랑.
        #expect(monitor.evaluate(s, now: kst(26, 1, 30)).map(\.code) == [.recordingsMissing])
    }

    @Test func yesterdayInfoAcrossYearEnd() {
        let newYear = seoul(2027, 1, 1, 10)
        var s = healthy()
        s.phoneLastConnectedAt = newYear.addingTimeInterval(-600)
        // 옛 녹음이 오늘 아침에 도착해서 "연속 3개" 조합은 아니다.
        s.lastRecordingArrivalAt = seoul(2027, 1, 1, 8)
        s.recentRecordings = [seoul(2026, 12, 30, 20)]
        s.endedMeetings = [seoul(2026, 12, 30, 23, 59), seoul(2026, 12, 31, 9), seoul(2026, 12, 31, 11),
                           seoul(2026, 12, 31, 13), seoul(2027, 1, 1, 9)]
        let issues = monitor.evaluate(s, now: newYear)
        #expect(issues.map(\.code) == [.yesterdayNoRecordings])
        #expect(issues.first?.message == "어제 끝난 수업·회의 3개 · 녹음 0")
        #expect(issues.first?.level == .info)
    }

    @Test func duplicateSubjectsAreDeduplicated() {
        var s = healthy()
        s.missingSourcePaths = ["/a", "/b", "/a"]
        s.failedTranscriptions = ["r1", "r1"]
        let issues = monitor.evaluate(s, now: now)
        #expect(issues.map(\.key) == ["sourcePathMissing|/a", "sourcePathMissing|/b", "transcriptionFailed|r1"])
    }

    @Test func establishedPathWithAllUnknownsIsSilent() {
        #expect(codes(HealthSnapshot(phonePathEstablishedAt: h(100))).isEmpty)
    }

    @Test func diskExactly10GBIsNotLow() {
        var s = healthy()
        s.diskFreeBytes = 10_000_000_000
        #expect(codes(s).isEmpty)
        s.diskFreeBytes = 9_999_999_999
        #expect(codes(s) == [.diskLow])
    }

    @Test func resolvedRedIsNotifiedAgainWhenItRecurs() {
        var s = healthy()
        s.googleToken = .invalidGrant
        let first = HealthMonitor.notifications(for: monitor.evaluate(s, now: now), alreadyNotified: [])
        #expect(first.new.map(\.code) == [.googleInvalidGrant])
        let resolved = HealthMonitor.notifications(for: monitor.evaluate(healthy(), now: now), alreadyNotified: first.active)
        #expect(resolved.new.isEmpty && resolved.active.isEmpty)
        let again = HealthMonitor.notifications(for: monitor.evaluate(s, now: now), alreadyNotified: resolved.active)
        #expect(again.new.map(\.code) == [.googleInvalidGrant])
    }
}

@Suite struct TasksEdgeTests {
    @Test func dueAcrossYearEndUsesSeoulDate() {
        // 1/1 00:30 KST는 UTC로 12/31이지만 서울 날짜는 1/1이다.
        #expect(TasksRFC3339.dueString(for: seoul(2026, 12, 31, 23, 30)) == "2026-12-31T00:00:00.000Z")
        #expect(TasksRFC3339.dueString(for: seoul(2027, 1, 1, 0, 30)) == "2027-01-01T00:00:00.000Z")
        #expect(TasksRFC3339.dueString(for: seoul(2027, 1, 1, 0, 0)) == "2027-01-01T00:00:00.000Z")
    }

    @Test func dueAtMonthEndAndLeapDay() {
        #expect(TasksRFC3339.dueString(for: seoul(2026, 11, 30, 23, 59)) == "2026-11-30T00:00:00.000Z")
        #expect(TasksRFC3339.dueString(for: seoul(2028, 2, 29, 12)) == "2028-02-29T00:00:00.000Z")
        #expect(TasksRFC3339.dueString(for: seoul(2028, 3, 1, 0, 5)) == "2028-03-01T00:00:00.000Z")
    }

    @Test func remoteDueRoundTripsInUTC() throws {
        let json = #"{"id":"t","due":"2027-01-01T00:00:00.000Z"}"#
        let item = try JSONDecoder().decode(TasksItem.self, from: Data(json.utf8))
        // 서울 달력으로 읽으면 같은 날이지만, 12/31 자정 UTC는 서울로 12/31 09:00이라 UTC로 읽어야 한다.
        #expect(TasksReconciler.utcDueString(item.due) == "2027-01-01T00:00:00.000Z")
        #expect(TasksReconciler.utcDueString(TasksRFC3339.parse("2026-12-31T00:00:00.000Z")) == "2026-12-31T00:00:00.000Z")
    }

    @Test func duplicateMarksInsertOnce() {
        let m = TasksMarkSnapshot(id: "m1", text: "보고서")
        let r = reconciler.reconcile(remote: [], marks: [m, m])
        #expect(r.inserts.map(\.markId) == ["m1"])
    }

    @Test func blankTitleIsNotExported() {
        let r = reconciler.reconcile(remote: [], marks: [TasksMarkSnapshot(id: "m1", text: "  \n ")])
        #expect(r.inserts.isEmpty)
    }

    @Test func emptyInputIsEmptyResult() {
        let r = reconciler.reconcile(remote: [], marks: [])
        #expect(r.inserts.isEmpty && r.stateChanges.isEmpty && r.adoptions.isEmpty)
        #expect(r.latestUpdated == nil)
    }

    @Test func crashDuringRecreateDoesNotDropMark() {
        // 기한 변경 재생성: t2를 만들고 t1을 지운 뒤 로컬 task_id를 저장하기 전에 죽었다.
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", deleted: true, notes: "mulgil:m1"),
                     TasksItem(id: "t2", due: TasksRFC3339.parse("2026-11-28T00:00:00.000Z"), notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(28, 0), hasTime: false),
                                      taskId: "t1", exportedDue: "2026-11-27T00:00:00.000Z")])
        #expect(r.stateChanges.isEmpty)
        #expect(r.adoptions == [TasksAdoption(markId: "m1", taskId: "t2", exportedDue: "2026-11-28T00:00:00.000Z")])
        #expect(r.inserts.isEmpty) // 재생성을 또 내보내 중복을 만들지 않는다
    }

    @Test func userDeletionWithoutReplacementStillDrops() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", deleted: true, notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.stateChanges.map(\.to) == [.dropped])
        #expect(r.adoptions.isEmpty)
    }

    @Test func replacementCompletedAfterCrashBecomesDone() {
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t1", deleted: true, notes: "mulgil:m1"),
                     TasksItem(id: "t2", status: .completed, notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", taskId: "t1")])
        #expect(r.adoptions.map(\.taskId) == ["t2"])
        #expect(r.stateChanges == [TasksMarkStateChange(markId: "m1", taskId: "t2", from: .open, to: .done, reason: .completedInTasks)])
    }

    @Test func orphanAdoptionDoesNotRevertPhoneMovedDate() {
        // 표식으로 입양한 항목의 날짜를 폰에서 옮겼어도 이번 회차에 재생성하지 않는다.
        let r = reconciler.reconcile(
            remote: [TasksItem(id: "t9", due: TasksRFC3339.parse("2026-11-30T00:00:00.000Z"), notes: "mulgil:m1")],
            marks: [TasksMarkSnapshot(id: "m1", text: "a", due: Due(date: kst(27, 0), hasTime: false))])
        #expect(r.adoptions == [TasksAdoption(markId: "m1", taskId: "t9", exportedDue: "2026-11-30T00:00:00.000Z")])
        #expect(r.inserts.isEmpty)
    }
}
