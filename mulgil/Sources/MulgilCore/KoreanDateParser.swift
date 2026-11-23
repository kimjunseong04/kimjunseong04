import Foundation

/// 한국어 문장에서 찾은 날짜 표현 한 개의 해석 결과.
public struct KoreanDateParse: Hashable, Sendable {
    public let due: Due
    /// 원문에서 날짜·시각 표현이 차지한 범위. 뒤따르는 "까지"는 포함하지 않는다.
    public let matchedRange: Range<String.Index>
    /// "~까지", "~전까지", "~내로", "~안으로", "~중으로"가 날짜 표현 바로 뒤에 붙었는지.
    public let isDeadline: Bool
    /// "공학관에서" 같은 단순 장소. 규칙에 걸리지 않으면 nil.
    public let location: String?

    public init(due: Due, matchedRange: Range<String.Index>, isDeadline: Bool, location: String?) {
        self.due = due; self.matchedRange = matchedRange
        self.isDeadline = isDeadline; self.location = location
    }
}

/// 카톡·회의 문장의 한국어 날짜 표현을 결정론적으로 해석한다(설계 §5.7, §7.7, §7.8).
///
/// 해석 규칙 (기준 시각 `now`, 서울 달력):
/// - 날짜 표현과 시각 표현을 각각 문장에서 **가장 앞의 것** 하나씩 고른다.
/// - 오늘/내일/모레/글피, 내일모레·낼모레(=모레), "낼"은 시각·까지 같은 문맥이 뒤에 올 때만.
/// - 요일 단독: 오늘이 그 요일이면 오늘(시각이 이미 지났으면 다음 주), 아니면 다가오는 그 요일.
/// - 이번 주/다음 주/담주/다다음 주 + 요일: 그 주(월~일) 안의 요일. 지난 날이어도 글자 그대로.
/// - 주만 있을 때: 기한("까지")이면 그 주 일요일, 아니면 그 주 월요일(이번 주면 오늘).
/// - 주말 = 그 주 토요일.
/// - "목" 같은 한 글자 요일은 뒤에 시각·시간대·"까지"가 오거나 "(목)"처럼 괄호 안일 때만. "일"·"수" 한 글자는 더 엄격하다.
/// - 11/27, 11.27, 11월 27일: 연도가 없고 오늘보다 이전이면 내년.
/// - 27일: 오늘 이후(오늘 포함)면 이번 달, 지났으면 다음 달.
/// - 시각 휴리스틱(오전/오후 등 없음): 0시·12시 이후는 그대로, 1~6시 → 오후, 7~10시 → 오후(문장에
///   아침·오전·출근 같은 아침 문맥이 있으면 오전), 11시 → 오전(단 "까지" 기한이면 23시).
/// - 시간대 단어만 있고 숫자가 없으면 아침 9시, 점심 12시, 저녁 19시, 밤 21시. 오전/오후/낮/새벽은 날짜만.
///   (시간대 단어 단독은 날짜 표현이 있을 때만 쓴다. "저녁 먹었어?"는 nil.)
/// - 밤 12시·자정 → 다음 날 0시, 밤 1~4시 → 다음 날 새벽. 정오 → 12시.
/// - 날짜 없이 시각만: 오늘 그 시각이 아직 안 왔으면 오늘, 지났으면 내일.
/// - "09:30", "08시"처럼 0을 채운 시각은 24시간제로 그대로. 저녁 12시는 밤 12시와 같다.
/// - 날짜만 없는 "밤 1시"·"자정"은 다음 도래 시각(00:30이면 오늘 01:00).
/// - 첫 표현이 없는 날짜(2/30, 25시)면 다음 표현을 쓴다. NFD로 들어온 한글도 받는다.
/// - "까지"가 날짜 바로 뒤나 시각 바로 뒤에 붙으면 기한이다("금요일까지 3시에" 포함).
/// - "오늘"을 명시했는데 휴리스틱 시각이 이미 지났으면 12시간 뒤(예: 오늘 11시 → 23시)를 쓴다.
public struct KoreanDateParser: Sendable {
    public let now: Date
    public let calendar: Calendar

    public init(now: Date, calendar: Calendar = Seoul.calendar) {
        self.now = now
        self.calendar = calendar
    }

    public func parse(_ text: String) -> KoreanDateParse? {
        // macOS 클립보드는 NFD(자모 분리)일 수 있어 정규식이 안 걸린다. NFC로 풀고 범위만 원문으로 되돌린다.
        let norm = text.precomposedStringWithCanonicalMapping
        guard let r = parseNFC(norm) else { return nil }
        // 한글 음절은 NFC·NFD 모두 한 Character라 글자 수 오프셋이 원문과 같다.
        let lo = norm.distance(from: norm.startIndex, to: r.matchedRange.lowerBound)
        let len = norm.distance(from: r.matchedRange.lowerBound, to: r.matchedRange.upperBound)
        guard let s = text.index(text.startIndex, offsetBy: lo, limitedBy: text.endIndex),
              let e = text.index(s, offsetBy: len, limitedBy: text.endIndex) else { return nil }
        return KoreanDateParse(due: r.due, matchedRange: s..<e, isDeadline: r.isDeadline, location: r.location)
    }

    private func parseNFC(_ text: String) -> KoreanDateParse? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let today = calendar.startOfDay(for: now)
        let morning = KDPRules.morningContext.firstMatch(in: text, range: full) != nil

        // 날짜: 우선순위 높은 규칙이 먼저 자리를 차지해 "11월 27일" 안의 "27일" 같은 중복을 막는다.
        var taken: [NSRange] = []
        var dates: [(range: NSRange, kind: KDPDateKind)] = []
        for rule in KDPRules.dateRules {
            for m in rule.regex.matches(in: text, range: full) {
                if taken.contains(where: { kdpOverlaps($0, m.range) }) { continue }
                guard let kind = rule.make(KDPMatch(m, ns)) else { continue }
                taken.append(m.range)
                dates.append((m.range, kind))
            }
        }
        // "2월 30일" 같은 없는 날짜가 앞에 있어도 뒤의 유효한 표현을 쓴다.
        let date = dates.sorted { $0.range.location < $1.range.location }
            .first { resolveDay($0.kind, today: today, deadline: false) != nil }

        var times: [(range: NSRange, kind: KDPTimeKind)] = []
        for rule in KDPRules.timeRules {
            for m in rule.regex.matches(in: text, range: full) {
                if taken.contains(where: { kdpOverlaps($0, m.range) }) { continue }
                guard let kind = rule.make(KDPMatch(m, ns)) else { continue }
                times.append((m.range, kind))
            }
        }
        var time = times.sorted { $0.range.location < $1.range.location }
            .first { resolveClock($0.kind, deadline: false, morning: morning) != nil }
        // 시간대 단어 단독은 날짜가 있을 때만 의미가 있다.
        if time == nil, date != nil {
            for m in KDPRules.periodOnly.matches(in: text, range: full) {
                if taken.contains(where: { kdpOverlaps($0, m.range) }) { continue }
                time = (m.range, .periodOnly(ns.substring(with: m.range)))
                break
            }
        }
        guard date != nil || time != nil else { return nil }
        if date == nil, case .periodOnly = time!.kind { return nil }

        var union = date?.range ?? time!.range
        if let t = time?.range { union = kdpUnion(union, t) }
        // "금요일까지 오후 3시에"처럼 까지가 날짜 바로 뒤에 붙고 시각이 뒤따르는 경우도 기한이다.
        func deadlineAfter(_ r: NSRange) -> Bool {
            let after = ns.substring(from: r.location + r.length)
            return KDPRules.hit(KDPRules.deadline, after)
        }
        let isDeadline = deadlineAfter(union) || (date.map { deadlineAfter($0.range) } ?? false)
            || (time.map { deadlineAfter($0.range) } ?? false)

        let clock = time.flatMap { resolveClock($0.kind, deadline: isDeadline, morning: morning) }

        let due: Due
        if let d = date {
            guard let day = resolveDay(d.kind, today: today, deadline: isDeadline) else { return nil }
            if let c = clock {
                guard var dt = at(day, c) else { return nil }
                if case .weekday = d.kind, dt <= now, let next = calendar.date(byAdding: .day, value: 7, to: dt) {
                    dt = next
                }
                if case .offset(0) = d.kind, dt <= now, c.ambiguous, c.hour < 12,
                   let later = calendar.date(byAdding: .hour, value: 12, to: dt), later > now {
                    dt = later
                }
                due = Due(date: dt, hasTime: true)
            } else {
                due = Due(date: day, hasTime: false)
            }
        } else {
            guard let c = clock, var dt = at(today, c) else { return nil }
            // 00:30에 "밤 1시"는 30분 뒤다. 다음 날로 넘긴 시각보다 하루 앞이 아직 안 왔으면 그쪽이 다음 도래 시각.
            if c.dayOffset > 0, let earlier = calendar.date(byAdding: .day, value: -1, to: dt), earlier > now {
                dt = earlier
            }
            if dt <= now, let next = calendar.date(byAdding: .day, value: 1, to: dt) { dt = next }
            due = Due(date: dt, hasTime: true)
        }

        guard let range = Range(union, in: text) else { return nil }
        return KoreanDateParse(due: due, matchedRange: range, isDeadline: isDeadline, location: KDPRules.location(in: text))
    }

    // MARK: - 해석

    private func at(_ day: Date, _ c: KDPClock) -> Date? {
        guard let base = calendar.date(byAdding: .day, value: c.dayOffset, to: day) else { return nil }
        return calendar.date(bySettingHour: c.hour, minute: c.minute, second: 0, of: base)
    }

    private func makeDay(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        // 2/30 같은 날짜가 3/2로 넘어가는 것을 막는다.
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year == y && c.month == m && c.day == d) ? date : nil
    }

    private func weekdayIndex(_ day: Date) -> Int { (calendar.component(.weekday, from: day) + 5) % 7 }

    private func resolveDay(_ kind: KDPDateKind, today: Date, deadline: Bool) -> Date? {
        let y = calendar.component(.year, from: today)
        let mo = calendar.component(.month, from: today)
        let dd = calendar.component(.day, from: today)
        func add(_ n: Int, _ to: Date = today) -> Date? { calendar.date(byAdding: .day, value: n, to: to) }
        switch kind {
        case .offset(let n):
            return add(n)
        case .monthDay(let year, let m, let d):
            guard let date = makeDay(year ?? y, m, d) else { return nil }
            if year == nil, date < today { return makeDay(y + 1, m, d) }
            return date
        case .dayOfMonth(let d):
            // 지난 날이거나 이번 달에 없는 날(31일 등)이면 다음 달로 넘긴다.
            for k in 0...2 {
                let total = mo - 1 + k
                if k == 0 && d < dd { continue }
                if let date = makeDay(y + total / 12, total % 12 + 1, d) { return date }
            }
            return nil
        case .monthRel(let k, let d):
            let total = mo - 1 + k
            return makeDay(y + total / 12, total % 12 + 1, d)
        case .weekend(let n, let explicit):
            // 일요일에 그냥 "주말"이라 하면 어제 토요일이 아니라 오늘이다.
            if !explicit, weekdayIndex(today) == 6 { return today }
            return add(-weekdayIndex(today) + 7 * n + 5)
        case .week(let n, let wd):
            guard let monday = add(-weekdayIndex(today) + 7 * n) else { return nil }
            if let wd { return add(wd, monday) }
            if deadline { return add(6, monday) }
            return n == 0 ? today : monday
        case .weekday(let wd):
            return add((wd - weekdayIndex(today) + 7) % 7)
        }
    }

    private func resolveClock(_ kind: KDPTimeKind, deadline: Bool, morning: Bool) -> KDPClock? {
        switch kind {
        case .noon: return KDPClock(hour: 12, minute: 0, dayOffset: 0, ambiguous: false)
        case .midnight: return KDPClock(hour: 0, minute: 0, dayOffset: 1, ambiguous: false)
        case .periodOnly(let p):
            let defaults = ["아침": 9, "점심": 12, "저녁": 19, "밤": 21]
            return defaults[p].map { KDPClock(hour: $0, minute: 0, dayOffset: 0, ambiguous: false) }
        case .clock(let h, let m, let period):
            guard (0...24).contains(h), (0...59).contains(m) else { return nil }
            if h == 24 { return KDPClock(hour: 0, minute: m, dayOffset: 1, ambiguous: false) }
            switch period {
            case "오전", "아침", "새벽":
                return KDPClock(hour: h == 12 ? 0 : h, minute: m, dayOffset: 0, ambiguous: false)
            case "24h": // "09:30", "08시"처럼 0을 채운 표기는 24시간제로 그대로 읽는다.
                return KDPClock(hour: h, minute: m, dayOffset: 0, ambiguous: false)
            case "저녁" where h == 12:
                return KDPClock(hour: 0, minute: m, dayOffset: 1, ambiguous: false)
            case "오후", "저녁":
                return KDPClock(hour: h < 12 ? h + 12 : h, minute: m, dayOffset: 0, ambiguous: false)
            case "낮", "점심":
                return KDPClock(hour: (1...6).contains(h) ? h + 12 : h, minute: m, dayOffset: 0, ambiguous: false)
            case "밤":
                if h == 12 || h == 0 { return KDPClock(hour: 0, minute: m, dayOffset: 1, ambiguous: false) }
                if h <= 4 { return KDPClock(hour: h, minute: m, dayOffset: 1, ambiguous: false) }
                return KDPClock(hour: h < 12 ? h + 12 : h, minute: m, dayOffset: 0, ambiguous: false)
            default:
                switch h {
                case 0, 12...23: return KDPClock(hour: h, minute: m, dayOffset: 0, ambiguous: false)
                case 1...6: return KDPClock(hour: h + 12, minute: m, dayOffset: 0, ambiguous: true)
                case 7...10: return KDPClock(hour: morning ? h : h + 12, minute: m, dayOffset: 0, ambiguous: !morning)
                default: // 11시: 수업·약속은 오전이 흔하고, 기한은 밤 11시가 흔하다.
                    return KDPClock(hour: (deadline && !morning) ? 23 : 11, minute: m, dayOffset: 0, ambiguous: !morning)
                }
            }
        }
    }
}

// MARK: - 내부 타입 (모듈 접두어 KDP)

enum KDPDateKind: Sendable {
    case offset(Int)                       // 오늘 + n일
    case monthDay(year: Int?, month: Int, day: Int)
    case dayOfMonth(Int)
    case monthRel(months: Int, day: Int)   // 이번 달/다음 달 N일
    case week(weeks: Int, weekday: Int?)   // 0=월 … 6=일
    case weekend(weeks: Int, explicit: Bool) // 주말: 그 주 토요일
    case weekday(Int)                      // 요일 단독
}

enum KDPTimeKind: Sendable {
    case clock(hour: Int, minute: Int, period: String?)
    case noon, midnight
    case periodOnly(String)
}

struct KDPClock: Sendable {
    let hour: Int, minute: Int, dayOffset: Int
    /// 오전/오후 표시 없이 휴리스틱으로 고른 시각인지.
    let ambiguous: Bool
}

struct KDPMatch {
    let groups: [String?]
    /// 매치 바로 앞·뒤 원문 (오탐 판정용)
    let before: String
    let after: String

    init(_ m: NSTextCheckingResult, _ ns: NSString) {
        groups = (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        before = ns.substring(to: m.range.location)
        after = ns.substring(from: m.range.location + m.range.length)
    }

    subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    func int(_ i: Int) -> Int? { self[i].flatMap { Int($0) } }
}

struct KDPRule<Kind>: @unchecked Sendable {
    let regex: NSRegularExpression
    let make: @Sendable (KDPMatch) -> Kind?
    init(_ pattern: String, _ make: @escaping @Sendable (KDPMatch) -> Kind?) {
        // 패턴은 코드에 박힌 상수라 실패하면 개발 중 즉시 드러나야 한다.
        self.regex = try! NSRegularExpression(pattern: pattern)
        self.make = make
    }
}

func kdpOverlaps(_ a: NSRange, _ b: NSRange) -> Bool {
    a.location < b.location + b.length && b.location < a.location + a.length
}

func kdpUnion(_ a: NSRange, _ b: NSRange) -> NSRange {
    let lo = min(a.location, b.location)
    let hi = max(a.location + a.length, b.location + b.length)
    return NSRange(location: lo, length: hi - lo)
}

func kdpRegex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

enum KDPRules {
    static let weekdays: [Character: Int] = ["월": 0, "화": 1, "수": 2, "목": 3, "금": 4, "토": 5, "일": 6]
    static func wd(_ s: String?) -> Int? { s.flatMap { $0.first }.flatMap { weekdays[$0] } }

    static let period = "(오전|오후|아침|저녁|밤|새벽|낮|점심)"
    static let parenWeekday = #"(?:\s*\(\s*[월화수목금토일](?:요일)?\s*\))?"#
    static let timeContext = #"\s*(?:\d{1,2}\s*시(?!간)|\d{1,2}:\d{2}|오전|오후|아침|점심|저녁|밤|새벽|낮|정오|자정)"#

    /// 숫자 뒤에 오면 날짜가 아니라는 신호(단위·분량).
    static let unitAfter = kdpRegex(#"^\s*(?:점|배|명|개|%|퍼|번|회(?![의식사])|문제|정도|씩|만|억|천|kg|km|학점|등(?!교)|위|차|장(?!소)|권|세(?!미))"#)
    static let unitBefore = kdpRegex(#"(?:버전|버젼|학점|평점|평균|성적|점수|GPA|gpa|ver|v|V)\s*$"#)
    static func hit(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static let dateRules: [KDPRule<KDPDateKind>] = [
        // 2026년 12월 24일, 11월 27일
        KDPRule(#"(?:(\d{4})\s*년\s*)?(?<!\d)(\d{1,2})\s*월\s*(\d{1,2})\s*일"# + parenWeekday) { m in
            guard let mo = m.int(2), let d = m.int(3) else { return nil }
            return .monthDay(year: m.int(1), month: mo, day: d)
        },
        // 11/27, 11.27 — 버전·학점·분수 오탐을 막는다.
        KDPRule(#"(?<![\d./:A-Za-z])(\d{1,2})([/.])(\d{1,2})(?![\d/%:]|\.\d)"# + parenWeekday) { m in
            guard let mo = m.int(1), let d = m.int(3), (1...12).contains(mo), (1...31).contains(d) else { return nil }
            if hit(unitBefore, m.before) || hit(unitAfter, m.after) { return nil }
            return .monthDay(year: nil, month: mo, day: d)
        },
        // 다음 달 5일, 이번 달 30일
        KDPRule(#"(이번|다음|담)\s*달\s*(\d{1,2})\s*일"#) { m in
            guard let d = m.int(2) else { return nil }
            return .monthRel(months: m[1] == "이번" ? 0 : 1, day: d)
        },
        // N일 뒤/후
        KDPRule(#"(?<![\d.])(\d{1,3})\s*일\s*(?:뒤|후|있다가|지나서)"#) { m in m.int(1).map { .offset($0) } },
        KDPRule(#"(이틀|사흘|나흘|일주일)\s*(?:뒤|후|있다가)"#) { m in
            ["이틀": 2, "사흘": 3, "나흘": 4, "일주일": 7][m[1] ?? ""].map { .offset($0) }
        },
        KDPRule(#"(?<![\d.])(\d{1,2})\s*주\s*(?:뒤|후)"#) { m in m.int(1).map { .offset($0 * 7) } },
        // 이번 주말, 다음 주말, 주말
        KDPRule(#"(?:(다다음|이번|다음|담|지난|저번)\s*)?주말"#) { m in
            .weekend(weeks: weekOffset(m[1]), explicit: m[1] != nil)
        },
        // 이번 주/다음 주/담주 (+ 요일)
        KDPRule(#"(?:(다다음|이번|다음|저번|지난)\s*주|(담)주)(?![말차간년기제소문요식])(?:\s*의)?(?:\s*(?:([월화수목금토일])(?:요일|욜)|([월화수목금토])(?![가-힣])))?"#) { m in
            .week(weeks: weekOffset(m[1] ?? m[2]), weekday: wd(m[3] ?? m[4]))
        },
        // 오늘/내일/모레/글피. "낼"은 단독 동사("낼게")와 헷갈리므로 문맥이 있을 때만.
        KDPRule(#"(내일\s*모레|낼\s*모레|오늘|금일|내일|명일|모레|글피|낼(?=\s*(?:\d|오전|오후|아침|점심|저녁|밤|새벽|낮|까지|봐|보자|만나|봬)))"#) { m in
            switch (m[1] ?? "").replacingOccurrences(of: " ", with: "") {
            case "오늘", "금일": return .offset(0)
            case "내일", "명일", "낼": return .offset(1)
            case "모레", "내일모레", "낼모레": return .offset(2)
            case "글피": return .offset(3)
            default: return nil
            }
        },
        // 목요일, 목욜
        KDPRule(#"([월화수목금토일])(?:요일|욜)"#) { m in wd(m[1]).map { .weekday($0) } },
        // "목 7시", "토 저녁" — 한 글자 요일은 시각 문맥에서만. "일"은 "할 일 3시"와 헷갈려 뺀다.
        KDPRule(#"(?<![가-힣\d])([월화수목금토])(?="# + timeContext + ")") { m in wd(m[1]).map { .weekday($0) } },
        KDPRule(#"(?<![가-힣\d])([월화목금토])(?=까지)"#) { m in wd(m[1]).map { .weekday($0) } },
        KDPRule(#"\(\s*([월화수목금토일])\s*\)"#) { m in wd(m[1]).map { .weekday($0) } },
        // 27일
        KDPRule(#"(?<![\d./])(\d{1,2})\s*일"#) { m in
            guard let d = m.int(1), (1...31).contains(d) else { return nil }
            if hit(dayNotDate, m.after) { return nil }
            // "1일 1커밋"처럼 숫자가 이어지면 시각일 때만 받는다.
            if hit(digitNext, m.after) && !hit(clockNext, m.after) { return nil }
            return .dayOfMonth(d)
        },
    ]

    static let dayNotDate = kdpRegex(#"^\s*(?:뒤|후|간|동안|째|차|이내|내|만에|치|연속|씩|정도|요일|분|주일|있다가|지나서|남|밖에|이상|미만)"#)
    static let digitNext = kdpRegex(#"^\s*\d"#)
    static let clockNext = kdpRegex(#"^\s*\d{1,2}\s*(?:시|:\d{2})"#)

    static func weekOffset(_ s: String?) -> Int {
        switch s {
        case "다음", "담": 1
        case "다다음": 2
        case "저번", "지난": -1
        default: 0
        }
    }

    static let hourNames = ["열한": 11, "열두": 12, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9,
                            "한": 1, "두": 2, "세": 3, "네": 4, "열": 10]
    /// "3시간", "시험", "시안"처럼 '시'로 시작하는 다른 낱말을 거른다.
    static let siTail = #"\s*시(?!간|즌|각|험|작|장|청|급|안|키|절|민|설|점|계|스|티|트|대|리|립|공|상|행|력|사|위|판|집|금|원|선|합|식|청|골|기|인|외|내|의|각)"#
    /// 숫자 뒤의 "시"는 낱말 시작일 일이 드물다. 넓게 거르면 "3시인가요", "7시의"를 놓친다.
    static let digitSiTail = #"\s*시(?!간|즌|리즈|\s*(?:편의점|영업|운영|상담))"#
    /// "한시적", "네 시도해볼게"를 거른다.
    static let korSiTail = siTail + "(?!도|적)"
    static func zeroPadded(_ h: String?) -> String? { (h?.count == 2 && h?.first == "0") ? "24h" : nil }
    static let minuteTail = #"(?:\s*(반)(?!납|대|드|복|응|영|찬|성|장|년|값|팔|지|죽|창|박|려|환)|\s*(\d{1,2})\s*분)?"#
    static let korNum = "(열한|열두|다섯|여섯|일곱|여덟|아홉|한|두|세|네|열)"

    static func clock(_ hour: Int?, _ m: KDPMatch, period: String?, half: Int, minute: Int) -> KDPTimeKind? {
        guard let h = hour else { return nil }
        let min = m[half] != nil ? 30 : (m.int(minute) ?? 0)
        return .clock(hour: h, minute: min, period: period)
    }

    static let timeRules: [KDPRule<KDPTimeKind>] = [
        // (저녁) 7시 (반|30분)
        KDPRule("(?:" + period + #"\s*)?(?<![\d.:/])(\d{1,2})"# + digitSiTail + minuteTail) { m in
            clock(m.int(2), m, period: m[1] ?? zeroPadded(m[2]), half: 3, minute: 4)
        },
        // (오후) 두시 반
        KDPRule(period + #"\s*"# + korNum + korSiTail + minuteTail) { m in
            clock(hourNames[m[2] ?? ""], m, period: m[1], half: 3, minute: 4)
        },
        KDPRule(#"(?<![가-힣])"# + korNum + korSiTail + minuteTail) { m in
            clock(hourNames[m[1] ?? ""], m, period: nil, half: 2, minute: 3)
        },
        // 19:30
        KDPRule("(?:" + period + #"\s*)?(?<![\d.:/])(\d{1,2}):(\d{2})(?![\d:])"#) { m in
            guard let h = m.int(2), let mi = m.int(3), h <= 24, mi < 60 else { return nil }
            return .clock(hour: h, minute: mi, period: m[1] ?? zeroPadded(m[2]))
        },
        KDPRule("(정오|자정)") { m in m[1] == "정오" ? .noon : .midnight },
    ]

    static let periodOnly = kdpRegex(period)
    static let deadline = kdpRegex(#"^\s*(?:(?:전\s*)?까지|내로|안으로|중으로)"#)
    static let morningContext = kdpRegex(#"아침|오전|모닝|조식|등교|출근|1교시|첫차"#)

    // MARK: 장소 (단순 규칙: "<장소>에서", 장소처럼 끝나는 낱말만)

    static let locationRegex = kdpRegex(#"([가-힣A-Za-z0-9]+)(?:\s+(앞|뒤|옆|근처|입구|로비))?\s*에서"#)
    static let placeSuffixes = ["관", "회의실", "강의실", "실습실", "연구실", "세미나실", "스터디룸", "동아리방", "도서관",
                                "센터", "카페", "식당", "라운지", "광장", "정문", "후문", "강당", "캠퍼스", "기숙사", "룸", "홀", "역"]
    static let placeWords: Set<String> = ["줌", "zoom", "Zoom", "디코", "디스코드", "구글밋", "학교", "학식", "스벅", "스타벅스", "집", "편의점"]
    static let notPlaces: Set<String> = ["영역", "지역", "구역", "역할", "상관", "기관", "관"]

    static func location(in text: String) -> String? {
        let ns = text as NSString
        for m in locationRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range(at: 1))
            let isPlace = placeWords.contains(word)
                || (!notPlaces.contains(word) && placeSuffixes.contains { word.hasSuffix($0) })
                || isNumberedRoom(word)
            guard isPlace else { continue }
            let extra = m.range(at: 2)
            return extra.location == NSNotFound ? word : word + " " + ns.substring(with: extra)
        }
        return nil
    }

    /// "302호", "B동", "3층"처럼 숫자·영문 뒤에 붙은 호·동·층.
    static func isNumberedRoom(_ w: String) -> Bool {
        guard let last = w.last, "호동층".contains(last), w.count >= 2 else { return false }
        let prev = w[w.index(w.endIndex, offsetBy: -2)]
        return prev.isNumber || prev.isASCII && prev.isLetter
    }
}
