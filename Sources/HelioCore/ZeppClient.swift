import Foundation

// A bearer token must never follow an HTTP redirect, even to another Zepp region.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct ZeppClient: Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    // Injection for offline protocol tests. Production always uses the restricted session above.
    init(session: URLSession) { self.session = session }

    public func fetch(credentials: ZeppCredentials, from: Date, to: Date) async throws -> CloudSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard let count = calendar.dateComponents([.day], from: start, to: end).day,
              (0..<30).contains(count), let afterEnd = calendar.date(byAdding: .day, value: 1, to: end) else {
            throw ZeppError.dateRange
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let startDay = formatter.string(from: start)
        let endDay = formatter.string(from: end)
        let fromMS = String(Int64(start.timeIntervalSince1970 * 1000))
        let toMS = String(Int64(afterEnd.timeIntervalSince1970 * 1000) - 1)
        let band = try await request(endpoint: .band, credentials: credentials, startDay: startDay, endDay: endDay, fromMS: fromMS, toMS: toMS)
        guard band["code"].number == 1 else { throw ZeppError.api(CloudEndpoint.band.title) }
        guard case .array = band["data"] else { throw ZeppError.malformed("band data") }
        var warnings: [String] = []
        let days: [BandDay]
        var bandWarning: String?
        do { days = try ZeppDecoder.bandDays(from: band) }
        catch {
            days = []
            bandWarning = "Band records were downloaded, but their summaries could not be decoded. Inspect the response in All cloud fields."
            warnings.append(bandWarning!)
        }
        var payloads = [EndpointPayload(endpoint: .band, raw: band, warning: bandWarning)]
        for endpoint in CloudEndpoint.allCases where endpoint != .band {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(150))
            do {
                let raw = try await request(endpoint: endpoint, credentials: credentials, startDay: startDay, endDay: endDay, fromMS: fromMS, toMS: toMS)
                let warning = responseWarning(raw, endpoint: endpoint)
                if let warning { warnings.append(warning) }
                payloads.append(EndpointPayload(endpoint: endpoint, raw: raw, warning: warning))
            } catch is CancellationError { throw CancellationError() }
            catch ZeppError.authentication { throw ZeppError.authentication }
            catch {
                try Task.checkCancellation()
                let warning = "\(endpoint.title): \(error.localizedDescription)"
                warnings.append(warning)
                payloads.append(EndpointPayload(endpoint: endpoint, raw: .null, warning: warning))
            }
        }
        try Task.checkCancellation()
        return CloudSnapshot(fetchedAt: Date(), startDate: startDay, endDate: endDay, region: credentials.region,
                             days: days, payloads: payloads, warnings: warnings)
    }

    func makeRequest(endpoint: CloudEndpoint, credentials: ZeppCredentials, startDay: String, endDay: String,
                     fromMS: String, toMS: String) -> URLRequest {
        let id = credentials.userID
        let path: String
        var params: [String: String]
        switch endpoint {
        case .band:
            path = "/v1/data/band_data.json"
            params = ["query_type": "detail", "device_type": "android_phone", "userid": id, "from_date": startDay, "to_date": endDay]
        case .stress:
            path = "/users/\(id)/events"
            params = ["eventType": "all_day_stress", "from": fromMS, "to": toMS, "limit": "200"]
        case .exertion, .phn:
            path = "/v2/users/me/events"
            params = ["eventType": endpoint == .exertion ? "exertion" : "phn",
                      "subType": endpoint == .exertion ? "algo_result" : "daily_analysis",
                      "from": fromMS, "to": toMS, "limit": "200"]
        case .sportLoad, .vo2Max:
            path = "/v2/watch/users/\(id)/WatchSportStatistics/" + (endpoint == .sportLoad ? "SPORT_LOAD" : "VO2_MAX")
            params = ["startDay": startDay, "endDay": endDay, "limit": "900", "isReverse": "true"]
        case .workouts:
            path = "/v1/sport/run/history.json"
            params = ["userid": id, "from": startDay, "to": endDay]
        }
        var components = URLComponents(url: credentials.region.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(credentials.token, forHTTPHeaderField: "apptoken")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The community capture used these unencrypted iOS headers for event/statistics endpoints.
        if [.stress, .exertion, .phn, .sportLoad, .vo2Max].contains(endpoint) {
            request.setValue("ios_phone", forHTTPHeaderField: "appPlatform")
            request.setValue("com.huami.midong", forHTTPHeaderField: "appname")
            request.setValue("2.0", forHTTPHeaderField: "v")
            request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "timezone")
        } else {
            request.setValue("web", forHTTPHeaderField: "appPlatform")
            request.setValue("com.xiaomi.hm.health", forHTTPHeaderField: "appname")
        }
        // Never set x-hm-ekv. It requests encrypted binary responses.
        return request
    }

    private func request(endpoint: CloudEndpoint, credentials: ZeppCredentials, startDay: String, endDay: String,
                         fromMS: String, toMS: String) async throws -> JSONValue {
        try Task.checkCancellation()
        let request = makeRequest(endpoint: endpoint, credentials: credentials, startDay: startDay, endDay: endDay, fromMS: fromMS, toMS: toMS)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw ZeppError.network((error as? URLError)?.errorCode ?? -1)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw ZeppError.malformed(endpoint.title) }
        if response.statusCode == 401 || response.statusCode == 403 { throw ZeppError.authentication }
        guard response.statusCode == 200 else { throw ZeppError.http(response.statusCode) }
        guard data.count <= 25 * 1024 * 1024 else { throw ZeppError.oversized }
        guard let raw = try? JSONValue.decode(data), case .object = raw else { throw ZeppError.malformed(endpoint.title) }
        return redact(raw, token: credentials.token)
    }

    private func responseWarning(_ raw: JSONValue, endpoint: CloudEndpoint) -> String? {
        if let code = raw["code"].number, code != 1 && code != 0 && code != 200 {
            return "\(endpoint.title): Zepp rejected this endpoint. The response is available in All cloud fields."
        }
        if endpoint == .workouts {
            return "Workout history is experimental. Its response format and pagination are not verified; this may not be your full history."
        }
        guard case .array(let items) = raw["items"] else {
            return "\(endpoint.title): Unrecognized response shape. Inspect All cloud fields."
        }
        let limit = [.sportLoad, .vo2Max].contains(endpoint) ? 900 : 200
        if items.count >= limit {
            return "\(endpoint.title): The server result limit was reached. Some records may be missing; choose a shorter range."
        }
        return nil
    }
}

// Raw cloud responses remain inspectable, but must never cache or export a bearer token.
private func redact(_ value: JSONValue, token: String) -> JSONValue {
    switch value {
    case .object(let object):
        let secrets: Set<String> = ["apptoken", "app_token", "token", "access_token", "refresh_token", "authorization", "password"]
        return .object(object.mapValues { redact($0, token: token) }.mapKeysAndValues { key, value in
            (key, secrets.contains(key.lowercased()) ? .string("[redacted]") : value)
        })
    case .array(let array): return .array(array.map { redact($0, token: token) })
    case .string(let text): return .string(text.replacingOccurrences(of: token, with: "[redacted]"))
    default: return value
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func mapKeysAndValues(_ transform: (String, JSONValue) -> (String, JSONValue)) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: map { transform($0.key, $0.value) })
    }
}
