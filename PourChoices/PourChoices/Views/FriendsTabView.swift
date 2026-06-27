//
//  FriendsTabView.swift
//  PourChoices
//
//  The Friends tab — pending requests, current friends, and Add Friends button.
//

import SwiftUI

struct FriendsTabView: View {
    @Bindable var friendsManager: FriendsManager
    let currentUID: String

    @State private var showingAddFriend = false

    var body: some View {
        NavigationStack {
            Group {
                if friendsManager.isLoading && friendsManager.friends.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Incoming friend requests
                        if !friendsManager.incomingRequests.isEmpty {
                            Section("Friend Requests") {
                                ForEach(friendsManager.incomingRequests, id: \.friendship.id) { item in
                                    IncomingRequestRow(
                                        sender: item.sender,
                                        onAccept: {
                                            Task { await friendsManager.acceptRequest(friendshipID: item.friendship.id) }
                                        },
                                        onDecline: {
                                            Task { await friendsManager.declineRequest(friendshipID: item.friendship.id) }
                                        }
                                    )
                                }
                            }
                        }

                        // Friends list
                        if !friendsManager.friends.isEmpty {
                            Section("Friends (\(friendsManager.friends.count))") {
                                ForEach(friendsManager.friends, id: \.uid) { friend in
                                    FriendRow(friend: friend)
                                }
                                .onDelete { indexSet in
                                    removeFriends(at: indexSet)
                                }
                            }
                        }

                        // Empty state (no requests, no friends)
                        if friendsManager.friends.isEmpty && friendsManager.incomingRequests.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "No Friends Yet",
                                    systemImage: "person.2",
                                    description: Text("Add friends to see them here")
                                )
                            }
                        }
                    }
                    .refreshable { await friendsManager.loadAll() }
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .task { await friendsManager.loadAll() }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendView(friendsManager: friendsManager, currentUID: currentUID)
            }
            .alert("Error", isPresented: Binding(
                get: { friendsManager.errorMessage != nil },
                set: { if !$0 { friendsManager.errorMessage = nil } }
            )) {
                Button("OK") { friendsManager.errorMessage = nil }
            } message: {
                Text(friendsManager.errorMessage ?? "")
            }
        }
    }

    private func removeFriends(at indexSet: IndexSet) {
        let friendsList = friendsManager.friends
        for index in indexSet {
            let friend = friendsList[index]
            // Find the friendship document ID for this friend pair
            let docID = [currentUID, friend.uid].sorted().joined(separator: "_")
            Task { await friendsManager.removeFriend(friendshipID: docID) }
        }
    }
}

// MARK: - Incoming Request Row

private struct IncomingRequestRow: View {
    let sender: FirestoreUser
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(sender.username ?? sender.uid)")
                    .font(.headline)
                if let name = sender.displayName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Decline", role: .destructive) { onDecline() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    let friend: FirestoreUser

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(friend.username ?? friend.uid)")
                    .font(.headline)
                if let name = friend.displayName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        }
    }
}
