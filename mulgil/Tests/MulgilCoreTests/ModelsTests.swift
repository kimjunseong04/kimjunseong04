import Foundation
import Testing
@testable import MulgilCore

@Test func occurrenceKeyIsStable() {
    let d = Date(timeIntervalSince1970: 1_800_000_000)
    let a = OccurrenceKey(calendarId: "c", seriesId: "s", originalStart: d)
    let b = OccurrenceKey(calendarId: "c", seriesId: "s", originalStart: d)
    #expect(a == b)
    #expect(a.description == "c|s|1800000000")
}
