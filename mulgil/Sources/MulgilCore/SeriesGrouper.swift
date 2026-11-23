import Foundation

// 시리즈 자동 생성(§4 Series = 제목 정규화 + 반복 규칙 + 캘린더 출처).
// 사람이 일괄 지정하지 않으므로 규칙이 보수적이어야 한다: 캘린더를 넘어 묶지 않는다.

public enum GCalSeriesReason: String, Codable, Sendable {
    /// 같은 recurringEventId(또는 그 반복 일정과 같은 정규화 제목)
    case recurrence
    /// 반복 규칙 없이 같은 정규화 제목이 최근 N주에 여러 번
    case repeatedTitle
}

public struct GCalSeries: Codable, Sendable, Hashable, Identifiable {
    /// 안정 id. 반복 일정이 섞이면 가장 작은 recurringEventId 기준이라
    /// "이번 및 향후 일정" 수정으로 생기는 `_R…` 분할 시리즈가 와도 바뀌지 않는다.
    public let id: String
    public let calendarId: String
    public let normalizedTitle: String
    /// 가장 최근 회차의 원래 제목(카드 표시용)
    public let displayTitle: String
    public let recurringEventIds: [String]
    public let members: [OccurrenceKey]
    public let reason: GCalSeriesReason
}

public struct GCalSeriesIndex: Sendable, Hashable {
    public let series: [GCalSeries]
    private let byKey: [OccurrenceKey: String]

    init(series: [GCalSeries]) {
        self.series = series
        var m: [OccurrenceKey: String] = [:]
        for s in series { for k in s.members { m[k] = s.id } }
        self.byKey = m
    }

    public func seriesId(for key: OccurrenceKey) -> String? { byKey[key] }
    public func series(for key: OccurrenceKey) -> GCalSeries? {
        byKey[key].flatMap { id in series.first { $0.id == id } }
    }
}

public struct SeriesGrouper: Sendable {
    /// "최근 N주"의 N. 첫 실행 백필 범위(지난 4주)와 같게 둔다.
    public var lookbackWeeks: Int
    /// 반복 규칙 없는 제목이 시리즈가 되는 최소 횟수(서로 다른 날 기준).
    public var minOccurrences: Int
    /// 앞으로 다가올 회차도 센다. 섀도 롤링 창(7일)에 들어온 회의를 바로 시리즈로 봐야 하기 때문이다.
    public var lookaheadDays: Int

    public init(lookbackWeeks: Int = 4, minOccurrences: Int = 3, lookaheadDays: Int = 7) {
        self.lookbackWeeks = lookbackWeeks; self.minOccurrences = minOccurrences; self.lookaheadDays = lookaheadDays
    }

    // MARK: 제목 정규화

    /// 회차 표기·날짜 꼬리표·이모지를 떼고 소문자로. 비교용이며 화면에는 쓰지 않는다.
    public static func normalizeTitle(_ title: String) -> String {
        var s = String(String.UnicodeScalarView(title.unicodeScalars.filter { !isEmojiScalar($0) }))
        s = s.lowercased()
        let patterns = [
            // 요일 꼬리표: (월) (목요일) — 날짜 패턴보다 먼저 떼야 "11/23(월)"의 날짜가 맨 뒤로 온다.
            #"[\(（]\s*[월화수목금토일]\s*(?:요일)?\s*[\)）]"#,
            // 연도 포함 날짜: 2026-12-07, 2026.11.23, 2026/11/23
            #"\d{4}\s*[/.\-]\s*\d{1,2}\s*[/.\-]\s*\d{1,2}\.?"#,
            // 한국어 날짜: 11월 23일, (12월 1일)
            #"[\(（]?\s*\d{1,2}\s*월\s*\d{1,2}\s*일\s*[\)）]?"#,
            // 날짜 + 요일: (12/31 목)
            #"[\(（]\s*\d{1,2}\s*[/.]\s*\d{1,2}\s*[월화수목금토일]?\s*[\)）]"#,
            // 괄호 속 날짜·숫자·회차: (11/23) [3] (2주차) (12.1)
            #"[\(\[（【]\s*(?:\d{1,4}\s*[/.\-]\s*\d{1,2}(?:\s*[/.\-]\s*\d{1,2})?|\d+\s*(?:차|회차|회|주차|교시|번째|기)?|#\s*\d+)\s*[\)\]）】]"#,
            // 해시 번호: #12
            #"#\s*\d+"#,
            // 숫자 회차: 3차, 12회, 5주차, 2교시, 3번째, 7기
            #"\d+\s*(?:회차|주차|교시|번째|차|회|기)(?![가-힣])"#,
            // 맨 뒤 날짜: 11/23, 12.1
            #"\s\d{1,2}\s*[/.]\s*\d{1,2}\s*$"#,
            // 맨 앞 날짜: 11/23 주간 싱크
            #"^\s*\d{1,2}\s*[/.]\s*\d{1,2}\s"#,
            // 영문 회차: ep.3, vol 2, no.5, session 4
            #"\b(?:ep|vol|no|session|week|wk)\.?\s*\d+\b"#,
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        // 남은 구분자·공백을 하나로 접는다. "ERPsim-3주차-1" 같은 표기를 같은 꼴로 만든다.
        s = s.replacingOccurrences(of: #"[\s\-_·•|:,]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[\(\)\[\]（）【】]"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_·.")))
    }

    // 숫자·#·*도 키캡 이모지 속성을 가지므로 U+2000 미만은 남긴다.
    static func isEmojiScalar(_ u: Unicode.Scalar) -> Bool {
        if u.value == 0x200D || (0xFE00...0xFE0F).contains(u.value) || (0xE0020...0xE007F).contains(u.value) { return true }
        if u.value < 0x2000 { return false }
        let p = u.properties
        return p.isEmojiPresentation || p.isEmojiModifier || (p.isEmoji && u.value >= 0x2100)
    }

    // MARK: 묶기

    public func group(_ events: [CalendarEvent], now: Date) -> GCalSeriesIndex {
        // 같은 회차가 두 번 들어와도(미러 + 백필 합치기 등) 멤버가 겹치지 않게 키로 한 번만 남긴다.
        var seen = Set<OccurrenceKey>()
        let usable = events.filter { !$0.cancelled && !$0.gcalIsInbox && seen.insert($0.key).inserted }
        // 캘린더 출처가 다르면 절대 묶지 않는다.
        let byCalendar = Dictionary(grouping: usable, by: \.calendarId)
        var out: [GCalSeries] = []
        for cal in byCalendar.keys.sorted() {
            out += groupCalendar(cal, byCalendar[cal]!, now: now)
        }
        return GCalSeriesIndex(series: out.sorted { $0.id < $1.id })
    }

    private func groupCalendar(_ cal: String, _ events: [CalendarEvent], now: Date) -> [GCalSeries] {
        let norm = Dictionary(events.map { ($0.key, Self.normalizeTitle($0.title)) }, uniquingKeysWith: { a, _ in a })

        // 1) recurringEventId 묶음
        var groups: [String: [CalendarEvent]] = [:]   // 그룹 대표 키 → 회차
        var recTitles: [String: String] = [:]          // 정규화 제목 → 그룹 대표 키
        for e in events {
            guard let rid = e.recurringEventId else { continue }
            groups["r:" + rid, default: []].append(e)
        }
        // 2) 같은 정규화 제목의 반복 일정끼리 합친다(분할된 반복 일정, 회차별 제목 수정).
        var merged: [String: [CalendarEvent]] = [:]
        var mergedRids: [String: Set<String>] = [:]
        for gk in groups.keys.sorted() {
            let members = groups[gk]!
            let title = Self.dominantTitle(members.map { norm[$0.key]! })
            let rid = String(gk.dropFirst(2))
            let target = title.isEmpty ? gk : (recTitles[title] ?? gk)
            if !title.isEmpty && recTitles[title] == nil { recTitles[title] = gk }
            merged[target, default: []] += members
            mergedRids[target, default: []].insert(rid)
        }

        // 3) 반복 규칙 없는 일정: 반복 일정과 제목이 같으면 합류, 아니면 횟수 규칙.
        let lookStart = now.addingTimeInterval(-Double(lookbackWeeks) * 7 * 86_400)
        let lookEnd = now.addingTimeInterval(Double(lookaheadDays) * 86_400)
        var singlesByTitle: [String: [CalendarEvent]] = [:]
        for e in events where e.recurringEventId == nil {
            let t = norm[e.key]!
            guard !t.isEmpty else { continue }
            if let gk = recTitles[t] { merged[gk]!.append(e) } else { singlesByTitle[t, default: []].append(e) }
        }

        var result: [GCalSeries] = []
        for (gk, members) in merged {
            let rids = mergedRids[gk]!.sorted()
            let title = Self.dominantTitle(members.map { norm[$0.key]! })
            result.append(makeSeries(id: "gcal-series:\(cal)|rec:\(rids[0])", cal: cal, title: title,
                                     rids: rids, members: members, reason: .recurrence))
        }
        let cal0 = Seoul.calendar
        for (t, members) in singlesByTitle {
            let recentDays = Set(members.filter { $0.start >= lookStart && $0.start < lookEnd }
                .map { cal0.startOfDay(for: $0.start) })
            guard recentDays.count >= minOccurrences else { continue }
            result.append(makeSeries(id: "gcal-series:\(cal)|title:\(t)", cal: cal, title: t,
                                     rids: [], members: members, reason: .repeatedTitle))
        }
        return result
    }

    private func makeSeries(id: String, cal: String, title: String, rids: [String],
                            members: [CalendarEvent], reason: GCalSeriesReason) -> GCalSeries {
        let sorted = members.sorted(by: CalendarMirror.eventOrder)
        return GCalSeries(id: id, calendarId: cal, normalizedTitle: title,
                          displayTitle: sorted.last?.title ?? title, recurringEventIds: rids,
                          members: sorted.map(\.key), reason: reason)
    }

    /// 가장 흔한 정규화 제목(동률이면 사전순). 회차 하나만 제목을 고친 경우를 견딘다.
    static func dominantTitle(_ titles: [String]) -> String {
        let counts = Dictionary(titles.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? ""
    }
}
