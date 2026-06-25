//
//  FirestoreService.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/25/26.
//


import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Firestore Collections
private enum Collection {
    static let users = "users"
    static let friends = "friends"
    static let sessions = "sessions"
}

// MARK: - User Profile Model
struct FirestoreUser: Codable {
    let uid: String
    var displayName: String?
    var email: String?
    var username: String?
    var avatarURL: String?
    let createdAt: Date
    var updatedAt: Date
}

// MARK: - FirestoreService
@Observable
final class FirestoreService {

    static let shared = FirestoreService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - User

    /// Creates a user document if one doesn't already exist.
    /// Safe to call on every sign-in -- will not overwrite existing data.
    func createUserIfNeeded(uid: String, displayName: String?, email: String?) async {
        let ref = db.collection(Collection.users).document(uid)
        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists { return }
            let user = FirestoreUser(
                uid: uid,
                displayName: displayName,
                email: email,
                username: nil,
                avatarURL: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            try ref.setData(from: user)
        } catch {
            print("[FirestoreService] createUserIfNeeded failed: \(error)")
        }
    }

    /// Fetches a user profile by UID.
    func getUser(uid: String) async -> FirestoreUser? {
        let ref = db.collection(Collection.users).document(uid)
        do {
            return try await ref.getDocument(as: FirestoreUser.self)
        } catch {
            print("[FirestoreService] getUser failed: \(error)")
            return nil
        }
    }

    /// Updates mutable profile fields.
    func updateUser(uid: String, displayName: String? = nil, username: String? = nil, avatarURL: String? = nil) async {
        let ref = db.collection(Collection.users).document(uid)
        var updates: [String: Any] = ["updatedAt": Date()]
        if let displayName { updates["displayName"] = displayName }
        if let username { updates["username"] = username }
        if let avatarURL { updates["avatarURL"] = avatarURL }
        do {
            try await ref.updateData(updates)
        } catch {
            print("[FirestoreService] updateUser failed: \(error)")
        }
    }
}

