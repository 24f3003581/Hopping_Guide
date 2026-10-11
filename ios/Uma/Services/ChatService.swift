// Services/ChatService.swift — Firestore-backed squad chat shared with Android.

import Foundation
import Observation
import FirebaseCore
import FirebaseFirestore

@MainActor
@Observable
final class ChatService {
    static let shared = ChatService()
    private(set) var messagesBySquad: [String: [ChatMessage]] = [:]
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    func messages(for squadId: String) -> [ChatMessage] {
        messagesBySquad[squadId] ?? []
    }

    func observe(squadId: String) {
        guard FirebaseApp.app() != nil, listeners[squadId] == nil else { return }
        listeners[squadId] = Firestore.firestore()
            .collection("squads").document(squadId)
            .collection("messages")
            .order(by: "timestamp")
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    guard let snapshot, error == nil else { return }
                    self.messagesBySquad[squadId] = snapshot.documents.map { document in
                        Self.message(from: document.data(), id: document.documentID, squadId: squadId)
                    }
                }
            }
    }

    func stopObserving(squadId: String) {
        listeners.removeValue(forKey: squadId)?.remove()
    }

    func send(squadId: String, senderName: String, text: String) async throws {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let identity = try await UserStateService.shared.ensureFirebaseIdentity()
        let timestamp = Date()
        let message = ChatMessage(
            id: "msg_\(UUID().uuidString.lowercased())",
            squadId: squadId,
            senderId: identity.uid,
            senderName: senderName,
            text: content,
            timestamp: timestamp
        )
        let squadRef = Firestore.firestore().collection("squads").document(squadId)
        let batch = Firestore.firestore().batch()
        batch.setData(Self.documentData(message), forDocument: squadRef.collection("messages").document(message.id))
        batch.updateData([
            "lastMessage": content,
            "lastMessageTime": Int(timestamp.timeIntervalSince1970 * 1000)
        ], forDocument: squadRef)
        try await batch.commit()
        Haptics.light()
    }

    private static func message(from data: [String: Any], id: String, squadId: String) -> ChatMessage {
        let rawTimestamp = data["timestamp"]
        let timestamp: Date
        if let firestoreTimestamp = rawTimestamp as? Timestamp {
            timestamp = firestoreTimestamp.dateValue()
        } else if let number = rawTimestamp as? NSNumber {
            timestamp = Date(timeIntervalSince1970: number.doubleValue / 1000)
        } else if let date = rawTimestamp as? Date {
            timestamp = date
        } else {
            timestamp = Date()
        }

        return ChatMessage(
            id: data["id"] as? String ?? id,
            squadId: data["squadId"] as? String ?? squadId,
            senderId: data["senderId"] as? String ?? "unknown",
            senderName: data["senderName"] as? String ?? "Hopper",
            senderPhotoUrl: data["senderPhotoUrl"] as? String ?? data["sender_photo_url"] as? String,
            type: ChatMessageType.from(data["type"] as? String),
            text: data["text"] as? String,
            mediaUrl: data["mediaUrl"] as? String ?? data["media_url"] as? String,
            thumbnailUrl: data["thumbnailUrl"] as? String ?? data["thumbnail_url"] as? String,
            timestamp: timestamp
        )
    }

    private static func documentData(_ message: ChatMessage) -> [String: Any] {
        [
            "id": message.id,
            "squadId": message.squadId,
            "senderId": message.senderId,
            "senderName": message.senderName,
            "senderPhotoUrl": message.senderPhotoUrl ?? "",
            "type": message.type.rawValue,
            "text": message.text ?? "",
            "mediaUrl": message.mediaUrl ?? "",
            "media_url": message.mediaUrl ?? "",
            "thumbnailUrl": message.thumbnailUrl ?? "",
            "timestamp": Int(message.timestamp.timeIntervalSince1970 * 1000)
        ]
    }
}
