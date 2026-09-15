import Foundation

public enum VPhoneHostControlValidationError: Error, Equatable, CustomStringConvertible {
    case invalidField(String)
    case outOfRange(String)
    case nonFinite(String)
    case oversized(String)

    public var description: String {
        switch self {
        case .invalidField(let name): "invalid field: \(name)"
        case .outOfRange(let name): "out of range: \(name)"
        case .nonFinite(let name): "non-finite value: \(name)"
        case .oversized(let name): "oversized value: \(name)"
        }
    }
}

public enum VPhoneHostControlLimits {
    public static let defaultDelayMilliseconds = 500
    public static let defaultSwipeDurationMilliseconds = 300
    public static let maxDelayMilliseconds = 5_000
    public static let maxSwipeDurationMilliseconds = 10_000
    public static let maxTextBytes = 64 * 1024
    public static let maxRequestBytes = 64 * 1024
    public static let clientReadTimeoutSeconds = 2

    public static func delay(_ value: Int?) throws -> Int {
        let value = value ?? defaultDelayMilliseconds
        guard (0...maxDelayMilliseconds).contains(value) else {
            throw VPhoneHostControlValidationError.outOfRange("delay")
        }
        return value
    }

    public static func swipeDuration(_ value: Int?) throws -> Int {
        let value = value ?? defaultSwipeDurationMilliseconds
        guard (1...maxSwipeDurationMilliseconds).contains(value) else {
            throw VPhoneHostControlValidationError.outOfRange("ms")
        }
        return value
    }

    public static func coordinate(_ value: Double, name: String) throws -> Double {
        guard value.isFinite else {
            throw VPhoneHostControlValidationError.nonFinite(name)
        }
        return value
    }

    public static func text(_ value: String) throws -> String {
        guard value.utf8.count <= maxTextBytes else {
            throw VPhoneHostControlValidationError.oversized("text")
        }
        return value
    }

    public static func integerField(_ value: Any?, name: String) throws -> Int? {
        guard let value else { return nil }
        guard let integer = value as? Int else {
            throw VPhoneHostControlValidationError.invalidField(name)
        }
        return integer
    }

    public static func stringField(_ value: Any?, name: String) throws -> String? {
        guard let value else { return nil }
        guard let string = value as? String else {
            throw VPhoneHostControlValidationError.invalidField(name)
        }
        return string
    }
}
