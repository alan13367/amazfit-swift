import Foundation

public enum ZeppRegion: String, Codable, CaseIterable, Sendable {
    case us, europe, global
    public var title: String {
        switch self { case .us: "United States"; case .europe: "Europe"; case .global: "Global" }
    }
    public var baseURL: URL {
        let host: String
        switch self {
        case .us: host = "api-mifit-us2.zepp.com"
        case .europe: host = "api-mifit-de2.zepp.com"
        case .global: host = "api-mifit.huami.com"
        }
        return URL(string: "https://" + host)!
    }
}

public enum ZeppError: LocalizedError, Sendable, Equatable {
    case credentials
    case dateRange
    case authentication
    case http(Int)
    case network(Int)
    case api(String)
    case malformed(String)
    case oversized
    public var errorDescription: String? {
        switch self {
        case .credentials: "Enter your numeric Zepp user ID and a valid session token. Spaces and line breaks are not allowed inside the token."
        case .dateRange: "Choose a date range of 1 to 30 days."
        case .authentication: "Zepp rejected this session. Sign in to Zepp again and check your account region."
        case .http(let code): "Zepp returned HTTP \(code). Check the account region or try again later."
        case .network(let code): "The Zepp connection failed, network error \(code). Check your internet connection and try again."
        case .api(let endpoint): "Zepp rejected the \(endpoint) request. Check your account region. The unofficial API may have changed."
        case .malformed(let context): "The \(context) response has an unrecognized format. The unofficial API may have changed."
        case .oversized: "Zepp returned too much data for one request. Try a shorter download range."
        }
    }
}

public struct ZeppCredentials: Codable, Sendable {
    public let userID: String
    public let token: String
    public let region: ZeppRegion
    public init(userID: String, token: String, region: ZeppRegion) throws {
        let id = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...32).contains(id.utf8.count), id.utf8.allSatisfy({ (48...57).contains($0) }),
              (1...8192).contains(secret.utf8.count), secret.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ZeppError.credentials
        }
        self.userID = id
        self.token = secret
        self.region = region
    }
    private enum CodingKeys: String, CodingKey { case userID, token, region }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(userID: values.decode(String.self, forKey: .userID),
                      token: values.decode(String.self, forKey: .token),
                      region: values.decode(ZeppRegion.self, forKey: .region))
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let boolean = try? value.decode(Bool.self) { self = .bool(boolean) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let boolean): try value.encode(boolean)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
    public subscript(_ key: String) -> JSONValue {
        guard case .object(let object) = self else { return .null }
        return object[key] ?? .null
    }
    public var number: Double? {
        switch self {
        case .number(let number): return number.isFinite ? number : nil
        case .string(let string): guard let number = Double(string), number.isFinite else { return nil }; return number
        default: return nil
        }
    }
    public var string: String? { if case .string(let string) = self { return string }; return nil }
    public var array: [JSONValue] { if case .array(let values) = self { return values }; return [] }
    public var scalarDescription: String? {
        if let string { return string }
        if let number { return number.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...6))) }
        return nil
    }
    public var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }
    public static func decode(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: data) }
}

public struct BandDay: Codable, Sendable, Identifiable {
    public var id: String { date + "-" + source }
    public let date: String
    public let source: String
    public let summary: JSONValue
    public let heartRate: [Int]
    public let raw: JSONValue
    public init(date: String, source: String, summary: JSONValue, heartRate: [Int], raw: JSONValue) {
        self.date = date; self.source = source; self.summary = summary; self.heartRate = heartRate; self.raw = raw
    }
}

public enum CloudEndpoint: String, CaseIterable, Codable, Sendable, Identifiable {
    case band, stress, exertion, phn, sportLoad, vo2Max, workouts
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .band: "Band data"
        case .stress: "Stress"
        case .exertion: "Training load"
        case .phn: "Training impulse"
        case .sportLoad: "Sport load"
        case .vo2Max: "VO₂ max"
        case .workouts: "Workout history"
        }
    }
}

public struct EndpointPayload: Codable, Sendable, Identifiable {
    public var id: String { endpoint.rawValue }
    public let endpoint: CloudEndpoint
    public let raw: JSONValue
    public let warning: String?
    public init(endpoint: CloudEndpoint, raw: JSONValue, warning: String? = nil) {
        self.endpoint = endpoint; self.raw = raw; self.warning = warning
    }
}

public struct CloudSnapshot: Codable, Sendable {
    public let fetchedAt: Date
    public let startDate: String
    public let endDate: String
    public let region: ZeppRegion
    public let days: [BandDay]
    public let payloads: [EndpointPayload]
    public let warnings: [String]
    public init(fetchedAt: Date, startDate: String, endDate: String, region: ZeppRegion,
                days: [BandDay], payloads: [EndpointPayload], warnings: [String]) {
        self.fetchedAt = fetchedAt; self.startDate = startDate; self.endDate = endDate; self.region = region
        self.days = days; self.payloads = payloads; self.warnings = warnings
    }
}
