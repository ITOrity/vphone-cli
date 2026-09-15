@testable import VPhoneCore
import Testing

struct HostControlValidationTests {
    @Test func rejectsNegativeDelay() {
        #expect(throws: VPhoneHostControlValidationError.self) {
            try VPhoneHostControlLimits.delay(-1)
        }
    }

    @Test func usesBoundedDefaultDelay() throws {
        #expect(try VPhoneHostControlLimits.delay(nil) == 500)
    }

    @Test func rejectsOversizedSwipeDuration() {
        #expect(throws: VPhoneHostControlValidationError.self) {
            try VPhoneHostControlLimits.swipeDuration(10_001)
        }
    }

    @Test func rejectsOversizedText() {
        let text = String(repeating: "x", count: VPhoneHostControlLimits.maxTextBytes + 1)
        #expect(throws: VPhoneHostControlValidationError.self) {
            try VPhoneHostControlLimits.text(text)
        }
    }

    @Test func rejectsNonFiniteCoordinate() {
        #expect(throws: VPhoneHostControlValidationError.self) {
            try VPhoneHostControlLimits.coordinate(.nan, name: "x")
        }
    }

    @Test func acceptsNormalValues() throws {
        #expect(try VPhoneHostControlLimits.delay(250) == 250)
        #expect(try VPhoneHostControlLimits.swipeDuration(300) == 300)
        #expect(try VPhoneHostControlLimits.coordinate(12.5, name: "x") == 12.5)
    }
}
