//
//  FirestoreService.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/25/26.
//


import Foundation
import FirebaseFirestore
import FirebaseAuth
import CryptoKit

// MARK: - Firestore Collections
private enum Collection {
    static let users       = "users"
    static let usernames   = "usernames"
    static let friendships = "friendships"
    static let sessions    = "sessions"
}

// MARK: - User Profile Model
struct FirestoreUser: Codable, Identifiable {
    var id: String { uid }
    let uid: String
    var displayName: String?
    var email: String?
    var username: String?
    var avatarURL: String?
    var phoneNumber: String?
    var phoneHash: String?
    var lastUsernameChange: Date?
    let createdAt: Date
    var updatedAt: Date
}

// MARK: - Friendship Model

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
}

struct FriendshipDocument: Codable, Identifiable {
    /// Canonical document ID: sorted UIDs joined by "_"
    var id: String
    var participantUIDs: [String]
    var initiatorUID: String
    var status: FriendshipStatus
    var createdAt: Date
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
            if snapshot.exists {
                // Document may have been created by claimUsername (merge) before
                // signInToFirebase runs. Back-fill displayName/email if missing.
                var updates: [String: Any] = ["updatedAt": Date()]
                let data = snapshot.data() ?? [:]
                if data["displayName"] == nil, let displayName { updates["displayName"] = displayName }
                if data["email"] == nil, let email { updates["email"] = email }
                if updates.count > 1 { // more than just updatedAt
                    try await ref.updateData(updates)
                }
                return
            }
            let user = FirestoreUser(
                uid: uid,
                displayName: displayName,
                email: email,
                username: nil,
                avatarURL: nil,
                phoneNumber: nil,
                phoneHash: nil,
                lastUsernameChange: nil,
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

    /// Fetches multiple user profiles by UID (batched, max 30 per Firestore `in` query).
    func getUsersByUIDs(_ uids: [String]) async -> [FirestoreUser] {
        guard !uids.isEmpty else { return [] }
        var results: [FirestoreUser] = []
        // Firestore `in` queries support max 30 items
        let batches = stride(from: 0, to: uids.count, by: 30).map {
            Array(uids[$0..<min($0 + 30, uids.count)])
        }
        for batch in batches {
            do {
                let snapshot = try await db.collection(Collection.users)
                    .whereField("uid", in: batch)
                    .getDocuments()
                let users = snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) }
                results.append(contentsOf: users)
            } catch {
                print("[FirestoreService] getUsersByUIDs batch failed: \(error)")
            }
        }
        return results
    }

    /// Searches for a user by exact username.
    func getUserByUsername(_ username: String) async -> FirestoreUser? {
        let lowercased = username.lowercased()
        do {
            // Check the usernames collection to get the UID, then fetch the user doc
            let usernameDoc = try await db.collection(Collection.usernames).document(lowercased).getDocument()
            guard usernameDoc.exists, let uid = usernameDoc.data()?["uid"] as? String else { return nil }
            return await getUser(uid: uid)
        } catch {
            print("[FirestoreService] getUserByUsername failed: \(error)")
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

    // MARK: - Username

    /// Returns true if the username is available (not taken).
    func isUsernameAvailable(_ username: String) async -> Bool {
        let lowercased = username.lowercased()
        do {
            let doc = try await db.collection(Collection.usernames).document(lowercased).getDocument()
            return !doc.exists
        } catch {
            print("[FirestoreService] isUsernameAvailable failed: \(error)")
            return false
        }
    }

    /// Atomically claims a username for a user.
    /// Throws if the username is already taken.
    func claimUsername(_ username: String, uid: String) async throws {
        let lowercased = username.lowercased()
        let usernameRef = db.collection(Collection.usernames).document(lowercased)
        let userRef = db.collection(Collection.users).document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            let usernameDoc: DocumentSnapshot
            do {
                usernameDoc = try transaction.getDocument(usernameRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            guard !usernameDoc.exists else {
                errorPointer?.pointee = NSError(
                    domain: "FirestoreService",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Username already taken."]
                )
                return nil
            }
            transaction.setData(["uid": uid], forDocument: usernameRef)
            // Use merge so this works even if the user doc hasn't been fully written yet
            transaction.setData(["username": lowercased, "updatedAt": Date()], forDocument: userRef, merge: true)
            return nil
        }
    }

    /// Changes a username: releases old name, claims new name, updates user doc.
    /// Requires that `lastUsernameChange` is either nil or more than 6 months ago.
    func changeUsername(from oldUsername: String, to newUsername: String, uid: String) async throws {
        let oldLower = oldUsername.lowercased()
        let newLower = newUsername.lowercased()
        let oldRef = db.collection(Collection.usernames).document(oldLower)
        let newRef = db.collection(Collection.usernames).document(newLower)
        let userRef = db.collection(Collection.users).document(uid)

        _ = try await db.runTransaction { transaction, errorPointer in
            let newDoc: DocumentSnapshot
            do {
                newDoc = try transaction.getDocument(newRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            guard !newDoc.exists else {
                errorPointer?.pointee = NSError(
                    domain: "FirestoreService",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Username already taken."]
                )
                return nil
            }
            transaction.deleteDocument(oldRef)
            transaction.setData(["uid": uid], forDocument: newRef)
            transaction.updateData([
                "username": newLower,
                "lastUsernameChange": Date(),
                "updatedAt": Date()
            ], forDocument: userRef)
            return nil
        }
    }

    // MARK: - Phone

    /// Saves a verified phone number and its SHA-256 hash to the user doc.
    func saveVerifiedPhone(uid: String, phoneNumber: String, phoneHash: String) async {
        let ref = db.collection(Collection.users).document(uid)
        do {
            try await ref.updateData([
                "phoneNumber": phoneNumber,
                "phoneHash": phoneHash,
                "updatedAt": Date()
            ])
        } catch {
            print("[FirestoreService] saveVerifiedPhone failed: \(error)")
        }
    }

    /// Finds users whose phone hashes match the given list.
    /// Batched in groups of 30 (Firestore `in` limit).
    func findUsersByPhoneHashes(_ hashes: [String]) async -> [FirestoreUser] {
        guard !hashes.isEmpty else { return [] }
        var results: [FirestoreUser] = []
        let batches = stride(from: 0, to: hashes.count, by: 30).map {
            Array(hashes[$0..<min($0 + 30, hashes.count)])
        }
        for batch in batches {
            do {
                let snapshot = try await db.collection(Collection.users)
                    .whereField("phoneHash", in: batch)
                    .getDocuments()
                let users = snapshot.documents.compactMap { try? $0.data(as: FirestoreUser.self) }
                results.append(contentsOf: users)
            } catch {
                print("[FirestoreService] findUsersByPhoneHashes batch failed: \(error)")
            }
        }
        return results
    }

    // MARK: - Friendships

    /// Canonical friendship document ID: sorted UIDs joined by "_".
    private func friendshipID(uid1: String, uid2: String) -> String {
        [uid1, uid2].sorted().joined(separator: "_")
    }

    /// Sends a friend request from `fromUID` to `toUID`.
    func sendFriendRequest(from fromUID: String, to toUID: String) async throws {
        let docID = friendshipID(uid1: fromUID, uid2: toUID)
        let ref = db.collection(Collection.friendships).document(docID)
        let friendship = FriendshipDocument(
            id: docID,
            participantUIDs: [fromUID, toUID],
            initiatorUID: fromUID,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try ref.setData(from: friendship)
    }

    /// Accepts a friend request.
    func acceptFriendRequest(friendshipID: String) async throws {
        let ref = db.collection(Collection.friendships).document(friendshipID)
        try await ref.updateData(["status": FriendshipStatus.accepted.rawValue, "updatedAt": Date()])
    }

    /// Declines or cancels a friend request / removes a friend.
    func removeFriendship(friendshipID: String) async throws {
        let ref = db.collection(Collection.friendships).document(friendshipID)
        try await ref.delete()
    }

    /// Returns all friendship documents (pending or accepted) for a given UID.
    func getFriendships(for uid: String) async -> [FriendshipDocument] {
        do {
            let snapshot = try await db.collection(Collection.friendships)
                .whereField("participantUIDs", arrayContains: uid)
                .getDocuments()
            return snapshot.documents.compactMap { doc -> FriendshipDocument? in
                guard var friendship = try? doc.data(as: FriendshipDocument.self) else { return nil }
                friendship.id = doc.documentID
                return friendship
            }
        } catch {
            print("[FirestoreService] getFriendships failed: \(error)")
            return []
        }
    }
}

