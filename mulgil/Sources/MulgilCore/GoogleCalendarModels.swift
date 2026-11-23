import Foundation

// Google Calendar API v3 `events.list` 응답 모델과 CalendarEvent 변환.
// 네트워크 코드는 없다. 앱이 받은 JSON 바이트를 여기로 넘긴다.

/// events.list 한 페이지. `nextSyncToken`은 마지막 페이지에만 온다.
public struct GCalEventsPage: Decodable, Sendable, Equatable {
    public var items: [GCalEvent]
    public var nextPageToken: String?
    public var nextSyncToken: String?
    public var timeZone: String?

    public init(items: [GCalEvent], nextPageToken: String? = nil, nextSyncToken: String? = nil, timeZone: String? = nil) {
        self.items = items; self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken; self.timeZone = timeZone
    }

    enum CodingKeys: String, CodingKey { case items, nextPageToken, nextSyncToken, timeZone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 변경이 없는 증분 응답은 items를 빼고 올 수 있다.
        items = try c.decodeIfPresent([GCalEvent].self, forKey: .items) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
        nextSyncToken = try c.decodeIfPresent(String.self, forKey: .nextSyncToken)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
    }

    public static func decode(_ data: Data) throws -> GCalEventsPage {
        try JSONDecoder().decode(GCalEventsPage.self, from: data)
    }
}

/// 디코드된 시각. 종일(date)은 날짜만 갖고 서울 자정으로 해석한다.
public enum GCalTime: Hashable, Sendable {
    case dateTime(Date)
    case date(year: Int, month: Int, day: Int)

    public var isAllDay: Bool { if case .date = self { true } else { false } }

    /// 종일 날짜는 서울 자정으로 바꾼다(물길의 모든 시각은 서울 기준).
    public var instant: Date {
        switch self {
        case .dateTime(let d): return d
        case .date(let y, let m, let d):
            return Seoul.calendar.date(from: DateComponents(year: y, month: m, day: d))!
        }
    }
}

/// start / end / originalStartTime 객체.
public struct GCalEventDateTime: Decodable, Sendable, Hashable {
    public var date: String?
    public var dateTime: String?
    public var timeZone: String?

    public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
        self.date = date; self.dateTime = dateTime; self.timeZone = timeZone
    }

    /// dateTime이 우선이다. 둘 다 없거나 형식이 틀리면 nil.
    public var time: GCalTime? {
        if let s = dateTime { return GCalTimeParser.parseDateTime(s).map(GCalTime.dateTime) }
        if let s = date, let (y, m, d) = GCalTimeParser.parseDate(s) { return .date(year: y, month: m, day: d) }
        return nil
    }
}

public struct GCalExtendedProperties: Decodable, Sendable, Hashable {
    public var `private`: [String: String]?
    public var shared: [String: String]?
    public init(private p: [String: String]? = nil, shared: [String: String]? = nil) { self.private = p; self.shared = shared }
}

public struct GCalConferenceData: Decodable, Sendable, Hashable {
    public struct EntryPoint: Decodable, Sendable, Hashable {
        public var entryPointType: String?
        public var uri: String?
    }
    public var entryPoints: [EntryPoint]?
}

/// events 리소스 중 물길이 쓰는 필드만.
public struct GCalEvent: Decodable, Sendable, Hashable {
    public var id: String
    public var status: String?
    public var summary: String?
    public var description: String?
    public var location: String?
    public var start: GCalEventDateTime?
    public var end: GCalEventDateTime?
    public var recurringEventId: String?
    public var originalStartTime: GCalEventDateTime?
    public var recurrence: [String]?
    public var extendedProperties: GCalExtendedProperties?
    public var hangoutLink: String?
    public var conferenceData: GCalConferenceData?
    public var created: String?
    public var updated: String?

    public init(id: String, status: String? = "confirmed", summary: String? = nil, description: String? = nil,
                location: String? = nil, start: GCalEventDateTime? = nil, end: GCalEventDateTime? = nil,
                recurringEventId: String? = nil, originalStartTime: GCalEventDateTime? = nil,
                recurrence: [String]? = nil, extendedProperties: GCalExtendedProperties? = nil,
                hangoutLink: String? = nil, conferenceData: GCalConferenceData? = nil,
                created: String? = nil, updated: String? = nil) {
        self.id = id; self.status = status; self.summary = summary; self.description = description
        self.location = location; self.start = start; self.end = end
        self.recurringEventId = recurringEventId; self.originalStartTime = originalStartTime
        self.recurrence = recurrence; self.extendedProperties = extendedProperties
        self.hangoutLink = hangoutLink; self.conferenceData = conferenceData
        self.created = created; self.updated = updated
    }

    public var isCancelled: Bool { status == "cancelled" }

    /// singleEvents=false로 받은 반복 원본. 회차가 아니므로 미러에 넣지 않는다.
    public var isRecurringMaster: Bool { !(recurrence ?? []).isEmpty && recurringEventId == nil }

    /// 물길이 쓴 섀도 이벤트인지. 섀도를 다시 미러로 읽으면 섀도의 섀도가 생긴다.
    public var isMulgilShadow: Bool { extendedProperties?.private?[ShadowEvent.srcKey] != nil }

    /// 문서상 안정 키: calendarId + (recurringEventId ‖ id) + originalStartTime.
    public func occurrenceKey(calendarId: String) -> OccurrenceKey {
        if let rid = recurringEventId {
            // originalStartTime이 빠진 회차는 시작 시각으로 대신한다. nil로 두면 그 시리즈의 회차가 한 키로 뭉친다.
            let os = originalStartTime?.time?.instant ?? start?.time?.instant
            return OccurrenceKey(calendarId: calendarId, seriesId: rid, originalStart: os)
        }
        return OccurrenceKey(calendarId: calendarId, seriesId: id, originalStart: nil)
    }

    /// 폰 맥락 이벤트에 넣을 https 링크. 회의 링크 → 장소 → 본문 순.
    public var contextLink: String? {
        var candidates: [String] = []
        if let h = hangoutLink { candidates.append(h) }
        for ep in conferenceData?.entryPoints ?? [] where ep.entryPointType == "video" {
            if let u = ep.uri { candidates.append(u) }
        }
        if let l = location { candidates.append(contentsOf: GCalLink.httpsURLs(in: l)) }
        if let d = description { candidates.append(contentsOf: GCalLink.httpsURLs(in: d)) }
        return candidates.first(where: GCalLink.isSafeHTTPS)
    }

    /// 취소 표시만 온 항목은 시각이 없을 수 있어 nil을 돌려준다.
    public func toCalendarEvent(calendarId: String) -> CalendarEvent? {
        guard let s = start?.time, let e = end?.time else { return nil }
        return CalendarEvent(
            key: occurrenceKey(calendarId: calendarId), id: id, calendarId: calendarId,
            title: summary ?? "", start: s.instant, end: e.instant, isAllDay: s.isAllDay,
            recurringEventId: recurringEventId, location: location, cancelled: isCancelled)
    }
}

public extension CalendarEvent {
    /// 제목이 '#'로 시작하면 수신함 항목(§5.7). 매칭·시리즈·섀도에서 뺀다.
    var gcalIsInbox: Bool { title.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
}

/// 링크 검증. 안드로이드 캘린더는 커스텀 스킴을 열지 않으므로 https만 통과시킨다.
public enum GCalLink {
    public static func isSafeHTTPS(_ s: String) -> Bool {
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) }),
              let c = URLComponents(string: s), c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty else { return false }
        return true
    }

    /// 자유 텍스트에서 https URL을 앞에서부터 뽑는다. 끝의 문장부호는 링크가 아니다.
    public static func httpsURLs(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let r = rest.range(of: "https://", options: .caseInsensitive) {
            var end = r.upperBound
            while end < rest.endIndex {
                let ch = rest[end]
                if ch.isWhitespace || "<>\"'".contains(ch) { break }
                end = rest.index(after: end)
            }
            var url = String(rest[r.lowerBound..<end])
            while let last = url.last, ".,;:!?)]}".contains(last) { url.removeLast() }
            if isSafeHTTPS(url) { out.append(url) }
            rest = rest[end...]
        }
        return out
    }
}

/// RFC3339 파서. ISO8601DateFormatter의 소수초 처리가 플랫폼마다 달라 직접 계산한다.
public enum GCalTimeParser {
    public static func parseDateTime(_ s: String) -> Date? {
        let u = Array(s.utf8)
        func num(_ i: Int, _ n: Int) -> Int? {
            guard i + n <= u.count else { return nil }
            var v = 0
            for k in i..<(i + n) {
                let c = u[k]
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard u.count >= 20,
              let y = num(0, 4), u[4] == UInt8(ascii: "-"), let mo = num(5, 2), u[7] == UInt8(ascii: "-"),
              let d = num(8, 2), [UInt8(ascii: "T"), UInt8(ascii: "t"), UInt8(ascii: " ")].contains(u[10]),
              let h = num(11, 2), u[13] == UInt8(ascii: ":"), let mi = num(14, 2), u[16] == UInt8(ascii: ":"),
              let sec = num(17, 2) else { return nil }
        guard validDate(y, mo, d), (0...23).contains(h), (0...59).contains(mi), (0...60).contains(sec) else { return nil }
        var i = 19
        var frac = 0.0
        if i < u.count && u[i] == UInt8(ascii: ".") {
            i += 1
            var scale = 0.1
            let begin = i
            while i < u.count, u[i] >= 48 && u[i] <= 57 { frac += Double(u[i] - 48) * scale; scale /= 10; i += 1 }
            guard i > begin else { return nil }
        }
        guard i < u.count else { return nil }
        var offset = 0
        switch u[i] {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            i += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            let sign = u[i] == UInt8(ascii: "-") ? -1 : 1
            guard let oh = num(i + 1, 2) else { return nil }
            i += 3
            if i < u.count && u[i] == UInt8(ascii: ":") { i += 1 }
            guard let om = num(i, 2), oh <= 23, om <= 59 else { return nil }
            i += 2
            offset = sign * (oh * 3600 + om * 60)
        default:
            return nil
        }
        guard i == u.count else { return nil }
        let secs = daysFromCivil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + sec - offset
        return Date(timeIntervalSince1970: Double(secs) + frac)
    }

    /// 종일 일정의 `YYYY-MM-DD`.
    public static func parseDate(_ s: String) -> (Int, Int, Int)? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard s.utf8.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), validDate(y, m, d) else { return nil }
        return (y, m, d)
    }

    static func validDate(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard (1...12).contains(m), d >= 1 else { return false }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        return d <= days
    }

    // Howard Hinnant의 days_from_civil. 달력 객체 없이 UTC 일수를 구한다.
    static func daysFromCivil(_ year: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// 서울 오프셋을 붙인 RFC3339 문자열. 사람이 읽는 mulgil_v와 페이로드 시각에 쓴다.
    public static func seoulRFC3339(_ date: Date) -> String {
        let cal = Seoul.calendar
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let off = Seoul.timeZone.secondsFromGMT(for: date)
        let sign = off < 0 ? "-" : "+"
        let a = abs(off)
        // %@는 Linux Foundation에서 Swift String을 받지 못하므로 이어 붙인다.
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
            + sign + String(format: "%02d:%02d", a / 3600, (a % 3600) / 60)
    }

    /// 쿼리 파라미터용 UTC RFC3339.
    public static func utcRFC3339(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
