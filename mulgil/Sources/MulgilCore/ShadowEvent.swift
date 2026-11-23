import Foundation

// "물길" 섀도 캘린더 쓰기(§6.3, §7.10). 페이로드 생성과 7일 롤링 diff만 하고 HTTP는 앱이 한다.
// 원본 이벤트에는 아무것도 쓰지 않는다. 섀도는 private 확장 속성의 원본 키로 다시 찾는다.

// MARK: 입력

/// 기한 있는 할 것 한 줄.
public struct ShadowOwe: Codable, Sendable, Hashable {
    public var text: String
    public var due: Due?
    public init(text: String, due: Due? = nil) { self.text = text; self.due = due }
}

/// 맥락 이벤트에 담을 내용. 내용이 하나도 없으면 섀도를 만들지 않는다.
public struct ShadowContext: Codable, Sendable, Hashable {
    public var decisions: [String]
    public var questions: [String]
    /// 열린(확정, 미완료) 할 것만 넣는다. Tasks에서 끝낸 것은 앱이 미리 뺀다.
    public var owes: [ShadowOwe]
    public var waits: [String]
    /// 원본 Zoom/Meet/Notion 링크. https가 아니면 버린다.
    public var link: String?
    /// 지난 회차 녹음이 있으면 내용이 비어도 맥락 이벤트 대상이다(§6.3).
    public var hasPriorRecording: Bool

    public init(decisions: [String] = [], questions: [String] = [], owes: [ShadowOwe] = [],
                waits: [String] = [], link: String? = nil, hasPriorRecording: Bool = false) {
        self.decisions = decisions; self.questions = questions; self.owes = owes
        self.waits = waits; self.link = link; self.hasPriorRecording = hasPriorRecording
    }

    public var hasContent: Bool {
        hasPriorRecording || !decisions.isEmpty || !questions.isEmpty || !owes.isEmpty || !waits.isEmpty
            || (link.map(GCalLink.isSafeHTTPS) ?? false)
    }
}

/// 섀도를 둘지 판단할 원본 회차와 맥락.
public struct ShadowTarget: Sendable, Hashable {
    public var event: CalendarEvent
    public var context: ShadowContext
    public init(event: CalendarEvent, context: ShadowContext) { self.event = event; self.context = context }
}

/// 시각 기한이 있는 확정 owe. 알람 이벤트 대상이다.
public struct ShadowOweAlarmItem: Sendable, Hashable {
    public var markId: String
    public var text: String
    public var due: Due
    public init(markId: String, text: String, due: Due) { self.markId = markId; self.text = text; self.due = due }
}

// MARK: 페이로드 (events.insert / events.patch 본문)

public struct ShadowDateTime: Encodable, Sendable, Hashable {
    public let dateTime: String
    public let timeZone: String
    init(_ d: Date) { dateTime = GCalTimeParser.seoulRFC3339(d); timeZone = Seoul.timeZone.identifier }
}

public struct ShadowReminderOverride: Encodable, Sendable, Hashable {
    public let method: String
    public let minutes: Int
}

public struct ShadowReminders: Encodable, Sendable, Hashable {
    public let useDefault: Bool
    public let overrides: [ShadowReminderOverride]
}

public struct ShadowExtendedProperties: Encodable, Sendable, Hashable {
    public let `private`: [String: String]
}

public struct ShadowPayload: Encodable, Sendable, Hashable {
    public let summary: String
    public let description: String
    public let start: ShadowDateTime
    public let end: ShadowDateTime
    public let reminders: ShadowReminders
    public let extendedProperties: ShadowExtendedProperties
    /// 섀도가 바쁨으로 잡히면 원본과 겹쳐 내 일정이 두 배로 막힌다.
    public let transparency: String

    public let startDate: Date
    public let endDate: Date

    enum CodingKeys: String, CodingKey {
        case summary, description, start, end, reminders, extendedProperties, transparency
    }

    init(summary: String, description: String, start: Date, end: Date, popupMinutes: Int?, src: String, now: Date) {
        self.summary = summary; self.description = description
        self.start = ShadowDateTime(start); self.end = ShadowDateTime(end)
        self.startDate = start; self.endDate = end
        self.reminders = ShadowReminders(useDefault: false,
                                         overrides: popupMinutes.map { [ShadowReminderOverride(method: "popup", minutes: $0)] } ?? [])
        self.extendedProperties = ShadowExtendedProperties(private: [
            ShadowEvent.srcKey: src, ShadowEvent.versionKey: GCalTimeParser.seoulRFC3339(now),
        ])
        self.transparency = "transparent"
    }

    public var src: String { extendedProperties.private[ShadowEvent.srcKey]! }

    /// 키 정렬 JSON. 같은 입력이면 같은 바이트가 나와 테스트·로그 비교가 쉽다.
    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }
}

// MARK: 이미 있는 섀도

/// 섀도 캘린더에서 읽어 온 이벤트(물길이 쓴 것).
public struct ShadowExisting: Sendable, Hashable {
    public var eventId: String
    public var src: String
    public var summary: String
    public var description: String
    public var start: Date
    public var end: Date

    public init(eventId: String, src: String, summary: String, description: String, start: Date, end: Date) {
        self.eventId = eventId; self.src = src; self.summary = summary
        self.description = description; self.start = start; self.end = end
    }

    /// mulgil_src가 없는 이벤트는 내가 손으로 넣은 것이므로 건드리지 않는다(nil).
    public init?(_ e: GCalEvent) {
        guard !e.isCancelled, let src = e.extendedProperties?.private?[ShadowEvent.srcKey],
              let s = e.start?.time?.instant, let en = e.end?.time?.instant else { return nil }
        self.init(eventId: e.id, src: src, summary: e.summary ?? "", description: e.description ?? "", start: s, end: en)
    }
}

public struct ShadowPatch: Sendable, Hashable {
    public let eventId: String
    public let payload: ShadowPayload
}

public struct ShadowPlan: Sendable, Hashable {
    public var inserts: [ShadowPayload] = []
    public var patches: [ShadowPatch] = []
    public var deletes: [String] = []
    /// 시작 20분 이내에 처음 발견해 섀도를 건너뛴 회차(맥 카드만 뜬다).
    public var skippedLate: [String] = []

    public var isEmpty: Bool { inserts.isEmpty && patches.isEmpty && deletes.isEmpty }
}

// MARK: 규칙

public enum ShadowEvent {
    public static let srcKey = "mulgil_src"
    public static let versionKey = "mulgil_v"
    /// 알람 이벤트의 src 접두어. 맥락 이벤트 diff가 이것을 건드리지 않게 한다.
    public static let owePrefix = "owe:"

    public static let maxLines = 6
    public static let lineLimit = 40
    public static let leadMinutes = 10
    public static let rollingDays = 7
    public static let lateDiscoveryMinutes = 20
    public static let owePopupMinutes = 60
    public static let oweMergeThreshold = 3

    // MARK: 서식(§7.10)

    public static func contextTitle(_ originalTitle: String) -> String {
        let t = clean(originalTitle)
        // 제목 없는 일정이면 "·  맥락"처럼 빈칸만 남는다.
        return "· \(t.isEmpty ? "(제목 없음)" : t) 맥락"
    }

    /// 최대 6줄. 1줄은 기준 시각, 비어 있는 종류와 링크 줄은 생략한다.
    public static func contextDescription(_ c: ShadowContext, now: Date) -> String {
        var lines = ["기준 \(monthDayTime(now)) · 원본 일정 확인"]
        let decisions = c.decisions.map(clean).filter { !$0.isEmpty }
        let questions = c.questions.map(clean).filter { !$0.isEmpty }
        let waits = c.waits.map(clean).filter { !$0.isEmpty }
        let owes = c.owes.filter { !clean($0.text).isEmpty }
        if !decisions.isEmpty { lines.append(truncate("\(MarkKind.decision.label): " + decisions.joined(separator: ", "))) }
        if !questions.isEmpty { lines.append(truncate("\(MarkKind.question.label): " + questions.joined(separator: ", "))) }
        if !owes.isEmpty {
            let items = owes.map { o in clean(o.text) + (o.due.map { "(\(dueLabel($0, now: now)))" } ?? "") }
            // " — 남음"은 상태 표시라 잘려 나가면 안 된다. 앞부분만 줄인다.
            let suffix = " — 남음"
            lines.append(truncate("\(MarkKind.owe.label): " + items.joined(separator: ", "), limit: lineLimit - suffix.count) + suffix)
        }
        if !waits.isEmpty { lines.append(truncate("\(MarkKind.wait.label): " + waits.joined(separator: ", "))) }
        // URL은 자르면 열리지 않으므로 40자 제한에서 뺀다.
        if let l = c.link, GCalLink.isSafeHTTPS(l) { lines.append(l) }
        return lines.prefix(maxLines).joined(separator: "\n")
    }

    /// 원본 시작 10분 전부터 10분짜리, 알람 없음.
    public static func contextPayload(for event: CalendarEvent, context: ShadowContext, now: Date) -> ShadowPayload {
        ShadowPayload(summary: contextTitle(event.title), description: contextDescription(context, now: now),
                      start: event.start.addingTimeInterval(-Double(leadMinutes) * 60), end: event.start,
                      popupMinutes: nil, src: event.key.description, now: now)
    }

    /// 시각 기한 owe의 알람 이벤트. 하루에 3개를 넘으면 하나로 합친다(§6.3).
    public static func oweAlarmPayloads(_ items: [ShadowOweAlarmItem], now: Date) -> [ShadowPayload] {
        let cal = Seoul.calendar
        let live = items.filter { $0.due.hasTime && $0.due.date > now }
        let byDay = Dictionary(grouping: live) { cal.startOfDay(for: $0.due.date) }
        var out: [ShadowPayload] = []
        for day in byDay.keys.sorted() {
            let list = byDay[day]!.sorted { ($0.due.date, $0.markId) < ($1.due.date, $1.markId) }
            if list.count > oweMergeThreshold {
                let first = list[0].due.date
                var lines = ["기준 \(monthDayTime(now)) · 할 것 \(list.count)개"]
                for it in list.prefix(maxLines - 1) { lines.append(truncate("\(hourMinute(it.due.date)) \(clean(it.text))")) }
                let c = cal.dateComponents([.year, .month, .day], from: day)
                let src = owePrefix + String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
                out.append(ShadowPayload(summary: "\(MarkKind.owe.label) \(list.count)개", description: lines.joined(separator: "\n"),
                                         start: first, end: first.addingTimeInterval(Double(leadMinutes) * 60),
                                         popupMinutes: owePopupMinutes, src: src, now: now))
            } else {
                for it in list {
                    let desc = ["기준 \(monthDayTime(now)) · 할 것", truncate("\(MarkKind.owe.label): \(clean(it.text))")]
                    out.append(ShadowPayload(summary: truncate("\(MarkKind.owe.label): \(clean(it.text))"),
                                             description: desc.joined(separator: "\n"),
                                             start: it.due.date, end: it.due.date.addingTimeInterval(Double(leadMinutes) * 60),
                                             popupMinutes: owePopupMinutes, src: owePrefix + it.markId, now: now))
                }
            }
        }
        return out
    }

    // MARK: 7일 롤링 diff

    /// 맥락 이벤트 diff. 대상: 취소·종일·수신함이 아니고, 내용이 있고, 시작이 (now, now+7일]인 회차.
    /// 이미 시작한 회차의 섀도는 지난 기록이므로 건드리지 않는다.
    public static func contextDiff(targets: [ShadowTarget], existing: [ShadowExisting], now: Date) -> ShadowPlan {
        let horizon = now.addingTimeInterval(Double(rollingDays) * 86_400)
        var desired: [String: ShadowPayload] = [:]
        for t in targets {
            let e = t.event
            guard !e.cancelled, !e.isAllDay, !e.gcalIsInbox, t.context.hasContent,
                  e.start > now, e.start <= horizon else { continue }
            let p = contextPayload(for: e, context: t.context, now: now)
            desired[p.src] = p
        }
        let mine = existing.filter { !$0.src.hasPrefix(owePrefix) }
        return reconcile(desired: desired, existing: mine, now: now,
                         lateCutoff: now.addingTimeInterval(Double(lateDiscoveryMinutes) * 60))
    }

    /// 알람 이벤트 diff. 기한이 바뀌면 시각이 달라지므로 patch로 옮긴다.
    public static func oweDiff(items: [ShadowOweAlarmItem], existing: [ShadowExisting], now: Date) -> ShadowPlan {
        let desired = Dictionary(oweAlarmPayloads(items, now: now).map { ($0.src, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = existing.filter { $0.src.hasPrefix(owePrefix) }
        return reconcile(desired: desired, existing: mine, now: now, lateCutoff: nil)
    }

    private static func reconcile(desired: [String: ShadowPayload], existing: [ShadowExisting],
                                  now: Date, lateCutoff: Date?) -> ShadowPlan {
        var plan = ShadowPlan()
        // 같은 src가 여럿이면(삽입 직후 앱이 죽은 경우) 하나만 남긴다.
        var bySrc: [String: ShadowExisting] = [:]
        for ex in existing.sorted(by: { $0.eventId < $1.eventId }) {
            if bySrc[ex.src] == nil { bySrc[ex.src] = ex }
            else if ex.end > now { plan.deletes.append(ex.eventId) }
        }
        for src in desired.keys.sorted() {
            let p = desired[src]!
            if let ex = bySrc[src] {
                if signature(ex) != signature(p) { plan.patches.append(ShadowPatch(eventId: ex.eventId, payload: p)) }
            } else if let cut = lateCutoff, p.endDate < cut {
                plan.skippedLate.append(src)
            } else {
                plan.inserts.append(p)
            }
        }
        for src in bySrc.keys.sorted() where desired[src] == nil {
            let ex = bySrc[src]!
            if ex.end > now { plan.deletes.append(ex.eventId) }
        }
        plan.deletes.sort()
        return plan
    }

    // 1줄(기준 시각)은 매번 바뀌므로 비교에서 뺀다. 안 그러면 폴링마다 전부 patch한다.
    private static func signature(_ e: ShadowExisting) -> [String] {
        [e.summary, secondKey(e.start), secondKey(e.end)]
            + e.description.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().map(String.init)
    }

    private static func signature(_ p: ShadowPayload) -> [String] {
        [p.summary, secondKey(p.startDate), secondKey(p.endDate)]
            + p.description.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().map(String.init)
    }

    // 페이로드 시각은 초 단위로 나가고 Google도 초 단위로 돌려준다. 소수초까지 비교하면 매 폴링마다 patch한다.
    private static func secondKey(_ d: Date) -> String { String(Int(d.timeIntervalSince1970.rounded(.down))) }

    // MARK: 문자열 도우미

    /// 줄바꿈이 섞이면 6줄 규격이 깨지므로 한 줄로 편다.
    static func clean(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// 글자(grapheme) 기준 40자. 넘치면 39자 + "…".
    public static func truncate(_ s: String, limit: Int = lineLimit) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)) + "…"
    }

    static func monthDayTime(_ d: Date) -> String {
        let c = Seoul.calendar.dateComponents([.month, .day], from: d)
        return String(format: "%02d/%02d ", c.month!, c.day!) + hourMinute(d)
    }

    static func hourMinute(_ d: Date) -> String {
        let c = Seoul.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// 오늘/내일/모레는 말로, 그 밖은 M/d. 시각이 있으면 덧붙인다.
    static func dueLabel(_ due: Due, now: Date) -> String {
        let cal = Seoul.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due.date)).day ?? 0
        let dayText: String
        switch days {
        case 0: dayText = "오늘"
        case 1: dayText = "내일"
        case 2: dayText = "모레"
        default:
            let c = cal.dateComponents([.month, .day], from: due.date)
            dayText = "\(c.month!)/\(c.day!)"
        }
        return due.hasTime ? "\(dayText) \(hourMinute(due.date))" : dayText
    }
}
