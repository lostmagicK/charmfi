import Foundation

final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    private init() {}

    let baseURL = URL(string: "https://fi-api.charmee.in/api")!
    private let session = URLSession.shared

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Handle null date fields — return epoch instead of throwing
            if container.decodeNil() { return Date(timeIntervalSince1970: 0) }
            let str = try container.decode(String.self)

            // ISO8601 with fractional seconds (covers .NET's 7-digit precision with timezone)
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFrac.date(from: str) { return date }

            // ISO8601 without fractional seconds
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }

            // .NET DateTime without timezone — append Z and retry
            if let date = isoFrac.date(from: str + "Z") { return date }
            if let date = iso.date(from: str + "Z") { return date }

            // Date-only fallback
            let dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: str) { return date }

            // Return current date as last resort so decoding doesn't fail an entire response
            // over a single unparseable date field
            return Date()
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func request<T: Decodable>(_ endpoint: some Endpoint, authState: AuthState) async throws -> T {
        let token = try await authState.validAccessToken()
        let urlRequest = try buildRequest(endpoint, token: token)
        let (data, response) = try await session.data(for: urlRequest)
        APIClient.log(urlRequest, response: response, data: data)
        try validate(response: response, data: data)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            print("❌ [DECODE ERROR] \(T.self): \(error)")
            if let body = String(data: data, encoding: .utf8) {
                print("   Response body: \(body.prefix(500))")
            }
            throw error
        }
    }

    func requestVoid(_ endpoint: some Endpoint, authState: AuthState) async throws {
        let token = try await authState.validAccessToken()
        let urlRequest = try buildRequest(endpoint, token: token)
        let (data, response) = try await session.data(for: urlRequest)
        APIClient.log(urlRequest, response: response, data: data)
        try validate(response: response, data: data)
    }

    private func buildRequest(_ endpoint: some Endpoint, token: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)!
        components.queryItems = endpoint.queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func log(_ req: URLRequest, response: URLResponse, data: Data) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let icon = (200...299).contains(status) ? "✅" : "❌"
        let method = req.httpMethod ?? "GET"
        let url = req.url?.absoluteString ?? ""
        print("\(icon) [\(method) \(status)] \(url)")
        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("   → \(bodyStr.prefix(300))")
        }
        if !(200...299).contains(status), let respStr = String(data: data, encoding: .utf8) {
            print("   ← \(respStr.prefix(500))")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 401: throw NetworkError.unauthorized
        case 403: throw NetworkError.forbidden
        case 404: throw NetworkError.notFound
        case 422:
            let msg = (try? Self.decoder.decode(APIError.self, from: data))?.message ?? "Validation error"
            throw NetworkError.validationError(msg)
        default:
            let msg = (try? Self.decoder.decode(APIError.self, from: data))?.message ?? "Server error \(http.statusCode)"
            throw NetworkError.serverError(http.statusCode, msg)
        }
    }
}

struct APIError: Decodable {
    let message: String?
    let title: String?
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case validationError(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response."
        case .unauthorized: "Session expired. Please sign in again."
        case .forbidden: "You don't have permission to do this."
        case .notFound: "Resource not found."
        case .validationError(let msg): msg
        case .serverError(_, let msg): msg
        }
    }
}
