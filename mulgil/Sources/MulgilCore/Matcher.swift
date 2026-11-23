import Foundation

/// 매칭 점수식·임계값. 기본값은 설계 §5.4 그대로다.
public struct MatchRules: Hashable, Sendable {
    /// 겹침이 없어도 시작이 이 안이면 후보(조기 시작·mtime 오차 흡수)
    public var startWindow: TimeInterval
    public var overlapWeight: Double
    public var seriesWeight: Double
    public var calendarWeight: Double
    public var threshold: Double
    public var margin: Double
    /// "확인할 것"에 띄울 후보 수(§7.9: 2~3개)
    public var maxCandidates: Int

    public init(startWindow: TimeInterval = 15 * 60, overlapWeight: Double = 0.7, seriesWeight: Double = 0.15,
                calendarWeight: Double = 0.15, threshold: Double = 0.6, margin: Double = 0.2, maxCandidates: Int = 3) {
        self.startWindow = startWindow; self.overlapWeight = overlapWeight; self.seriesWeight = seriesWeight
        self.calendarWeight = calendarWeight; self.threshold = threshold; self.margin = margin
        self.maxCandidates = maxCandidates
    }

    public static let `default` = MatchRules()
}

/// 점수식의 이력 항목과 제외 규칙에 필요한 바깥 상태. 호출자가 미러·로그에서 만든다.
public struct MatchContext: Hashable, Sendable {
    /// 최근 녹음이 연결된 시리즈(`OccurrenceKey.seriesId`)
    public var recentlyRecordedSeries: Set<String>
    /// 이 녹음 출처가 보통 연결되는 캘린더
    public var expectedCalendarIds: Set<String>
    /// 사용자가 '무시'로 지정한 캘린더
    public var ignoredCalendarIds: Set<String>

    public init(recentlyRecordedSeries: Set<String> = [], expectedCalendarIds: Set<String> = [],
                ignoredCalendarIds: Set<String> = []) {
        self.recentlyRecordedSeries = recentlyRecordedSeries
        self.expectedCalendarIds = expectedCalendarIds
        self.ignoredCalendarIds = ignoredCalendarIds
    }
}

/// 점수를 매긴 후보 하나. 근거를 남겨야 1탭 해제·"확인할 것" 설명이 가능하다(§4 Link).
public struct MatchCandidate: Hashable, Sendable {
    public let event: CalendarEvent
    public let score: Double
    public let overlapRatio: Double
    /// 이벤트 시작 − 녹음 시작(초). 양수면 녹음이 먼저 시작했다
    public let startOffset: TimeInterval
    public let seriesHit: Bool
    public let calendarHit: Bool
}

/// 애매한 이유. §5.4 실패 분류(겹침/조기 시작)와 대응한다.
public enum MatchAmbiguity: String, Codable, Sendable, CaseIterable {
    /// 겹치는 두 이벤트(연속 회의에 걸친 녹음 포함) 점수 차 < margin
    case overlappingEvents
    /// 녹음이 일정보다 먼저 시작해 겹침이 부족
    case earlyStart
    /// 겹침이 부족한 그 밖의 경우
    case weakOverlap
}

/// 연결할 후보가 없었던 이유. 제외 규칙에 걸린 이벤트만 있었으면 그 종류를 밝힌다.
public enum MatchMiss: String, Codable, Sendable, CaseIterable {
    /// 근처에 이벤트가 아예 없음
    case noOverlap
    case cancelledOnly
    /// '#' 수신함 이벤트만(캘린더로 옮기지 않은 일정)
    case inboxOnly
    case ignoredCalendarOnly
    case allDayOnly
}

/// §5.4 의 세 가지 실패 분류 + 기타. §10.2·§10.4 집계가 쓴다.
public enum MatchFailureCategory: String, Codable, Sendable, CaseIterable {
    case overlap, earlyStart, notInCalendar, other
}

public enum MatchOutcome: Hashable, Sendable {
    case matched(CalendarEvent, score: Double)
    case ambiguous([MatchCandidate], MatchAmbiguity)
    case none(MatchMiss)

    public var isMatched: Bool { if case .matched = self { true } else { false } }

    public var failureCategory: MatchFailureCategory? {
        switch self {
        case .matched: return nil
        case .ambiguous(_, .overlappingEvents): return .overlap
        case .ambiguous(_, .earlyStart): return .earlyStart
        case .ambiguous(_, .weakOverlap): return .other
        // 취소·수신함만 있었다면 실제 일정이 Google 캘린더에 없다는 뜻이다.
        case .none(.noOverlap), .none(.cancelledOnly), .none(.inboxOnly): return .notInCalendar
        // 종일(해커톤 감싸기)·무시 캘린더는 사용자가 의도한 상태라 경보 대상이 아니다.
        case .none(.allDayOnly), .none(.ignoredCalendarOnly): return .other
        }
    }
}

public enum Matcher {
    // 부동소수 합(0.7+0.15…)이 경계에서 흔들리지 않게 한다.
    static let epsilon = 1e-9

    public static func match(_ span: RecordingSpan, events: [CalendarEvent],
                             context: MatchContext = .init(), rules: MatchRules = .default) -> MatchOutcome {
        match(recordingStart: span.start, end: span.end, events: events, context: context, rules: rules)
    }

    public static func match(recordingStart rStart: Date, end rEndRaw: Date, events: [CalendarEvent],
                             context: MatchContext = .init(), rules: MatchRules = .default) -> MatchOutcome {
        let rEnd = max(rStart, rEndRaw)
        var eligible: [CalendarEvent] = []
        var excluded: Set<MatchMiss> = []

        for e in events where isNear(e, rStart, rEnd, rules) {
            if let why = exclusion(e, context) { excluded.insert(why) } else { eligible.append(e) }
        }

        let scored = dedupe(eligible.map { score($0, rStart, rEnd, context, rules) }).sorted(by: order)
        guard let top = scored.first else { return .none(missReason(excluded)) }

        let second = scored.dropFirst().first
        let clearMargin = second.map { top.score - $0.score >= rules.margin - epsilon } ?? true
        if top.score >= rules.threshold - epsilon && clearMargin {
            return .matched(top.event, score: top.score)
        }

        let shown = Array(scored.prefix(max(1, rules.maxCandidates)))
        let reason: MatchAmbiguity
        if let second, second.overlapRatio > 0, !clearMargin {
            reason = .overlappingEvents
        } else if top.score < rules.threshold - epsilon {
            reason = top.startOffset > 0 ? .earlyStart : .weakOverlap
        } else {
            reason = .overlappingEvents
        }
        return .ambiguous(shown, reason)
    }

    /// 후보 조건: R과 실제로 겹치거나(접하기만 하면 아님) 시작이 ±startWindow.
    static func isNear(_ e: CalendarEvent, _ rStart: Date, _ rEnd: Date, _ rules: MatchRules) -> Bool {
        // 길이 0 이벤트(마감 표시)는 회의가 아니다. 후보로 두면 '조기 시작' 분류가 오염된다.
        guard e.end > e.start else { return false }
        if overlapLength(rStart, rEnd, e.start, e.end) > 0 { return true }
        if rStart == rEnd && pointInside(rStart, e) { return true }
        return abs(e.start.timeIntervalSince(rStart)) <= rules.startWindow
    }

    static func exclusion(_ e: CalendarEvent, _ context: MatchContext) -> MatchMiss? {
        if e.cancelled { return .cancelledOnly }
        // 폰 키보드는 줄바꿈·전각 '＃'을 넣기도 한다.
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") || t.hasPrefix("＃") { return .inboxOnly }
        if context.ignoredCalendarIds.contains(e.calendarId) { return .ignoredCalendarOnly }
        if e.isAllDay { return .allDayOnly }
        return nil
    }

    /// 여러 종류가 섞이면 '캘린더가 실제와 어긋남' 신호가 강한 쪽을 우선한다.
    static func missReason(_ excluded: Set<MatchMiss>) -> MatchMiss {
        for m in [MatchMiss.cancelledOnly, .inboxOnly, .ignoredCalendarOnly, .allDayOnly] where excluded.contains(m) {
            return m
        }
        return .noOverlap
    }

    static func overlapLength(_ a0: Date, _ a1: Date, _ b0: Date, _ b1: Date) -> TimeInterval {
        max(0, min(a1, b1).timeIntervalSince(max(a0, b0)))
    }

    static func overlapRatio(_ rStart: Date, _ rEnd: Date, _ e: CalendarEvent) -> Double {
        let r = rEnd.timeIntervalSince(rStart)
        let len = max(0, e.duration)
        if r == 0 { return (len > 0 && pointInside(rStart, e)) ? 1 : 0 }
        // 길이 0 이벤트(마감 표시 등)는 녹음과 겹친다고 보지 않는다.
        guard len > 0 else { return 0 }
        return min(1, overlapLength(rStart, rEnd, e.start, e.end) / min(r, len))
    }

    /// 길이 0 녹음의 시각은 mtime(=녹음 끝)이라 (start, end] 로 본다. 연속 회의 경계는 앞 회의 것이다.
    static func pointInside(_ p: Date, _ e: CalendarEvent) -> Bool { p > e.start && p <= e.end }

    static func score(_ e: CalendarEvent, _ rStart: Date, _ rEnd: Date,
                      _ context: MatchContext, _ rules: MatchRules) -> MatchCandidate {
        let ratio = overlapRatio(rStart, rEnd, e)
        let seriesHit = context.recentlyRecordedSeries.contains(e.key.seriesId)
        let calendarHit = context.expectedCalendarIds.contains(e.calendarId)
        let s = rules.overlapWeight * ratio + (seriesHit ? rules.seriesWeight : 0) + (calendarHit ? rules.calendarWeight : 0)
        return MatchCandidate(event: e, score: s, overlapRatio: ratio,
                              startOffset: e.start.timeIntervalSince(rStart), seriesHit: seriesHit, calendarHit: calendarHit)
    }

    /// 같은 회의가 여러 캘린더에 보이면(초대받은 공유 일정) 하나로 친다. 안 그러면 늘 동점이라 애매해진다.
    static func dedupe(_ cs: [MatchCandidate]) -> [MatchCandidate] {
        var best: [String: MatchCandidate] = [:]
        for c in cs {
            let k = "\(c.event.id)|\(c.event.start.timeIntervalSince1970)|\(c.event.end.timeIntervalSince1970)"
            if let cur = best[k], !order(c, cur) { continue }
            best[k] = c
        }
        return Array(best.values)
    }

    /// 결정론 정렬: 점수 → 시작 근접 → 이른 시작 → 캘린더 → 키 → id.
    static func order(_ a: MatchCandidate, _ b: MatchCandidate) -> Bool {
        // ε 비교는 추이적이지 않아 정렬이 깨질 수 있어 정수로 양자화한다.
        let qa = quantized(a.score), qb = quantized(b.score)
        if qa != qb { return qa > qb }
        let da = abs(a.startOffset), db = abs(b.startOffset)
        if da != db { return da < db }
        if a.event.start != b.event.start { return a.event.start < b.event.start }
        if a.event.calendarId != b.event.calendarId { return a.event.calendarId < b.event.calendarId }
        if a.event.key.description != b.event.key.description { return a.event.key.description < b.event.key.description }
        return a.event.id < b.event.id
    }

    static func quantized(_ s: Double) -> Int64 { Int64((s * 1e6).rounded()) }
}

// MARK: - 집계 (§5.4 마지막, §10.2)

/// 녹음 한 건의 매칭 결과 기록. 녹음 시작 시각으로 주·일에 배정한다.
public struct MatchRecord: Hashable, Sendable {
    public let recordedAt: Date
    public let outcome: MatchOutcome
    public init(recordedAt: Date, outcome: MatchOutcome) { self.recordedAt = recordedAt; self.outcome = outcome }
}

public struct MatchTally: Hashable, Sendable {
    public var total = 0
    public var matched = 0
    public var ambiguous = 0
    public var unmatched = 0
    public var byCategory: [MatchFailureCategory: Int] = [:]

    public init() {}

    /// 녹음이 없으면 nil. 0%로 보이면 고장처럼 읽히기 때문이다.
    public var matchRate: Double? { total == 0 ? nil : Double(matched) / Double(total) }
    public var notInCalendar: Int { byCategory[.notInCalendar, default: 0] }
    /// 팝오버 한 줄 "어제 일정 매칭 2/3"
    public var fractionText: String { "\(matched)/\(total)" }
}

public enum MatchStats {
    /// "캘린더에 없음" 주간 경보 임계(§5.4, §11-①)
    public static let notInCalendarWeeklyThreshold = 2

    /// [start, end) 안의 기록만 센다.
    public static func tally(_ records: [MatchRecord], in interval: DateInterval) -> MatchTally {
        var t = MatchTally()
        for r in records where r.recordedAt >= interval.start && r.recordedAt < interval.end {
            t.total += 1
            switch r.outcome {
            case .matched: t.matched += 1
            case .ambiguous: t.ambiguous += 1
            case .none: t.unmatched += 1
            }
            if let c = r.outcome.failureCategory { t.byCategory[c, default: 0] += 1 }
        }
        return t
    }

    /// 서울 기준 월요일 00:00 ~ 다음 월요일 00:00.
    public static func week(containing date: Date) -> DateInterval {
        let cal = Seoul.calendar
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86400)
        return DateInterval(start: start, end: end)
    }

    /// 서울 기준 하루.
    public static func day(containing date: Date) -> DateInterval {
        let cal = Seoul.calendar
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    /// 어제 하루 집계(§5.4 보정 기간 한 줄).
    public static func yesterday(_ records: [MatchRecord], now: Date) -> MatchTally {
        let today = day(containing: now)
        let start = Seoul.calendar.date(byAdding: .day, value: -1, to: today.start) ?? today.start.addingTimeInterval(-86400)
        return tally(records, in: DateInterval(start: start, end: today.start))
    }

    /// 이번 주(서울, 월요일 시작) "캘린더에 없음"이 임계 이상이면 팝오버 경보를 띄운다.
    public static func shouldWarnNotInCalendar(_ records: [MatchRecord], now: Date,
                                               threshold: Int = notInCalendarWeeklyThreshold) -> Bool {
        // 임계 0 이하면 녹음이 없어도 경보가 떠서 1로 막는다.
        tally(records, in: week(containing: now)).notInCalendar >= max(1, threshold)
    }
}
