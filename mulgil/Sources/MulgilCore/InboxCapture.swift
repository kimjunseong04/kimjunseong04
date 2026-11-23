import Foundation

// InboxCapture: 폰 Google Calendar 앱에서 제목을 '#'로 시작해 만든 이벤트 → 수신함 항목(§5.7, §4 kind=inbox).
// 순수 함수만 둔다. events.move·삭제는 호출자 몫이다.
//
// 설계에 없거나 모호해서 여기서 정한 것:
// 1. 접두 문자: '#'(U+0023), 전각 '＃'(U+FF03), 작은 '﹟'(U+FE5F). 한국어 IME·Gboard 전각 모드 대비.
//    앞쪽 공백(전각 공백 U+3000, NBSP 포함)과 폭 0 문자(U+200B/C/D, U+2060, BOM)는 무시한다.
//    '##', '# #' 처럼 접두가 겹쳐도 전부 떼어 낸다(오타 두 번 탭).
// 2. '#AUSG 밋업', '#연사 리스트' 처럼 접두 바로 뒤에 글자가 붙어도 수신함이다.
//    설계 §5.7이 "제목이 #으로 시작하면 어느 캘린더든 수신함"이라고 정했고, Gboard 음성 입력
//    "#연사 리스트 금요일까지"(§5.7-3)도 공백 없이 들어오기 때문이다.
// 3. 보수적 예외(설계에 없음): '#' 뒤가 숫자만으로 된 번호면 수신함이 아니다. 예) "#3 정기회의", "#12", "#2. 발표".
//    동아리 공유 캘린더의 회차 번호 표기와 충돌하면 남의 일정을 events.move 해 버리므로 이쪽을 막는다.
//    숫자 뒤에 한글·영문이 바로 붙으면("#3시 공학관", "#2차 회의") 수신함이다.
//    구분자 뒤에 다시 숫자가 오면 번호가 아니라 시각·날짜다("#7:30 공학관", "#11.27 밋업", "#12/3 회의") → 수신함.
//    숫자는 전각(３)도 같은 숫자로 본다.
// 4. 접두를 떼고 남는 글자가 없으면 수신함이 아니다(빈 '#' 이벤트는 처리할 내용이 없다).
// 5. 취소된(cancelled) 이벤트는 무시한다. 이미 지워진 항목을 되살리지 않기 위해서다.
// 6. 안정 키는 "inbox|<이벤트 id>". events.move 는 이벤트 id 를 유지하고 calendarId 만 바꾸므로,
//    calendarId 를 키에 넣으면 수신함 캘린더로 옮긴 뒤 같은 항목을 새것으로 다시 집는다.
//    반복 일정 회차면 id 대신 recurringEventId 를 쓴다. 실수로 반복을 건 '#' 일정 하나가
//    회차 수만큼 수신함을 채우지 않게 하고, events.move 도 시리즈 단위로만 되기 때문이다.
// 7. 만든 시각: §5.7은 이벤트 `created`를 기준 시각으로 쓴다. CalendarEvent 에는 그 필드가 없어서
//    호출자가 넘기고, 없으면 start 로 대체하되 출처를 `.start`로 표시한다(날짜 파서가 신뢰도를 낮출 수 있게).
// 8. 원문 텍스트는 앞뒤 공백만 정리하고 내부는 그대로 둔다(원문 보존).

/// 만든 시각을 어디서 얻었는지.
public enum InboxCaptureTimeSource: String, Codable, Sendable {
    /// Google 이벤트 `created`
    case created
    /// created 가 없어 이벤트 시작 시각으로 대체
    case start
}

/// 수신함 항목 하나.
public struct InboxCaptureItem: Hashable, Codable, Sendable {
    /// 접두와 공백을 뗀 원문
    public let text: String
    public let createdAt: Date
    public let createdAtSource: InboxCaptureTimeSource
    /// '이미 처리됨' 판단용. 캘린더를 옮겨도 바뀌지 않는다.
    public let stableKey: String
    public let eventId: String
    /// 지금 들어 있는 캘린더(옮기기 전이면 원래 캘린더)
    public let calendarId: String
    public let rawTitle: String
}

public enum InboxCapture {
    static let prefixChars: Set<Character> = ["#", "＃", "﹟"]
    static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]

    /// 수신함 제목이면 접두를 뗀 본문, 아니면 nil.
    public static func body(ofTitle title: String) -> String? {
        var s = Substring(title)
        dropLeading(&s)
        guard let f = s.first, prefixChars.contains(f) else { return nil }
        while let c = s.first, prefixChars.contains(c) || isSkippable(c) { s = s.dropFirst() }
        let body = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isOrdinal(Substring(body)) else { return nil }
        return body
    }

    public static func isInboxTitle(_ title: String) -> Bool { body(ofTitle: title) != nil }

    public static func stableKey(eventId: String) -> String { "inbox|\(eventId)" }

    /// 이벤트의 안정 키. 반복 회차는 시리즈 id 로 묶는다.
    public static func stableKey(for event: CalendarEvent) -> String {
        stableKey(eventId: event.recurringEventId ?? event.id)
    }

    /// 이벤트 하나를 수신함 항목으로. 해당 없으면 nil.
    /// - Parameter created: Google 이벤트 `created`. 없으면 start 로 대체한다.
    public static func capture(_ event: CalendarEvent, created: Date? = nil) -> InboxCaptureItem? {
        guard !event.cancelled, let text = body(ofTitle: event.title) else { return nil }
        return InboxCaptureItem(text: text, createdAt: created ?? event.start,
                                createdAtSource: created == nil ? .start : .created,
                                stableKey: stableKey(for: event), eventId: event.id,
                                calendarId: event.calendarId, rawTitle: event.title)
    }

    /// 아직 처리하지 않은 수신함 항목. 같은 키는 하나만 남기고 만든 시각 순으로 돌려준다.
    /// - Parameters:
    ///   - processed: 이미 처리한 stableKey 집합
    ///   - created: 이벤트 id → `created`
    public static func pending(_ events: [CalendarEvent], processed: Set<String> = [],
                               created: [String: Date] = [:]) -> [InboxCaptureItem] {
        var seen = processed
        var out: [InboxCaptureItem] = []
        for e in events {
            guard let item = capture(e, created: created[e.id]), !seen.contains(item.stableKey) else { continue }
            seen.insert(item.stableKey)
            out.append(item)
        }
        // 동시각이면 키로 정렬해 결정론을 지킨다.
        return out.sorted { ($0.createdAt, $0.stableKey) < ($1.createdAt, $1.stableKey) }
    }

    // MARK: 내부

    private static func isSkippable(_ c: Character) -> Bool {
        c.isWhitespace || c.unicodeScalars.allSatisfy { invisible.contains($0) }
    }

    private static func dropLeading(_ s: inout Substring) {
        while let c = s.first, isSkippable(c) { s = s.dropFirst() }
    }

    /// "3", "12 정기회의", "2. 발표", "3) …" 처럼 숫자 번호로 시작하는지.
    private static func isOrdinal(_ s: Substring) -> Bool {
        let digits = s.prefix(while: { $0.wholeNumberValue != nil })
        guard !digits.isEmpty else { return false }
        let after = s.dropFirst(digits.count)
        guard let next = after.first else { return true }
        if next.isWhitespace { return true }
        guard ".)-:,/".contains(next) else { return false }
        // "7:30", "11.27" 처럼 구분자 뒤에 숫자가 이어지면 시각·날짜다.
        return after.dropFirst().first?.wholeNumberValue == nil
    }
}
