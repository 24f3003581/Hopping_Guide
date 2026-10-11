// Services/UserStateService.swift — visited/favorites persistence (UserDefaults)

import Foundation
import Observation
import FirebaseAuth
import FirebaseCore

struct FirebaseUserIdentity: Sendable {
    let uid: String
    let displayName: String
    let idToken: String
}

enum FirebaseSetupError: LocalizedError {
    case missingConfiguration
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Firebase is not configured for this iOS app. Add the Firebase iOS app configuration to enable squads and video calls."
        case .signInFailed:
            return "Could not sign in to Firebase. Check your connection and try again."
        }
    }
}

enum FirebaseStartup {
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil,
              Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
    }
}

@MainActor
@Observable
final class UserStateService {
    static let shared = UserStateService()

    private(set) var visitedIds: Set<String> = []
    private(set) var favoriteIds: Set<String> = []
    private(set) var currentUserName: String = "Pujo Hopper"
    private(set) var isGuest: Bool = true
    private(set) var firebaseSetupMessage: String?

    private let visitedKey = "uma.visitedPandalIds"
    private let favoriteKey = "uma.favoritePandalIds"
    private let userKey = "uma.currentUserName"
    private let guestKey = "uma.isGuest"

    init() {
        load()
    }

    func load() {
        let defaults = UserDefaults.standard
        if let arr = defaults.array(forKey: visitedKey) as? [String] {
            visitedIds = Set(arr)
        }
        if let arr = defaults.array(forKey: favoriteKey) as? [String] {
            favoriteIds = Set(arr)
        }
        currentUserName = defaults.string(forKey: userKey) ?? "Pujo Hopper"
        isGuest = defaults.object(forKey: guestKey) as? Bool ?? true
    }

    func toggleVisited(_ id: String) {
        if visitedIds.contains(id) { visitedIds.remove(id) } else { visitedIds.insert(id) }
        persist(visitedKey, value: Array(visitedIds))
        Haptics.light()
    }

    func toggleFavorite(_ id: String) {
        if favoriteIds.contains(id) { favoriteIds.remove(id) } else { favoriteIds.insert(id) }
        persist(favoriteKey, value: Array(favoriteIds))
        Haptics.soft()
    }

    func isVisited(_ id: String) -> Bool { visitedIds.contains(id) }
    func isFavorite(_ id: String) -> Bool { favoriteIds.contains(id) }

    func signInGuest(name: String) {
        currentUserName = name
        isGuest = true
        defaults().set(name, forKey: userKey)
        defaults().set(true, forKey: guestKey)
    }

    var firebaseUserId: String? { Auth.authIfConfigured?.currentUser?.uid }

    func prepareFirebaseSession() async {
        do {
            _ = try await ensureFirebaseIdentity()
            firebaseSetupMessage = nil
        } catch {
            firebaseSetupMessage = error.localizedDescription
        }
    }

    func ensureFirebaseIdentity() async throws -> FirebaseUserIdentity {
        guard FirebaseApp.app() != nil else { throw FirebaseSetupError.missingConfiguration }

        let auth = Auth.auth()
        let user: FirebaseAuth.User
        if let existing = auth.currentUser {
            user = existing
        } else {
            user = try await auth.signInAnonymously().user
        }

        let displayName = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty, user.displayName != displayName {
            let profile = user.createProfileChangeRequest()
            profile.displayName = displayName
            try? await profile.commitChanges()
        }

        let token = try await user.getIDToken()
        return FirebaseUserIdentity(
            uid: user.uid,
            displayName: displayName.isEmpty ? "Pujo Hopper" : displayName,
            idToken: token
        )
    }

    func setUserName(_ name: String) {
        currentUserName = name
        defaults().set(name, forKey: userKey)
    }

    private func defaults() -> UserDefaults { .standard }
    private func persist(_ key: String, value: [String]) { defaults().set(value, forKey: key) }
}

private extension Auth {
    static var authIfConfigured: Auth? {
        FirebaseApp.app() == nil ? nil : Auth.auth()
    }
}

@MainActor
@Observable
final class ThemeService {
    static let shared = ThemeService()
    enum Mode: String, CaseIterable { case system, light, dark }
    var mode: Mode = .system {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "uma.themeMode") }
    }
    init() {
        if let raw = UserDefaults.standard.string(forKey: "uma.themeMode"),
           let m = Mode(rawValue: raw) {
            mode = m
        }
    }
}
