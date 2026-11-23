import Foundation

// 캘린더 미러 상태기계(§5.5). HTTP는 앱이 하고, 여기는 "다음에 뭘 요청할지"와
// "받은 페이지를 어떻게 반영할지"만 결정한다. 같은 입력이면 같은 상태가 나온다.

/// 전체 동기화 범위. 첫 실행 백필(§7.4, 지난 4주)과 맞추고, 미래는 8주.
public struct GCalSyncWindow: Codable, Sendable, Hashable {
    public var pastDays: Int
    public var futureDays: Int

    public init(pastDays: Int = 28, futureDays: Int = 56) {
        self.pastDays = pastDays; self.futureDays = futureDays
    }

    public static let `default` = GCalSyncWindow()

    /// 서울 자정에 맞춘다. 같은 날 여러 번 재동기화해도 요청이 같아야 비교·캐시가 쉽다.
    public func interval(now: Date) -> DateInterval {
        let cal = Seoul.calendar
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -pastDays, to: today)!
        let end = cal.date(byAdding: .day, value: futureDays + 1, to: today)!
        return DateInterval(start: start, end: end)
    }
}

public enum GCalSyncMode: String, Codable, Sendable { case full, incremental }

public struct GCalQueryParam: Codable, Sendable, Hashable {
    public let name: String
    public let value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}

/// 앱이 그대로 GET 하면 되는 events.list 요청.
public struct GCalSyncRequest: Codable, Sendable, Hashable {
    public let calendarId: String
    public let mode: GCalSyncMode
    public let syncToken: String?
    public let pageToken: String?
    public let timeMin: Date?
    public let timeMax: Date?
    public let maxResults: Int

    public init(calendarId: String, mode: GCalSyncMode, syncToken: String?, pageToken: String?,
                timeMin: Date?, timeMax: Date?, maxResults: Int = 250) {
        self.calendarId = calendarId; self.mode = mode; self.syncToken = syncToken; self.pageToken = pageToken
        self.timeMin = timeMin; self.timeMax = timeMax; self.maxResults = maxResults
    }

    /// calendarId에는 '#'·'@'가 들어간다(공휴일 캘린더 등). 경로 조각으로 안전하게 인코딩한다.
    public var path: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~@")
        let enc = calendarId.addingPercentEncoding(withAllowedCharacters: allowed) ?? calendarId
        return "/calendar/v3/calendars/\(enc)/events"
    }

    /// syncToken과 timeMin/timeMax·orderBy는 함께 보낼 수 없다(API가 400). 그래서 모드별로 나눈다.
    /// singleEvents는 회차 키를 받기 위해 항상 true로, 첫 요청과 이후 요청의 조건을 같게 둔다.
    public var queryItems: [GCalQueryParam] {
        var q = [GCalQueryParam("singleEvents", "true"), GCalQueryParam("showDeleted", "true"),
                 GCalQueryParam("maxResults", String(maxResults))]
        switch mode {
        case .incremental:
            if let t = syncToken { q.append(GCalQueryParam("syncToken", t)) }
        case .full:
            if let a = timeMin { q.append(GCalQueryParam("timeMin", GCalTimeParser.utcRFC3339(a))) }
            if let b = timeMax { q.append(GCalQueryParam("timeMax", GCalTimeParser.utcRFC3339(b))) }
        }
        if let p = pageToken { q.append(GCalQueryParam("pageToken", p)) }
        return q
    }

    public func url(base: String = "https://www.googleapis.com") -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        c.percentEncodedPath = path
        c.queryItems = queryItems.map { URLQueryItem(name: $0.name, value: $0.value) }
        return c.url
    }
}

/// 캘린더 하나의 동기화 진행 상태.
public struct GCalCalendarSyncState: Codable, Sendable, Hashable {
    public internal(set) var syncToken: String?
    /// 진행 중인 페이지 연속 토큰. nil이면 다음 요청이 새 라운드의 첫 페이지다.
    public internal(set) var pageToken: String?
    /// 전체 동기화 도중에는 첫 페이지의 창을 끝까지 유지해야 한다(페이지마다 조건이 같아야 함).
    public internal(set) var fullSyncWindow: DateInterval?
    public internal(set) var needsFullSync: Bool = true
    public internal(set) var lastCompletedAt: Date?
    public internal(set) var goneCount: Int = 0

    public init() {}
}

/// 미러에 저장하는 회차 한 개 + 섀도에 필요한 링크.
public struct GCalMirrorEntry: Codable, Sendable, Hashable {
    public var event: CalendarEvent
    public var link: String?
    public init(event: CalendarEvent, link: String? = nil) { self.event = event; self.link = link }
}

public struct GCalApplyResult: Sendable, Hashable {
    public var upserted: [OccurrenceKey] = []
    public var removed: [OccurrenceKey] = []
    /// 섀도·반복 원본·시각 없는 항목처럼 미러에 넣지 않은 것의 수.
    public var skipped: Int = 0
    /// 이 페이지로 라운드가 끝났는지(nextSyncToken 수신).
    public var completed: Bool = false
    public var mode: GCalSyncMode = .incremental
}

public enum GCalMirrorError: Error, Equatable {
    case unknownCalendar(String)
    /// 미러가 기대한 요청과 다른 요청의 응답이다(늦게 도착한 응답 등). 반영하면 토큰이 꼬인다.
    case staleResponse(calendarId: String)
    /// 마지막 페이지인데 nextSyncToken이 없다. 증분을 이어갈 수 없으니 전체 동기화로 돌린다.
    case missingSyncToken(calendarId: String)
}

/// HTTP 오류를 받았을 때 앱이 할 일.
public enum GCalErrorAction: Equatable, Sendable {
    case fullResyncScheduled
    case reauthorize
    case retryLater
    case fail
}

public struct CalendarMirror: Codable, Sendable {
    public private(set) var window: GCalSyncWindow
    public private(set) var states: [String: GCalCalendarSyncState]
    private var entries: [String: [OccurrenceKey: GCalMirrorEntry]]
    /// 전체 동기화 페이지를 모으는 곳. 마지막 페이지에서 한 번에 바꿔 끼워 중간에 미러가 비지 않게 한다.
    private var staging: [String: [OccurrenceKey: GCalMirrorEntry]]

    public init(calendarIds: [String], window: GCalSyncWindow = .default) {
        self.window = window
        self.states = Dictionary(uniqueKeysWithValues: calendarIds.map { ($0, GCalCalendarSyncState()) })
        self.entries = [:]
        self.staging = [:]
    }

    public var calendarIds: [String] { states.keys.sorted() }

    public mutating func addCalendar(_ id: String) {
        if states[id] == nil { states[id] = GCalCalendarSyncState() }
    }

    public mutating func removeCalendar(_ id: String) {
        states[id] = nil; entries[id] = nil; staging[id] = nil
    }

    // MARK: 요청

    /// 이 캘린더의 다음 요청. 상태를 바꾸지 않으므로 몇 번 불러도 같다.
    public func nextRequest(for calendarId: String, now: Date) -> GCalSyncRequest? {
        guard let s = states[calendarId] else { return nil }
        if s.needsFullSync || s.syncToken == nil {
            let w = s.fullSyncWindow ?? window.interval(now: now)
            return GCalSyncRequest(calendarId: calendarId, mode: .full, syncToken: nil, pageToken: s.pageToken,
                                   timeMin: w.start, timeMax: w.end)
        }
        return GCalSyncRequest(calendarId: calendarId, mode: .incremental, syncToken: s.syncToken,
                               pageToken: s.pageToken, timeMin: nil, timeMax: nil)
    }

    /// 폴링 한 번에 돌릴 요청들(캘린더 id 순).
    public func nextRequests(now: Date) -> [GCalSyncRequest] {
        calendarIds.compactMap { nextRequest(for: $0, now: now) }
    }

    // MARK: 응답 반영

    public mutating func apply(_ page: GCalEventsPage, for request: GCalSyncRequest) throws -> GCalApplyResult {
        let cal = request.calendarId
        guard var s = states[cal] else { throw GCalMirrorError.unknownCalendar(cal) }
        let expectedMode: GCalSyncMode = (s.needsFullSync || s.syncToken == nil) ? .full : .incremental
        guard request.mode == expectedMode, request.pageToken == s.pageToken,
              expectedMode == .full || request.syncToken == s.syncToken else {
            throw GCalMirrorError.staleResponse(calendarId: cal)
        }
        if expectedMode == .full, let w = s.fullSyncWindow,
           w.start != request.timeMin || w.end != request.timeMax {
            throw GCalMirrorError.staleResponse(calendarId: cal)
        }

        var result = GCalApplyResult()
        result.mode = expectedMode
        if expectedMode == .full {
            if request.pageToken == nil { staging[cal] = [:] }
            var bucket = staging[cal] ?? [:]
            Self.merge(page.items, calendarId: cal, into: &bucket, result: &result)
            staging[cal] = bucket
        } else {
            var bucket = entries[cal] ?? [:]
            Self.merge(page.items, calendarId: cal, into: &bucket, result: &result)
            entries[cal] = bucket
        }

        if let next = page.nextPageToken {
            s.pageToken = next
            if expectedMode == .full, let a = request.timeMin, let b = request.timeMax {
                s.fullSyncWindow = DateInterval(start: a, end: b)
            }
        } else if let token = page.nextSyncToken {
            if expectedMode == .full {
                let old = entries[cal] ?? [:]
                let fresh = staging[cal] ?? [:]
                // 전체 동기화에서 사라진 회차는 삭제로 알려 준다(섀도 정리에 필요).
                result.removed = Self.unique(result.removed + old.keys.filter { fresh[$0] == nil }.sorted(by: Self.keyOrder))
                entries[cal] = fresh
                staging[cal] = nil
                s.needsFullSync = false
                s.fullSyncWindow = nil
            }
            s.syncToken = token
            s.pageToken = nil
            result.completed = true
        } else {
            // 토큰 없는 마지막 페이지: 증분을 이어갈 근거가 없으므로 처음부터 다시 받는다.
            s = Self.resetForFullSync(s)
            staging[cal] = nil
            states[cal] = s
            throw GCalMirrorError.missingSyncToken(calendarId: cal)
        }
        states[cal] = s
        return result
    }

    /// 라운드가 끝난 시각 기록. 앱이 마지막 페이지 반영 후 부른다(헬스 표시용).
    public mutating func markCompleted(calendarId: String, at now: Date) {
        states[calendarId]?.lastCompletedAt = now
    }

    /// 410 Gone: 토큰이 무효다. 그 캘린더만 토큰 없이 전체 동기화로 돌린다.
    public mutating func handleGone(calendarId: String) {
        guard let s = states[calendarId] else { return }
        var n = Self.resetForFullSync(s)
        n.goneCount += 1
        states[calendarId] = n
        staging[calendarId] = nil
    }

    public mutating func handleHTTPStatus(_ status: Int, calendarId: String) -> GCalErrorAction {
        switch status {
        case 410:
            handleGone(calendarId: calendarId)
            return .fullResyncScheduled
        case 401:
            return .reauthorize
        case 403, 429, 500...599:
            // 403은 대개 rateLimitExceeded다. 토큰은 그대로 두고 다음 폴링에서 다시 한다.
            return .retryLater
        default:
            return .fail
        }
    }

    private static func resetForFullSync(_ s: GCalCalendarSyncState) -> GCalCalendarSyncState {
        var n = s
        n.syncToken = nil; n.pageToken = nil; n.fullSyncWindow = nil; n.needsFullSync = true
        return n
    }

    private static func merge(_ items: [GCalEvent], calendarId: String,
                              into bucket: inout [OccurrenceKey: GCalMirrorEntry], result: inout GCalApplyResult) {
        for item in items {
            if item.isMulgilShadow { result.skipped += 1; continue }
            if item.isCancelled {
                if item.recurringEventId == nil {
                    // 단일 일정 삭제이거나 반복 원본 통째 삭제다. 둘 다 seriesId가 id와 같다.
                    let gone = bucket.keys.filter { $0.seriesId == item.id }
                    for k in gone.sorted(by: keyOrder) { bucket[k] = nil; result.removed.append(k) }
                } else {
                    // 반복 일정의 취소된 단일 회차. 키는 recurringEventId + originalStartTime.
                    let k = item.occurrenceKey(calendarId: calendarId)
                    if bucket.removeValue(forKey: k) != nil { result.removed.append(k) }
                }
                continue
            }
            if item.isRecurringMaster { result.skipped += 1; continue }
            guard let ev = item.toCalendarEvent(calendarId: calendarId) else { result.skipped += 1; continue }
            // 단일↔반복 전환은 옛 꼴의 취소 항목 없이 새 꼴만 온다. 옛 키를 지우지 않으면 같은 회의가 두 번 뜬다.
            let ghosts = bucket.keys.filter { k in
                ev.recurringEventId != nil
                    ? (k.seriesId == ev.key.seriesId && k.originalStart == nil)
                    : (k.seriesId == item.id && k.originalStart != nil)
            }
            for k in ghosts.sorted(by: keyOrder) { bucket[k] = nil; result.removed.append(k) }
            bucket[ev.key] = GCalMirrorEntry(event: ev, link: item.contextLink)
            result.upserted.append(ev.key)
        }
        result.upserted = unique(result.upserted)
        result.removed = unique(result.removed)
    }

    // 한 페이지에 같은 항목이 두 번 와도(또는 스테이징 삭제 후 최종 비교) 한 번만 알린다.
    private static func unique(_ keys: [OccurrenceKey]) -> [OccurrenceKey] {
        var seen = Set<OccurrenceKey>()
        return keys.filter { seen.insert($0).inserted }
    }

    static func keyOrder(_ a: OccurrenceKey, _ b: OccurrenceKey) -> Bool { a.description < b.description }

    // MARK: 조회

    public func entry(for key: OccurrenceKey) -> GCalMirrorEntry? { entries[key.calendarId]?[key] }

    public func event(for key: OccurrenceKey) -> CalendarEvent? { entry(for: key)?.event }

    public var allEvents: [CalendarEvent] {
        entries.values.flatMap { $0.values.map(\.event) }.sorted(by: Self.eventOrder)
    }

    /// 구간과 겹치는 회차(시작 시각 순).
    public func events(overlapping interval: DateInterval) -> [CalendarEvent] {
        allEvents.filter { $0.start < interval.end && $0.end > interval.start }
    }

    public func entries(calendarId: String) -> [GCalMirrorEntry] {
        (entries[calendarId] ?? [:]).values.sorted { Self.eventOrder($0.event, $1.event) }
    }

    static func eventOrder(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        a.start != b.start ? a.start < b.start : a.key.description < b.key.description
    }
}
