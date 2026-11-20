import Foundation

public struct CodexAccountUsage: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let usedPercent: Double
        public let resetAt: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }

    public let rateLimit: RateLimit?

    public struct RateLimit: Decodable, Sendable {
        public let primary: Window?
        public let secondary: Window?

        private enum CodingKeys: String, CodingKey {
            case primary = "primary_window"
            case secondary = "secondary_window"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    public static func read() async throws -> Self {
        let credentials = try CodexResetCredentials.load()
        let request = CodexResetAPI.accountRequest(credentials, path: "usage")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw CodexResetError.invalidResponse
        }
        if status == 401 || status == 403 { throw CodexResetError.signInRequired }
        guard (200...299).contains(status) else { throw CodexResetError.http(status) }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
