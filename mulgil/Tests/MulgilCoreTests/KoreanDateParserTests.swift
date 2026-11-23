import Foundation
import Testing
@testable import MulgilCore

// 기준 시각: 2026-11-23(월) 14:00 KST. 이번 주 = 11/23~11/29, 다음 주 = 11/30~12/6.
private let baseNow: Date = Seoul.calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14, minute: 0))!
private let parser = KoreanDateParser(now: baseNow)

private func render(_ due: Due) -> String {
    let c = Seoul.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due.date)
    let d = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    return due.hasTime ? d + String(format: " %02d:%02d", c.hour!, c.minute!) : d
}

struct DateCase: Sendable, CustomStringConvertible {
    let text: String
    let expected: String
    let deadline: Bool
    let location: String?
    init(_ text: String, _ expected: String, deadline: Bool = false, location: String? = nil) {
        self.text = text; self.expected = expected; self.deadline = deadline; self.location = location
    }
    var description: String { text }
}

// 카톡·회의 회귀 세트 (설계 §5.7 "실제 카톡 문장 50개")
private let regression: [DateCase] = [
    DateCase("그럼 목요일 7시에 공학관에서 봬요", "2026-11-26 19:00", location: "공학관"),
    DateCase("내일 3시에 회의 어때?", "2026-11-24 15:00"),
    DateCase("모레 저녁에 밥 먹자", "2026-11-25 19:00"),
    DateCase("글피 오전 10시 면접 잡혔어", "2026-11-26 10:00"),
    DateCase("오늘 저녁 7시 반에 정문 앞에서 봐", "2026-11-23 19:30", location: "정문 앞"),
    DateCase("연사 리스트 금요일까지 공유할게", "2026-11-27", deadline: true),
    DateCase("다음 주 화요일 2시에 2차 미팅 해요", "2026-12-01 14:00"),
    DateCase("담주 수욜 저녁 어때요", "2026-12-02 19:00"),
    DateCase("보고서 11/27까지 제출", "2026-11-27", deadline: true),
    DateCase("11.30 회의 잡을게요", "2026-11-30"),
    DateCase("12월 3일 19:30 송년회 장소 공지합니다", "2026-12-03 19:30"),
    DateCase("27일에 발표 리허설해요", "2026-11-27"),
    DateCase("15일까지 회비 입금 부탁드려요", "2026-12-15", deadline: true),
    DateCase("3일 뒤에 다시 얘기하자", "2026-11-26"),
    DateCase("5일 후 마감이에요", "2026-11-28"),
    DateCase("7시에 봐", "2026-11-23 19:00"),
    DateCase("1시에 보자", "2026-11-24 13:00"),
    DateCase("11시까지 과제 내야 됨", "2026-11-23 23:00", deadline: true),
    DateCase("오전 11시 수업 끝나고 보자", "2026-11-24 11:00"),
    DateCase("월요일 아침 9시 스탠드업", "2026-11-30 09:00"),
    DateCase("월요일 회의 잊지 마", "2026-11-23"),
    DateCase("수요일 오후 4시 반 스터디", "2026-11-25 16:30"),
    DateCase("토욜 점심 같이 먹을래?", "2026-11-28 12:00"),
    DateCase("목 7시 공학관", "2026-11-26 19:00"),
    DateCase("이번 주 일요일 밤 10시까지 제출", "2026-11-29 22:00", deadline: true),
    DateCase("다음 주 금요일 정오에 발표", "2026-12-04 12:00"),
    DateCase("오늘 자정까지 업로드해 주세요", "2026-11-24 00:00", deadline: true),
    DateCase("내일 새벽 2시에 서버 점검 있어요", "2026-11-24 02:00"),
    DateCase("오늘 밤 12시까지 보내줘", "2026-11-24 00:00", deadline: true),
    DateCase("낼 아침 10시 반 도서관에서 만나", "2026-11-24 10:30", location: "도서관"),
    DateCase("다음 달 5일에 정기총회 있습니다", "2026-12-05"),
    DateCase("이번 달 30일까지 회비 내 주세요", "2026-11-30", deadline: true),
    DateCase("2026년 12월 24일 크리스마스 파티", "2026-12-24"),
    DateCase("1/5에 개강 준비 모임", "2027-01-05"),
    DateCase("11월 25일 오후 6시 학생회관에서 오리엔테이션", "2026-11-25 18:00", location: "학생회관"),
    DateCase("일주일 뒤에 중간 점검해요", "2026-11-30"),
    DateCase("이틀 후 결과 발표", "2026-11-25"),
    DateCase("2주 뒤 최종 발표입니다", "2026-12-07"),
    DateCase("이번 주말에 MT 가요", "2026-11-28"),
    DateCase("다음 주말 시간 돼?", "2026-12-05"),
    DateCase("다음 주까지 초안 부탁해요", "2026-12-06", deadline: true),
    DateCase("금요일 6시까지 PPT 넘겨줄게", "2026-11-27 18:00", deadline: true),
    DateCase("8시 반에 줌에서 회의해요", "2026-11-23 20:30", location: "줌"),
    DateCase("저녁 8시 회식", "2026-11-23 20:00"),
    DateCase("오후 1시 반에 302호에서 면담", "2026-11-24 13:30", location: "302호"),
    DateCase("화요일 오전 10:30 랩미팅", "2026-11-24 10:30"),
    DateCase("21:00에 디코에서 모여", "2026-11-23 21:00", location: "디코"),
    DateCase("내일모레까지 답장 줄게", "2026-11-25", deadline: true),
    DateCase("11/26(목) 18:30 동아리 회의", "2026-11-26 18:30"),
    DateCase("목요일 2시에 2학년 3명이서 회의실에서 모여요", "2026-11-26 14:00", location: "회의실"),
    DateCase("다다음 주 월요일 오전 9시 반 시험", "2026-12-07 09:30"),
    DateCase("수요일 자정까지 과제 제출", "2026-11-26 00:00", deadline: true),
    DateCase("내일 오후에 연락드릴게요", "2026-11-24"),
    DateCase("오늘까지 피드백 부탁드립니다", "2026-11-23", deadline: true),
    DateCase("화 저녁 7시 스터디 ㄱㄱ", "2026-11-24 19:00"),
    DateCase("다음주 목욜 6시 반 카페에서", "2026-12-03 18:30", location: "카페"),
    DateCase("28일 오전 11시에 장비 반납", "2026-11-28 11:00"),
    DateCase("12.1 오후 3시 발표 순서 정해요", "2026-12-01 15:00"),
    DateCase("토요일 아침 8시 도서관 앞에서 출발", "2026-11-28 08:00", location: "도서관 앞"),
    DateCase("그럼 2시 반쯤 볼까요?", "2026-11-23 14:30"),
    DateCase("회의는 다음 주 수요일 7시 30분입니다", "2026-12-02 19:30"),
    DateCase("목요일 11시까지 제출", "2026-11-26 23:00", deadline: true),
    DateCase("일요일까지 각자 파트 정리", "2026-11-29", deadline: true),
    DateCase("점심 12시에 학식에서", "2026-11-24 12:00", location: "학식"),
    DateCase("6시 회의실 예약했어", "2026-11-23 18:00"),
    DateCase("오늘 11시에 통화 가능?", "2026-11-23 23:00"),
    DateCase("오후 두시 반에 봬요", "2026-11-23 14:30"),
    DateCase("한시 반에 봬요", "2026-11-24 13:30"),
    DateCase("11.30 장소 공지할게요", "2026-11-30"),
    DateCase("낼 7시 어때", "2026-11-24 19:00"),
    DateCase("금요일 전까지 리뷰 부탁", "2026-11-27", deadline: true),
    DateCase("12/2 내로 회신 주세요", "2026-12-02", deadline: true),
]

@Test("카톡 회귀 세트", arguments: regression)
func regressionSentences(_ c: DateCase) throws {
    let r = try #require(parser.parse(c.text), "날짜를 못 찾음: \(c.text)")
    #expect(render(r.due) == c.expected)
    #expect(r.isDeadline == c.deadline)
    if let loc = c.location { #expect(r.location == loc) }
}

@Test func regressionSetIsAtLeastFifty() {
    #expect(regression.count >= 50)
}

// 숫자는 있지만 날짜가 아닌 문장 — 오탐 방지
private let falsePositives: [String] = [
    "우리 팀 3명이서 하자",
    "나 2학년이야",
    "1차 회의록 올렸어요",
    "버전 2.0 배포했어",
    "v1.2 릴리즈 노트 봐줘",
    "진행률 50% 넘음",
    "학점 3.5 넘겼다",
    "4.5점 만점에 몇 점이야",
    "3시간 걸렸어",
    "10분만 기다려줘",
    "1/3 정도 했어",
    "1일 1커밋 챌린지 하자",
    "2:1로 이겼다",
    "회비 5만원 보내줘",
    "월 회비 만원이에요",
    "목 아파서 말 못 해",
    "할 수 있어?",
    "지금까지 고생했어",
    "그 일까지 다 해야 돼",
    "3번 문제 질문 있어요",
    "2주차 과제 봤어?",
    "점심 뭐 먹지",
    "저녁 먹었어?",
    "몇 시에 볼래?",
    "발표한 시점이 언제였지",
    "3일 동안 밤샜다",
]

@Test("오탐 방지", arguments: falsePositives)
func noFalsePositive(_ text: String) {
    #expect(parser.parse(text) == nil, "오탐: \(text)")
}

@Test func falsePositiveSetIsAtLeastFifteen() {
    #expect(falsePositives.count >= 15)
}

@Test func matchedRangeCoversDateAndTime() throws {
    let t1 = "그럼 목요일 7시에 공학관에서 봬요"
    let r1 = try #require(parser.parse(t1))
    #expect(String(t1[r1.matchedRange]) == "목요일 7시")

    let t2 = "연사 리스트 금요일까지 공유할게"
    let r2 = try #require(parser.parse(t2))
    #expect(String(t2[r2.matchedRange]) == "금요일")

    let t3 = "오늘 저녁 7시 반에 정문 앞에서 봐"
    let r3 = try #require(parser.parse(t3))
    #expect(String(t3[r3.matchedRange]) == "오늘 저녁 7시 반")

    let t4 = "11/26(목) 18:30 동아리 회의"
    let r4 = try #require(parser.parse(t4))
    #expect(String(t4[r4.matchedRange]) == "11/26(목) 18:30")
}

@Test func weekdayAloneTodayVersusPassed() throws {
    // 오늘이 월요일: 시각이 아직이면 오늘, 지났으면 다음 주.
    #expect(render(try #require(parser.parse("월요일 오후 5시")).due) == "2026-11-23 17:00")
    #expect(render(try #require(parser.parse("월요일 오전 10시")).due) == "2026-11-30 10:00")
}

@Test func timeOnlyRollsToTomorrowWhenPassed() throws {
    #expect(render(try #require(parser.parse("오전 9시에 보자")).due) == "2026-11-24 09:00")
    #expect(render(try #require(parser.parse("오후 3시에 보자")).due) == "2026-11-23 15:00")
}

@Test func deadlineWithoutTimeHasNoTime() throws {
    let r = try #require(parser.parse("목요일까지 보내 줄게요"))
    #expect(r.isDeadline)
    #expect(r.due.hasTime == false)
    #expect(render(r.due) == "2026-11-26")
}

@Test func morningContextKeepsAmbiguousHourInMorning() throws {
    // "아침"이 시각과 떨어져 있어도 문장 전체가 아침 문맥이면 오전으로 본다.
    #expect(render(try #require(parser.parse("내일 출근 전에 8시 커피")).due) == "2026-11-24 08:00")
    #expect(render(try #require(parser.parse("내일 8시 커피")).due) == "2026-11-24 20:00")
}

@Test func yearRollsOverForPastMonthDay() throws {
    #expect(render(try #require(parser.parse("11월 20일 회고")).due) == "2027-11-20")
    #expect(render(try #require(parser.parse("오늘 11/23 회의")).due) == "2026-11-23")
}

@Test func invalidCalendarDateIsRejected() {
    #expect(parser.parse("2월 30일에 보자") == nil)
}

@Test func dayOfMonthSkipsMonthWithoutThatDay() throws {
    // 11월엔 31일이 없으므로 12월 31일.
    #expect(render(try #require(parser.parse("31일 종강 파티")).due) == "2026-12-31")
}

@Test func noDateReturnsNil() {
    #expect(parser.parse("다음에 밥 한번 먹자") == nil)
    #expect(parser.parse("") == nil)
}

@Test func otherReferenceTimeIsDeterministic() throws {
    // 기준 시각을 바꾸면 결과도 그에 맞게 바뀐다 (2026-11-27 금 20:00).
    let now = Seoul.calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 20))!
    let p = KoreanDateParser(now: now)
    #expect(render(try #require(p.parse("금요일 7시")).due) == "2026-12-04 19:00")
    #expect(render(try #require(p.parse("다음 주 월요일")).due) == "2026-11-30")
    #expect(render(try #require(p.parse("27일")).due) == "2026-11-27")
}

// MARK: - 경계 사례 (적대적 리뷰에서 추가)

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> KoreanDateParser {
    KoreanDateParser(now: Seoul.calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!)
}

@Test func yearEndRollsIntoNextYear() throws {
    // 2026-12-31(목) 22:00
    let p = at(2026, 12, 31, 22)
    #expect(render(try #require(p.parse("내일 3시")).due) == "2027-01-01 15:00")
    #expect(render(try #require(p.parse("밤 12시까지")).due) == "2027-01-01 00:00")
    #expect(render(try #require(p.parse("1/2 회의")).due) == "2027-01-02")
    #expect(render(try #require(p.parse("3일에 보자")).due) == "2027-01-03")
    #expect(render(try #require(p.parse("다음 달 5일")).due) == "2027-01-05")
    #expect(render(try #require(p.parse("다음 주 월요일")).due) == "2027-01-04")
    #expect(render(try #require(p.parse("글피")).due) == "2027-01-03")
}

@Test func lateNightTimeMeansTonightNotTomorrowNight() throws {
    // 화요일 00:30: "밤 1시"는 30분 뒤다. 다음 날 01:00이 아니다.
    let p = at(2026, 11, 24, 0, 30)
    #expect(render(try #require(p.parse("밤 1시에 통화하자")).due) == "2026-11-24 01:00")
    #expect(render(try #require(p.parse("자정까지 보내")).due) == "2026-11-25 00:00")
}

@Test func instantIsInterpretedInSeoulNotUTC() throws {
    // 2026-11-23T15:30Z = 서울 11/24(화) 00:30. "오늘"은 11/24다.
    let utc = ISO8601DateFormatter().date(from: "2026-11-23T15:30:00Z")!
    let p = KoreanDateParser(now: utc)
    #expect(render(try #require(p.parse("오늘까지")).due) == "2026-11-24")
    #expect(render(try #require(p.parse("화요일 오후 3시")).due) == "2026-11-24 15:00")
}

@Test func invalidFirstDateFallsBackToNextExpression() throws {
    #expect(render(try #require(parser.parse("2월 30일은 없으니 내일 3시에 보자")).due) == "2026-11-24 15:00")
    #expect(render(try #require(parser.parse("25시 말고 내일 7시")).due) == "2026-11-24 19:00")
}

@Test func deadlineDetectedEvenWhenTimeFollows() throws {
    let r = try #require(parser.parse("금요일까지 오후 3시에 올려줘"))
    #expect(r.isDeadline)
    #expect(render(r.due) == "2026-11-27 15:00")
}

@Test func zeroPaddedColonTimeIsLiteral24h() throws {
    #expect(render(try #require(parser.parse("내일 09:30 회의")).due) == "2026-11-24 09:30")
    #expect(render(try #require(parser.parse("내일 08시 집합")).due) == "2026-11-24 08:00")
}

@Test func lastWeekendIsNotThisWeekend() throws {
    #expect(render(try #require(parser.parse("지난 주말에 찍은 사진")).due) == "2026-11-21")
    // 일요일에 "주말"은 오늘이다(어제 토요일이 아니다).
    #expect(render(try #require(at(2026, 11, 29, 10).parse("주말에 보자")).due) == "2026-11-29")
}

@Test func decomposedHangulIsParsed() throws {
    // macOS에서 복사한 문자열은 NFD(자모 분리)일 수 있다.
    let nfd = "그럼 목요일 7시에 공학관에서 봬요".decomposedStringWithCanonicalMapping
    let r = try #require(parser.parse(nfd))
    #expect(render(r.due) == "2026-11-26 19:00")
    #expect(String(nfd[r.matchedRange]).precomposedStringWithCanonicalMapping == "목요일 7시")
}

@Test func clockFollowedByCopulaStillParses() throws {
    #expect(render(try #require(parser.parse("내일 3시인가요?")).due) == "2026-11-24 15:00")
    #expect(render(try #require(parser.parse("회의 내일 4시예요")).due) == "2026-11-24 16:00")
}

@Test func eveningTwelveIsMidnight() throws {
    #expect(render(try #require(parser.parse("오늘 저녁 12시까지")).due) == "2026-11-24 00:00")
}

@Test func duplicateAndWhitespaceInputs() throws {
    #expect(parser.parse("   \n\t ") == nil)
    #expect(render(try #require(parser.parse("내일 내일 3시 3시")).due) == "2026-11-24 15:00")
    #expect(render(try #require(parser.parse("목요일? 아니 금요일 6시")).due) == "2026-11-26 18:00")
}

@Test func outlierNumbersDoNotCrash() {
    #expect(parser.parse("13월 45일") == nil)
    #expect(parser.parse("99:99에 봐") == nil)
    #expect(parser.parse(String(repeating: "가", count: 5000)) == nil)
    #expect(parser.parse("32일") == nil)
}

private let moreFalsePositives: [String] = [
    "월 3시간씩 봉사해요",
    "이번 주제는 AI야",
    "다음 주소로 보내주세요",
    "평균 3.8 나왔어",
    "한시적으로 무료래",
    "네 시도해볼게요",
    "3일 남았어 화이팅",
    "24시 편의점 가자",
]

@Test("오탐 방지(추가)", arguments: moreFalsePositives)
func noFalsePositiveMore(_ text: String) {
    #expect(parser.parse(text) == nil, "오탐: \(text)")
}
