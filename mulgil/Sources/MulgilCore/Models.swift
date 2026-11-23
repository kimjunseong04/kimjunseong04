import Foundation

/// 물길의 모든 시각 계산은 서울 시간대 기준이다.
public enum Seoul {
    public static let timeZone = TimeZone(identifier: "Asia/Seoul")!
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 2 // 월요일 시작
        return c
    }
}

/// 반복 일정의 한 회차를 안정적으로 가리키는 키.
/// Google Calendar API 문서가 보장하는 `recurringEventId + originalStartTime` 조합이다.
/// 단일 일정은 `seriesId = id`, `originalStart = nil`.
public struct OccurrenceKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let calendarId: String
    public let seriesId: String
    public let originalStart: Date?

    public init(calendarId: String, seriesId: String, originalStart: Date?) {
        self.calendarId = calendarId
        self.seriesId = seriesId
        self.originalStart = originalStart
    }

    public var description: String {
        let t = originalStart.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "\(calendarId)|\(seriesId)|\(t)"
    }
}

/// 로컬 미러에 들어 있는 일정 한 회차. 제목·시각의 진실 원천은 Google이다.
public struct CalendarEvent: Hashable, Codable, Sendable {
    public let key: OccurrenceKey
    /// Google 이벤트 id (회차 인스턴스면 인스턴스 id)
    public let id: String
    public let calendarId: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var recurringEventId: String?
    public var location: String?
    public var cancelled: Bool

    public init(key: OccurrenceKey, id: String, calendarId: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, recurringEventId: String? = nil, location: String? = nil, cancelled: Bool = false) {
        self.key = key; self.id = id; self.calendarId = calendarId; self.title = title
        self.start = start; self.end = end; self.isAllDay = isAllDay
        self.recurringEventId = recurringEventId; self.location = location; self.cancelled = cancelled
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 약속·결정의 네 종류. 화면 문구는 순서대로 할 것 / 기다리는 것 / 정한 것 / 미정.
public enum MarkKind: String, Codable, Sendable, CaseIterable {
    case owe, wait, decision, question

    public var label: String {
        switch self {
        case .owe: "할 것"
        case .wait: "기다리는 것"
        case .decision: "정한 것"
        case .question: "미정"
        }
    }
}

/// 날짜 파서가 돌려주는 기한. 시각이 없으면 날짜만 있는 기한이다.
public struct Due: Hashable, Codable, Sendable {
    public let date: Date
    public let hasTime: Bool
    public init(date: Date, hasTime: Bool) { self.date = date; self.hasTime = hasTime }
}

/// 동기화 폴더에 도착한 녹음 파일 한 개의 메타데이터.
public struct RecordingFile: Hashable, Codable, Sendable {
    public let path: String
    /// m4a mvhd creation_time. 0 또는 1904 기본값이면 nil로 넘긴다.
    public let creationTime: Date?
    /// 파일 수정 시각(Syncthing이 보존). 녹음 종료 시각에 가깝다.
    public let modificationTime: Date
    public let duration: TimeInterval

    public init(path: String, creationTime: Date?, modificationTime: Date, duration: TimeInterval) {
        self.path = path; self.creationTime = creationTime
        self.modificationTime = modificationTime; self.duration = duration
    }
}
