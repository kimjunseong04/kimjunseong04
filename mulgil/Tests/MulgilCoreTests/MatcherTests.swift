import Foundation
import Testing
@testable import MulgilCore

// 모든 기준 시각은 서울 2026-11-23(월) 기준으로 고정한다.
private func at(_ h: Int, _ m: Int = 0, day: Int = 23, month: Int = 11, year: Int = 2026) -> Date {
    Seoul.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: h, minute: m))!
}

private let min_: TimeInterval = 60
private let hour: TimeInterval = 3600
private let now = at(23, 0)

private func file(creation: Date?, mtime: Date, duration: TimeInterval) -> RecordingFile {
    RecordingFile(path: "/inbox/phone/a.m4a", creationTime: creation, modificationTime: mtime, duration: duration)
}

private func ev(_ id: String, _ s: Date, _ e: Date, cal: String = "primary", series: String? = nil,
                 title: String = "회의", allDay: Bool = false, cancelled: Bool = false) -> CalendarEvent {
    CalendarEvent(key: OccurrenceKey(calendarId: cal, seriesId: series ?? id, originalStart: series == nil ? nil : s),
                  id: id, calendarId: cal, title: title, start: s, end: e, isAllDay: allDay,
                  recurringEventId: series, cancelled: cancelled)
}

private func matchedId(_ o: MatchOutcome) -> String? {
    if case .matched(let e, _) = o { return e.id } else { return nil }
}

// MARK: - RecordingTime

@Suite struct RecordingTimeTests {
    @Test func validCreationTimeIsStart() {
        let s = RecordingTime.resolve(file(creation: at(10), mtime: at(11), duration: hour), now: now)
        #expect(s.start == at(10))
        #expect(s.end == at(11))
        #expect(s.source == .creationTime)
        #expect(s.rejection == nil)
    }

    @Test func missingCreationFallsBackToMtimeMinusDuration() {
        let s = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: 30 * min_), now: now)
        #expect(s.start == at(10, 30))
        #expect(s.end == at(11))
        #expect(s.source == .modificationTimeMinusDuration)
        #expect(s.rejection == .missing)
    }

    @Test func epoch1904IsPlaceholder() {
        let d1904 = Date(timeIntervalSince1970: -2_082_844_800)
        let s = RecordingTime.resolve(file(creation: d1904, mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .placeholderEpoch)
        #expect(s.start == at(10))
    }

    @Test func unixZeroIsPlaceholder() {
        let s = RecordingTime.resolve(file(creation: Date(timeIntervalSince1970: 0), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .placeholderEpoch)
        #expect(s.source == .modificationTimeMinusDuration)
    }

    @Test func justAfterEarliestPlausibleIsAccepted() {
        let rules = RecordingTimeRules(earliestPlausible: at(9))
        let s = RecordingTime.resolve(file(creation: at(9), mtime: at(10), duration: hour), now: now, rules: rules)
        #expect(s.source == .creationTime)
    }

    @Test func futureCreationRejected() {
        let s = RecordingTime.resolve(file(creation: at(23, 10), mtime: at(23, 20), duration: 10 * min_), now: now)
        #expect(s.rejection == .inFuture)
    }

    @Test func futureWithinSkewAccepted() {
        // 기기 시계가 1분 빠른 정도는 허용한다.
        let c = now.addingTimeInterval(60)
        let s = RecordingTime.resolve(file(creation: c, mtime: c.addingTimeInterval(60), duration: 60), now: now)
        #expect(s.source == .creationTime)
    }

    @Test func creationAfterModificationRejected() {
        let s = RecordingTime.resolve(file(creation: at(12), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .afterModification)
        #expect(s.start == at(10))
    }

    @Test func creationSlightlyAfterModificationWithinSkewAccepted() {
        let s = RecordingTime.resolve(file(creation: at(11).addingTimeInterval(30), mtime: at(11), duration: 0),
                                      meaning: .savedAt, now: now)
        #expect(s.source == .creationTimeMinusDuration)
    }

    @Test func sixHourDisagreementRejected() {
        // 9시간 시간대 버그(UTC로 써야 할 곳에 현지 시각)
        let s = RecordingTime.resolve(file(creation: at(1), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .disagreesWithModification)
        #expect(s.start == at(10))
    }

    @Test func exactlySixHoursIsRejected() {
        let s = RecordingTime.resolve(file(creation: at(4), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .disagreesWithModification)
    }

    @Test func justUnderSixHoursAccepted() {
        let c = at(4).addingTimeInterval(1)
        let s = RecordingTime.resolve(file(creation: c, mtime: at(11), duration: hour), now: now)
        #expect(s.source == .creationTime)
        #expect(s.start == c)
    }

    @Test func pausedRecordingKeepsCreationStart() {
        // 20분 일시정지: duration 40분, 실제 경과 60분. creation 이 더 정확하다.
        let s = RecordingTime.resolve(file(creation: at(10), mtime: at(11), duration: 40 * min_), now: now)
        #expect(s.start == at(10))
        #expect(s.end == at(10, 40))
    }

    @Test func savedAtMeaningSubtractsDuration() {
        let s = RecordingTime.resolve(file(creation: at(11), mtime: at(11, 1), duration: hour),
                                      meaning: .savedAt, now: now)
        #expect(s.start == at(10))
        #expect(s.end == at(11))
        #expect(s.source == .creationTimeMinusDuration)
    }

    @Test func unusableMeaningIgnoresCreation() {
        let s = RecordingTime.resolve(file(creation: at(10), mtime: at(11), duration: hour),
                                      meaning: .unusable, now: now)
        #expect(s.source == .modificationTimeMinusDuration)
        #expect(s.rejection == .ignoredBySetting)
    }

    @Test func zeroDurationFallsBackToMtimeOnly() {
        let s = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: 0), now: now)
        #expect(s.source == .modificationTime)
        #expect(s.start == at(11))
        #expect(s.end == at(11))
    }

    @Test func negativeDurationTreatedAsZero() {
        let s = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: -5), now: now)
        #expect(s.source == .modificationTime)
        #expect(s.duration == 0)
    }

    @Test func nanDurationTreatedAsZero() {
        let s = RecordingTime.resolve(file(creation: at(10, 59), mtime: at(11), duration: .nan), now: now)
        #expect(s.source == .creationTime)
        #expect(s.duration == 0)
    }

    @Test func infiniteDurationTreatedAsZero() {
        let s = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: .infinity), now: now)
        #expect(s.source == .modificationTime)
    }

    @Test func savedAtPlaceholderStillRejected() {
        let s = RecordingTime.resolve(file(creation: Date(timeIntervalSince1970: 0), mtime: at(11), duration: hour),
                                      meaning: .savedAt, now: now)
        #expect(s.rejection == .placeholderEpoch)
    }

    @Test func savedAtDisagreementChecksDerivedStart() {
        // 저장 시각 해석에서는 creation − duration 이 mtime − duration 과 비교된다.
        let s = RecordingTime.resolve(file(creation: at(11), mtime: at(11), duration: 3 * hour),
                                      meaning: .savedAt, now: now)
        #expect(s.start == at(8))
        #expect(s.rejection == nil)
    }

    @Test func intervalMatchesStartEnd() {
        let s = RecordingTime.resolve(file(creation: at(10), mtime: at(11), duration: hour), now: now)
        #expect(s.interval.duration == hour)
        #expect(s.interval.start == s.start)
    }

    @Test func midnightCrossingRecording() {
        let s = RecordingTime.resolve(file(creation: at(23, 30, day: 22), mtime: at(0, 30), duration: hour), now: now)
        #expect(s.start == at(23, 30, day: 22))
        #expect(s.end == at(0, 30))
    }

    @Test func sourceRawValuesMatchDesignNames() {
        #expect(RecordingTimeSource.creationTime.rawValue == "creation_time")
        #expect(RecordingTimeSource.modificationTimeMinusDuration.rawValue == "mtime-duration")
        #expect(RecordingTimeSource.modificationTime.rawValue == "mtime")
    }

    @Test func customDisagreementRule() {
        let rules = RecordingTimeRules(maxDisagreement: 30 * min_)
        let s = RecordingTime.resolve(file(creation: at(9), mtime: at(11), duration: hour), now: now, rules: rules)
        #expect(s.rejection == .disagreesWithModification)
    }

    @Test func rejectionOrderPlaceholderBeforeFuture() {
        let s = RecordingTime.resolve(file(creation: Date(timeIntervalSince1970: 0), mtime: at(11), duration: hour),
                                      meaning: .recordingStart, now: Date(timeIntervalSince1970: -100))
        #expect(s.rejection == .placeholderEpoch)
    }

    @Test(arguments: CreationTimeMeaning.allCases)
    func everyMeaningFallsBackOnMissing(meaning: CreationTimeMeaning) {
        let s = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: hour), meaning: meaning, now: now)
        #expect(s.start == at(10))
        #expect(s.source == .modificationTimeMinusDuration)
    }
}

// MARK: - Matcher

@Suite struct MatcherTests {
    @Test func exactOverlapMatches() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [ev("a", at(10), at(11))])
        guard case .matched(let e, let s) = o else { Issue.record("\(o)"); return }
        #expect(e.id == "a")
        #expect(abs(s - 0.7) < 1e-9)
    }

    @Test func overlapOnlyScoreExactlyAtThresholdMatches() {
        // 0.7·(r) = 0.6 → r = 6/7. 녹음 70분 중 60분 겹침, 이벤트 70분.
        let o = Matcher.match(recordingStart: at(10), end: at(11, 10), events: [ev("a", at(10, 10), at(11, 20))])
        #expect(o.isMatched)
    }

    @Test func justBelowThresholdIsAmbiguous() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [ev("a", at(10, 20), at(11, 20))])
        guard case .ambiguous(let cs, let r) = o else { Issue.record("\(o)"); return }
        #expect(cs.count == 1)
        #expect(r == .earlyStart)
    }

    @Test func historyAndCalendarLiftWeakOverlap() {
        let ctx = MatchContext(recentlyRecordedSeries: ["s1"], expectedCalendarIds: ["club"])
        let o = Matcher.match(recordingStart: at(10), end: at(11),
                              events: [ev("a", at(10, 30), at(11, 30), cal: "club", series: "s1")], context: ctx)
        // 0.7·0.5 + 0.15 + 0.15 = 0.65
        guard case .matched(_, let s) = o else { Issue.record("\(o)"); return }
        #expect(abs(s - 0.65) < 1e-9)
    }

    @Test func earlyStartTenMinutesMatches() {
        let o = Matcher.match(recordingStart: at(9, 50), end: at(11), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }

    @Test func lateEndingMeetingMatches() {
        let o = Matcher.match(recordingStart: at(10), end: at(11, 40), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }

    @Test func shortRecordingInsideLongEventMatches() {
        let o = Matcher.match(recordingStart: at(14), end: at(14, 5), events: [ev("a", at(13), at(16))])
        #expect(matchedId(o) == "a")
    }

    @Test func backToBackRecordingStartingInSecondMatchesSecond() {
        let evs = [ev("A", at(10), at(11)), ev("B", at(11), at(12))]
        let o = Matcher.match(recordingStart: at(11), end: at(12), events: evs)
        #expect(matchedId(o) == "B")
    }

    @Test func recordingSpanningBothConsecutiveIsAmbiguous() {
        let evs = [ev("A", at(10), at(11)), ev("B", at(11), at(12))]
        let o = Matcher.match(recordingStart: at(10), end: at(12), events: evs)
        guard case .ambiguous(let cs, let r) = o else { Issue.record("\(o)"); return }
        #expect(r == .overlappingEvents)
        #expect(cs.map(\.event.id) == ["A", "B"]) // 동점이면 시작 근접 순
    }

    @Test func recordingMostlyInSecondOfConsecutivePicksSecond() {
        let evs = [ev("A", at(10), at(11)), ev("B", at(11), at(12))]
        let o = Matcher.match(recordingStart: at(10, 30), end: at(12), events: evs)
        #expect(matchedId(o) == "B")
    }

    @Test func recordingRunningLateIntoNextMeetingKeepsFirst() {
        // A가 늦게 끝나 B 시작 20분까지 녹음됨: A 1.0, B 20/60.
        let evs = [ev("A", at(10), at(11)), ev("B", at(11), at(12))]
        let o = Matcher.match(recordingStart: at(10), end: at(11, 20), events: evs)
        #expect(matchedId(o) == "A")
    }

    @Test func simultaneousOverlappingEventsAreAmbiguous() {
        let evs = [ev("A", at(10), at(11)), ev("B", at(10), at(11), cal: "club")]
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: evs)
        guard case .ambiguous(_, let r) = o else { Issue.record("\(o)"); return }
        #expect(r == .overlappingEvents)
        #expect(o.failureCategory == .overlap)
    }

    @Test func seriesHistoryBreaksSimultaneousTie() {
        let evs = [ev("A", at(10), at(11), series: "lab"), ev("B", at(10), at(11), cal: "club", series: "ausg")]
        let ctx = MatchContext(recentlyRecordedSeries: ["lab"], expectedCalendarIds: ["primary"])
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: evs, context: ctx)
        // 1.0 vs 0.7 → 차 0.3
        #expect(matchedId(o) == "A")
    }

    @Test func marginBelowPointTwoIsAmbiguous() {
        // 시리즈 이력만으로는 차 0.15라 애매, 캘린더 출처까지 맞으면 차 0.3
        let evs = [ev("A", at(10), at(11), series: "s"), ev("B", at(10), at(11), cal: "c2")]
        let o1 = Matcher.match(recordingStart: at(10), end: at(11), events: evs,
                               context: MatchContext(recentlyRecordedSeries: ["s"]))
        #expect(!o1.isMatched) // 0.85 vs 0.7 = 0.15
        let o2 = Matcher.match(recordingStart: at(10), end: at(11), events: evs,
                               context: MatchContext(recentlyRecordedSeries: ["s"], expectedCalendarIds: ["primary"]))
        #expect(matchedId(o2) == "A") // 1.0 vs 0.7 = 0.3
    }

    @Test func customMarginBoundaryInclusive() {
        let evs = [ev("A", at(10), at(11), series: "s"), ev("B", at(10), at(11), cal: "c2")]
        let rules = MatchRules(margin: 0.15)
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: evs,
                              context: MatchContext(recentlyRecordedSeries: ["s"]), rules: rules)
        #expect(matchedId(o) == "A")
    }

    @Test func allDayOnlyIsNone() {
        let o = Matcher.match(recordingStart: at(10), end: at(11),
                              events: [ev("h", at(0), at(0, day: 24), title: "해커톤", allDay: true)])
        #expect(o == .none(.allDayOnly))
        #expect(o.failureCategory == .other)
    }

    @Test func allDayIgnoredWhenTimedEventExists() {
        let evs = [ev("h", at(0), at(0, day: 24), allDay: true), ev("a", at(10), at(11))]
        #expect(matchedId(Matcher.match(recordingStart: at(10), end: at(11), events: evs)) == "a")
    }

    @Test func cancelledOnlyIsNoneAndCountsAsNotInCalendar() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [ev("a", at(10), at(11), cancelled: true)])
        #expect(o == .none(.cancelledOnly))
        #expect(o.failureCategory == .notInCalendar)
    }

    @Test func inboxHashEventExcluded() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [ev("a", at(10), at(11), title: " #목욜 7시")])
        #expect(o == .none(.inboxOnly))
    }

    @Test func ignoredCalendarExcluded() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [ev("a", at(10), at(11), cal: "holidays")],
                              context: MatchContext(ignoredCalendarIds: ["holidays"]))
        #expect(o == .none(.ignoredCalendarOnly))
    }

    @Test func cancelledTakesPriorityOverAllDayInMissReason() {
        let evs = [ev("h", at(0), at(0, day: 24), allDay: true), ev("a", at(10), at(11), cancelled: true)]
        #expect(Matcher.match(recordingStart: at(10), end: at(11), events: evs) == .none(.cancelledOnly))
    }

    @Test func noEventsIsNoOverlap() {
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: [])
        #expect(o == .none(.noOverlap))
        #expect(o.failureCategory == .notInCalendar)
    }

    @Test func farEventIsNoOverlap() {
        let o = Matcher.match(recordingStart: at(16, 5), end: at(16, 43), events: [ev("g", at(19), at(22))])
        #expect(o == .none(.noOverlap))
    }

    @Test func touchingEndIsNotOverlap() {
        // 앞 회의가 녹음 시작 시각에 끝났을 뿐이면 후보가 아니다.
        let o = Matcher.match(recordingStart: at(11), end: at(12), events: [ev("A", at(10), at(11))])
        #expect(o == .none(.noOverlap))
    }

    @Test func startWithinFifteenMinutesWithoutOverlapIsCandidate() {
        let o = Matcher.match(recordingStart: at(9, 45), end: at(9, 50), events: [ev("a", at(10), at(11))])
        guard case .ambiguous(_, let r) = o else { Issue.record("\(o)"); return }
        #expect(r == .earlyStart)
        #expect(o.failureCategory == .earlyStart)
    }

    @Test func startSixteenMinutesAwayWithoutOverlapIsNone() {
        let o = Matcher.match(recordingStart: at(9, 44), end: at(9, 50), events: [ev("a", at(10), at(11))])
        #expect(o == .none(.noOverlap))
    }

    @Test func lateShortRecordingAfterEventEndIsWeakOverlap() {
        let o = Matcher.match(recordingStart: at(10, 10), end: at(10, 12), events: [ev("a", at(10), at(10, 5))])
        guard case .ambiguous(_, let r) = o else { Issue.record("\(o)"); return }
        #expect(r == .weakOverlap)
    }

    @Test func zeroDurationEventNeverMatches() {
        let o = Matcher.match(recordingStart: at(23), end: at(23, 59), events: [ev("d", at(23, 30), at(23, 30))])
        #expect(!o.isMatched)
    }

    @Test func zeroLengthRecordingInsideEventMatches() {
        let o = Matcher.match(recordingStart: at(10, 30), end: at(10, 30), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }

    @Test func duplicateEventAcrossCalendarsDeduped() {
        let evs = [ev("x", at(10), at(11), cal: "primary"), ev("x", at(10), at(11), cal: "club")]
        let o = Matcher.match(recordingStart: at(10), end: at(11), events: evs,
                              context: MatchContext(expectedCalendarIds: ["club"]))
        guard case .matched(let e, _) = o else { Issue.record("\(o)"); return }
        #expect(e.calendarId == "club")
    }

    @Test func candidateListCappedAtThree() {
        let evs = (0..<5).map { ev("e\($0)", at(10), at(11), cal: "c\($0)") }
        guard case .ambiguous(let cs, _) = Matcher.match(recordingStart: at(10), end: at(11), events: evs) else {
            Issue.record("not ambiguous"); return
        }
        #expect(cs.count == 3)
    }

    @Test func resultIsIndependentOfInputOrder() {
        let evs = [ev("A", at(10), at(11)), ev("B", at(11), at(12)), ev("C", at(10, 30), at(11, 30), cal: "z")]
        let a = Matcher.match(recordingStart: at(10), end: at(12), events: evs)
        let b = Matcher.match(recordingStart: at(10), end: at(12), events: evs.reversed())
        #expect(a == b)
    }

    @Test func spanOverloadUsesRecordingTime() {
        let span = RecordingTime.resolve(file(creation: nil, mtime: at(11), duration: hour), now: now)
        #expect(matchedId(Matcher.match(span, events: [ev("a", at(10), at(11))])) == "a")
    }

    @Test func pausedRecordingLateStartAbsorbedByWindow() {
        // 일시정지로 mtime−duration 이 10분 늦게 잡혀도 매칭된다(§5.1).
        let o = Matcher.match(recordingStart: at(10, 10), end: at(11), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }

    @Test func candidateCarriesEvidence() {
        let ctx = MatchContext(recentlyRecordedSeries: ["s"])
        guard case .ambiguous(let cs, _) = Matcher.match(recordingStart: at(9, 50), end: at(10, 10),
                                                       events: [ev("a", at(10), at(11), series: "s")], context: ctx) else {
            Issue.record("not ambiguous"); return
        }
        #expect(cs[0].seriesHit)
        #expect(!cs[0].calendarHit)
        #expect(cs[0].startOffset == 10 * min_)
        #expect(abs(cs[0].overlapRatio - 0.5) < 1e-9)
    }

    @Test func reversedRecordingBoundsAreClamped() {
        let o = Matcher.match(recordingStart: at(10, 30), end: at(10), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }
}

// MARK: - 집계

@Suite struct MatchStatsTests {
    private let matched = MatchOutcome.matched(ev("a", at(10), at(11)), score: 0.7)
    private let missing = MatchOutcome.none(.noOverlap)

    @Test func weekStartsMondaySeoul() {
        let w = MatchStats.week(containing: at(3, day: 29)) // 일요일 새벽
        #expect(w.start == at(0, day: 23))
        #expect(w.end == at(0, day: 30))
    }

    @Test func weekBoundaryMondayMidnight() {
        #expect(MatchStats.week(containing: at(0, day: 30)).start == at(0, day: 30))
        #expect(MatchStats.week(containing: at(0, day: 30).addingTimeInterval(-1)).start == at(0, day: 23))
    }

    @Test func twoNotInCalendarThisWeekWarns() {
        let rs = [MatchRecord(recordedAt: at(10, day: 24), outcome: missing),
                  MatchRecord(recordedAt: at(10, day: 26), outcome: .none(.cancelledOnly))]
        #expect(MatchStats.shouldWarnNotInCalendar(rs, now: at(12, day: 27)))
    }

    @Test func oneNotInCalendarDoesNotWarn() {
        let rs = [MatchRecord(recordedAt: at(10, day: 24), outcome: missing),
                  MatchRecord(recordedAt: at(10, day: 25), outcome: matched)]
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(12, day: 27)))
    }

    @Test func lastWeekMissesDoNotCount() {
        let rs = [MatchRecord(recordedAt: at(23, day: 22), outcome: missing),
                  MatchRecord(recordedAt: at(10, day: 23), outcome: missing)]
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(12, day: 23)))
    }

    @Test func allDayAndAmbiguousDoNotFeedAlert() {
        let amb = MatchOutcome.ambiguous([], .overlappingEvents)
        let rs = [MatchRecord(recordedAt: at(10), outcome: .none(.allDayOnly)),
                  MatchRecord(recordedAt: at(11), outcome: amb),
                  MatchRecord(recordedAt: at(12), outcome: .none(.ignoredCalendarOnly))]
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(13)))
    }

    @Test func tallyCountsCategories() {
        let rs = [MatchRecord(recordedAt: at(10), outcome: matched),
                  MatchRecord(recordedAt: at(11), outcome: missing),
                  MatchRecord(recordedAt: at(12), outcome: .ambiguous([], .earlyStart)),
                  MatchRecord(recordedAt: at(13), outcome: .ambiguous([], .overlappingEvents))]
        let t = MatchStats.tally(rs, in: MatchStats.day(containing: at(9)))
        #expect(t.total == 4)
        #expect(t.matched == 1 && t.ambiguous == 2 && t.unmatched == 1)
        #expect(t.byCategory[.earlyStart] == 1 && t.byCategory[.overlap] == 1 && t.notInCalendar == 1)
        #expect(t.matchRate == 0.25)
    }

    @Test func emptyTallyHasNoRate() {
        #expect(MatchStats.tally([], in: MatchStats.week(containing: now)).matchRate == nil)
    }

    @Test func yesterdayFraction() {
        let rs = [MatchRecord(recordedAt: at(10, day: 22), outcome: matched),
                  MatchRecord(recordedAt: at(15, day: 22), outcome: matched),
                  MatchRecord(recordedAt: at(23, 59, day: 22), outcome: missing),
                  MatchRecord(recordedAt: at(0, day: 23), outcome: missing)]
        #expect(MatchStats.yesterday(rs, now: at(9)).fractionText == "2/3")
    }

    @Test func customThreshold() {
        let rs = [MatchRecord(recordedAt: at(10), outcome: missing)]
        #expect(MatchStats.shouldWarnNotInCalendar(rs, now: at(11), threshold: 1))
    }
}

// MARK: - 리뷰: 경계 사례(자정·월말·연말·시간대·빈 입력·중복·이상치)

@Suite struct ReviewEdgeCaseTests {
    // 연말 기준 시각(2027-01-01 이후)
    private let newYearNow = at(12, day: 2, month: 1, year: 2027)
    private let miss = MatchOutcome.none(.noOverlap)

    // RecordingTime

    @Test func startMeaningMisconfiguredOnSaveTimeDeviceIsRejected() {
        // 저장 시각을 쓰는 기기에 .recordingStart 를 설정하면 creation≈mtime 이라 R이 1시간 미래로 밀린다.
        let s = RecordingTime.resolve(file(creation: at(11), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .endsAfterModification)
        #expect(s.start == at(10))
        #expect(s.end == at(11))
    }

    @Test func endExactlyAtModificationPlusSkewAccepted() {
        let s = RecordingTime.resolve(file(creation: at(10).addingTimeInterval(120), mtime: at(11), duration: hour), now: now)
        #expect(s.source == .creationTime)
    }

    @Test func localTimeWrittenAsUTCPlusNineIsRejected() {
        // 서울 현지 시각을 UTC로 기록한 기기: creation 이 9시간 늦게 읽힌다.
        let s = RecordingTime.resolve(file(creation: at(19), mtime: at(11), duration: hour), now: now)
        #expect(s.rejection == .afterModification)
        #expect(s.start == at(10))
    }

    @Test func yearEndCrossingRecordingKeepsCreation() {
        let s = RecordingTime.resolve(file(creation: at(23, 30, day: 31, month: 12),
                                           mtime: at(0, 31, day: 1, month: 1, year: 2027), duration: hour), now: newYearNow)
        #expect(s.start == at(23, 30, day: 31, month: 12))
        #expect(s.end == at(0, 30, day: 1, month: 1, year: 2027))
        #expect(s.source == .creationTime)
    }

    @Test func savedAtAcrossMonthEndGoesBackToPreviousMonth() {
        let s = RecordingTime.resolve(file(creation: at(0, 10, day: 1, month: 12), mtime: at(0, 10, day: 1, month: 12),
                                           duration: 20 * min_), meaning: .savedAt, now: at(9, day: 1, month: 12))
        #expect(s.start == at(23, 50, day: 30, month: 11))
        #expect(s.source == .creationTimeMinusDuration)
    }

    // Matcher

    @Test func mtimeOnlyPointAtEndOfMeetingMatchesThatMeeting() {
        // 길이 0 녹음의 시각은 mtime(=녹음 끝)이다. 회의 끝과 같으면 그 회의다.
        let o = Matcher.match(recordingStart: at(11), end: at(11), events: [ev("a", at(10), at(11))])
        #expect(matchedId(o) == "a")
    }

    @Test func mtimeOnlyPointAtBackToBackBoundaryPicksEarlierMeeting() {
        let evs = [ev("a", at(10), at(11)), ev("b", at(11), at(12))]
        let o = Matcher.match(recordingStart: at(11), end: at(11), events: evs)
        #expect(matchedId(o) == "a")
    }

    @Test func zeroLengthDeadlineNearRecordingIsNotACandidate() {
        // 마감 표시(길이 0)는 회의가 아니다. 조기 시작으로 분류되면 §10.4 분기가 오염된다.
        let o = Matcher.match(recordingStart: at(23), end: at(23, 40), events: [ev("d", at(23, 10), at(23, 10))])
        #expect(o == .none(.noOverlap))
        #expect(o.failureCategory == .notInCalendar)
    }

    @Test func inboxTitleWithLeadingNewlineOrFullWidthHashExcluded() {
        let evs = [ev("i1", at(10), at(11), title: "\n#그럼 목욜 7시"), ev("i2", at(10), at(11), cal: "x", title: "＃공학관")]
        #expect(Matcher.match(recordingStart: at(10), end: at(11), events: evs) == .none(.inboxOnly))
    }

    @Test func midnightCrossingRecordingMatchesNextDayEvent() {
        let o = Matcher.match(recordingStart: at(23, 50), end: at(0, 40, day: 24),
                              events: [ev("n", at(0, day: 24), at(0, 30, day: 24))])
        #expect(matchedId(o) == "n")
    }

    @Test func yearEndCrossingEventMatches() {
        let o = Matcher.match(recordingStart: at(23, 40, day: 31, month: 12), end: at(0, 50, day: 1, month: 1, year: 2027),
                              events: [ev("ny", at(23, 45, day: 31, month: 12), at(0, 45, day: 1, month: 1, year: 2027))])
        #expect(matchedId(o) == "ny")
    }

    @Test func exactDuplicateInSameCalendarIsNotAmbiguous() {
        let e = ev("a", at(10), at(11))
        #expect(matchedId(Matcher.match(recordingStart: at(10), end: at(11), events: [e, e, e])) == "a")
    }

    @Test func candidateOrderIndependentOfInputWhenKeysCollide() {
        // 같은 시리즈 회차가 id만 다르게 두 번(예외 회차 복제) 들어와도 순서가 결정론이어야 한다.
        let evs = (0..<8).map { ev("i\($0)", at(10), at(11), series: "s") }
        let ids: ([CalendarEvent]) -> [String] = { input in
            guard case .ambiguous(let cs, _) = Matcher.match(recordingStart: at(10), end: at(11), events: input) else { return [] }
            return cs.map(\.event.id)
        }
        let expected = ["i0", "i1", "i2"]
        #expect(ids(evs) == expected)
        #expect(ids(evs.reversed()) == expected)
        #expect(ids([evs[5], evs[2], evs[7], evs[0], evs[3], evs[1], evs[6], evs[4]]) == expected)
    }

    @Test func emptyEventsWithFullContextIsNoOverlap() {
        let ctx = MatchContext(recentlyRecordedSeries: ["s"], expectedCalendarIds: ["primary"], ignoredCalendarIds: ["x"])
        #expect(Matcher.match(recordingStart: at(10), end: at(11), events: [], context: ctx) == .none(.noOverlap))
    }

    @Test func earlyStartSameLengthRecordingIsEarlyStartAmbiguity() {
        // 10분 일찍 눌러 같은 길이로 녹음하면 겹침 50/60 → 0.583 < 0.6. 설계 점수식 그대로 '조기 시작'이다.
        let o = Matcher.match(recordingStart: at(9, 50), end: at(10, 50), events: [ev("a", at(10), at(11))])
        guard case .ambiguous(let cs, let r) = o else { Issue.record("\(o)"); return }
        #expect(r == .earlyStart)
        #expect(cs.map(\.event.id) == ["a"])
        #expect(o.failureCategory == .earlyStart)
    }

    // 집계

    @Test func weekContainingNewYearsEveSpansYearBoundary() {
        let w = MatchStats.week(containing: at(22, day: 31, month: 12))
        #expect(w.start == at(0, day: 28, month: 12))
        #expect(w.end == at(0, day: 4, month: 1, year: 2027))
    }

    @Test func yesterdayOnNewYearsDayIsDecember31() {
        let rs = [MatchRecord(recordedAt: at(10, day: 31, month: 12), outcome: miss),
                  MatchRecord(recordedAt: at(0, 10, day: 1, month: 1, year: 2027), outcome: miss)]
        let t = MatchStats.yesterday(rs, now: at(0, 30, day: 1, month: 1, year: 2027))
        #expect(t.fractionText == "0/1")
    }

    @Test func notInCalendarWarningAcrossYearBoundaryWeek() {
        let rs = [MatchRecord(recordedAt: at(10, day: 29, month: 12), outcome: miss),
                  MatchRecord(recordedAt: at(10, day: 2, month: 1, year: 2027), outcome: miss)]
        #expect(MatchStats.shouldWarnNotInCalendar(rs, now: at(20, day: 3, month: 1, year: 2027)))
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(9, day: 4, month: 1, year: 2027)))
    }

    @Test func monthEndSundayAndMondayAreDifferentWeeks() {
        let rs = [MatchRecord(recordedAt: at(23, 59, day: 29), outcome: miss),
                  MatchRecord(recordedAt: at(0, 1, day: 30), outcome: miss)]
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(12, day: 30)))
        #expect(!MatchStats.shouldWarnNotInCalendar(rs, now: at(12, day: 29)))
    }

    @Test func weekUsesSeoulNotUTC() {
        // UTC 일요일 15:30 = 서울 월요일 00:30 → 다음 주
        let utcSunday = Date(timeIntervalSince1970: 1_795_966_200) // 2026-11-29T15:30:00Z
        #expect(utcSunday == at(0, 30, day: 30))
        #expect(MatchStats.week(containing: utcSunday).start == at(0, day: 30))
        #expect(MatchStats.day(containing: utcSunday).start == at(0, day: 30))
    }

    @Test func emptyRecordsNeverWarnAndHaveNoRate() {
        #expect(!MatchStats.shouldWarnNotInCalendar([], now: now, threshold: 0))
        #expect(!MatchStats.shouldWarnNotInCalendar([], now: now))
        #expect(MatchStats.yesterday([], now: now).matchRate == nil)
        #expect(MatchStats.yesterday([], now: now).fractionText == "0/0")
    }
}
