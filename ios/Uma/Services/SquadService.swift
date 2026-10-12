// Services/SquadService.swift — Firebase-backed squads shared with the Android app.

import Foundation
import CoreLocation
import Observation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

@MainActor
@Observable
final class SquadService {
    static let shared = SquadService()

    private(set) var currentId: String?
    private(set) var currentCode: String?
    private(set) var currentName: String?
    var meetupPointName: String?
    var meetupPointCoordinate: CLLocationCoordinate2D?
    var shareLocation = true {
        didSet { UserDefaults.standard.set(shareLocation, forKey: Self.shareLocationKey) }
    }
    var separationAlertMeters: Double = 500
    private(set) var members: [SquadMember] = []
    private(set) var connectionState: ConnectionState = .offline

    private var memberListener: ListenerRegistration?
    private var currentUserId: String?
    private var lastLocationSync: CLLocation?
    private var lastLocationSyncDate: Date?
    private let savedSquadIdKey = "uma.squad.id"
    private let savedSquadCodeKey = "uma.squad.code"
    private static let shareLocationKey = "uma.squad.shareLocation"

    enum ConnectionState { case connected, connecting, reconnecting, offline }

    var hasActiveSquad: Bool { currentId != nil && currentCode != nil && currentName != nil }
    var companionMembers: [SquadMember] { members.filter { !$0.isUser } }

    private init() {
        currentId = UserDefaults.standard.string(forKey: savedSquadIdKey)
        currentCode = UserDefaults.standard.string(forKey: savedSquadCodeKey)
        shareLocation = UserDefaults.standard.object(forKey: Self.shareLocationKey) as? Bool ?? true
    }

    func restoreSavedSquad() async {
        guard let squadId = currentId,
              let identity = try? await UserStateService.shared.ensureFirebaseIdentity() else { return }

        do {
            let document = try await Firestore.firestore().collection("squads").document(squadId).getDocument()
            guard let data = document.data(),
                  data["status"] as? String != "closed",
                  (data["membersUid"] as? [String])?.contains(identity.uid) == true else {
                clearSavedSquad()
                return
            }
            applySquad(data, id: document.documentID)
            currentUserId = identity.uid
            observeMembers(squadId: document.documentID, userId: identity.uid)
        } catch {
            connectionState = .offline
        }
    }

    func createSquad(name: String, hostName: String, latitude: Double, longitude: Double) async throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw SquadServiceError.invalidName }
        let identity = try await UserStateService.shared.ensureFirebaseIdentity()
        let db = Firestore.firestore()
        let squadId = "sq_\(UUID().uuidString.lowercased())"
        let code = Self.generateSquadCode()
        let meetupName = "Park Street Metro"
        let meetupLat = 22.5535
        let meetupLng = 88.3517
        let host = SquadMember(
            id: identity.uid,
            name: hostName,
            latitude: latitude,
            longitude: longitude,
            isHost: true,
            isUser: true,
            shareLocation: shareLocation,
            isOnline: true
        )
        let squadRef = db.collection("squads").document(squadId)
        let batch = db.batch()
        batch.setData([
            "squadId": squadId,
            "squadCode": code,
            "name": cleanName,
            "hostId": identity.uid,
            "hostName": hostName,
            "meetupPointName": meetupName,
            "meetupLat": meetupLat,
            "meetupLng": meetupLng,
            "separationThresholdMeters": Int(separationAlertMeters),
            "membersUid": [identity.uid],
            "chosenPandals": [[String: Any]](),
            "isHoppingActive": false,
            "activeStopIndex": 0,
            "lastMessage": "Squad created. Welcome to Durga Puja hopping!",
            "lastMessageTime": Int(Date().timeIntervalSince1970 * 1000),
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: squadRef)
        batch.setData(Self.memberDocument(host), forDocument: squadRef.collection("members").document(identity.uid))
        let welcome = ChatMessage(
            id: "welcome_\(squadId)", squadId: squadId,
            senderId: "system_pujo", senderName: "Pujo Bot 🪈",
            text: "Welcome to \"\(cleanName)\"! Share meetup notes and pandal updates here.",
            timestamp: Date()
        )
        try await batch.commit()
        // Android's rules authorize chat using committed membership (get),
        // while member creation uses getAfter. Send notices after the batch.
        // A failed optional notice must not hide a successfully created group.
        try? await squadRef.collection("messages").document(welcome.id)
            .setData(Self.messageDocument(welcome))

        applySquad([
            "squadCode": code, "name": cleanName,
            "meetupPointName": meetupName, "meetupLat": meetupLat, "meetupLng": meetupLng
        ], id: squadId)
        currentUserId = identity.uid
        members = [host]
        observeMembers(squadId: squadId, userId: identity.uid)
        syncLocationTrackingRequest()
        Haptics.notifySuccess()
    }

    func joinSquad(code rawCode: String, userName: String, latitude: Double, longitude: Double) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.range(of: "^PUJA[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$", options: .regularExpression) != nil else {
            throw SquadServiceError.invalidCode
        }
        let identity = try await UserStateService.shared.ensureFirebaseIdentity()
        let db = Firestore.firestore()
        let query = try await db.collection("squads")
            .whereField("squadCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()
        guard let document = query.documents.first else { throw SquadServiceError.squadNotFound }
        let data = document.data()
        guard data["status"] as? String != "closed" else { throw SquadServiceError.squadClosed }

        let member = SquadMember(
            id: identity.uid,
            name: userName,
            latitude: latitude,
            longitude: longitude,
            isHost: false,
            isUser: true,
            shareLocation: shareLocation,
            isOnline: true
        )
        let squadRef = document.reference
        let batch = db.batch()
        batch.updateData(["membersUid": FieldValue.arrayUnion([identity.uid])], forDocument: squadRef)
        batch.setData(Self.memberDocument(member), forDocument: squadRef.collection("members").document(identity.uid), merge: true)
        let joinMessage = ChatMessage(
            id: "join_\(identity.uid)_\(Int(Date().timeIntervalSince1970 * 1000))",
            squadId: document.documentID,
            senderId: "system_pujo",
            senderName: "Pujo Bot 🪈",
            text: "👋 \(userName) joined the squad!",
            timestamp: Date()
        )
        try await batch.commit()
        try? await squadRef.collection("messages").document(joinMessage.id)
            .setData(Self.messageDocument(joinMessage))

        applySquad(data, id: document.documentID)
        currentUserId = identity.uid
        members = [member]
        observeMembers(squadId: document.documentID, userId: identity.uid)
        syncLocationTrackingRequest()
        Haptics.notifySuccess()
    }

    func leaveSquad() async throws {
        guard let squadId = currentId, let userId = currentUserId ?? UserStateService.shared.firebaseUserId else {
            clearSavedSquad()
            return
        }
        let db = Firestore.firestore()
        let squadRef = db.collection("squads").document(squadId)
        let batch = db.batch()
        batch.updateData(["membersUid": FieldValue.arrayRemove([userId])], forDocument: squadRef)
        batch.deleteDocument(squadRef.collection("members").document(userId))
        if let name = members.first(where: { $0.id == userId })?.name {
            let message = ChatMessage(
                id: "leave_\(userId)_\(Int(Date().timeIntervalSince1970 * 1000))",
                squadId: squadId, senderId: "system_pujo", senderName: "Pujo Bot 🪈",
                text: "🏃 \(name) left the squad.", timestamp: Date()
            )
            batch.setData(Self.messageDocument(message), forDocument: squadRef.collection("messages").document(message.id))
        }
        try await batch.commit()
        clearSavedSquad()
    }

    func updateUserLocation(_ coord: CLLocationCoordinate2D) {
        guard shareLocation,
              LocationService.shared.isFixValid(maxAge: 30, maxAccuracy: 100) else { return }
        guard let userId = currentUserId, let squadId = currentId else { return }
        let fix = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let elapsed = Date().timeIntervalSince(lastLocationSyncDate ?? .distantPast)
        if let lastLocationSync,
           fix.distance(from: lastLocationSync) < 15,
           elapsed < 15 {
            return
        }
        lastLocationSync = fix
        lastLocationSyncDate = Date()
        if let index = members.firstIndex(where: { $0.id == userId }) {
            members[index].latitude = coord.latitude
            members[index].longitude = coord.longitude
            members[index].lastSeen = Date()
        }
        Task {
            try? await Firestore.firestore().collection("squads").document(squadId)
                .collection("members").document(userId).setData([
                    "lat": coord.latitude,
                    "lng": coord.longitude,
                    "last_seen": Int(Date().timeIntervalSince1970 * 1000),
                    "share_location": shareLocation,
                    "is_online": true
                ], merge: true)
        }
    }

    func toggleLocationSharing() {
        shareLocation.toggle()
        if let index = members.firstIndex(where: { $0.id == currentUserId }) {
            members[index].shareLocation = shareLocation
        }
        if let userId = currentUserId, let squadId = currentId {
            Task {
                try? await Firestore.firestore().collection("squads").document(squadId)
                    .collection("members").document(userId).setData(["share_location": shareLocation], merge: true)
            }
        }
        syncLocationTrackingRequest()
        Haptics.selection()
    }

    private func syncLocationTrackingRequest() {
        if hasActiveSquad && shareLocation {
            LocationService.shared.startLiveTracking(for: .squad)
        } else {
            LocationService.shared.stopLiveTracking(for: .squad)
        }
    }

    func setSeparationAlert(meters: Double) {
        separationAlertMeters = meters
        if let squadId = currentId {
            Task {
                try? await Firestore.firestore().collection("squads").document(squadId)
                    .updateData(["separationThresholdMeters": Int(meters)])
            }
        }
        Haptics.selection()
    }

    func setMeetupPoint(name: String, coordinate: CLLocationCoordinate2D) {
        meetupPointName = name
        meetupPointCoordinate = coordinate
        guard let squadId = currentId else { return }
        Task {
            try? await Firestore.firestore().collection("squads").document(squadId).updateData([
                "meetupPointName": name, "meetupLat": coordinate.latitude, "meetupLng": coordinate.longitude
            ])
        }
        Haptics.notifySuccess()
    }

    private func observeMembers(squadId: String, userId: String) {
        memberListener?.remove()
        connectionState = .connecting
        memberListener = Firestore.firestore().collection("squads").document(squadId)
            .collection("members").addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard let snapshot, error == nil else {
                        self.connectionState = .reconnecting
                        return
                    }
                    self.members = snapshot.documents.map { document in
                        Self.member(from: document.data(), id: document.documentID, userId: userId)
                    }
                    if let ownMember = self.members.first(where: { $0.id == userId }) {
                        self.shareLocation = ownMember.shareLocation
                        self.syncLocationTrackingRequest()
                    }
                    self.connectionState = .connected
                }
            }
    }

    private func applySquad(_ data: [String: Any], id: String) {
        currentId = id
        currentCode = data["squadCode"] as? String ?? currentCode
        currentName = data["name"] as? String ?? "Hop Squad"
        meetupPointName = data["meetupPointName"] as? String
        let lat = (data["meetupLat"] as? NSNumber)?.doubleValue
        let lng = (data["meetupLng"] as? NSNumber)?.doubleValue
        if let lat, let lng { meetupPointCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        if let meters = data["separationThresholdMeters"] as? NSNumber { separationAlertMeters = meters.doubleValue }
        UserDefaults.standard.set(id, forKey: savedSquadIdKey)
        UserDefaults.standard.set(currentCode, forKey: savedSquadCodeKey)
    }

    private func clearSavedSquad() {
        if let currentId { ChatService.shared.stopObserving(squadId: currentId) }
        LocationService.shared.stopLiveTracking(for: .squad)
        memberListener?.remove()
        memberListener = nil
        currentId = nil
        currentCode = nil
        currentName = nil
        currentUserId = nil
        lastLocationSync = nil
        lastLocationSyncDate = nil
        meetupPointCoordinate = nil
        meetupPointName = nil
        members = []
        connectionState = .offline
        UserDefaults.standard.removeObject(forKey: savedSquadIdKey)
        UserDefaults.standard.removeObject(forKey: savedSquadCodeKey)
    }

    private static func memberDocument(_ member: SquadMember) -> [String: Any] {
        [
            "id": member.id, "name": member.name,
            "lat": member.latitude, "lng": member.longitude,
            "status": member.status, "photo_url": member.photoUrl ?? "",
            "phone_number": member.phoneNumber ?? "",
            "is_host": member.isHost, "is_user": member.isUser,
            "share_location": member.shareLocation, "is_online": member.isOnline,
            "battery": member.batteryLevel, "batteryLevel": member.batteryLevel,
            "color": member.avatarColorHex,
            "last_seen": Int(member.lastSeen.timeIntervalSince1970 * 1000)
        ]
    }

    private static func messageDocument(_ message: ChatMessage) -> [String: Any] {
        [
            "id": message.id, "squadId": message.squadId,
            "senderId": message.senderId, "senderName": message.senderName,
            "senderPhotoUrl": message.senderPhotoUrl ?? "",
            "type": message.type.rawValue, "text": message.text ?? "",
            "mediaUrl": message.mediaUrl ?? "", "media_url": message.mediaUrl ?? "",
            "thumbnailUrl": message.thumbnailUrl ?? "",
            "timestamp": Int(message.timestamp.timeIntervalSince1970 * 1000)
        ]
    }

    private static func member(from data: [String: Any], id: String, userId: String) -> SquadMember {
        let lastSeenMillis = (data["last_seen"] as? NSNumber)?.doubleValue
        let photoURL = data["photo_url"] as? String ?? data["photoUrl"] as? String
        let phone = data["phone_number"] as? String ?? data["phoneNumber"] as? String
        return SquadMember(
            id: id,
            name: data["name"] as? String ?? "Hopper",
            latitude: (data["lat"] as? NSNumber)?.doubleValue ?? (data["latitude"] as? NSNumber)?.doubleValue ?? 22.5958,
            longitude: (data["lng"] as? NSNumber)?.doubleValue ?? (data["longitude"] as? NSNumber)?.doubleValue ?? 88.3725,
            status: data["status"] as? String ?? "Active • Pandal Hopping",
            lastSeen: lastSeenMillis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
            photoUrl: photoURL,
            phoneNumber: phone,
            isHost: data["is_host"] as? Bool ?? false,
            isUser: id == userId,
            shareLocation: data["share_location"] as? Bool ?? true,
            isOnline: data["is_online"] as? Bool ?? true,
            batteryLevel: (data["battery"] as? NSNumber)?.intValue ?? (data["batteryLevel"] as? NSNumber)?.intValue ?? 85,
            avatarColorHex: (data["color"] as? NSNumber)?.intValue ?? 0xFFFFB300
        )
    }

    private static func generateSquadCode() -> String {
        let characters = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return "PUJA" + String((0..<4).compactMap { _ in characters.randomElement() })
    }
}

enum SquadServiceError: LocalizedError {
    case invalidName
    case invalidCode
    case squadNotFound
    case squadClosed

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a squad name before creating it."
        case .invalidCode: return "Enter a valid 8-character squad code, such as PUJA7K9X."
        case .squadNotFound: return "No active squad was found for that code. Check the code and try again."
        case .squadClosed: return "That squad has been closed. Ask your host for a current invite code."
        }
    }
}
