import Foundation

// MarkInference: 마무리 모드 한 줄 → MarkKind 추론(§7.7), 녹음 끝 호출어 추출(§5.7-2).
// 결정론 규칙만 쓴다(§8). 설계에 없거나 모호해서 여기서 정한 것:
//
// [줄 추론 우선순위] 위에서 먼저 걸린 규칙이 이긴다.
//   1. label            "할 것:/내가 할 것:/받을 것:/기다리는 것:/정한 것:/미정:" 접두. §7.10 맥락 서식을 그대로 붙여넣어도 왕복되게.
//   2. wait.arrow       "← 이름" / "<- 이름". who = 화살표 뒤 첫 토큰, 나머지는 본문에 남긴다(날짜 파서용).
//   3. question.mark    끝이 ? / ？. "내가 할까?"는 약속이 아니라 질문이라 약속보다 먼저 본다.
//   4. owe.promise      받침 ㄹ + 게/께(할게·보낼게·올릴게·드릴께…), 겠습니다/겠어요/겠음.
//                       "알게 됐다"류 오탐을 막으려 뒤 단어가 되/돼/됐/된/하/한/해/했 로 시작하면 제외.
//                       부사형 형용사("길게/힘들게/멀게 …")와 추측·바람·응답의 겠("좋겠어요/알겠습니다/
//                       되겠습니다/같겠음/모르겠어요")은 약속이 아니라서 제외.
//   5. wait.receive     "받기로". who = "~한테(서)/에게(서)/(으)로부터/께" 앞 토큰.
//   6. wait.give        "주기로 했/함/하셨/하심/하였" 이고 1인칭 주어가 없을 때. who = 문두 "~이/가/께서" 주어.
//                       단, 주어가 없고 받는 사람이 3인칭("민지한테 주기로 했어")이면 생략된 주어는 나라서 owe.commit.
//   7. owe.commit       1인칭 주어(내가/제가/나는/저는) + "~기로". "내가 주기로 했어"는 기다림이 아니라 할 것.
//   8. question.undecided 미정/정해야/결정 필요/TBD 가 줄 어디에든 있으면. 설계는 "끝이"지만
//                       "장소 미정인 상태" 같은 어순도 흔해서 위치를 묻지 않는다(약속·기다림이 먼저 이김).
//   9. decision.default 그 외.
//   줄 앞 글머리(-, *, •, ·, 1., 1), [ ], [x])는 떼고 본다. 빈 줄은 버린다.
//   알려진 한계: 화자 분리가 없으므로 "민지가 보낼게래" 같은 인용도 owe 로 본다. 칩으로 고친다.
//   "비슷하겠음"처럼 하다-형용사의 추측 겠은 동사 약속과 구분하지 못해 owe 로 본다.
//
// [호출어 허용 범위] 전사 오인식을 고려한 퍼지 매칭(§5.7 "물길/물 길").
//   허용: 물길, 물 길, 무길 + 선택적 호격 아/야 + 선택적 쉼표·마침표. 예) "물길,", "물길아", "물 길 아", "무길,"
//   불허: 물기, 무기, 물결, 물길이(조사 '이'는 "물길이 막혔다" 같은 일반 문장이라서).
//   호출어는 단어 경계(세그먼트 시작 또는 공백·문장부호 뒤)에서만 인정하고, 바로 뒤에 라벨이 와야 후보가 된다.
//   라벨: 내가 할 것 / 할 것 → owe, 받을 것 / 기다리는 것 → wait, 정한 것 → decision, 미정 → question.
//   "것" 대신 "거", 띄어쓰기 누락, 조사 은/는, 콜론 누락·쉼표 대체를 허용한다(STT가 콜론을 거의 안 찍음).
//   한 발화에 라벨이 여럿이면("…까지. 받을 것: …") 문장부호 뒤에 온 라벨에서만 끊는다.
//   본문이 비면 다음 세그먼트를 본문으로 쓴다(Whisper가 호출어 뒤에서 세그먼트를 자르는 경우).
//   라벨 바로 뒤에 한글이 붙으면 라벨이 아니다("할 거야", "미정인", "정한 거지" 오인 방지).
//   기본 창은 녹음 끝에서 90초(§5.7). nil 이면 전체. 세그먼트는 t0 순으로 다시 정렬하고,
//   t0/t1 이 유한하지 않은 세그먼트는 버린다(이상치 한 개가 창 전체를 비우지 않게).
//   Whisper 반복 루프로 같은 (종류, 본문)이 여러 번 나오면 가장 이른 것 하나만 남긴다.

/// 추론 근거. 원시값은 저장·로그용 안정 id, `hint`는 회색 칩 문구.
public enum MarkInferenceRule: String, Codable, Sendable, CaseIterable {
    case explicitLabel = "label"
    case waitArrow = "wait.arrow"
    case questionMark = "question.mark"
    case owePromise = "owe.promise"
    case waitReceive = "wait.receive"
    case waitGive = "wait.give"
    case oweCommit = "owe.commit"
    case questionUndecided = "question.undecided"
    case decisionDefault = "decision.default"

    public var hint: String {
        switch self {
        case .explicitLabel: "직접 적은 종류"
        case .waitArrow: "← 표시"
        case .questionMark: "물음표"
        case .owePromise: "'~할게'"
        case .waitReceive: "'~받기로'"
        case .waitGive: "'~주기로 했'"
        case .oweCommit: "'내가 ~하기로'"
        case .questionUndecided: "'미정'"
        case .decisionDefault: "기본값"
        }
    }
}

/// 한 줄 추론 결과. 사용자가 칩을 바꾸면 `overriding(kind:)`로 새 값을 만든다.
public struct MarkInferenceResult: Hashable, Codable, Sendable {
    /// 입력 원문 줄(공백만 정리)
    public let line: String
    /// 저장할 본문(라벨·화살표·글머리 제거)
    public let text: String
    public let kind: MarkKind
    public let rule: MarkInferenceRule
    /// 기다리는 상대. 추출 못 하면 nil
    public let who: String?
    /// 사용자가 추론을 바꿨는지
    public let overridden: Bool

    public init(line: String, text: String, kind: MarkKind, rule: MarkInferenceRule, who: String?, overridden: Bool = false) {
        self.line = line; self.text = text; self.kind = kind; self.rule = rule; self.who = who; self.overridden = overridden
    }

    public func overriding(kind newKind: MarkKind) -> MarkInferenceResult {
        MarkInferenceResult(line: line, text: text, kind: newKind, rule: rule,
                            who: newKind == .wait ? who : nil, overridden: newKind != kind || overridden)
    }
}

/// 전사 세그먼트(§4 Segment[t0,t1,text]). 초 단위, 녹음 시작 기준.
public struct MarkInferenceSegment: Hashable, Codable, Sendable {
    public let t0: TimeInterval
    public let t1: TimeInterval
    public let text: String
    public init(t0: TimeInterval, t1: TimeInterval, text: String) { self.t0 = t0; self.t1 = t1; self.text = text }
}

/// 호출어로 뽑은 후보. origin=voice-keyword 로 저장될 재료.
public struct MarkInferenceVoiceCandidate: Hashable, Codable, Sendable {
    public let kind: MarkKind
    public let text: String
    /// 호출어가 들어 있던 세그먼트의 t0
    public let t0: TimeInterval
    public let who: String?
    /// 인식한 라벨 원문(예: "내가 할 것")
    public let label: String
    /// 인식한 호출어 원문(예: "물 길아")
    public let hotword: String
    public let segmentIndex: Int
}

public enum MarkInference {

    // MARK: 줄 추론

    /// 여러 줄 입력을 줄 단위로 추론한다. 빈 줄은 건너뛴다.
    public static func inferLines(_ input: String) -> [MarkInferenceResult] {
        input.split(whereSeparator: { $0.isNewline }).compactMap { infer(String($0)) }
    }

    /// 한 줄 추론. 내용이 없으면 nil.
    public static func infer(_ rawLine: String) -> MarkInferenceResult? {
        let line = collapseSpaces(rawLine)
        let body = stripBullet(line)
        guard !body.isEmpty else { return nil }

        if let (kind, rest) = typedLabel(body) {
            guard !rest.isEmpty else { return nil }
            if kind == .wait {
                if let (t, w) = arrowSplit(rest) {
                    return MarkInferenceResult(line: line, text: t, kind: .wait, rule: .explicitLabel, who: w)
                }
                return MarkInferenceResult(line: line, text: rest, kind: .wait, rule: .explicitLabel,
                                           who: receiveWho(rest) ?? giveWho(rest))
            }
            return MarkInferenceResult(line: line, text: rest, kind: kind, rule: .explicitLabel, who: nil)
        }
        if let (t, w) = arrowSplit(body) {
            return MarkInferenceResult(line: line, text: t, kind: .wait, rule: .waitArrow, who: w)
        }
        if let last = trimmedTail(body).last, last == "?" || last == "？" {
            return MarkInferenceResult(line: line, text: body, kind: .question, rule: .questionMark, who: nil)
        }
        if hasPromise(body) {
            return MarkInferenceResult(line: line, text: body, kind: .owe, rule: .owePromise, who: nil)
        }
        if matches(#"받기로"#, body) {
            return MarkInferenceResult(line: line, text: body, kind: .wait, rule: .waitReceive, who: receiveWho(body))
        }
        let firstPerson = hasFirstPersonSubject(body)
        if !firstPerson, matches(#"주기로\s*(했|함|하셨|하심|하였)"#, body) {
            let giver = giveWho(body)
            // 주어 없이 3인칭에게 주기로 했으면 주는 사람은 나다.
            if giver == nil, let to = receiveWho(body), !firstPersonWords.contains(to) {
                return MarkInferenceResult(line: line, text: body, kind: .owe, rule: .oweCommit, who: nil)
            }
            return MarkInferenceResult(line: line, text: body, kind: .wait, rule: .waitGive, who: giver)
        }
        if firstPerson, body.contains("기로") {
            return MarkInferenceResult(line: line, text: body, kind: .owe, rule: .oweCommit, who: nil)
        }
        if matches(#"미정|정해야|결정\s*필요|(?<![A-Za-z])(?i:tbd)(?![A-Za-z])"#, body) {
            return MarkInferenceResult(line: line, text: body, kind: .question, rule: .questionUndecided, who: nil)
        }
        return MarkInferenceResult(line: line, text: body, kind: .decision, rule: .decisionDefault, who: nil)
    }

    // MARK: 호출어

    /// 전사 세그먼트에서 "물길, 내가 할 것: …" 발화를 후보로 뽑는다.
    /// - Parameter tailWindow: 녹음 끝(max t1)에서 이만큼 안쪽과 겹치는 세그먼트만 본다. nil 이면 전체.
    public static func voiceCandidates(_ segments: [MarkInferenceSegment],
                                       tailWindow: TimeInterval? = 90) -> [MarkInferenceVoiceCandidate] {
        let valid = segments.indices.filter { segments[$0].t0.isFinite && segments[$0].t1.isFinite }
            .sorted { (segments[$0].t0, $0) < (segments[$1].t0, $1) }
        guard let end = valid.map({ segments[$0].t1 }).max() else { return [] }
        let minT = tailWindow.map { end - $0 } ?? -.infinity
        let inWindow = valid.filter { segments[$0].t1 >= minT }
        var out: [MarkInferenceVoiceCandidate] = []
        var seen = Set<String>()

        for (pos, idx) in inWindow.enumerated() {
            let text = segments[idx].text
            for hw in hotwordMatches(in: text) {
                // 다음 호출어 전까지가 이 발화다.
                let utterEnd = hotwordMatches(in: text).first(where: { $0.range.lowerBound >= hw.range.upperBound })?.range.lowerBound ?? text.endIndex
                let utter = String(text[hw.range.upperBound..<utterEnd])
                let parts = splitLabels(utter)
                guard !parts.isEmpty else { continue }
                for (i, part) in parts.enumerated() {
                    var body = cleanBody(part.body)
                    if body.isEmpty, i == parts.count - 1, pos + 1 < inWindow.count {
                        // Whisper가 호출어 뒤에서 세그먼트를 끊은 경우
                        let next = segments[inWindow[pos + 1]].text
                        let cut = hotwordMatches(in: next).first?.range.lowerBound ?? next.endIndex
                        body = cleanBody(String(next[next.startIndex..<cut]))
                    }
                    guard !body.isEmpty else { continue }
                    guard seen.insert("\(part.kind.rawValue)|\(body)").inserted else { continue }
                    let who = part.kind == .wait ? (arrowSplit(body)?.1 ?? receiveWho(body) ?? giveWho(body)) : nil
                    out.append(MarkInferenceVoiceCandidate(kind: part.kind, text: body, t0: segments[idx].t0, who: who,
                                                           label: part.label, hotword: hw.text, segmentIndex: idx))
                }
            }
        }
        return out
    }

    /// 텍스트가 호출어로 시작하는지(앞 공백 무시). UI·테스트용.
    public static func startsWithHotword(_ text: String) -> Bool {
        hotwordMatches(in: text).first?.range.lowerBound == text.firstIndex(where: { !$0.isWhitespace })
    }

    // MARK: 내부 — 라벨

    private static let labelTable: [(pattern: String, kind: MarkKind)] = [
        (#"내가\s*할\s*(?:것|거)"#, .owe),
        (#"할\s*(?:것|거)"#, .owe),
        (#"받을\s*(?:것|거)"#, .wait),
        (#"기다리는\s*(?:것|거)"#, .wait),
        (#"정한\s*(?:것|거)"#, .decision),
        (#"미정"#, .question),
    ]

    private static func typedLabel(_ s: String) -> (MarkKind, String)? {
        for (p, kind) in labelTable {
            if let m = firstMatch("^(?:" + p + #")\s*[:：]\s*"#, s) {
                return (kind, String(s[m.range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private struct LabelPart { let kind: MarkKind; let label: String; let body: String }

    /// 호출어 직후 발화를 라벨 단위로 자른다. 첫 라벨은 맨 앞에 있어야 한다.
    private static func splitLabels(_ utter: String) -> [LabelPart] {
        let alt = labelTable.map(\.pattern).joined(separator: "|")
        let head = #"^\s*("# + alt + #")(?:은|는)?(?![가-힣])\s*[:：,，]?\s*"#
        guard let first = firstMatch(head, utter) else { return [] }
        // 이어지는 라벨은 문장부호 뒤에서만 인정한다("~해야 할 것 같아" 오분할 방지).
        let cont = #"[.。!?,，]\s*("# + alt + #")(?:은|는)?(?![가-힣])\s*[:：,，]?\s*"#
        var starts: [(label: String, labelEnd: String.Index, cutAt: String.Index)] = [
            (String(utter[first.groups[0]]), first.range.upperBound, utter.startIndex)
        ]
        var searchFrom = first.range.upperBound
        while let m = firstMatch(cont, utter, from: searchFrom) {
            starts.append((String(utter[m.groups[0]]), m.range.upperBound, m.range.lowerBound))
            searchFrom = m.range.upperBound
        }
        var parts: [LabelPart] = []
        for (i, s) in starts.enumerated() {
            let endIdx = i + 1 < starts.count ? starts[i + 1].cutAt : utter.endIndex
            let body = s.labelEnd <= endIdx ? String(utter[s.labelEnd..<endIdx]) : ""
            parts.append(LabelPart(kind: kindForLabel(s.label), label: s.label, body: body))
        }
        return parts
    }

    private static func kindForLabel(_ label: String) -> MarkKind {
        for (p, kind) in labelTable where matches("^(?:" + p + ")$", label) { return kind }
        return .decision
    }

    // MARK: 내부 — 호출어

    private struct Hit { let range: Range<String.Index>; let text: String }

    private static func hotwordMatches(in s: String) -> [Hit] {
        // 앞은 단어 경계, 뒤는 '이' 같은 조사가 붙지 않아야 호출로 본다.
        let p = #"(?:^|(?<=[\s.,!?。，、…"'“‘]))(?:물\s?길|무길)(?:\s?[아야])?(?![가-힣])\s*[,，、.!]?\s*"#
        return allMatches(p, s).map { Hit(range: $0.range, text: String(s[$0.range]).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))) }
    }

    // MARK: 내부 — 약속·주어·상대

    /// 받침 ㄹ + 게 가 부사형인 형용사 어간(단어 전체가 이것일 때만). "맡길게"는 약속이라 접미 비교를 하지 않는다.
    private static let adverbialStems: Set<String> = ["길", "멀", "둥글", "가늘", "힘들", "낯설", "거칠", "드물", "기다랗"]
    private static let firstPersonWords: Set<String> = ["나", "내", "저", "제"]

    private static func hasPromise(_ s: String) -> Bool {
        // 추측·바람·응답의 겠은 약속이 아니다.
        if matches(#"(?<!좋|알|같|싶|있|없|모르|되|괜찮|어렵|힘들|맞|비싸|늦)겠(?:습니다|어요|음)"#, s) { return true }
        let chars = Array(s)
        for i in 0..<chars.count where i + 1 < chars.count {
            guard hasRieulFinal(chars[i]), chars[i + 1] == "게" || chars[i + 1] == "께" else { continue }
            var w = i
            while w > 0, !chars[w - 1].isWhitespace { w -= 1 }
            if adverbialStems.contains(String(chars[w...i])) { continue }
            var j = i + 2
            if j < chars.count, chars[j] == "요" { j += 1 }
            if j >= chars.count { return true }
            let c = chars[j]
            if isHangulSyllable(c) { continue } // "할게임" 같은 다른 단어
            // 다음 단어가 되/하 계열이면 "알게 됐다"류 서술이다.
            var k = j
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            if k < chars.count, "되돼됐된하한해했".contains(chars[k]) { continue }
            return true
        }
        return false
    }

    private static func hasFirstPersonSubject(_ s: String) -> Bool {
        matches(#"(?:^|\s)(?:내가|제가|나는|저는|나도|저도)(?:\s|$)"#, s)
    }

    private static func receiveWho(_ s: String) -> String? {
        for m in allMatches(#"(?:^|(?<=\s))(\S+?)(?:한테서|에게서|으로부터|로부터|한테|에게|께)(?=\s|$|[.,])"#, s) {
            let name = String(s[m.groups[0]])
            if name == "함" || name.isEmpty { continue } // "함께"
            return name
        }
        return nil
    }

    private static func giveWho(_ s: String) -> String? {
        guard let m = firstMatch(#"^(\S+?)(?:\s+(?:씨|님))?(?:께서|이|가)\s"#, s) else { return nil }
        let name = String(s[m.groups[0]])
        return ["내", "제", "나", "저"].contains(name) ? nil : name
    }

    /// "본문 ← 이름 나머지" → ("본문 나머지", "이름")
    private static func arrowSplit(_ s: String) -> (String, String)? {
        guard let m = firstMatch(#"\s*(?:←|<-+)\s*"#, s) else { return nil }
        let before = String(s[..<m.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let after = String(s[m.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let tokens = after.split(separator: " ", maxSplits: 1).map(String.init)
        guard let rawWho = tokens.first else { return nil }
        let who = trimmedTail(rawWho)
        guard !who.isEmpty else { return nil }
        let rest = tokens.count > 1 ? tokens[1] : ""
        var text = [before, rest].filter { !$0.isEmpty }.joined(separator: " ")
        if text.isEmpty { text = who }
        return (text, who)
    }

    // MARK: 내부 — 문자열

    private static func isHangulSyllable(_ c: Character) -> Bool {
        guard let u = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return (0xAC00...0xD7A3).contains(u.value)
    }

    private static func hasRieulFinal(_ c: Character) -> Bool {
        guard isHangulSyllable(c), let u = c.unicodeScalars.first else { return false }
        return (u.value - 0xAC00) % 28 == 8
    }

    private static func collapseSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func stripBullet(_ s: String) -> String {
        guard let m = firstMatch(#"^(?:(?:[-*•·▪◦‣]|\d+[.)])(?:\s+|$))?(?:\[[ xX]?\]\s*)?"#, s) else { return s }
        return String(s[m.range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// 끝의 닫는 따옴표·괄호·공백을 뗀다(물음표 판정용).
    private static func trimmedTail(_ s: String) -> String {
        var t = Substring(s)
        while let l = t.last, l.isWhitespace || "\"'”’)]」』.,".contains(l) { t = t.dropLast() }
        return String(t)
    }

    private static func cleanBody(_ s: String) -> String {
        var t = Substring(collapseSpaces(s))
        while let l = t.last, ".。,，!、…".contains(l) || l.isWhitespace { t = t.dropLast() }
        while let f = t.first, ",，:：".contains(f) || f.isWhitespace { t = t.dropFirst() }
        return String(t)
    }

    private struct RegexMatch { let range: Range<String.Index>; let groups: [Range<String.Index>] }

    private static func regex(_ p: String) -> NSRegularExpression {
        // 패턴은 전부 이 파일의 상수라 실패하면 프로그래머 오류다.
        try! NSRegularExpression(pattern: p)
    }

    private static func convert(_ r: NSTextCheckingResult, in s: String) -> RegexMatch? {
        guard let whole = Range(r.range, in: s) else { return nil }
        var groups: [Range<String.Index>] = []
        if r.numberOfRanges > 1 {
            for g in 1..<r.numberOfRanges {
                let nr = r.range(at: g)
                if nr.location != NSNotFound, let gr = Range(nr, in: s) { groups.append(gr) }
            }
        }
        return RegexMatch(range: whole, groups: groups)
    }

    private static func firstMatch(_ p: String, _ s: String, from: String.Index? = nil) -> RegexMatch? {
        let start = from ?? s.startIndex
        let ns = NSRange(start..<s.endIndex, in: s)
        guard let r = regex(p).firstMatch(in: s, range: ns) else { return nil }
        return convert(r, in: s)
    }

    private static func allMatches(_ p: String, _ s: String) -> [RegexMatch] {
        regex(p).matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { convert($0, in: s) }
    }

    private static func matches(_ p: String, _ s: String) -> Bool { firstMatch(p, s) != nil }
}
