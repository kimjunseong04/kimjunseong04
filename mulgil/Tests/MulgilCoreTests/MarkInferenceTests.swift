import Foundation
import Testing
@testable import MulgilCore

// MARK: - MarkInference: 줄 추론

@Suite struct MarkInferenceLineTests {
    func one(_ s: String) -> MarkInferenceResult { MarkInference.infer(s)! }

    @Test(arguments: [
        "연사 리스트 금요일까지 공유할게",
        "연사 리스트 금요일까지 공유할게요",
        "자료 정리해서 공유할께",
        "발표 자료 해올게",
        "견적서 메일로 보낼게",
        "회의록 노션에 올릴게요",
        "데이터셋 정리해서 공유할게.",
        "제가 다음 주까지 초안 작성하겠습니다",
        "슬라이드 수정하겠음",
        "예약은 내가 알아볼게 내일까지",
        "책 읽을게요",
        "교수님께 메일 드릴께요",
    ])
    func owePromise(_ s: String) {
        let r = one(s)
        #expect(r.kind == .owe)
        #expect(r.rule == .owePromise)
    }

    @Test func promiseFalsePositiveAlgeDwaetda() {
        let r = one("새로운 사실을 알게 됐다")
        #expect(r.kind == .decision)
        #expect(r.rule == .decisionDefault)
    }

    @Test func promiseFalsePositiveGlued() {
        #expect(one("오늘 할게임 정함").kind == .decision)
    }

    @Test(arguments: ["예산안 ← 민지", "예산안 <- 민지", "예산안←민지", "예산안 <-- 민지"])
    func waitArrow(_ s: String) {
        let r = one(s)
        #expect(r.kind == .wait)
        #expect(r.rule == .waitArrow)
        #expect(r.who == "민지")
        #expect(r.text == "예산안")
    }

    @Test func waitArrowKeepsRestForDateParser() {
        let r = one("예산안 ← 민지 금요일까지")
        #expect(r.who == "민지")
        #expect(r.text == "예산안 금요일까지")
    }

    @Test func waitArrowBeatsPromise() {
        let r = one("장소 확인해 줄게 ← 지훈")
        #expect(r.kind == .wait)
        #expect(r.who == "지훈")
    }

    @Test func waitReceiveWithWho() {
        let r = one("민지한테 예산안 받기로 함")
        #expect(r.kind == .wait)
        #expect(r.rule == .waitReceive)
        #expect(r.who == "민지")
    }

    @Test func waitReceiveVariants() {
        #expect(one("교수님께 피드백 받기로").who == "교수님")
        #expect(one("지훈에게서 로그 받기로 했음").who == "지훈")
        #expect(one("모두 함께 받기로 했음").who == nil)
        #expect(one("제가 민지한테 받기로 했어요").kind == .wait)
    }

    @Test func waitGive() {
        let r = one("민지가 예산안 주기로 했음")
        #expect(r.kind == .wait)
        #expect(r.rule == .waitGive)
        #expect(r.who == "민지")
        #expect(one("민지 씨가 보내주기로 함").who == "민지")
    }

    @Test func firstPersonGiveIsOwe() {
        let r = one("내가 자료 주기로 했어")
        #expect(r.kind == .owe)
        #expect(r.rule == .oweCommit)
    }

    @Test func firstPersonCommit() {
        let r = one("제가 장소 섭외하기로 했어요")
        #expect(r.kind == .owe)
        #expect(r.rule == .oweCommit)
    }

    @Test(arguments: ["예산 승인 주체?", "장소는 어디로 하지？", "내가 할까?", "발표 누가 해?)"])
    func questionMark(_ s: String) {
        let r = one(s)
        #expect(r.kind == .question)
        #expect(r.rule == .questionMark)
    }

    @Test(arguments: ["예산 승인 주체 미정", "날짜 정해야 함", "장소 결정 필요", "장소 결정필요", "연사 TBD", "연사 tbd"])
    func questionUndecided(_ s: String) {
        let r = one(s)
        #expect(r.kind == .question)
        #expect(r.rule == .questionUndecided)
    }

    @Test func promiseBeatsUndecided() {
        #expect(one("미정인 장소 내가 알아볼게").kind == .owe)
    }

    @Test(arguments: ["12월 밋업 장소 = 판교", "다음 회의는 목요일 7시", "회비 2만 원으로"])
    func decisionDefault(_ s: String) {
        let r = one(s)
        #expect(r.kind == .decision)
        #expect(r.rule == .decisionDefault)
        #expect(r.who == nil)
    }

    @Test func explicitLabels() {
        #expect(one("할 것: 연사 리스트 공유").kind == .owe)
        #expect(one("내가 할 것: 연사 리스트").text == "연사 리스트")
        #expect(one("정한 것: 장소 판교 할게").kind == .decision)
        #expect(one("미정: 예산 승인 주체").kind == .question)
        #expect(one("받을 것：예산안").kind == .wait)
        #expect(one("정한 것: 장소 판교").rule == .explicitLabel)
    }

    @Test func explicitWaitLabelWithArrow() {
        let r = one("기다리는 것: 예산안 ← 민지")
        #expect(r.kind == .wait)
        #expect(r.rule == .explicitLabel)
        #expect(r.who == "민지")
        #expect(r.text == "예산안")
    }

    @Test func emptyLabelIsNil() {
        #expect(MarkInference.infer("할 것:") == nil)
    }

    @Test func bulletsStripped() {
        #expect(one("- 연사 리스트 공유할게").text == "연사 리스트 공유할게")
        #expect(one("• 장소 판교").text == "장소 판교")
        #expect(one("2. 예산안 ← 민지").who == "민지")
        #expect(one("- [ ] 회의록 올릴게").kind == .owe)
    }

    @Test func blankIsNil() {
        #expect(MarkInference.infer("") == nil)
        #expect(MarkInference.infer("   \t ") == nil)
        #expect(MarkInference.infer("- ") == nil)
    }

    @Test func spacesCollapsed() {
        let r = one("  장소   판교  ")
        #expect(r.line == "장소 판교")
        #expect(r.text == "장소 판교")
    }

    @Test func multiLine() {
        let rs = MarkInference.inferLines("연사 리스트 금요일까지 공유할게\n\n예산안 ← 민지\r\n장소 판교\n예산 승인 주체?")
        #expect(rs.map(\.kind) == [.owe, .wait, .decision, .question])
    }

    @Test func overrideKeepsRuleAndFlags() {
        let r = one("장소 판교").overriding(kind: .owe)
        #expect(r.kind == .owe)
        #expect(r.rule == .decisionDefault)
        #expect(r.overridden)
        let w = one("예산안 ← 민지").overriding(kind: .decision)
        #expect(w.who == nil)
        #expect(!one("장소 판교").overriding(kind: .decision).overridden)
    }

    @Test func everyRuleHasHint() {
        for r in MarkInferenceRule.allCases { #expect(!r.hint.isEmpty) }
        #expect(MarkInferenceRule.waitArrow.rawValue == "wait.arrow")
    }

    @Test func deterministic() {
        let s = "연사 리스트 금요일까지 공유할게\n예산안 ← 민지"
        #expect(MarkInference.inferLines(s) == MarkInference.inferLines(s))
    }
}

// MARK: - MarkInference: 호출어

@Suite struct MarkInferenceVoiceTests {
    func seg(_ t0: Double, _ text: String, len: Double = 5) -> MarkInferenceSegment {
        MarkInferenceSegment(t0: t0, t1: t0 + len, text: text)
    }

    @Test func basicOwe() {
        let c = MarkInference.voiceCandidates([seg(100, "오늘 회의 끝."), seg(2400, "물길, 내가 할 것: 연사 리스트 금요일까지.")])
        #expect(c.count == 1)
        #expect(c[0].kind == .owe)
        #expect(c[0].text == "연사 리스트 금요일까지")
        #expect(c[0].t0 == 2400)
        #expect(c[0].label == "내가 할 것")
        #expect(c[0].hotword == "물길")
    }

    @Test(arguments: ["물길, 할 것: 회의록", "물길아 할 것: 회의록", "물 길, 할 것: 회의록", "무길, 할 것: 회의록",
                      "물길야, 할 것 회의록", "물 길 아, 할것, 회의록", "물길. 할 거 회의록", "  물길, 할 것은 회의록"])
    func hotwordVariants(_ text: String) {
        let c = MarkInference.voiceCandidates([seg(0, text)])
        #expect(c.count == 1)
        #expect(c.first?.kind == .owe)
        #expect(c.first?.text == "회의록")
    }

    @Test(arguments: ["물기, 할 것: 회의록", "무기 할 것: 회의록", "물결, 할 것: 회의록", "물길이 할 것 회의록", "흙물길, 할 것: 회의록"])
    func hotwordRejected(_ text: String) {
        #expect(MarkInference.voiceCandidates([seg(0, text)]).isEmpty)
    }

    @Test func hotwordWithoutLabelIgnored() {
        #expect(MarkInference.voiceCandidates([seg(0, "물길 따라 걸었다")]).isEmpty)
        #expect(MarkInference.voiceCandidates([seg(0, "물길, 오늘 수고했어")]).isEmpty)
    }

    @Test func labelsMapToKinds() {
        let c = MarkInference.voiceCandidates([
            seg(0, "물길, 받을 것: 예산안 민지한테서."),
            seg(5, "물길, 정한 것: 장소 판교."),
            seg(10, "물길, 미정: 예산 승인 주체."),
            seg(15, "물길, 기다리는 것: 포스터 시안."),
        ])
        #expect(c.map(\.kind) == [.wait, .decision, .question, .wait])
        #expect(c[0].who == "민지")
        #expect(c[0].text == "예산안 민지한테서")
    }

    @Test func multipleLabelsInOneUtterance() {
        let c = MarkInference.voiceCandidates([seg(0, "물길, 내가 할 것: 연사 리스트 금요일까지. 받을 것: 예산안 민지한테서. 정한 것, 장소 판교")])
        #expect(c.map(\.kind) == [.owe, .wait, .decision])
        #expect(c.map(\.text) == ["연사 리스트 금요일까지", "예산안 민지한테서", "장소 판교"])
    }

    @Test func doesNotSplitNaturalHalGeot() {
        let c = MarkInference.voiceCandidates([seg(0, "물길, 할 것: 보고서 정리해야 할 것 같아")])
        #expect(c.count == 1)
        #expect(c[0].text == "보고서 정리해야 할 것 같아")
    }

    @Test func twoHotwordsInOneSegment() {
        let c = MarkInference.voiceCandidates([seg(0, "물길, 할 것: 회의록 올리기. 물길아 정한 것: 다음 주 휴회.")])
        #expect(c.map(\.kind) == [.owe, .decision])
        #expect(c[0].text == "회의록 올리기")
        #expect(c[1].hotword == "물길아")
    }

    @Test func bodyContinuesInNextSegment() {
        let c = MarkInference.voiceCandidates([seg(10, "물길, 내가 할 것:"), seg(15, "연사 리스트 금요일까지.")])
        #expect(c.count == 1)
        #expect(c[0].text == "연사 리스트 금요일까지")
        #expect(c[0].t0 == 10)
        #expect(c[0].segmentIndex == 0)
    }

    @Test func emptyBodyAtEndIsDropped() {
        #expect(MarkInference.voiceCandidates([seg(0, "물길, 할 것:")]).isEmpty)
    }

    @Test func tailWindowExcludesEarly() {
        let segs = [seg(0, "물길, 할 것: 옛날 이야기"), seg(3000, "마무리"), seg(3590, "물길, 할 것: 회의록")]
        let c = MarkInference.voiceCandidates(segs)
        #expect(c.map(\.text) == ["회의록"])
        #expect(MarkInference.voiceCandidates(segs, tailWindow: nil).count == 2)
    }

    @Test func tailWindowBoundaryIncludesOverlap() {
        // 끝 3600, 창 90 → t1 ≥ 3510 이면 포함
        let segs = [seg(3500, "물길, 할 것: 경계", len: 10), seg(3595, "끝")]
        #expect(MarkInference.voiceCandidates(segs).map(\.text) == ["경계"])
        let segs2 = [seg(3500, "물길, 할 것: 경계", len: 9.9), seg(3595, "끝")]
        #expect(MarkInference.voiceCandidates(segs2).isEmpty)
    }

    @Test func emptyInput() {
        #expect(MarkInference.voiceCandidates([]).isEmpty)
    }

    @Test func midSentenceAfterPunctuation() {
        let c = MarkInference.voiceCandidates([seg(0, "네 그럼 이만. 물길, 할 것: 회의록")])
        #expect(c.map(\.text) == ["회의록"])
    }

    @Test func startsWithHotword() {
        #expect(MarkInference.startsWithHotword("물길, 내가 할 것"))
        #expect(MarkInference.startsWithHotword("  물 길아 할 것"))
        #expect(!MarkInference.startsWithHotword("오늘 물길, 할 것"))
        #expect(!MarkInference.startsWithHotword("물기 할 것"))
    }
}

// MARK: - InboxCapture

@Suite struct InboxCaptureTests {
    // 2026-11-23 10:00 KST
    let base: Date = Seoul.calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10))!

    func ev(_ title: String, id: String = "e1", cal: String = "primary", startOffset: TimeInterval = 3600,
            cancelled: Bool = false) -> CalendarEvent {
        let s = base.addingTimeInterval(startOffset)
        return CalendarEvent(key: OccurrenceKey(calendarId: cal, seriesId: id, originalStart: nil), id: id, calendarId: cal,
                             title: title, start: s, end: s.addingTimeInterval(3600), cancelled: cancelled)
    }

    @Test(arguments: [
        ("#그럼 목욜 7시 공학관", "그럼 목욜 7시 공학관"),
        ("# 그럼 목욜 7시 공학관", "그럼 목욜 7시 공학관"),
        ("＃그럼 목욜 7시", "그럼 목욜 7시"),
        ("＃ 그럼 목욜 7시", "그럼 목욜 7시"),
        ("﹟연사 리스트", "연사 리스트"),
        ("  #연사 리스트", "연사 리스트"),
        ("\u{3000}#연사 리스트", "연사 리스트"),
        ("\u{00A0}#연사 리스트", "연사 리스트"),
        ("\u{200B}#연사 리스트", "연사 리스트"),
        ("\u{FEFF}＃연사 리스트", "연사 리스트"),
        ("##연사 리스트", "연사 리스트"),
        ("# # 연사 리스트", "연사 리스트"),
        ("#연사 리스트 금요일까지  ", "연사 리스트 금요일까지"),
        ("#AUSG 밋업 연사 섭외", "AUSG 밋업 연사 섭외"),
        ("#3시 공학관", "3시 공학관"),
        ("#2차 회의 목요일", "2차 회의 목요일"),
        ("#놓침: 과제 제출", "놓침: 과제 제출"),
        ("#그럼  목욜   7시", "그럼  목욜   7시"),
    ])
    func recognized(_ pair: (String, String)) {
        #expect(InboxCapture.body(ofTitle: pair.0) == pair.1)
        #expect(InboxCapture.isInboxTitle(pair.0))
    }

    @Test(arguments: [
        "AUSG 운영 회의", "회의 #AUSG", "", "   ", "#", "# ", "＃　", "##", "#3 정기회의", "#12", "#2. 발표", "#3) 회의",
        "＃4 세미나", "· AUSG 운영 회의 맥락", "♯연사",
    ])
    func notRecognized(_ title: String) {
        #expect(InboxCapture.body(ofTitle: title) == nil)
        #expect(!InboxCapture.isInboxTitle(title))
    }

    @Test func captureUsesCreated() {
        let created = base.addingTimeInterval(-120)
        let item = InboxCapture.capture(ev("#그럼 목욜 7시"), created: created)!
        #expect(item.text == "그럼 목욜 7시")
        #expect(item.createdAt == created)
        #expect(item.createdAtSource == .created)
        #expect(item.stableKey == "inbox|e1")
        #expect(item.eventId == "e1")
        #expect(item.calendarId == "primary")
        #expect(item.rawTitle == "#그럼 목욜 7시")
    }

    @Test func captureFallsBackToStart() {
        let item = InboxCapture.capture(ev("#그럼 목욜 7시"))!
        #expect(item.createdAt == base.addingTimeInterval(3600))
        #expect(item.createdAtSource == .start)
    }

    @Test func cancelledIgnored() {
        #expect(InboxCapture.capture(ev("#연사", cancelled: true)) == nil)
    }

    @Test func nonInboxEventIsNil() {
        #expect(InboxCapture.capture(ev("AUSG 운영 회의")) == nil)
    }

    @Test func stableKeySurvivesMove() {
        let before = InboxCapture.capture(ev("#연사", id: "abc", cal: "primary"))!
        let after = InboxCapture.capture(ev("#연사", id: "abc", cal: "mulgil-inbox"))!
        #expect(before.stableKey == after.stableKey)
        #expect(before.calendarId != after.calendarId)
    }

    @Test func stableKeyIndependentOfTitleEdit() {
        let a = InboxCapture.capture(ev("#연사", id: "x"))!
        let b = InboxCapture.capture(ev("#연사 리스트 금요일", id: "x"))!
        #expect(a.stableKey == b.stableKey)
    }

    @Test func pendingSkipsProcessedAndNonInbox() {
        let events = [ev("#a", id: "1"), ev("회의", id: "2"), ev("#b", id: "3"), ev("#c", id: "4", cancelled: true)]
        let p = InboxCapture.pending(events, processed: [InboxCapture.stableKey(eventId: "1")])
        #expect(p.map(\.eventId) == ["3"])
    }

    @Test func pendingDedupesAcrossCalendars() {
        let events = [ev("#a", id: "1", cal: "primary"), ev("#a", id: "1", cal: "mulgil-inbox")]
        let p = InboxCapture.pending(events)
        #expect(p.count == 1)
        #expect(p[0].calendarId == "primary")
    }

    @Test func pendingSortedByCreatedThenKey() {
        let events = [ev("#late", id: "z"), ev("#early", id: "y"), ev("#tieB", id: "b"), ev("#tieA", id: "a")]
        let created: [String: Date] = [
            "z": base.addingTimeInterval(300), "y": base.addingTimeInterval(-300),
            "b": base, "a": base,
        ]
        let p = InboxCapture.pending(events, created: created)
        #expect(p.map(\.eventId) == ["y", "a", "b", "z"])
        #expect(p.allSatisfy { $0.createdAtSource == .created })
    }

    @Test func pendingEmpty() {
        #expect(InboxCapture.pending([]).isEmpty)
    }

    @Test func itemIsCodableRoundTrip() throws {
        let item = InboxCapture.capture(ev("#연사"), created: base)!
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(InboxCaptureItem.self, from: data) == item)
    }

    @Test func voiceTypedInboxFlowsIntoInference() {
        // 폰 '#' 입력도 같은 종류 추론을 탄다(§7.9 "폰에서 넣은 것").
        let item = InboxCapture.capture(ev("#연사 리스트 금요일까지 공유할게"))!
        #expect(MarkInference.infer(item.text)?.kind == .owe)
    }
}

// MARK: - 적대적 리뷰에서 추가한 경계 사례

@Suite struct MarkInferenceReviewTests {
    func one(_ s: String) -> MarkInferenceResult { MarkInference.infer(s)! }
    func seg(_ t0: Double, _ text: String, len: Double = 5) -> MarkInferenceSegment {
        MarkInferenceSegment(t0: t0, t1: t0 + len, text: text)
    }

    // 부사형 형용사 '~ㄹ게'는 약속이 아니다.
    @Test(arguments: ["힘들게 합의함", "회의를 길게 논의함", "멀게 느껴짐", "낯설게 봄"])
    func adverbialRieulGeIsNotPromise(_ s: String) {
        #expect(one(s).kind == .decision)
    }

    // 접미가 같아도 동사면 약속이다(맡길게 ≠ 길게, 만들게 ≠ 힘들게).
    @Test(arguments: ["그 건 민지한테 맡길게", "목업 만들게", "댓글 달게요"])
    func verbRieulGeStillPromise(_ s: String) {
        #expect(one(s).kind == .owe)
    }

    // 추측·바람·응답의 '겠'은 약속이 아니다.
    @Test(arguments: ["금요일까지 끝나면 좋겠어요", "네 알겠습니다", "그렇게 하면 되겠습니다", "장소는 괜찮겠어요", "잘 모르겠어요"])
    func nonPromiseGet(_ s: String) {
        #expect(one(s).kind != .owe)
    }

    @Test func promiseGetStillOwe() {
        #expect(one("제가 확인해 보겠습니다").kind == .owe)
        #expect(one("초안 작성하겠습니다").kind == .owe)
    }

    // 주어 생략 + 3인칭에게 주기로 → 주는 사람은 나.
    @Test func implicitSubjectGiveToOtherIsOwe() {
        let r = one("민지한테 자료 주기로 했어")
        #expect(r.kind == .owe)
        #expect(r.rule == .oweCommit)
    }

    @Test func giveToMeIsWait() {
        let a = one("민지가 나한테 자료 주기로 했어")
        #expect(a.kind == .wait)
        #expect(a.who == "민지")
        #expect(one("저한테 보내주기로 하셨음").kind == .wait)
        #expect(one("교수님께서 피드백 주기로 하셨음").who == "교수님")
    }

    @Test func tbdInsideWordIsNotUndecided() {
        #expect(one("ATBDX 장비로 결정").kind == .decision)
        #expect(one("장소: TBD").kind == .question)
    }

    // 빈 입력·공백·글머리뿐인 줄.
    @Test func emptyAndWhitespaceInputs() {
        #expect(MarkInference.infer("") == nil)
        #expect(MarkInference.infer(" \t\u{3000} ") == nil)
        #expect(MarkInference.infer("- ") == nil)
        #expect(MarkInference.inferLines("\n\r\n\n").isEmpty)
        #expect(MarkInference.inferLines("할게\r\n장소 미정").map(\.kind) == [.owe, .question])
    }

    // 라벨 뒤에 한글이 붙으면 라벨이 아니다.
    @Test func gluedLabelIsNotLabel() {
        #expect(MarkInference.voiceCandidates([seg(0, "물길, 할 거야 그거")]).isEmpty)
        #expect(MarkInference.voiceCandidates([seg(0, "물길, 미정인 건 많아")]).isEmpty)
        let c = MarkInference.voiceCandidates([seg(0, "물길, 정한 것은 장소 판교")])
        #expect(c.map(\.kind) == [.decision])
        #expect(c.first?.text == "장소 판교")
    }

    // Whisper 반복 루프: 같은 발화가 여러 세그먼트로 반복돼도 후보는 하나.
    @Test func whisperRepetitionDeduped() {
        let segs = (0..<20).map { seg(Double($0) * 3, "물길, 내가 할 것: 연사 리스트 공유.") }
        let c = MarkInference.voiceCandidates(segs)
        #expect(c.count == 1)
        #expect(c.first?.t0 == 0)
    }

    // 세그먼트 순서가 뒤섞여 와도 '다음 세그먼트'는 시간상 다음이다.
    @Test func unsortedSegmentsUseTimeOrder() {
        let segs = [seg(105, "회의록 정리 금요일까지"), seg(110, "회의 끝."), seg(100, "물길, 내가 할 것:")]
        let c = MarkInference.voiceCandidates(segs)
        #expect(c.count == 1)
        #expect(c.first?.text == "회의록 정리 금요일까지")
        #expect(c.first?.segmentIndex == 2)
    }

    // 이상치: t1 이 NaN/무한인 세그먼트 하나가 창 전체를 망가뜨리지 않는다.
    @Test func nonFiniteTimestampIgnored() {
        let segs = [seg(100, "물길, 할 것: 회의록"),
                    MarkInferenceSegment(t0: 105, t1: .nan, text: "잡음"),
                    MarkInferenceSegment(t0: 110, t1: .infinity, text: "잡음")]
        #expect(MarkInference.voiceCandidates(segs).map(\.text) == ["회의록"])
    }

    // 이상치: 창 밖(91초 전 끝난) 세그먼트는 빠지고 경계(정확히 90초)는 들어온다.
    @Test func windowBoundaryExact() {
        let segs = [seg(0, "물길, 할 것: 너무 이름", len: 9), seg(10, "물길, 할 것: 경계", len: 10), seg(100, "끝.", len: 10)]
        #expect(MarkInference.voiceCandidates(segs).map(\.text) == ["경계"])
    }

    // 자정을 넘긴 녹음(t 가 24시간 초과)도 상대 초 단위라 그대로 동작한다.
    @Test func recordingAcrossMidnight() {
        let late = 86_400.0 + 30
        let c = MarkInference.voiceCandidates([seg(late - 4000, "시작"), seg(late, "물길아 받을 것: 예산안 ← 민지")])
        #expect(c.count == 1)
        #expect(c.first?.kind == .wait)
        #expect(c.first?.who == "민지")
    }
}

@Suite struct InboxCaptureReviewTests {
    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        Seoul.calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
    func ev(_ title: String, id: String, start: Date, recurring: String? = nil, allDay: Bool = false,
            cal: String = "primary") -> CalendarEvent {
        CalendarEvent(key: OccurrenceKey(calendarId: cal, seriesId: recurring ?? id, originalStart: recurring == nil ? nil : start),
                      id: id, calendarId: cal, title: title, start: start, end: start.addingTimeInterval(3600),
                      isAllDay: allDay, recurringEventId: recurring)
    }

    // 시각·날짜로 시작하는 제목은 번호가 아니라 수신함이다.
    @Test(arguments: ["#7:30 공학관 회의", "#11.27 밋업 장소", "#12/3 회의 자료", "#3,000원 회비 입금"])
    func timeOrDatePrefixIsInbox(_ t: String) {
        #expect(InboxCapture.isInboxTitle(t))
    }

    // 전각 숫자 번호도 번호로 본다(보수적).
    @Test func fullWidthOrdinalNotInbox() {
        #expect(!InboxCapture.isInboxTitle("＃３ 정기회의"))
        #expect(!InboxCapture.isInboxTitle("#3: 정기회의"))
    }

    // 실수로 반복을 건 '#' 일정은 회차가 여럿이어도 수신함 항목 하나.
    @Test func recurringSeriesCollapsesToOne() {
        let s = at(2026, 11, 23, 19, 0)
        let evs = (0..<4).map { ev("#연사 리스트", id: "abc_2026112\($0)", start: s.addingTimeInterval(Double($0) * 86_400), recurring: "abc") }
        let p = InboxCapture.pending(evs)
        #expect(p.count == 1)
        #expect(p.first?.stableKey == "inbox|abc")
        #expect(InboxCapture.pending(evs, processed: ["inbox|abc"]).isEmpty)
    }

    // 연말 자정: 12/31 23:59:59 KST 와 1/1 00:00:00 KST 의 순서(UTC로는 같은 날 14:59/15:00).
    @Test func yearEndOrdering() {
        let a = ev("#새해 첫 회의", id: "b", start: at(2027, 1, 1, 9, 0))
        let b = ev("#연말 정산", id: "a", start: at(2027, 1, 1, 9, 0))
        let p = InboxCapture.pending([a, b], created: ["b": at(2027, 1, 1, 0, 0, 0), "a": at(2026, 12, 31, 23, 59, 59)])
        #expect(p.map(\.text) == ["연말 정산", "새해 첫 회의"])
        #expect(Seoul.calendar.component(.year, from: p[1].createdAt) == 2027)
    }

    // 월말 → 다음 달, created 가 없으면 start 를 쓰고 출처를 표시한다(종일 일정 포함).
    @Test func monthEndAllDayFallback() {
        let start = at(2026, 12, 1, 0, 0)
        let it = InboxCapture.capture(ev("#과제 제출", id: "x", start: start, allDay: true))!
        #expect(it.createdAt == start)
        #expect(it.createdAtSource == .start)
        let c = InboxCapture.capture(ev("#과제 제출", id: "x", start: start, allDay: true), created: at(2026, 11, 30, 23, 58))!
        #expect(Seoul.calendar.component(.month, from: c.createdAt) == 11)
        #expect(c.createdAtSource == .created)
    }

    // 중복: 같은 이벤트가 두 번(옮기기 전/후 미러) 들어와도 하나.
    @Test func exactDuplicateEvents() {
        let s = at(2026, 11, 23, 23, 59)
        let e = ev("#자정 직전 메모", id: "d", start: s)
        let moved = ev("#자정 직전 메모", id: "d", start: s, cal: "inbox-cal")
        #expect(InboxCapture.pending([e, e, moved]).count == 1)
    }

    @Test func emptyInputs() {
        #expect(InboxCapture.pending([]).isEmpty)
        #expect(InboxCapture.body(ofTitle: "\u{200B}\u{FEFF}") == nil)
        #expect(InboxCapture.body(ofTitle: "#\u{200B}") == nil)
    }
}
