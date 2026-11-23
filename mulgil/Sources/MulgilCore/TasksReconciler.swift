import Foundation

// MARK: - Google Tasks 항목

public enum TasksItemStatus: Hashable, Sendable {
    case needsAction
    case completed
    /// 문서에 없는 값. 모르는 상태로 Mark를 바꾸지 않기 위해 따로 둔다.
    case unknown(String)

    public init(raw: String) {
        switch raw {
        case "needsAction": self = .needsAction
        case "completed": self = .completed
        default: self = .unknown(raw)
        }
    }

    public var raw: String {
        switch self {
        case .needsAction: "needsAction"
        case .completed: "completed"
        case .unknown(let s): s
        }
    }
}

/// `tasks.list` 응답의 항목 한 개. 필요한 필드만 읽는다.
public struct TasksItem: Decodable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let status: TasksItemStatus
    public let deleted: Bool
    public let hidden: Bool
    /// 날짜만 의미가 있다(API가 시간을 버린다).
    public let due: Date?
    public let updated: Date?
    public let notes: String?

    public init(id: String, title: String = "", status: TasksItemStatus = .needsAction, deleted: Bool = false,
                hidden: Bool = false, due: Date? = nil, updated: Date? = nil, notes: String? = nil) {
        self.id = id; self.title = title; self.status = status; self.deleted = deleted
        self.hidden = hidden; self.due = due; self.updated = updated; self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, title, status, deleted, hidden, due, updated, notes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = TasksItemStatus(raw: try c.decodeIfPresent(String.self, forKey: .status) ?? "needsAction")
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        due = try Self.date(c, .due)
        updated = try Self.date(c, .updated)
    }

    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let d = TasksRFC3339.parse(s) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "RFC3339 아님: \(s)")
        }
        return d
    }
}

/// `tasks.list` 응답 한 페이지.
public struct TasksListPage: Decodable, Sendable {
    public let items: [TasksItem]
    public let nextPageToken: String?

    private enum CodingKeys: String, CodingKey { case items, nextPageToken }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 빈 목록이면 items 키 자체가 없다.
        items = try c.decodeIfPresent([TasksItem].self, forKey: .items) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// RFC3339 파싱·표기. 포매터는 Sendable이 아니라 호출마다 만든다.
public enum TasksRFC3339 {
    public static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Tasks due 표기: 서울 기준 날짜를 그 날 자정 UTC로 쓴다(API가 시간을 무시하므로 날짜가 밀리지 않게).
    public static func dueString(for date: Date, calendar: Calendar = Seoul.calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        // String(format:)의 %d와 Int 조합은 플랫폼마다 다르게 읽힐 수 있어 직접 채운다.
        func pad(_ v: Int, _ n: Int) -> String { let s = String(v); return String(repeating: "0", count: max(0, n - s.count)) + s }
        return "\(pad(p.year!, 4))-\(pad(p.month!, 2))-\(pad(p.day!, 2))T00:00:00.000Z"
    }

    /// updatedMin 등에 쓰는 일반 표기.
    public static func string(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.string(from: date)
    }
}

// MARK: - 로컬 Mark

public enum TasksMarkState: String, Codable, Sendable {
    case candidate, open, done, dropped
}

/// Reconciler가 보는 로컬 Mark의 단면.
public struct TasksMarkSnapshot: Hashable, Sendable {
    public let id: String
    public let kind: MarkKind
    public let text: String
    public let due: Due?
    public let state: TasksMarkState
    /// 로컬 매핑 테이블의 Google Tasks 항목 id.
    public let taskId: String?
    /// 그 항목을 만들 때 쓴 due 문자열. 기한 변경 감지용.
    public let exportedDue: String?

    public init(id: String, kind: MarkKind = .owe, text: String, due: Due? = nil, state: TasksMarkState = .open,
                taskId: String? = nil, exportedDue: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.due = due
        self.state = state; self.taskId = taskId; self.exportedDue = exportedDue
    }

    /// Tasks로 내보내는 대상: 확정된 할 것만(§6.3).
    public var isExportable: Bool { kind == .owe && state == .open }
}

// MARK: - 결과

public struct TasksMarkStateChange: Hashable, Sendable {
    public enum Reason: String, Sendable { case completedInTasks, deletedInTasks }
    public let markId: String
    public let taskId: String
    public let from: TasksMarkState
    public let to: TasksMarkState
    public let reason: Reason
}

/// `tasks.insert` 요청 본문.
public struct TasksInsertBody: Encodable, Hashable, Sendable {
    public let title: String
    public let notes: String
    public let due: String?
    public let status: String
}

public struct TasksInsert: Hashable, Sendable {
    public let markId: String
    public let body: TasksInsertBody
    /// 이 항목 대신 지울 옛 항목(기한 변경 시 재생성). nil이면 새로 만들기만.
    public let replacesTaskId: String?
}

/// notes 표식으로 찾은 항목을 로컬 매핑에 다시 붙인다(insert 뒤 로컬 저장 전에 죽은 경우).
public struct TasksAdoption: Hashable, Sendable {
    public let markId: String
    public let taskId: String
    /// 그 항목의 due(우리가 쓴 표기). 호출자가 exportedDue로 저장해야 다음 폴링에서 재생성을 반복하지 않는다.
    public let exportedDue: String?

    public init(markId: String, taskId: String, exportedDue: String? = nil) {
        self.markId = markId; self.taskId = taskId; self.exportedDue = exportedDue
    }
}

public struct TasksReconciliation: Sendable {
    public var stateChanges: [TasksMarkStateChange] = []
    public var adoptions: [TasksAdoption] = []
    public var inserts: [TasksInsert] = []
    /// 다음 폴링의 updatedMin. 받은 항목 중 가장 늦은 updated.
    public var latestUpdated: Date?
}

// MARK: - Reconciler

/// Google Tasks "물길" 목록과 로컬 Mark를 맞춘다(§6.3). 결정론, 부수효과 없음.
/// - 회수: completed → done, deleted → dropped. 제목·기한 수정은 회수하지 않는다.
/// - 내보내기: 확정 owe 중 Task가 없는 것의 insert 본문.
public struct TasksReconciler: Sendable {
    /// notes 마지막 줄 표식의 접두어.
    public static let notesMarker = "mulgil:"
    public var calendar: Calendar

    public init(calendar: Calendar = Seoul.calendar) { self.calendar = calendar }

    public func reconcile(remote: [TasksItem], marks: [TasksMarkSnapshot]) -> TasksReconciliation {
        var result = TasksReconciliation()

        // 페이지가 겹쳐 같은 id가 두 번 오면 updated가 늦은 쪽을 쓴다.
        var byId: [String: TasksItem] = [:]
        for item in remote {
            if let old = byId[item.id], (old.updated ?? .distantPast) > (item.updated ?? .distantPast) { continue }
            byId[item.id] = item
        }
        result.latestUpdated = byId.values.compactMap(\.updated).max()

        // notes 표식 → 항목. 같은 Mark에 여럿이면 지워지지 않은 것, 그다음 id 순.
        var byMarker: [String: TasksItem] = [:]
        for item in byId.values.sorted(by: { $0.id < $1.id }) {
            guard let mid = Self.markId(fromNotes: item.notes) else { continue }
            if let cur = byMarker[mid], !cur.deleted || item.deleted { continue }
            byMarker[mid] = item
        }

        // 같은 Mark가 두 번 들어오면 insert가 두 번 나가 Tasks에 중복이 생긴다. 먼저 온 것만 쓴다.
        var seenMarks = Set<String>()
        let uniqueMarks = marks.filter { seenMarks.insert($0.id).inserted }

        for mark in uniqueMarks.sorted(by: { $0.id < $1.id }) {
            var taskId = mark.taskId
            var exported = mark.exportedDue
            if taskId == nil, mark.kind == .owe, let found = byMarker[mark.id], !found.deleted {
                // 로컬 매핑이 없는데 표식이 있는 항목: 다시 만들면 중복이 생기므로 입양한다.
                let due = Self.utcDueString(found.due)
                result.adoptions.append(TasksAdoption(markId: mark.id, taskId: found.id, exportedDue: due))
                taskId = found.id
                // 이번 회차에는 재생성 비교를 하지 않는다: 그사이 폰에서 옮긴 날짜를 되돌리지 않게.
            } else if let tid = taskId, let mapped = byId[tid], mapped.deleted, mapped.status != .completed,
                      mark.kind == .owe, let live = byMarker[mark.id], !live.deleted, live.id != tid {
                // 기한 변경 재생성(새로 만들고 옛 것 지우기) 뒤 로컬 저장 전에 죽은 경우:
                // 옛 항목의 삭제는 우리가 한 것이므로 dropped가 아니라 새 항목으로 다시 붙인다.
                let due = Self.utcDueString(live.due)
                result.adoptions.append(TasksAdoption(markId: mark.id, taskId: live.id, exportedDue: due))
                taskId = live.id
                // 방금 우리가 만든 항목이므로 그 due가 곧 우리가 쓴 값이다. 옛 값과 비교하면 재생성이 또 나간다.
                exported = due
            }

            // 회수. 매핑은 로컬 task_id만 믿는다: 기한 변경으로 우리가 지운 옛 항목이 표식으로 Mark를 dropped시키지 않게.
            if let tid = taskId, let item = byId[tid], mark.state == .open, mark.kind == .owe {
                if let to = Self.recoveredState(item) {
                    result.stateChanges.append(TasksMarkStateChange(
                        markId: mark.id, taskId: tid, from: mark.state, to: to,
                        reason: to == .done ? .completedInTasks : .deletedInTasks))
                    continue
                }
            }

            guard mark.isExportable else { continue }
            let body = insertBody(for: mark)
            // 제목 없는 할 것은 폰에서 빈 줄로만 보인다. "무엇"이 없는 Mark는 내보내지 않는다.
            guard !body.title.isEmpty else { continue }
            if taskId == nil {
                result.inserts.append(TasksInsert(markId: mark.id, body: body, replacesTaskId: nil))
            } else if let tid = taskId, let exported, exported != (body.due ?? "") {
                // 로컬 기한이 바뀐 경우. due는 다시 PATCH하지 않는다(issuetracker 170143566) → 지우고 새로 만든다.
                // 비교 기준은 우리가 쓴 값뿐이다: 원격 due와 비교하면 폰에서 옮긴 날짜를 되돌려 버린다.
                result.inserts.append(TasksInsert(markId: mark.id, body: body, replacesTaskId: tid))
            }
        }
        return result
    }

    /// completed가 deleted보다 우선한다: 끝낸 뒤 목록에서 치운 것은 버린 게 아니라 한 일이다.
    static func recoveredState(_ item: TasksItem) -> TasksMarkState? {
        if item.status == .completed { return .done }
        if item.deleted { return .dropped }
        return nil
    }

    public func insertBody(for mark: TasksMarkSnapshot) -> TasksInsertBody {
        TasksInsertBody(
            title: mark.text.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: Self.notes(forMarkId: mark.id),
            due: mark.due.map { TasksRFC3339.dueString(for: $0.date, calendar: calendar) },
            status: "needsAction")
    }

    /// 원격 due(자정 UTC)를 우리가 쓰는 표기로 되돌린다. 날짜는 UTC 기준이어야 하루 밀리지 않는다.
    static func utcDueString(_ due: Date?) -> String? {
        guard let due else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return TasksRFC3339.dueString(for: due, calendar: utc)
    }

    public static func notes(forMarkId id: String) -> String { "\(notesMarker)\(id)" }

    /// notes 마지막 표식 줄에서 Mark id를 읽는다. 사람이 notes에 글을 더해도 표식 줄만 본다.
    public static func markId(fromNotes notes: String?) -> String? {
        guard let notes else { return nil }
        for line in notes.split(whereSeparator: \.isNewline).reversed() {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix(notesMarker) {
                let id = String(l.dropFirst(notesMarker.count)).trimmingCharacters(in: .whitespaces)
                return id.isEmpty ? nil : id
            }
        }
        return nil
    }
}
