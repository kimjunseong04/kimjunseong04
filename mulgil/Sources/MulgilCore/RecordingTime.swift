import Foundation

/// m4a `creation_time`이 무엇을 뜻하는지. 기기마다 달라서 D0-2 결과를 설정으로 받는다(§5.0-2).
public enum CreationTimeMeaning: String, Codable, Sendable, CaseIterable {
    /// 녹음 시작 시각 → 그대로 시작으로 쓴다
    case recordingStart
    /// 저장(종료) 시각 → `creation_time − duration`
    case savedAt
    /// 0·기본값만 나오는 기기 → 쓰지 않고 `mtime − duration`
    case unusable
}

/// 녹음 시작 시각을 어떤 규칙으로 얻었는지. Capture.recorded_at_source 로 기록된다(§4).
public enum RecordingTimeSource: String, Codable, Sendable, CaseIterable {
    case creationTime = "creation_time"
    case creationTimeMinusDuration = "creation_time-duration"
    case modificationTimeMinusDuration = "mtime-duration"
    case modificationTime = "mtime"
}

/// creation_time 을 버린 이유. 기기별 이상치 패턴을 로그로 모으려고 남긴다.
public enum CreationTimeRejection: String, Codable, Sendable, CaseIterable {
    case missing
    /// 1904(mp4 기준점)·1970(0) 같은 기본값
    case placeholderEpoch
    case inFuture
    /// 수정 시각보다 늦게 만들어졌다는 모순
    case afterModification
    /// creation + duration 이 수정 시각보다 늦음. 저장 시각 기기를 '시작'으로 잘못 설정한 신호
    case endsAfterModification
    /// mtime − duration 과 6시간 이상 차이(시간대 버그 등)
    case disagreesWithModification
    /// 설정이 `.unusable`
    case ignoredBySetting
}

/// 이상치 판정 기준. 기본값은 설계 §5.1·§5.0-2 를 따른다.
public struct RecordingTimeRules: Hashable, Sendable {
    public var maxDisagreement: TimeInterval
    /// 기기 시계 오차 허용(미래·수정시각 비교)
    public var clockSkew: TimeInterval
    /// 이보다 이른 creation_time 은 기본값으로 본다
    public var earliestPlausible: Date

    public init(maxDisagreement: TimeInterval = 6 * 3600,
                clockSkew: TimeInterval = 120,
                earliestPlausible: Date = Date(timeIntervalSince1970: 946_684_800)) { // 2000-01-01Z
        self.maxDisagreement = maxDisagreement
        self.clockSkew = clockSkew
        self.earliestPlausible = earliestPlausible
    }

    public static let `default` = RecordingTimeRules()
}

/// 결정된 녹음 구간 R.
public struct RecordingSpan: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let source: RecordingTimeSource
    /// creation_time 을 쓰지 않았다면 그 이유
    public let rejection: CreationTimeRejection?

    public init(start: Date, end: Date, source: RecordingTimeSource, rejection: CreationTimeRejection?) {
        self.start = start; self.end = max(start, end); self.source = source; self.rejection = rejection
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var interval: DateInterval { DateInterval(start: start, end: end) }
}

public enum RecordingTime {
    /// creation_time > mtime − duration > mtime 순서로 시작 시각을 정한다(§5.1). 파일명은 보지 않는다.
    /// - Parameter now: 미래 판정 기준. 테스트 결정론을 위해 주입한다.
    public static func resolve(_ file: RecordingFile,
                               meaning: CreationTimeMeaning = .recordingStart,
                               now: Date,
                               rules: RecordingTimeRules = .default) -> RecordingSpan {
        // 일시정지·손상으로 duration 이 이상하면 0으로 보고 mtime 단독 규칙으로 떨어진다.
        let duration = (file.duration.isFinite && file.duration > 0) ? file.duration : 0
        let mtime = file.modificationTime
        let fallbackStart = mtime.addingTimeInterval(-duration)

        switch evaluate(file.creationTime, meaning: meaning, duration: duration,
                        mtime: mtime, fallbackStart: fallbackStart, now: now, rules: rules) {
        case .success(let (start, source)):
            return RecordingSpan(start: start, end: start.addingTimeInterval(duration), source: source, rejection: nil)
        case .failure(let why):
            let source: RecordingTimeSource = duration > 0 ? .modificationTimeMinusDuration : .modificationTime
            return RecordingSpan(start: fallbackStart, end: mtime, source: source, rejection: why.reason)
        }
    }

    private struct Rejected: Error { let reason: CreationTimeRejection }

    private static func evaluate(_ creation: Date?, meaning: CreationTimeMeaning, duration: TimeInterval,
                                 mtime: Date, fallbackStart: Date, now: Date,
                                 rules: RecordingTimeRules) -> Result<(Date, RecordingTimeSource), Rejected> {
        if meaning == .unusable { return .failure(Rejected(reason: .ignoredBySetting)) }
        guard let creation else { return .failure(Rejected(reason: .missing)) }
        if creation < rules.earliestPlausible { return .failure(Rejected(reason: .placeholderEpoch)) }
        if creation > now.addingTimeInterval(rules.clockSkew) { return .failure(Rejected(reason: .inFuture)) }
        if creation > mtime.addingTimeInterval(rules.clockSkew) { return .failure(Rejected(reason: .afterModification)) }

        let start: Date
        let source: RecordingTimeSource
        switch meaning {
        case .recordingStart:
            // 녹음 끝은 파일 기록(mtime)보다 늦을 수 없다. 늦으면 creation 이 사실 저장 시각이다.
            if creation.addingTimeInterval(duration) > mtime.addingTimeInterval(rules.clockSkew) {
                return .failure(Rejected(reason: .endsAfterModification))
            }
            start = creation; source = .creationTime
        case .savedAt: start = creation.addingTimeInterval(-duration); source = .creationTimeMinusDuration
        case .unusable: return .failure(Rejected(reason: .ignoredBySetting))
        }
        if abs(start.timeIntervalSince(fallbackStart)) >= rules.maxDisagreement {
            return .failure(Rejected(reason: .disagreesWithModification))
        }
        return .success((start, source))
    }
}
