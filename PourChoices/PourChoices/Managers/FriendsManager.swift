//
//  FriendsManager.swift
//  PourChoices
//
//  Observable manager for the friends system. Owned by ContentView so it
//  stays alive for the full authenticated session.
//

import Foundation

@Observable
final class FriendsManager {

    // MARK: - State

    /// All accepted friends (resolved to FirestoreUser profiles).
    var friends: [FirestoreUser] = []
    /// Incoming pending requests (the current user is NOT the initiator).
    var incomingRequests: [(friendship: FriendshipDocument, sender: FirestoreUser)] = []
    /// Outgoing pending requests sent by the current user.
    var outgoingRequests: [FriendshipDocument] = []
    /// Users found via contact phone hash matching.
    var contactSuggestions: [FirestoreUser] = []

    var isLoading = false
    var errorMessage: String?

    private let uid: String

    init(uid: String) {
        self.uid = uid
    }

    // MARK: - Load

    @MainActor
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        let friendships = await FirestoreService.shared.getFriendships(for: uid)

        let acceptedFriendships = friendships.filter { $0.status == .accepted }
        let pendingFriendships  = friendships.filter { $0.status == .pending }

        // Resolve UIDs to user profiles
        let friendUIDs = acceptedFriendships.flatMap { $0.participantUIDs }.filter { $0 != uid }
        friends = await FirestoreService.shared.getUsersByUIDs(friendUIDs)

        // Incoming = pending where we are NOT the initiator
        let incomingFriendships = pendingFriendships.filter { $0.initiatorUID != uid }
        let senderUIDs = incomingFriendships.map { $0.initiatorUID }
        let senders = await FirestoreService.shared.getUsersByUIDs(senderUIDs)
        let senderMap = Dictionary(uniqueKeysWithValues: senders.map { ($0.uid, $0) })
        incomingRequests = incomingFriendships.compactMap { f in
            guard let sender = senderMap[f.initiatorUID] else { return nil }
            return (friendship: f, sender: sender)
        }

        // Outgoing = pending where we ARE the initiator
        outgoingRequests = pendingFriendships.filter { $0.initiatorUID == uid }
    }

    @MainActor
    func loadContactSuggestions() async {
        let contacts = await ContactsService.fetchContactHashes()
        guard !contacts.isEmpty else { return }
        let hashes = contacts.map { $0.phoneHash }
        let matched = await FirestoreService.shared.findUsersByPhoneHashes(hashes)
        // Exclude self and existing friends/requests
        let knownUIDs = Set(friends.map { $0.uid }
            + incomingRequests.map { $0.sender.uid }
            + outgoingRequests.flatMap { $0.participantUIDs }
            + [uid])
        contactSuggestions = matched.filter { !knownUIDs.contains($0.uid) }
    }

    // MARK: - Actions

    @MainActor
    func sendRequest(to targetUID: String) async {
        do {
            try await FirestoreService.shared.sendFriendRequest(from: uid, to: targetUID)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func acceptRequest(friendshipID: String) async {
        do {
            try await FirestoreService.shared.acceptFriendRequest(friendshipID: friendshipID)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func declineRequest(friendshipID: String) async {
        do {
            try await FirestoreService.shared.removeFriendship(friendshipID: friendshipID)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func removeFriend(friendshipID: String) async {
        do {
            try await FirestoreService.shared.removeFriendship(friendshipID: friendshipID)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Search

    func searchByUsername(_ username: String) async -> FirestoreUser? {
        await FirestoreService.shared.getUserByUsername(username)
    }
}
