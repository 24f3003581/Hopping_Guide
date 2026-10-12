// Services/GroupVideoApi.swift — authenticated session exchange for squad video calls.

import Foundation

struct GroupVideoSession: Decodable, Sendable {
    let apiKey: String
    let userId: String
    let token: String
    let callId: String
    let callType: String
}

enum GroupVideoError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case notSquadMember
    case notConfigured
    case serverUnavailable(String)
    case invalidResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The video calling server URL is invalid."
        case .unauthorized:
            return "Your sign-in expired. Reopen the squad and try again."
        case .notSquadMember:
            return "Only current members of this squad can join its call."
        case .notConfigured:
            return "Video calling is not configured on the server yet."
        case .serverUnavailable(let message):
            return message
        case .invalidResponse:
            return "The video server returned an invalid response. Please try again."
        case .networkError(let message):
            return "Could not reach the video server: \(message)"
        }
    }
}

final class GroupVideoApi: Sendable {
    static let shared = GroupVideoApi()
    static let defaultHostedUrl = "https://uma-group-calling.onrender.com"

    private init() {}

    var effectiveBaseUrl: String {
        if let custom = UserDefaults.standard.string(forKey: "uma.videoApiUrl")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if let infoUrl = Bundle.main.infoDictionary?["VIDEO_API_URL"] as? String,
           !infoUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return infoUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return Self.defaultHostedUrl
    }

    func requestSession(
        squadId: String,
        firebaseIdToken: String,
        userName: String
    ) async throws -> GroupVideoSession {
        var pathCharacters = CharacterSet.alphanumerics
        pathCharacters.insert(charactersIn: "-_")
        guard let safeSquadId = squadId.addingPercentEncoding(withAllowedCharacters: pathCharacters),
              let url = URL(string: "\(effectiveBaseUrl)/api/squads/\(safeSquadId)/video/session") else {
            throw GroupVideoError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(firebaseIdToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: ["userName": userName])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GroupVideoError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GroupVideoError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw GroupVideoError.unauthorized
        case 403:
            throw GroupVideoError.notSquadMember
        case 503:
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            if envelope?.error.code == "VIDEO_NOT_CONFIGURED" {
                throw GroupVideoError.notConfigured
            }
            throw GroupVideoError.serverUnavailable(envelope?.error.message ?? "Video calling is temporarily unavailable.")
        default:
            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw GroupVideoError.serverUnavailable(envelope?.error.message ?? "Video calling failed (HTTP \(http.statusCode)).")
        }

        guard let session = try? JSONDecoder().decode(GroupVideoSession.self, from: data),
              !session.apiKey.isEmpty,
              !session.token.isEmpty,
              !session.userId.isEmpty,
              !session.callId.isEmpty,
              !session.callType.isEmpty else {
            throw GroupVideoError.invalidResponse
        }
        return session
    }
}

private struct ErrorEnvelope: Decodable {
    struct ServerError: Decodable {
        let code: String
        let message: String
    }
    let error: ServerError
}
