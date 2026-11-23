import Foundation
import Testing
@testable import MulgilCore

// 기준 시각: 2026-11-23(월) 07:30 KST. 모든 테스트가 이 값을 주입받는다.
private func kst(_ s: String) -> Date { GCalTimeParser.parseDateTime(s)! }
private let now = kst("2026-11-23T07:30:00+09:00")
private let primary = "junseong@example.com"

// 실제 events.list 응답 모양(불필요한 필드 포함)을 그대로 둔다.
private let fullPage1 = #"""
{
  "kind": "calendar#events",
  "etag": "\"p32of7ufk2ve8m0o\"",
  "summary": "junseong@example.com",
  "description": "",
  "updated": "2026-11-23T00:10:11.123Z",
  "timeZone": "Asia/Seoul",
  "accessRole": "owner",
  "defaultReminders": [{"method": "popup", "minutes": 10}],
  "nextPageToken": "CigKGjBhbWQ",
  "items": [
    {
      "kind": "calendar#event",
      "etag": "\"3461234567890000\"",
      "id": "ausg123_20261124T100000Z",
      "status": "confirmed",
      "htmlLink": "https://www.google.com/calendar/event?eid=YXVzZzEyMw",
      "created": "2026-09-01T03:00:00.000Z",
      "updated": "2026-11-20T03:00:00.000Z",
      "summary": "🚀 AUSG 운영 회의",
      "location": "https://zoom.us/j/123456789?pwd=abc",
      "creator": {"email": "junseong@example.com", "self": true},
      "organizer": {"email": "junseong@example.com", "self": true},
      "start": {"dateTime": "2026-11-24T19:00:00+09:00", "timeZone": "Asia/Seoul"},
      "end": {"dateTime": "2026-11-24T20:00:00+09:00", "timeZone": "Asia/Seoul"},
      "recurringEventId": "ausg123",
      "originalStartTime": {"dateTime": "2026-11-24T19:00:00+09:00", "timeZone": "Asia/Seoul"},
      "iCalUID": "ausg123@google.com",
      "sequence": 0,
      "reminders": {"useDefault": true},
      "eventType": "default"
    },
    {
      "kind": "calendar#event",
      "id": "exam2026",
      "status": "confirmed",
      "summary": "기말고사 기간",
      "start": {"date": "2026-12-14"},
      "end": {"date": "2026-12-19"},
      "transparency": "transparent",
      "reminders": {"useDefault": false}
    }
  ]
}
"""#

private let fullPage2 = #"""
{
  "kind": "calendar#events",
  "timeZone": "Asia/Seoul",
  "nextSyncToken": "CPDAlvWDx70CEPDAlvWDx70CGAU=",
  "items": [
    {
      "kind": "calendar#event",
      "id": "lunch1",
      "status": "confirmed",
      "summary": "점심 미팅",
      "description": "자료: https://www.notion.so/team/abc. 참고",
      "hangoutLink": "https://meet.google.com/abc-defg-hij",
      "start": {"dateTime": "2026-11-23T03:30:00.000Z"},
      "end": {"dateTime": "2026-11-23T04:30:00Z"},
      "extendedProperties": {"shared": {"foo": "bar"}}
    },
    {
      "kind": "calendar#event",
      "id": "ausg123_20261201T100000Z",
      "status": "confirmed",
      "summary": "AUSG 운영 회의",
      "start": {"dateTime": "2026-12-01T19:00:00+09:00", "timeZone": "Asia/Seoul"},
      "end": {"dateTime": "2026-12-01T20:00:00+09:00", "timeZone": "Asia/Seoul"},
      "recurringEventId": "ausg123",
      "originalStartTime": {"dateTime": "2026-12-01T19:00:00+09:00", "timeZone": "Asia/Seoul"}
    }
  ]
}
"""#

private let incrementalPage = #"""
{
  "kind": "calendar#events",
  "timeZone": "Asia/Seoul",
  "nextSyncToken": "SYNC-2",
  "items": [
    {
      "kind": "calendar#event",
      "etag": "\"3461234567899999\"",
      "id": "ausg123_20261201T100000Z",
      "status": "cancelled",
      "recurringEventId": "ausg123",
      "originalStartTime": {"dateTime": "2026-12-01T19:00:00+09:00", "timeZone": "Asia/Seoul"}
    },
    {
      "kind": "calendar#event",
      "id": "ausg123_20261124T100000Z",
      "status": "confirmed",
      "summary": "AUSG 운영 회의 (장소 변경)",
      "start": {"dateTime": "2026-11-24T20:30:00.000+09:00"},
      "end": {"dateTime": "2026-11-24T21:30:00.000+09:00"},
      "recurringEventId": "ausg123",
      "originalStartTime": {"dateTime": "2026-11-24T10:00:00Z"}
    },
    {
      "kind": "calendar#event",
      "id": "shadow-xyz",
      "status": "confirmed",
      "summary": "· AUSG 운영 회의 맥락",
      "start": {"dateTime": "2026-11-24T18:50:00+09:00"},
      "end": {"dateTime": "2026-11-24T19:00:00+09:00"},
      "extendedProperties": {"private": {"mulgil_src": "x|y|1", "mulgil_v": "2026-11-23T07:30:00+09:00"}}
    }
  ]
}
"""#

private func page(_ s: String) throws -> GCalEventsPage { try GCalEventsPage.decode(Data(s.utf8)) }

private func syncedMirror() throws -> CalendarMirror {
    var m = CalendarMirror(calendarIds: [primary])
    let r1 = m.nextRequest(for: primary, now: now)!
    _ = try m.apply(try page(fullPage1), for: r1)
    let r2 = m.nextRequest(for: primary, now: now)!
    _ = try m.apply(try page(fullPage2), for: r2)
    return m
}

private func ev(_ cal: String = "c", id: String, title: String, start: String, minutes: Int = 60,
                rid: String? = nil, allDay: Bool = false, cancelled: Bool = false) -> CalendarEvent {
    let s = kst(start)
    let key = OccurrenceKey(calendarId: cal, seriesId: rid ?? id, originalStart: rid == nil ? nil : s)
    return CalendarEvent(key: key, id: id, calendarId: cal, title: title, start: s,
                         end: s.addingTimeInterval(Double(minutes) * 60), isAllDay: allDay,
                         recurringEventId: rid, cancelled: cancelled)
}

// MARK: - GoogleCalendarModels

@Suite struct GoogleCalendarModelsTests {
    @Test func parsesDateTimeWithOffset() {
        let d = GCalTimeParser.parseDateTime("2026-11-24T19:00:00+09:00")
        #expect(d == Date(timeIntervalSince1970: 1_795_514_400))
        #expect(GCalTimeParser.parseDateTime("2026-11-24T10:00:00Z") == d)
        #expect(GCalTimeParser.parseDateTime("2026-11-24T05:00:00-05:00") == d)
    }

    @Test func parsesFractionalSeconds() {
        let a = GCalTimeParser.parseDateTime("2026-11-23T03:30:00.250Z")!
        let b = GCalTimeParser.parseDateTime("2026-11-23T12:30:00+09:00")!
        #expect(abs(a.timeIntervalSince(b) - 0.25) < 0.0001)
        #expect(GCalTimeParser.parseDateTime("2026-11-23T03:30:00.000000Z") == GCalTimeParser.parseDateTime("2026-11-23T03:30:00Z"))
    }

    @Test func rejectsMalformedDateTimes() {
        for s in ["", "2026-11-24", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-11-24T19:00:00",
                  "2026-11-24T19:00:00+0900x", "2026-11-24T25:00:00Z", "2026-11-24T19:00:00.Z"] {
            #expect(GCalTimeParser.parseDateTime(s) == nil, "\(s)")
        }
        #expect(GCalTimeParser.parseDateTime("2026-11-24T19:00:00+0900") != nil)
    }

    @Test func parsesAllDayDates() {
        #expect(GCalTimeParser.parseDate("2028-02-29")! == (2028, 2, 29))
        #expect(GCalTimeParser.parseDate("2026-02-29") == nil)
        #expect(GCalTimeParser.parseDate("2026-1-05") == nil)
    }

    @Test func decodesPageTokens() throws {
        let p1 = try page(fullPage1)
        #expect(p1.items.count == 2)
        #expect(p1.nextPageToken == "CigKGjBhbWQ")
        #expect(p1.nextSyncToken == nil)
        let p2 = try page(fullPage2)
        #expect(p2.nextSyncToken == "CPDAlvWDx70CEPDAlvWDx70CGAU=")
        #expect(p2.nextPageToken == nil)
    }

    @Test func decodesPageWithoutItems() throws {
        let p = try page(#"{"kind":"calendar#events","nextSyncToken":"T"}"#)
        #expect(p.items.isEmpty)
        #expect(p.nextSyncToken == "T")
    }

    @Test func recurringInstanceKeyUsesOriginalStart() throws {
        let item = try page(fullPage1).items[0]
        let e = item.toCalendarEvent(calendarId: primary)!
        #expect(e.key == OccurrenceKey(calendarId: primary, seriesId: "ausg123", originalStart: kst("2026-11-24T19:00:00+09:00")))
        #expect(e.id == "ausg123_20261124T100000Z")
        #expect(e.recurringEventId == "ausg123")
        #expect(e.duration == 3600)
        #expect(!e.isAllDay)
        #expect(e.key.description == "\(primary)|ausg123|1795514400")
    }

    @Test func allDayEventIsSeoulMidnightWithExclusiveEnd() throws {
        let e = try page(fullPage1).items[1].toCalendarEvent(calendarId: primary)!
        #expect(e.isAllDay)
        #expect(e.start == kst("2026-12-14T00:00:00+09:00"))
        #expect(e.end == kst("2026-12-19T00:00:00+09:00"))
        #expect(e.duration == 5 * 86_400)
        #expect(e.key.originalStart == nil)
        #expect(e.key.description == "\(primary)|exam2026|-")
    }

    @Test func cancelledInstanceHasKeyButNoEvent() throws {
        let item = try page(incrementalPage).items[0]
        #expect(item.isCancelled)
        #expect(item.toCalendarEvent(calendarId: primary) == nil)
        #expect(item.occurrenceKey(calendarId: primary)
                == OccurrenceKey(calendarId: primary, seriesId: "ausg123", originalStart: kst("2026-12-01T19:00:00+09:00")))
    }

    @Test func movedInstanceKeepsSameKey() throws {
        let original = try page(fullPage1).items[0].toCalendarEvent(calendarId: primary)!
        let moved = try page(incrementalPage).items[1].toCalendarEvent(calendarId: primary)!
        #expect(moved.key == original.key)
        #expect(moved.start == kst("2026-11-24T20:30:00+09:00"))
    }

    @Test func allDayOriginalStartTimeDecodes() throws {
        let json = #"{"items":[{"id":"r_20261125","status":"confirmed","summary":"과제","recurringEventId":"r","originalStartTime":{"date":"2026-11-25"},"start":{"date":"2026-11-26"},"end":{"date":"2026-11-27"}}]}"#
        let e = try page(json).items[0].toCalendarEvent(calendarId: "c")!
        #expect(e.key.originalStart == kst("2026-11-25T00:00:00+09:00"))
        #expect(e.start == kst("2026-11-26T00:00:00+09:00"))
    }

    @Test func contextLinkPrefersMeetingLinkAndOnlyHTTPS() throws {
        let p2 = try page(fullPage2)
        #expect(p2.items[0].contextLink == "https://meet.google.com/abc-defg-hij")
        let zoom = try page(fullPage1).items[0]
        #expect(zoom.contextLink == "https://zoom.us/j/123456789?pwd=abc")
        let notion = GCalEvent(id: "x", description: "링크 https://www.notion.so/team/abc. 끝")
        #expect(notion.contextLink == "https://www.notion.so/team/abc")
        let bad = GCalEvent(id: "y", description: "zoommtg://zoom.us/join http://insecure.example.com",
                            location: "강의동 301")
        #expect(bad.contextLink == nil)
        #expect(!GCalLink.isSafeHTTPS("https://"))
        #expect(!GCalLink.isSafeHTTPS("javascript:alert(1)"))
    }

    @Test func detectsShadowAndInbox() throws {
        let items = try page(incrementalPage).items
        #expect(items[2].isMulgilShadow)
        #expect(!items[1].isMulgilShadow)
        #expect(ev(id: "a", title: " #연사 리스트 금요일까지", start: "2026-11-23T10:00:00+09:00").gcalIsInbox)
        #expect(!ev(id: "b", title: "AUSG #12", start: "2026-11-23T10:00:00+09:00").gcalIsInbox)
    }
}

// MARK: - CalendarMirror

@Suite struct CalendarMirrorTests {
    @Test func firstRequestIsWindowedFullSync() throws {
        let m = CalendarMirror(calendarIds: [primary])
        let r = m.nextRequest(for: primary, now: now)!
        #expect(r.mode == .full)
        #expect(r.syncToken == nil)
        #expect(r.timeMin == kst("2026-10-26T00:00:00+09:00"))  // 4주 전 자정
        #expect(r.timeMax == kst("2027-01-19T00:00:00+09:00"))  // 8주 뒤 날의 끝
        let q = Dictionary(uniqueKeysWithValues: r.queryItems.map { ($0.name, $0.value) })
        #expect(q["singleEvents"] == "true")
        #expect(q["timeMin"] == "2026-10-25T15:00:00Z")
        #expect(q["syncToken"] == nil)
    }

    @Test func customWindowFromDesignValue() {
        let m = CalendarMirror(calendarIds: ["c"], window: GCalSyncWindow(pastDays: 7, futureDays: 7))
        let r = m.nextRequest(for: "c", now: now)!
        #expect(r.timeMin == kst("2026-11-16T00:00:00+09:00"))
        #expect(r.timeMax == kst("2026-12-01T00:00:00+09:00"))
    }

    @Test func fullSyncPagesKeepWindowAndSwapAtEnd() throws {
        var m = CalendarMirror(calendarIds: [primary])
        let r1 = m.nextRequest(for: primary, now: now)!
        let res1 = try m.apply(try page(fullPage1), for: r1)
        #expect(!res1.completed)
        #expect(m.allEvents.isEmpty)  // 아직 바꿔 끼우지 않음
        // 다음 페이지는 시각이 바뀌어도 첫 페이지의 창을 그대로 쓴다.
        let r2 = m.nextRequest(for: primary, now: now.addingTimeInterval(86_400 * 3))!
        #expect(r2.pageToken == "CigKGjBhbWQ")
        #expect(r2.timeMin == r1.timeMin)
        #expect(r2.timeMax == r1.timeMax)
        let res2 = try m.apply(try page(fullPage2), for: r2)
        #expect(res2.completed)
        #expect(m.allEvents.count == 4)
        #expect(m.states[primary]?.syncToken == "CPDAlvWDx70CEPDAlvWDx70CGAU=")
        #expect(m.states[primary]?.needsFullSync == false)
    }

    @Test func afterFullSyncRequestIsIncremental() throws {
        let m = try syncedMirror()
        let r = m.nextRequest(for: primary, now: now)!
        #expect(r.mode == .incremental)
        #expect(r.syncToken == "CPDAlvWDx70CEPDAlvWDx70CGAU=")
        #expect(r.timeMin == nil && r.timeMax == nil)
        let names = r.queryItems.map(\.name)
        #expect(names.contains("syncToken"))
        #expect(!names.contains("timeMin") && !names.contains("timeMax") && !names.contains("orderBy"))
    }

    @Test func incrementalAppliesCancelMoveAndSkipsShadow() throws {
        var m = try syncedMirror()
        let r = m.nextRequest(for: primary, now: now)!
        let res = try m.apply(try page(incrementalPage), for: r)
        let dec1 = OccurrenceKey(calendarId: primary, seriesId: "ausg123", originalStart: kst("2026-12-01T19:00:00+09:00"))
        let nov24 = OccurrenceKey(calendarId: primary, seriesId: "ausg123", originalStart: kst("2026-11-24T19:00:00+09:00"))
        #expect(res.removed == [dec1])
        #expect(res.upserted == [nov24])
        #expect(res.skipped == 1)
        #expect(m.event(for: dec1) == nil)
        #expect(m.event(for: nov24)?.start == kst("2026-11-24T20:30:00+09:00"))
        #expect(m.allEvents.count == 3)
        #expect(m.states[primary]?.syncToken == "SYNC-2")
    }

    @Test func cancelledMasterRemovesAllInstances() throws {
        var m = try syncedMirror()
        let r = m.nextRequest(for: primary, now: now)!
        let res = try m.apply(try page(#"{"nextSyncToken":"S3","items":[{"id":"ausg123","status":"cancelled"},{"id":"lunch1","status":"cancelled"}]}"#), for: r)
        #expect(res.removed.count == 3)
        #expect(m.allEvents.map(\.id) == ["exam2026"])
    }

    @Test func goneTriggersFullResyncAndReportsVanished() throws {
        var m = try syncedMirror()
        #expect(m.handleHTTPStatus(410, calendarId: primary) == .fullResyncScheduled)
        #expect(m.states[primary]?.goneCount == 1)
        let r = m.nextRequest(for: primary, now: now)!
        #expect(r.mode == .full && r.syncToken == nil)
        // 재동기화가 끝날 때까지 기존 미러는 남아 있다.
        #expect(m.allEvents.count == 4)
        let fresh = #"{"nextSyncToken":"NEW","items":[{"id":"exam2026","status":"confirmed","summary":"기말고사 기간","start":{"date":"2026-12-14"},"end":{"date":"2026-12-19"}}]}"#
        let res = try m.apply(try page(fresh), for: r)
        #expect(res.completed)
        #expect(res.removed.count == 3)
        #expect(m.allEvents.map(\.id) == ["exam2026"])
        #expect(m.states[primary]?.syncToken == "NEW")
    }

    @Test func goneOnlyAffectsThatCalendar() throws {
        var m = CalendarMirror(calendarIds: ["a", "b"])
        for c in ["a", "b"] {
            let r = m.nextRequest(for: c, now: now)!
            _ = try m.apply(GCalEventsPage(items: [], nextSyncToken: "T-\(c)"), for: r)
        }
        m.handleGone(calendarId: "a")
        #expect(m.nextRequest(for: "a", now: now)?.mode == .full)
        #expect(m.nextRequest(for: "b", now: now)?.syncToken == "T-b")
        #expect(m.nextRequests(now: now).map(\.calendarId) == ["a", "b"])
    }

    @Test func staleResponseIsRejected() throws {
        var m = try syncedMirror()
        let old = GCalSyncRequest(calendarId: primary, mode: .incremental, syncToken: "OLD", pageToken: nil, timeMin: nil, timeMax: nil)
        #expect(throws: GCalMirrorError.staleResponse(calendarId: primary)) {
            try m.apply(try page(incrementalPage), for: old)
        }
        #expect(throws: GCalMirrorError.unknownCalendar("zzz")) {
            try m.apply(GCalEventsPage(items: []), for: GCalSyncRequest(calendarId: "zzz", mode: .full, syncToken: nil, pageToken: nil, timeMin: nil, timeMax: nil))
        }
    }

    @Test func lastPageWithoutSyncTokenResetsToFullSync() throws {
        var m = try syncedMirror()
        let r = m.nextRequest(for: primary, now: now)!
        #expect(throws: GCalMirrorError.missingSyncToken(calendarId: primary)) {
            try m.apply(GCalEventsPage(items: []), for: r)
        }
        #expect(m.nextRequest(for: primary, now: now)?.mode == .full)
    }

    @Test func incrementalPagingKeepsSyncTokenUntilLastPage() throws {
        var m = try syncedMirror()
        let r1 = m.nextRequest(for: primary, now: now)!
        let res = try m.apply(GCalEventsPage(items: [], nextPageToken: "P2"), for: r1)
        #expect(!res.completed)
        let r2 = m.nextRequest(for: primary, now: now)!
        #expect(r2.mode == .incremental && r2.syncToken == r1.syncToken && r2.pageToken == "P2")
        _ = try m.apply(GCalEventsPage(items: [], nextSyncToken: "S9"), for: r2)
        #expect(m.nextRequest(for: primary, now: now)?.pageToken == nil)
        #expect(m.states[primary]?.syncToken == "S9")
    }

    @Test func httpStatusMapping() {
        var m = CalendarMirror(calendarIds: [primary])
        #expect(m.handleHTTPStatus(401, calendarId: primary) == .reauthorize)
        #expect(m.handleHTTPStatus(403, calendarId: primary) == .retryLater)
        #expect(m.handleHTTPStatus(503, calendarId: primary) == .retryLater)
        #expect(m.handleHTTPStatus(404, calendarId: primary) == .fail)
    }

    @Test func pathEncodesCalendarId() {
        let r = GCalSyncRequest(calendarId: "ko.south_korea#holiday@group.v.calendar.google.com", mode: .full,
                                syncToken: nil, pageToken: nil, timeMin: nil, timeMax: nil)
        #expect(r.path == "/calendar/v3/calendars/ko.south_korea%23holiday@group.v.calendar.google.com/events")
        let url = r.url()!.absoluteString
        #expect(url.hasPrefix("https://www.googleapis.com/calendar/v3/calendars/ko.south_korea%23holiday@"))
        #expect(url.contains("singleEvents=true"))
    }

    @Test func mirrorRoundTripsThroughCodable() throws {
        let m = try syncedMirror()
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(CalendarMirror.self, from: data)
        #expect(back.allEvents == m.allEvents)
        #expect(back.nextRequest(for: primary, now: now) == m.nextRequest(for: primary, now: now))
    }

    @Test func entriesKeepContextLinkAndOverlapQuery() throws {
        let m = try syncedMirror()
        let lunch = OccurrenceKey(calendarId: primary, seriesId: "lunch1", originalStart: nil)
        #expect(m.entry(for: lunch)?.link == "https://meet.google.com/abc-defg-hij")
        let today = DateInterval(start: kst("2026-11-23T00:00:00+09:00"), end: kst("2026-11-24T00:00:00+09:00"))
        #expect(m.events(overlapping: today).map(\.id) == ["lunch1"])
    }
}

// MARK: - SeriesGrouper

@Suite struct SeriesGrouperTests {
    @Test func normalizesEpisodeMarkersEmojiAndCase() {
        let n = SeriesGrouper.normalizeTitle
        #expect(n("AUSG 운영 회의 3차") == "ausg 운영 회의")
        #expect(n("🚀 AUSG 운영 회의") == "ausg 운영 회의")
        #expect(n("AUSG 운영회의 #12") == "ausg 운영회의")
        #expect(n("주간 싱크 (11/23)") == "주간 싱크")
        #expect(n("주간 싱크 11/30") == "주간 싱크")
        #expect(n("[3] 주간 싱크 ✅") == "주간 싱크")
        #expect(n("ERPsim-3주차-1교시") == "erpsim")
        #expect(n("JAVA-5주차") == "java")
        #expect(n("👨‍👩‍👧 가족 저녁") == "가족 저녁")
    }

    @Test func normalizationKeepsMeaningfulWords() {
        let n = SeriesGrouper.normalizeTitle
        #expect(n("데이터베이스실습") == "데이터베이스실습")
        #expect(n("3D 프린팅 세미나") == "3d 프린팅 세미나")
        #expect(n("🎉") == "")
    }

    @Test func groupsByRecurringEventId() {
        let evs = [
            ev(id: "r_1", title: "AUSG 운영 회의", start: "2026-11-17T19:00:00+09:00", rid: "r"),
            ev(id: "r_2", title: "AUSG 운영 회의 (장소 변경)", start: "2026-11-24T19:00:00+09:00", rid: "r"),
            ev(id: "x", title: "치과", start: "2026-11-25T10:00:00+09:00"),
        ]
        let idx = SeriesGrouper().group(evs, now: now)
        #expect(idx.series.count == 1)
        let s = idx.series[0]
        #expect(s.id == "gcal-series:c|rec:r")
        #expect(s.reason == .recurrence)
        #expect(s.members == [evs[0].key, evs[1].key])
        #expect(s.displayTitle == "AUSG 운영 회의 (장소 변경)")
        #expect(idx.seriesId(for: evs[2].key) == nil)
    }

    @Test func mergesSplitRecurringSeriesWithSameTitle() {
        // "이번 및 향후 일정" 수정은 새 recurringEventId(r_R…)를 만든다.
        let evs = [
            ev(id: "r_1", title: "알고리즘", start: "2026-11-10T09:00:00+09:00", rid: "r"),
            ev(id: "rR_1", title: "알고리즘 5주차", start: "2026-11-24T10:00:00+09:00", rid: "r_R20261124"),
        ]
        let idx = SeriesGrouper().group(evs, now: now)
        #expect(idx.series.count == 1)
        #expect(idx.series[0].id == "gcal-series:c|rec:r")
        #expect(idx.series[0].recurringEventIds == ["r", "r_R20261124"])
    }

    @Test func repeatedTitleWithoutRuleBecomesSeriesAtThree() {
        let three = [
            ev(id: "a", title: "주간 싱크", start: "2026-11-02T14:00:00+09:00"),
            ev(id: "b", title: "주간 싱크 2차", start: "2026-11-09T14:00:00+09:00"),
            ev(id: "c", title: "🔁 주간 싱크", start: "2026-11-16T14:00:00+09:00"),
        ]
        let idx = SeriesGrouper().group(three, now: now)
        #expect(idx.series.count == 1)
        #expect(idx.series[0].reason == .repeatedTitle)
        #expect(idx.series[0].id == "gcal-series:c|title:주간 싱크")
        #expect(SeriesGrouper().group(Array(three.prefix(2)), now: now).series.isEmpty)
    }

    @Test func upcomingOccurrenceWithinSevenDaysCounts() {
        let evs = [
            ev(id: "a", title: "주간 싱크", start: "2026-11-09T14:00:00+09:00"),
            ev(id: "b", title: "주간 싱크", start: "2026-11-16T14:00:00+09:00"),
            ev(id: "c", title: "주간 싱크", start: "2026-11-29T14:00:00+09:00"),
        ]
        #expect(SeriesGrouper().group(evs, now: now).series.count == 1)
    }

    @Test func occurrencesOutsideLookbackDoNotCount() {
        let evs = [
            ev(id: "a", title: "주간 싱크", start: "2026-10-05T14:00:00+09:00"),
            ev(id: "b", title: "주간 싱크", start: "2026-10-12T14:00:00+09:00"),
            ev(id: "c", title: "주간 싱크", start: "2026-11-16T14:00:00+09:00"),
        ]
        #expect(SeriesGrouper().group(evs, now: now).series.isEmpty)
        // 일단 시리즈가 되면 오래된 회차도 구성원이다.
        let more = evs + [ev(id: "d", title: "주간 싱크", start: "2026-11-09T14:00:00+09:00"),
                          ev(id: "e", title: "주간 싱크", start: "2026-11-02T14:00:00+09:00")]
        let s = SeriesGrouper().group(more, now: now).series
        #expect(s.count == 1 && s[0].members.count == 5)
    }

    @Test func sameDayRepeatsCountOnce() {
        let evs = [
            ev(id: "a", title: "공부", start: "2026-11-20T09:00:00+09:00"),
            ev(id: "b", title: "공부", start: "2026-11-20T13:00:00+09:00"),
            ev(id: "c", title: "공부", start: "2026-11-20T19:00:00+09:00"),
        ]
        #expect(SeriesGrouper().group(evs, now: now).series.isEmpty)
    }

    @Test func neverGroupsAcrossCalendars() {
        let evs = [
            ev("work", id: "a", title: "주간 싱크", start: "2026-11-02T14:00:00+09:00"),
            ev("work", id: "b", title: "주간 싱크", start: "2026-11-09T14:00:00+09:00"),
            ev("club", id: "c", title: "주간 싱크", start: "2026-11-16T14:00:00+09:00"),
            ev("club", id: "r1", title: "주간 싱크", start: "2026-11-17T14:00:00+09:00", rid: "r"),
        ]
        let idx = SeriesGrouper().group(evs, now: now)
        #expect(idx.series.map(\.calendarId) == ["club"])
        #expect(idx.seriesId(for: evs[2].key) == "gcal-series:club|rec:r")  // 같은 캘린더 반복 일정에 합류
        #expect(idx.seriesId(for: evs[0].key) == nil)
    }

    @Test func excludesInboxAndCancelled() {
        let evs = [
            ev(id: "a", title: "#회의 잡기", start: "2026-11-10T14:00:00+09:00"),
            ev(id: "b", title: "#회의 잡기", start: "2026-11-11T14:00:00+09:00"),
            ev(id: "c", title: "#회의 잡기", start: "2026-11-12T14:00:00+09:00"),
            ev(id: "r1", title: "스터디", start: "2026-11-12T20:00:00+09:00", rid: "r", cancelled: true),
        ]
        #expect(SeriesGrouper().group(evs, now: now).series.isEmpty)
    }

    @Test func customThresholds() {
        let evs = [
            ev(id: "a", title: "1:1", start: "2026-11-09T14:00:00+09:00"),
            ev(id: "b", title: "1:1", start: "2026-11-16T14:00:00+09:00"),
        ]
        #expect(SeriesGrouper(lookbackWeeks: 2, minOccurrences: 2).group(evs, now: now).series.count == 1)
    }
}

// MARK: - ShadowEvent

@Suite struct ShadowEventTests {
    let meeting = ev(primary, id: "ausg123_20261124T100000Z", title: "AUSG 운영 회의",
                     start: "2026-11-24T19:00:00+09:00", rid: "ausg123")

    var fullContext: ShadowContext {
        ShadowContext(decisions: ["12월 밋업 장소 = 판교"], questions: ["예산 승인 주체"],
                      owes: [ShadowOwe(text: "연사 리스트 공유", due: Due(date: kst("2026-11-23T00:00:00+09:00"), hasTime: false))],
                      waits: ["예산안 ← 민지"], link: "https://zoom.us/j/123456789")
    }

    @Test func descriptionMatchesSpecExactly() {
        let d = ShadowEvent.contextDescription(fullContext, now: now)
        #expect(d == """
        기준 11/23 07:30 · 원본 일정 확인
        정한 것: 12월 밋업 장소 = 판교
        미정: 예산 승인 주체
        할 것: 연사 리스트 공유(오늘) — 남음
        기다리는 것: 예산안 ← 민지
        https://zoom.us/j/123456789
        """)
        #expect(d.split(separator: "\n").count == ShadowEvent.maxLines)
        #expect(ShadowEvent.contextTitle(meeting.title) == "· AUSG 운영 회의 맥락")
    }

    @Test func longLinesAreTruncatedToFortyCharacters() {
        let c = ShadowContext(decisions: [String(repeating: "가", count: 60)], link: "https://example.com/" + String(repeating: "a", count: 60))
        let lines = ShadowEvent.contextDescription(c, now: now).split(separator: "\n").map(String.init)
        #expect(lines[1].count == 40)
        #expect(lines[1].hasSuffix("…"))
        #expect(lines[2].hasSuffix(String(repeating: "a", count: 60)))  // URL은 자르지 않음
        #expect(ShadowEvent.truncate("짧음") == "짧음")
    }

    @Test func emptySectionsAndNonHTTPSLinksAreOmitted() {
        let c = ShadowContext(questions: ["회비\n얼마"], link: "zoommtg://zoom.us/join?confno=1")
        #expect(ShadowEvent.contextDescription(c, now: now) == "기준 11/23 07:30 · 원본 일정 확인\n미정: 회비 얼마")
        #expect(!ShadowContext(link: "http://x.com").hasContent)
        #expect(ShadowContext(hasPriorRecording: true).hasContent)
    }

    @Test func dueLabels() {
        let c = ShadowContext(owes: [
            ShadowOwe(text: "A", due: Due(date: kst("2026-11-24T14:00:00+09:00"), hasTime: true)),
            ShadowOwe(text: "B", due: Due(date: kst("2026-11-25T00:00:00+09:00"), hasTime: false)),
            ShadowOwe(text: "C", due: Due(date: kst("2026-12-03T00:00:00+09:00"), hasTime: false)),
            ShadowOwe(text: "D"),
        ])
        let line = ShadowEvent.contextDescription(c, now: now).split(separator: "\n")[1]
        #expect(line == "할 것: A(내일 14:00), B(모레), C(12/3), D — 남음")
    }

    @Test func contextPayloadJSON() throws {
        let p = ShadowEvent.contextPayload(for: meeting, context: fullContext, now: now)
        #expect(p.startDate == kst("2026-11-24T18:50:00+09:00"))
        #expect(p.endDate == meeting.start)
        let obj = try JSONSerialization.jsonObject(with: try p.jsonData()) as! [String: Any]
        let start = obj["start"] as! [String: Any]
        #expect(start["dateTime"] as? String == "2026-11-24T18:50:00+09:00")
        #expect(start["timeZone"] as? String == "Asia/Seoul")
        let rem = obj["reminders"] as! [String: Any]
        #expect(rem["useDefault"] as? Bool == false)
        #expect((rem["overrides"] as? [Any])?.isEmpty == true)
        let priv = (obj["extendedProperties"] as! [String: Any])["private"] as! [String: String]
        #expect(priv == ["mulgil_src": meeting.key.description, "mulgil_v": "2026-11-23T07:30:00+09:00"])
        #expect(obj["transparency"] as? String == "transparent")
        #expect(obj["startDate"] == nil)
        // 같은 입력이면 같은 바이트
        #expect(try p.jsonData() == ShadowEvent.contextPayload(for: meeting, context: fullContext, now: now).jsonData())
    }

    @Test func payloadDecodesBackAsExistingShadow() throws {
        let p = ShadowEvent.contextPayload(for: meeting, context: fullContext, now: now)
        var json = try JSONSerialization.jsonObject(with: try p.jsonData()) as! [String: Any]
        json["id"] = "sh1"
        let data = try JSONSerialization.data(withJSONObject: ["items": [json], "nextSyncToken": "x"])
        let g = try GCalEventsPage.decode(data).items[0]
        #expect(g.isMulgilShadow)
        let ex = ShadowExisting(g)!
        #expect(ex.src == meeting.key.description)
        #expect(ex.start == p.startDate && ex.end == p.endDate)
        // 그대로 다시 돌리면 아무것도 안 바뀐다.
        let plan = ShadowEvent.contextDiff(targets: [ShadowTarget(event: meeting, context: fullContext)],
                                           existing: [ex], now: now.addingTimeInterval(3600))
        #expect(plan.isEmpty)
        #expect(ShadowExisting(GCalEvent(id: "manual", summary: "내가 넣은 일정",
                                         start: GCalEventDateTime(dateTime: "2026-11-24T10:00:00+09:00"),
                                         end: GCalEventDateTime(dateTime: "2026-11-24T11:00:00+09:00"))) == nil)
    }

    @Test func oweAlarmHasPopupSixtyMinutes() throws {
        let item = ShadowOweAlarmItem(markId: "m1", text: "연사 리스트 공유", due: Due(date: kst("2026-11-27T18:00:00+09:00"), hasTime: true))
        let dateOnly = ShadowOweAlarmItem(markId: "m2", text: "보고서", due: Due(date: kst("2026-11-27T00:00:00+09:00"), hasTime: false))
        let past = ShadowOweAlarmItem(markId: "m3", text: "지난 것", due: Due(date: kst("2026-11-22T18:00:00+09:00"), hasTime: true))
        let ps = ShadowEvent.oweAlarmPayloads([item, dateOnly, past], now: now)
        #expect(ps.count == 1)
        let p = ps[0]
        #expect(p.src == "owe:m1")
        #expect(p.summary == "할 것: 연사 리스트 공유")
        #expect(p.startDate == item.due.date)
        #expect(p.reminders == ShadowReminders(useDefault: false, overrides: [ShadowReminderOverride(method: "popup", minutes: 60)]))
    }

    @Test func moreThanThreeOwesOnOneDayMerge() {
        let day = (0..<4).map { i in
            ShadowOweAlarmItem(markId: "m\(i)", text: "일\(i)", due: Due(date: kst("2026-11-26T1\(i):00:00+09:00"), hasTime: true))
        }
        let other = ShadowOweAlarmItem(markId: "z", text: "다른 날", due: Due(date: kst("2026-11-27T09:00:00+09:00"), hasTime: true))
        let ps = ShadowEvent.oweAlarmPayloads(day + [other], now: now)
        #expect(ps.count == 2)
        #expect(ps[0].src == "owe:2026-11-26")
        #expect(ps[0].summary == "할 것 4개")
        #expect(ps[0].startDate == kst("2026-11-26T10:00:00+09:00"))
        #expect(ps[0].description.split(separator: "\n").count == 5)
        #expect(ps[0].description.contains("13:00 일3"))
        #expect(ps[1].src == "owe:z")
        #expect(ShadowEvent.oweAlarmPayloads(Array(day.prefix(3)), now: now).count == 3)
    }

    @Test func diffInsertsOnlyEligibleWithinSevenDays() {
        let ctx = ShadowContext(hasPriorRecording: true)
        let targets = [
            ShadowTarget(event: meeting, context: ctx),
            ShadowTarget(event: ev(id: "empty", title: "빈 회의", start: "2026-11-25T10:00:00+09:00"), context: ShadowContext()),
            ShadowTarget(event: ev(id: "far", title: "먼 회의", start: "2026-12-01T08:00:00+09:00"), context: ctx),
            ShadowTarget(event: ev(id: "edge", title: "경계", start: "2026-11-30T07:30:00+09:00"), context: ctx),
            ShadowTarget(event: ev(id: "allday", title: "종일", start: "2026-11-25T00:00:00+09:00", allDay: true), context: ctx),
            ShadowTarget(event: ev(id: "inbox", title: "#내일 3시", start: "2026-11-25T15:00:00+09:00"), context: ctx),
            ShadowTarget(event: ev(id: "gone", title: "취소됨", start: "2026-11-25T15:00:00+09:00", cancelled: true), context: ctx),
            ShadowTarget(event: ev(id: "past", title: "지난 회의", start: "2026-11-23T07:00:00+09:00"), context: ctx),
        ]
        let plan = ShadowEvent.contextDiff(targets: targets, existing: [], now: now)
        #expect(plan.inserts.map(\.src).sorted() == ["c|edge|-", meeting.key.description].sorted())
        #expect(plan.patches.isEmpty && plan.deletes.isEmpty)
    }

    @Test func lateDiscoverySkipsShadowWithinTwentyMinutes() {
        let ctx = ShadowContext(hasPriorRecording: true)
        let soon = ev(id: "soon", title: "곧 회의", start: "2026-11-23T07:45:00+09:00")
        let ok = ev(id: "ok", title: "조금 뒤", start: "2026-11-23T07:51:00+09:00")
        let plan = ShadowEvent.contextDiff(targets: [ShadowTarget(event: soon, context: ctx), ShadowTarget(event: ok, context: ctx)],
                                           existing: [], now: now)
        #expect(plan.skippedLate == ["c|soon|-"])
        #expect(plan.inserts.map(\.src) == ["c|ok|-"])
    }

    @Test func diffPatchesOnlyRealChanges() {
        let p = ShadowEvent.contextPayload(for: meeting, context: fullContext, now: now.addingTimeInterval(-7200))
        let ex = ShadowExisting(eventId: "sh1", src: p.src, summary: p.summary, description: p.description,
                                start: p.startDate, end: p.endDate)
        // 기준 시각만 달라진 것은 patch하지 않는다.
        #expect(ShadowEvent.contextDiff(targets: [ShadowTarget(event: meeting, context: fullContext)], existing: [ex], now: now).isEmpty)
        // 원본이 옮겨지면 patch
        var moved = meeting
        moved.start = kst("2026-11-24T20:00:00+09:00"); moved.end = kst("2026-11-24T21:00:00+09:00")
        let plan = ShadowEvent.contextDiff(targets: [ShadowTarget(event: moved, context: fullContext)], existing: [ex], now: now)
        #expect(plan.patches.map(\.eventId) == ["sh1"])
        #expect(plan.patches[0].payload.startDate == kst("2026-11-24T19:50:00+09:00"))
        // Mark가 바뀌어도 patch
        var ctx = fullContext
        ctx.decisions = ["장소 = 강남"]
        #expect(ShadowEvent.contextDiff(targets: [ShadowTarget(event: meeting, context: ctx)], existing: [ex], now: now).patches.count == 1)
    }

    @Test func diffDeletesOrphansButKeepsPastAndOweAlarms() {
        let future = ShadowExisting(eventId: "f", src: "c|cancelled|-", summary: "· 취소된 회의 맥락", description: "",
                                    start: kst("2026-11-25T09:50:00+09:00"), end: kst("2026-11-25T10:00:00+09:00"))
        let past = ShadowExisting(eventId: "p", src: "c|old|-", summary: "· 지난 회의 맥락", description: "",
                                  start: kst("2026-11-22T09:50:00+09:00"), end: kst("2026-11-22T10:00:00+09:00"))
        let owe = ShadowExisting(eventId: "o", src: "owe:m1", summary: "할 것: x", description: "",
                                 start: kst("2026-11-26T10:00:00+09:00"), end: kst("2026-11-26T10:10:00+09:00"))
        let plan = ShadowEvent.contextDiff(targets: [], existing: [future, past, owe], now: now)
        #expect(plan.deletes == ["f"])
        #expect(plan.inserts.isEmpty)
    }

    @Test func diffRemovesDuplicateShadows() {
        let ctx = ShadowContext(hasPriorRecording: true)
        let p = ShadowEvent.contextPayload(for: meeting, context: ctx, now: now)
        let a = ShadowExisting(eventId: "a", src: p.src, summary: p.summary, description: p.description, start: p.startDate, end: p.endDate)
        var b = a; b.eventId = "b"
        let plan = ShadowEvent.contextDiff(targets: [ShadowTarget(event: meeting, context: ctx)], existing: [b, a], now: now)
        #expect(plan.deletes == ["b"])
        #expect(plan.inserts.isEmpty && plan.patches.isEmpty)
    }

    @Test func oweDiffMovesAlarmWhenDueChanges() {
        let item = ShadowOweAlarmItem(markId: "m1", text: "보고서", due: Due(date: kst("2026-11-27T18:00:00+09:00"), hasTime: true))
        let p = ShadowEvent.oweAlarmPayloads([item], now: now)[0]
        let ex = ShadowExisting(eventId: "o1", src: p.src, summary: p.summary, description: p.description, start: p.startDate, end: p.endDate)
        #expect(ShadowEvent.oweDiff(items: [item], existing: [ex], now: now).isEmpty)
        var moved = item
        moved.due = Due(date: kst("2026-11-28T18:00:00+09:00"), hasTime: true)
        #expect(ShadowEvent.oweDiff(items: [moved], existing: [ex], now: now).patches.map(\.eventId) == ["o1"])
        #expect(ShadowEvent.oweDiff(items: [], existing: [ex], now: now).deletes == ["o1"])
    }

    @Test func endToEndMirrorToShadowPlan() throws {
        let m = try syncedMirror()
        let idx = SeriesGrouper().group(m.allEvents, now: now)
        let targets = m.allEvents.map { e in
            ShadowTarget(event: e, context: idx.seriesId(for: e.key) != nil
                         ? ShadowContext(link: m.entry(for: e.key)?.link, hasPriorRecording: true) : ShadowContext())
        }
        let plan = ShadowEvent.contextDiff(targets: targets, existing: [], now: now)
        // 11/24 회차만 7일 창 안에 있다(12/1 19:00은 창 밖).
        #expect(plan.inserts.count == 1)
        #expect(plan.inserts[0].summary == "· 🚀 AUSG 운영 회의 맥락")
        #expect(plan.inserts[0].description.hasSuffix("\nhttps://zoom.us/j/123456789?pwd=abc"))
    }
}

// MARK: - 경계 사례(리뷰에서 추가)

@Suite struct GoogleCalendarEdgeTests {
    private func incremental(_ m: inout CalendarMirror, _ json: String) throws -> GCalApplyResult {
        let r = m.nextRequest(for: primary, now: now)!
        return try m.apply(try page(json), for: r)
    }

    @Test func offsetCrossesYearBoundary() {
        // 12/31 23:30 (-01:00) = 1/1 00:30 UTC = 1/1 09:30 KST
        #expect(GCalTimeParser.parseDateTime("2026-12-31T23:30:00-01:00") == kst("2027-01-01T09:30:00+09:00"))
        #expect(GCalTimeParser.parseDateTime("2026-12-31T15:00:00Z") == kst("2027-01-01T00:00:00+09:00"))
        #expect(GCalTimeParser.parseDate("2028-02-29")! == (2028, 2, 29))
        #expect(GCalTimeParser.parseDate("2027-02-29") == nil)
        #expect(GCalTimeParser.parseDateTime("2026-11-31T10:00:00Z") == nil)
    }

    @Test func allDayEventOnDecember31EndsOnNewYearMidnight() throws {
        let p = try page(#"{"items":[{"id":"nye","status":"confirmed","summary":"송년회","start":{"date":"2026-12-31"},"end":{"date":"2027-01-01"}}]}"#)
        let e = p.items[0].toCalendarEvent(calendarId: primary)!
        #expect(e.isAllDay)
        #expect(e.start == kst("2026-12-31T00:00:00+09:00"))
        #expect(e.end == kst("2027-01-01T00:00:00+09:00"))
        #expect(e.duration == 86_400)
    }

    @Test func windowAtSeoulMidnightVersusUTCDay() {
        // UTC로는 11/23이지만 서울은 11/24 01:00이다. 창은 서울 날짜 기준이어야 한다.
        let n = kst("2026-11-24T01:00:00+09:00")
        let w = GCalSyncWindow.default.interval(now: n)
        #expect(w.start == kst("2026-10-27T00:00:00+09:00"))
        #expect(w.end == kst("2027-01-20T00:00:00+09:00"))
        let r = CalendarMirror(calendarIds: [primary]).nextRequest(for: primary, now: n)!
        #expect(r.queryItems.first { $0.name == "timeMin" }?.value == "2026-10-26T15:00:00Z")
    }

    @Test func windowAcrossYearEnd() {
        let w = GCalSyncWindow.default.interval(now: kst("2026-12-31T23:59:59+09:00"))
        #expect(w.start == kst("2026-12-03T00:00:00+09:00"))
        #expect(w.end == kst("2027-02-26T00:00:00+09:00"))
        // 자정 정각도 같은 날로 본다.
        #expect(GCalSyncWindow.default.interval(now: kst("2027-01-01T00:00:00+09:00")).start == kst("2026-12-04T00:00:00+09:00"))
    }

    @Test func emptyIncrementalPageKeepsMirrorAndAdvancesToken() throws {
        var m = try syncedMirror()
        let res = try incremental(&m, #"{"nextSyncToken":"S-EMPTY"}"#)
        #expect(res.completed && res.upserted.isEmpty && res.removed.isEmpty)
        #expect(m.allEvents.count == 4)
        #expect(m.states[primary]?.syncToken == "S-EMPTY")
    }

    @Test func emptyInputsProduceEmptyOutputs() {
        #expect(SeriesGrouper().group([], now: now).series.isEmpty)
        #expect(ShadowEvent.contextDiff(targets: [], existing: [], now: now).isEmpty)
        #expect(ShadowEvent.oweDiff(items: [], existing: [], now: now).isEmpty)
        #expect(ShadowEvent.oweAlarmPayloads([], now: now).isEmpty)
        #expect(CalendarMirror(calendarIds: []).nextRequests(now: now).isEmpty)
        #expect(SeriesGrouper.normalizeTitle("") == "")
        #expect(SeriesGrouper.normalizeTitle("🎉🎉") == "")
    }

    @Test func singleEventConvertedToRecurringLeavesNoGhost() throws {
        // lunch1(단일)을 반복으로 바꾸면 증분은 회차만 보낸다. 옛 단일 키가 남으면 같은 회의가 두 번 뜬다.
        var m = try syncedMirror()
        let res = try incremental(&m, #"""
        {"nextSyncToken":"S4","items":[
          {"id":"lunch1_20261123T033000Z","status":"confirmed","summary":"점심 미팅","recurringEventId":"lunch1",
           "start":{"dateTime":"2026-11-23T12:30:00+09:00"},"end":{"dateTime":"2026-11-23T13:30:00+09:00"},
           "originalStartTime":{"dateTime":"2026-11-23T12:30:00+09:00"}}]}
        """#)
        let old = OccurrenceKey(calendarId: primary, seriesId: "lunch1", originalStart: nil)
        #expect(m.event(for: old) == nil)
        #expect(res.removed == [old])
        #expect(m.allEvents.filter { $0.title == "점심 미팅" }.count == 1)
    }

    @Test func recurringConvertedToSingleLeavesNoGhost() throws {
        var m = try syncedMirror()
        _ = try incremental(&m, #"""
        {"nextSyncToken":"S5","items":[
          {"id":"ausg123","status":"confirmed","summary":"AUSG 운영 회의",
           "start":{"dateTime":"2026-11-24T19:00:00+09:00"},"end":{"dateTime":"2026-11-24T20:00:00+09:00"}}]}
        """#)
        #expect(m.allEvents.filter { $0.key.seriesId == "ausg123" }.map(\.key.originalStart) == [nil])
    }

    @Test func instanceWithoutOriginalStartTimeDoesNotCollide() throws {
        let p = try page(#"""
        {"items":[
          {"id":"r_1","status":"confirmed","summary":"x","recurringEventId":"r","start":{"dateTime":"2026-11-24T10:00:00+09:00"},"end":{"dateTime":"2026-11-24T11:00:00+09:00"}},
          {"id":"r_2","status":"confirmed","summary":"x","recurringEventId":"r","start":{"dateTime":"2026-11-25T10:00:00+09:00"},"end":{"dateTime":"2026-11-25T11:00:00+09:00"}}]}
        """#)
        let keys = p.items.map { $0.occurrenceKey(calendarId: primary) }
        #expect(Set(keys).count == 2)
        #expect(keys[0].originalStart == kst("2026-11-24T10:00:00+09:00"))
    }

    @Test func fullSyncDoesNotReportSameRemovalTwice() throws {
        var m = try syncedMirror()
        m.handleGone(calendarId: primary)
        let r1 = m.nextRequest(for: primary, now: now)!
        _ = try m.apply(try page(#"{"nextPageToken":"P2","items":[{"id":"lunch1","status":"confirmed","summary":"점심 미팅","start":{"dateTime":"2026-11-23T12:30:00+09:00"},"end":{"dateTime":"2026-11-23T13:30:00+09:00"}}]}"#), for: r1)
        let r2 = m.nextRequest(for: primary, now: now)!
        let res = try m.apply(try page(#"{"nextSyncToken":"N","items":[{"id":"lunch1","status":"cancelled"}]}"#), for: r2)
        let lunch = OccurrenceKey(calendarId: primary, seriesId: "lunch1", originalStart: nil)
        #expect(res.removed.filter { $0 == lunch }.count == 1)
        #expect(Set(res.removed).count == res.removed.count)
    }

    @Test func duplicateItemsInOnePageAreReportedOnce() throws {
        var m = try syncedMirror()
        let item = #"{"id":"lunch1","status":"confirmed","summary":"점심","start":{"dateTime":"2026-11-23T12:30:00+09:00"},"end":{"dateTime":"2026-11-23T13:30:00+09:00"}}"#
        let res = try incremental(&m, #"{"nextSyncToken":"S6","items":["# + item + "," + item + "]}")
        #expect(res.upserted.count == 1)
    }

    @Test func normalizesKoreanAndFullDates() {
        let base = "주간 싱크"
        for t in ["주간 싱크 11월 23일", "주간 싱크 (11월 30일)", "2026.11.23 주간 싱크", "주간 싱크 2026-12-07",
                  "주간 싱크 11/23(월)", "주간 싱크 (12/31 목)", "[주간 싱크] 1/1"] {
            #expect(SeriesGrouper.normalizeTitle(t) == base, "\(t) → \(SeriesGrouper.normalizeTitle(t))")
        }
        // 의미 있는 숫자는 남긴다.
        #expect(SeriesGrouper.normalizeTitle("3회의실 미팅") == "3회의실 미팅")
    }

    @Test func duplicateEventsDoNotDuplicateMembers() {
        let a = ev(id: "s1", title: "주간 싱크", start: "2026-11-02T10:00:00+09:00")
        let b = ev(id: "s2", title: "주간 싱크", start: "2026-11-09T10:00:00+09:00")
        let c = ev(id: "s3", title: "주간 싱크", start: "2026-11-16T10:00:00+09:00")
        let idx = SeriesGrouper().group([a, b, c, a, b], now: now)
        #expect(idx.series.count == 1)
        #expect(idx.series[0].members.count == 3)
    }

    @Test func midnightSplitCountsAsTwoDays() {
        // 23:30과 다음날 00:10은 서울 기준 서로 다른 날이다. UTC로 세면 같은 날(14:30Z, 15:10Z)로 접힌다.
        let evs = [ev(id: "a", title: "야간 스터디", start: "2026-11-10T23:30:00+09:00"),
                   ev(id: "b", title: "야간 스터디", start: "2026-11-11T00:10:00+09:00"),
                   ev(id: "c", title: "야간 스터디", start: "2026-11-17T23:30:00+09:00")]
        #expect(SeriesGrouper().group(evs, now: now).series.count == 1)
    }

    @Test func shadowJustAfterMidnightStartsPreviousDay() throws {
        let m = ev(primary, id: "nye", title: "새해 회의", start: "2027-01-01T00:05:00+09:00")
        let p = ShadowEvent.contextPayload(for: m, context: ShadowContext(hasPriorRecording: true), now: kst("2026-12-30T09:00:00+09:00"))
        let obj = try JSONSerialization.jsonObject(with: try p.jsonData()) as! [String: Any]
        #expect((obj["start"] as! [String: Any])["dateTime"] as? String == "2026-12-31T23:55:00+09:00")
        #expect((obj["end"] as! [String: Any])["dateTime"] as? String == "2027-01-01T00:05:00+09:00")
        #expect(p.description.hasPrefix("기준 12/30 09:00 · 원본 일정 확인"))
    }

    @Test func dueLabelsAcrossYearEnd() {
        let n = kst("2026-12-31T23:59:00+09:00")
        #expect(ShadowEvent.dueLabel(Due(date: kst("2027-01-01T00:00:00+09:00"), hasTime: false), now: n) == "내일")
        #expect(ShadowEvent.dueLabel(Due(date: kst("2027-01-02T09:00:00+09:00"), hasTime: true), now: n) == "모레 09:00")
        #expect(ShadowEvent.dueLabel(Due(date: kst("2027-01-05T00:00:00+09:00"), hasTime: false), now: n) == "1/5")
    }

    @Test func rollingWindowBoundaries() {
        let ctx = ShadowContext(hasPriorRecording: true)
        let exact = ev(id: "edge", title: "끝", start: "2026-11-30T07:30:00+09:00")       // now+7일 정각: 포함
        let over = ev(id: "over", title: "넘음", start: "2026-11-30T07:31:00+09:00")      // 창 밖
        let late = ev(id: "late", title: "임박", start: "2026-11-23T07:49:59+09:00")      // 20분 이내
        let atCut = ev(id: "cut", title: "딱20분", start: "2026-11-23T07:50:00+09:00")    // 정확히 20분: 만든다
        let started = ev(id: "now", title: "지금", start: "2026-11-23T07:30:00+09:00")    // 이미 시작
        let plan = ShadowEvent.contextDiff(targets: [exact, over, late, atCut, started].map { ShadowTarget(event: $0, context: ctx) },
                                           existing: [], now: now)
        #expect(plan.inserts.map(\.src).sorted() == ["c|cut|-", "c|edge|-"])
        #expect(plan.skippedLate == ["c|late|-"])
    }

    @Test func fractionalSecondStartDoesNotPatchForever() throws {
        // 원본 시작에 소수초가 있어도 Google이 돌려주는 섀도 시각은 초 단위다.
        let raw = try page(#"{"items":[{"id":"f1","status":"confirmed","summary":"소수초 회의","start":{"dateTime":"2026-11-24T10:00:00.750+09:00"},"end":{"dateTime":"2026-11-24T11:00:00+09:00"}}]}"#)
        let e = raw.items[0].toCalendarEvent(calendarId: primary)!
        let ctx = ShadowContext(hasPriorRecording: true)
        let p = ShadowEvent.contextPayload(for: e, context: ctx, now: now)
        var json = try JSONSerialization.jsonObject(with: try p.jsonData()) as! [String: Any]
        json["id"] = "sh"
        let back = try GCalEventsPage.decode(try JSONSerialization.data(withJSONObject: ["items": [json]])).items[0]
        let ex = ShadowExisting(back)!
        #expect(ShadowEvent.contextDiff(targets: [ShadowTarget(event: e, context: ctx)], existing: [ex], now: now).isEmpty)
    }

    @Test func truncatedOweLineKeepsRemainingMarker() {
        let c = ShadowContext(owes: [ShadowOwe(text: "아주 긴 할 일 설명이 계속 이어지는 항목 하나와 또 다른 항목")])
        let line = String(ShadowEvent.contextDescription(c, now: now).split(separator: "\n")[1])
        #expect(line.count == 40)
        #expect(line.hasSuffix("… — 남음"))
        #expect(line.hasPrefix("할 것: "))
    }

    @Test func descriptionNeverExceedsSixLinesAndOneLineEach() {
        let c = ShadowContext(decisions: ["a\nb", "  "], questions: ["q\r\nr"], owes: [ShadowOwe(text: "o\n")],
                              waits: ["w"], link: "https://meet.google.com/x\n", hasPriorRecording: true)
        let lines = ShadowEvent.contextDescription(c, now: now).components(separatedBy: "\n")
        #expect(lines.count == 5) // 개행 섞인 링크는 버린다
        #expect(lines[1] == "정한 것: a b")
        #expect(lines[2] == "미정: q r")
        #expect(lines.allSatisfy { !$0.contains("\r") })
    }

    @Test func emptyTitleShadowHasPlaceholder() {
        #expect(ShadowEvent.contextTitle("   ") == "· (제목 없음) 맥락")
        #expect(ShadowEvent.contextTitle(" AUSG\n회의 ") == "· AUSG 회의 맥락")
    }

    @Test func oweMergeUsesSeoulDayNotUTCDay() {
        // 11/24 00:30~01:30 KST는 UTC로 11/23이다. 서울 기준 하루로 합쳐야 한다.
        let items = (0..<4).map { i in
            ShadowOweAlarmItem(markId: "m\(i)", text: "일\(i)",
                               due: Due(date: kst("2026-11-24T00:30:00+09:00").addingTimeInterval(Double(i) * 1200), hasTime: true))
        }
        let ps = ShadowEvent.oweAlarmPayloads(items, now: now)
        #expect(ps.map(\.src) == ["owe:2026-11-24"])
        #expect(ps[0].summary == "할 것 4개")
    }

    @Test func dueExactlyNowIsNotAlarmed() {
        let it = ShadowOweAlarmItem(markId: "x", text: "지금", due: Due(date: now, hasTime: true))
        #expect(ShadowEvent.oweAlarmPayloads([it], now: now).isEmpty)
    }

    @Test func reapplyingSamePageIsIdempotentButSecondCallIsStale() throws {
        var m = try syncedMirror()
        let r = m.nextRequest(for: primary, now: now)!
        _ = try m.apply(try page(incrementalPage), for: r)
        #expect(throws: GCalMirrorError.staleResponse(calendarId: primary)) {
            _ = try m.apply(try page(incrementalPage), for: r)
        }
    }
}
