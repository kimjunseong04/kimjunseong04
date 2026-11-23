import Foundation

// MARK: - 결과 타입

/// 경보 단계. red = 알림 + 아이콘, yellow = 팝오버 맨 위 한 줄(알림 없음), info = 팝오버 첫 화면 한 줄.
public enum HealthLevel: Int, Comparable, Codable, Sendable, CaseIterable {
    case red = 0, yellow = 1, info = 2

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 알림을 띄우는 단계인가. yellow·info까지 알리면 오경보 피로로 진짜 고장도 무시하게 된다.
    public var notifies: Bool { self == .red }
}

/// 고장 종류. 선언 순서가 같은 단계 안의 표시 순서다(원인에 가까운 것 먼저).
public enum HealthCode: String, Codable, Sendable, CaseIterable {
    case macSyncthingDown
    case inboxMissing
    case googleInvalidGrant
    case phoneDisconnected
    case phoneFolderBroken
    case phoneNoArrival
    case diskLow
    case speechAssetMissing
    case sourcePathMissing
    case googleSyncStale
    case recordingsMissing
    case yesterdayNoRecordings
    case folderAccessLost
    case notInCalendar
    case transcriptionFailed
}

/// 문구 끝의 행동 1개.
public enum HealthAction: String, Codable, Sendable {
    case showGuide            // 확인 방법
    case checkPhonePermission // 폰 권한 확인
    case confirmRecordings    // 녹음했다면 확인
    case restartReceiver      // 다시 켜기
    case recreateInbox        // 폴더 다시 만들기
    case signInAgain          // 다시 로그인
    case checkNetwork         // 연결 확인
    case openStorage          // 저장 공간
    case playRecording        // 재생
    case redownloadAsset      // 다시 받기
    case locateSource         // 위치 확인
    case grantFolderAccess    // 권한 다시 주기
    case checkCalendarAccount // 폰 캘린더 저장 계정 확인
    case none
}

public struct HealthIssue: Hashable, Codable, Sendable {
    public let level: HealthLevel
    public let code: HealthCode
    /// 한 줄 문구(§7.11).
    public let message: String
    public let action: HealthAction
    /// 같은 code가 대상별로 여러 개일 수 있는 경우의 대상(경로, 녹음 id 등).
    public let subject: String?

    public init(level: HealthLevel, code: HealthCode, message: String, action: HealthAction, subject: String? = nil) {
        self.level = level; self.code = code; self.message = message; self.action = action; self.subject = subject
    }

    /// 중복 판정 키. 문구가 바뀌어도(개수 치환 등) 같은 문제는 같은 키다.
    public var key: String { subject.map { "\(code.rawValue)|\($0)" } ?? code.rawValue }
}

// MARK: - 입력

public enum HealthPhonePath: String, Codable, Sendable {
    /// G1: Syncthing-Fork. 연결 상태 API가 있다.
    case syncthing
    /// G2: FolderSync → SFTP. 연결 상태 API가 없어 마지막 수신 시각으로 본다.
    case folderSync
}

public enum HealthGoogleTokenState: String, Codable, Sendable {
    case ok
    case invalidGrant
    case networkError
}

public enum HealthSpeechAssetState: String, Codable, Sendable {
    /// SpeechTranscriber를 쓰지 않음(mlx-whisper 등) 또는 3단계 전.
    case notUsed
    case installed
    case missing
}

/// 한 번의 점검에 쓰는 관측값. 모르는 값은 nil로 두면 그 규칙은 건너뛴다(모르는 걸로 경보하지 않는다).
public struct HealthSnapshot: Sendable {
    /// 폰 경로가 생긴 시각. nil이면 폰 경로 감시를 켜지 않는다(P6: 경로가 생긴 날부터).
    public var phonePathEstablishedAt: Date?
    public var phonePath: HealthPhonePath

    /// 맥 Syncthing 프로세스(REST 응답) 생존. nil = 모름.
    public var macSyncthingRunning: Bool?
    /// `~/Mulgil/inbox/phone` 존재 여부. nil = 모름.
    public var inboxPhoneExists: Bool?

    /// `/rest/system/connections`의 connected.
    public var phoneConnected: Bool?
    /// 마지막으로 connected=true를 본 시각(물길이 기록).
    public var phoneLastConnectedAt: Date?
    /// `/rest/stats/device`의 lastSeen. 보조로만 쓴다.
    public var phoneLastSeen: Date?

    /// `/rest/db/status`의 state, error.
    public var folderState: String?
    public var folderError: String?
    /// 폰 쪽 폴더 완료율(0~100)과 그 값이 된 시각.
    public var phoneFolderCompletion: Double?
    public var phoneFolderCompletionSince: Date?
    /// 폰이 광고하는 폴더 파일 수: 이번 관측과 직전 관측.
    public var phoneFolderFileCount: Int?
    public var phoneFolderFileCountPrevious: Int?

    /// 마지막 녹음 도착 시각.
    public var lastRecordingArrivalAt: Date?
    /// 최근 N일 녹음의 녹음 시각.
    public var recentRecordings: [Date]
    /// 과거 평균 녹음 빈도(주당). 0이면 녹음 습관이 없는 사람이라 "녹음 없음" 조합을 끈다.
    public var baselineRecordingsPerWeek: Double
    /// 최근 끝난 수업·회의(녹음 대상 종류)의 종료 시각.
    public var endedMeetings: [Date]

    public var googleToken: HealthGoogleTokenState
    public var lastSuccessfulGoogleSyncAt: Date?

    /// `~/Mulgil` 볼륨 여유 바이트.
    public var diskFreeBytes: Int64?
    public var speechAsset: HealthSpeechAssetState
    /// 사라진 원본 경로들.
    public var missingSourcePaths: [String]
    /// 접근 권한을 잃은 폴더들(Downloads, Documents).
    public var lostFolderAccess: [String]
    /// 전사 실패한 녹음 id들.
    public var failedTranscriptions: [String]
    /// 이번 주 "캘린더에 없음" 건수.
    public var notInCalendarThisWeek: Int

    public init(
        phonePathEstablishedAt: Date? = nil,
        phonePath: HealthPhonePath = .syncthing,
        macSyncthingRunning: Bool? = nil,
        inboxPhoneExists: Bool? = nil,
        phoneConnected: Bool? = nil,
        phoneLastConnectedAt: Date? = nil,
        phoneLastSeen: Date? = nil,
        folderState: String? = nil,
        folderError: String? = nil,
        phoneFolderCompletion: Double? = nil,
        phoneFolderCompletionSince: Date? = nil,
        phoneFolderFileCount: Int? = nil,
        phoneFolderFileCountPrevious: Int? = nil,
        lastRecordingArrivalAt: Date? = nil,
        recentRecordings: [Date] = [],
        baselineRecordingsPerWeek: Double = 0,
        endedMeetings: [Date] = [],
        googleToken: HealthGoogleTokenState = .ok,
        lastSuccessfulGoogleSyncAt: Date? = nil,
        diskFreeBytes: Int64? = nil,
        speechAsset: HealthSpeechAssetState = .notUsed,
        missingSourcePaths: [String] = [],
        lostFolderAccess: [String] = [],
        failedTranscriptions: [String] = [],
        notInCalendarThisWeek: Int = 0
    ) {
        self.phonePathEstablishedAt = phonePathEstablishedAt
        self.phonePath = phonePath
        self.macSyncthingRunning = macSyncthingRunning
        self.inboxPhoneExists = inboxPhoneExists
        self.phoneConnected = phoneConnected
        self.phoneLastConnectedAt = phoneLastConnectedAt
        self.phoneLastSeen = phoneLastSeen
        self.folderState = folderState
        self.folderError = folderError
        self.phoneFolderCompletion = phoneFolderCompletion
        self.phoneFolderCompletionSince = phoneFolderCompletionSince
        self.phoneFolderFileCount = phoneFolderFileCount
        self.phoneFolderFileCountPrevious = phoneFolderFileCountPrevious
        self.lastRecordingArrivalAt = lastRecordingArrivalAt
        self.recentRecordings = recentRecordings
        self.baselineRecordingsPerWeek = baselineRecordingsPerWeek
        self.endedMeetings = endedMeetings
        self.googleToken = googleToken
        self.lastSuccessfulGoogleSyncAt = lastSuccessfulGoogleSyncAt
        self.diskFreeBytes = diskFreeBytes
        self.speechAsset = speechAsset
        self.missingSourcePaths = missingSourcePaths
        self.lostFolderAccess = lostFolderAccess
        self.failedTranscriptions = failedTranscriptions
        self.notInCalendarThisWeek = notInCalendarThisWeek
    }
}

/// 임계값. 기본값은 설계 문서 값이고, 문서에 없는 것은 주석에 근거를 적는다.
public struct HealthThresholds: Sendable {
    /// 폰 미연결 경보(§9).
    public var phoneDisconnected: TimeInterval = 24 * 3600
    /// D0 3번에서 "집 Wi-Fi에서만 동기화"로 확정되면 true.
    public var homeWifiOnly: Bool = false
    public var phoneDisconnectedHomeWifiOnly: TimeInterval = 48 * 3600
    /// G2 마지막 수신(§7.11).
    public var phoneNoArrival: TimeInterval = 24 * 3600
    /// "수업·회의 N개 연속 종료 + 녹음 0"의 N(§7.11).
    public var missingRecordingMeetings: Int = 3
    /// 회의가 끝나고 녹음이 도착하기까지 기다리는 시간. 정지·저장·동기화 지연을 경보로 착각하지 않게.
    public var recordingArrivalGrace: TimeInterval = 3600
    /// 폰 폴더 완료율이 이 시간 동안 100 미만으로 멈춰 있으면 정체. 문서에 수치가 없어 D0 4번 실측 전 임시값.
    public var folderCompletionStall: TimeInterval = 6 * 3600
    /// 광고 파일 수가 이 비율 이상 줄면 경보. 한두 개는 사람이 폰에서 지운 것일 수 있다.
    public var fileCountDropRatio: Double = 0.5
    /// 이 상태 문자열이면 폴더 고장.
    public var brokenFolderStates: Set<String> = ["error", "stopped", "paused"]
    /// 디스크 여유 하한(§5.1, §9). macOS 표기와 같은 십진 GB.
    public var minDiskFreeBytes: Int64 = 10_000_000_000
    /// 네트워크 오류가 이어질 때 Google 동기화가 낡았다고 보는 시간. 문서에 없는 항목이라 보수적으로 하루.
    public var googleSyncStale: TimeInterval = 24 * 3600
    /// "캘린더에 없음" 주간 경고 기준(§7.11, §11-①).
    public var notInCalendarPerWeek: Int = 2
    /// "어제 끝난 수업·회의 N개 · 녹음 0" 정보 줄의 N(§9).
    public var yesterdayInfoMeetings: Int = 3

    public init() {}
}

// MARK: - 평가기

/// 경로 생존 신호 규칙 평가기(§9). 상태 없음, 같은 입력이면 같은 출력.
public struct HealthMonitor: Sendable {
    public var thresholds: HealthThresholds
    public var calendar: Calendar

    public init(thresholds: HealthThresholds = HealthThresholds(), calendar: Calendar = Seoul.calendar) {
        self.thresholds = thresholds
        self.calendar = calendar
    }

    /// 정상이면 빈 배열. 단계 → 원인 순으로 정렬하고 같은 key는 하나만 남긴다.
    public func evaluate(_ s: HealthSnapshot, now: Date) -> [HealthIssue] {
        var out: [HealthIssue] = []
        let t = thresholds

        // Google
        switch s.googleToken {
        case .invalidGrant:
            out.append(issue(.red, .googleInvalidGrant, "Google 연결이 끊겼어요 · 다시 로그인 ›", .signInAgain))
        case .networkError:
            if let last = s.lastSuccessfulGoogleSyncAt, now.timeIntervalSince(last) > t.googleSyncStale {
                out.append(issue(.yellow, .googleSyncStale, "Google 일정을 하루 넘게 받아 오지 못했어요 · 연결 확인 ›", .checkNetwork))
            }
        case .ok:
            break
        }

        out += phonePathIssues(s, now: now)

        // 맥 쪽(3단계 항목이지만 값이 들어오면 언제든 본다)
        if let free = s.diskFreeBytes, free < t.minDiskFreeBytes {
            out.append(issue(.red, .diskLow, "맥 저장 공간이 부족해 녹음을 받지 못할 수 있어요 ›", .openStorage))
        }
        if s.speechAsset == .missing {
            out.append(issue(.red, .speechAssetMissing, "한국어 음성 인식 파일이 사라졌어요 · 다시 받기 ›", .redownloadAsset))
        }
        for p in s.missingSourcePaths {
            out.append(issue(.red, .sourcePathMissing, "원본 녹음 위치를 찾을 수 없어요 · 위치 확인 ›", .locateSource, p))
        }
        for p in s.lostFolderAccess {
            out.append(issue(.info, .folderAccessLost, "폴더를 읽을 권한이 풀렸어요 · 권한 다시 주기 ›", .grantFolderAccess, p))
        }
        for id in s.failedTranscriptions {
            out.append(issue(.info, .transcriptionFailed, "이 녹음은 글로 바꾸지 못했어요 · 녹음은 그대로 있어요 ‹재생›", .playRecording, id))
        }
        if s.notInCalendarThisWeek >= t.notInCalendarPerWeek {
            out.append(issue(.info, .notInCalendar, "이 시각 일정이 Google에 없어요 · 폰 캘린더 저장 계정 확인 ›", .checkCalendarAccount))
        }

        return Self.normalize(out)
    }

    /// 이번 점검에서 새로 알림을 띄울 것. 이미 알린 key는 다시 알리지 않는다.
    /// 해결된 key를 지워야 재발 때 다시 알리므로, 호출자는 `active`를 다음 `alreadyNotified`로 쓴다.
    public static func notifications(for issues: [HealthIssue], alreadyNotified: Set<String>) -> (new: [HealthIssue], active: Set<String>) {
        let reds = issues.filter { $0.level.notifies }
        let active = Set(reds.map(\.key))
        return (reds.filter { !alreadyNotified.contains($0.key) }, active)
    }

    /// 정렬 + 중복 제거. 같은 key면 더 높은 단계 하나만 남긴다.
    public static func normalize(_ issues: [HealthIssue]) -> [HealthIssue] {
        let order = Dictionary(uniqueKeysWithValues: HealthCode.allCases.enumerated().map { ($1, $0) })
        let sorted = issues.sorted {
            if $0.level != $1.level { return $0.level < $1.level }
            let a = order[$0.code]!, b = order[$1.code]!
            if a != b { return a < b }
            return ($0.subject ?? "") < ($1.subject ?? "")
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.key).inserted }
    }

    // MARK: 폰 경로

    private func phonePathIssues(_ s: HealthSnapshot, now: Date) -> [HealthIssue] {
        guard let established = s.phonePathEstablishedAt else { return [] }
        let t = thresholds
        var out: [HealthIssue] = []

        // 받는 쪽이 죽으면 그 아래 신호(연결, 폴더, 녹음 수)는 전부 거짓이라 근본 원인 하나만 낸다.
        if s.phonePath == .syncthing, s.macSyncthingRunning == false {
            out.append(issue(.red, .macSyncthingDown, "맥에서 폰 녹음 받기가 멈췄어요 · 다시 켜기 ›", .restartReceiver))
            if s.inboxPhoneExists == false { out.append(inboxMissing()) }
            return out
        }
        if s.inboxPhoneExists == false {
            out.append(inboxMissing())
            return out
        }

        // 미래 시각(시계 어긋남, 1904 기본값 오해석 등)을 증거로 쓰면 경보가 영영 꺼지므로 버린다.
        let lastEvidence = [Self.past(s.lastRecordingArrivalAt, now), s.recentRecordings.filter { $0 <= now }.max()]
            .compactMap { $0 }.max()

        switch s.phonePath {
        case .syncthing:
            guard let connected = s.phoneConnected else { break }
            if !connected {
                // 경로가 생기기 전 기록(옛 기기·재설정)으로 첫날부터 경보하지 않게 established로 하한을 둔다.
                let seen = Self.past(s.phoneLastConnectedAt, now) ?? Self.past(s.phoneLastSeen, now) ?? established
                let since = max(seen, established)
                let limit = t.homeWifiOnly ? t.phoneDisconnectedHomeWifiOnly : t.phoneDisconnected
                if now.timeIntervalSince(since) > limit {
                    out.append(issue(.red, .phoneDisconnected, "폰과 하루 넘게 연결되지 않았어요 · 확인 방법 ›", .showGuide))
                }
                // 미연결이면 폴더·녹음 조합 신호는 의미가 없다.
                return out
            }
            if folderBroken(s, now: now) {
                out.append(issue(.red, .phoneFolderBroken, "폰은 연결됐는데 녹음 폴더를 못 읽고 있어요 · 폰 권한 확인 ›", .checkPhonePermission))
                return out
            }
            out += recordingComboIssues(s, lastEvidence: lastEvidence, established: established, now: now)

        case .folderSync:
            // G2는 연결 상태 API가 없어 마지막 수신이 유일한 생존 신호다(§5.3, §7.11).
            let since = lastEvidence ?? established
            if now.timeIntervalSince(since) > t.phoneNoArrival {
                out.append(issue(.red, .phoneNoArrival, "폰에서 마지막으로 받은 지 하루가 넘었어요 · 확인 방법 ›", .showGuide))
                return out
            }
            out += recordingComboIssues(s, lastEvidence: lastEvidence, established: established, now: now)
        }
        return out
    }

    private static func past(_ d: Date?, _ now: Date) -> Date? {
        guard let d, d <= now else { return nil }
        return d
    }

    private func inboxMissing() -> HealthIssue {
        issue(.red, .inboxMissing, "폰 녹음을 받는 폴더가 사라졌어요 · 폴더 다시 만들기 ›", .recreateInbox)
    }

    private func folderBroken(_ s: HealthSnapshot, now: Date) -> Bool {
        let t = thresholds
        if let st = s.folderState?.lowercased(), t.brokenFolderStates.contains(st) { return true }
        if let err = s.folderError, !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let c = s.phoneFolderCompletion, c < 100, let since = s.phoneFolderCompletionSince,
           now.timeIntervalSince(since) > t.folderCompletionStall { return true }
        if let cur = s.phoneFolderFileCount, let prev = s.phoneFolderFileCountPrevious, prev > 0, cur < prev {
            if cur == 0 || Double(prev - cur) / Double(prev) >= t.fileCountDropRatio { return true }
        }
        return false
    }

    /// "연결됨 + 녹음 0" 조합. 녹음 0 단독으로는 절대 부르지 않는다(호출자가 연결·폴더 정상을 확인한 뒤에만).
    private func recordingComboIssues(_ s: HealthSnapshot, lastEvidence: Date?, established: Date, now: Date) -> [HealthIssue] {
        let t = thresholds
        // 녹음 습관이 없는 사람에게 이 조합은 매번 오경보다.
        guard s.baselineRecordingsPerWeek > 0 else { return [] }

        let after = max(lastEvidence ?? established, established)
        let cutoff = now.addingTimeInterval(-t.recordingArrivalGrace)
        // 같은 회차가 두 캘린더에 걸려 중복으로 들어와도 녹음은 하나뿐이라 종료 시각 기준으로 한 번만 센다.
        let ended = Set(s.endedMeetings)
        let missed = ended.filter { $0 > after && $0 <= cutoff }.count
        if missed >= t.missingRecordingMeetings {
            return [issue(.yellow, .recordingsMissing,
                          "최근 수업·회의 \(t.missingRecordingMeetings)개에 녹음이 없어요. 녹음했다면 확인해 주세요 ›",
                          .confirmRecordings)]
        }

        // 정보 줄: 어제(서울) 끝난 수업·회의 N개인데 어제 녹음 0.
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        let range = yesterday..<today
        // 자정 직전에 끝난 회의는 녹음이 아직 오는 중일 수 있어 유예 시간을 똑같이 적용한다.
        let meetings = ended.filter { range.contains($0) && $0 > established && $0 <= cutoff }.count
        let recs = s.recentRecordings.filter { range.contains($0) }.count

        if meetings >= t.yesterdayInfoMeetings && recs == 0 {
            return [issue(.info, .yesterdayNoRecordings, "어제 끝난 수업·회의 \(meetings)개 · 녹음 0", .none)]
        }
        return []
    }

    private func issue(_ level: HealthLevel, _ code: HealthCode, _ message: String, _ action: HealthAction, _ subject: String? = nil) -> HealthIssue {
        HealthIssue(level: level, code: code, message: message, action: action, subject: subject)
    }
}
