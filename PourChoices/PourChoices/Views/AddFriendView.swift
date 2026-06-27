//
//  AddFriendView.swift
//  PourChoices
//
//  Search by username, see contact matches, and send friend requests or invites.
//

import SwiftUI

struct AddFriendView: View {
    @Bindable var friendsManager: FriendsManager
    let currentUID: String

    @State private var searchText = ""
    @State private var searchResult: FirestoreUser? = nil
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var sentRequests: Set<String> = []

    @State private var showingMessageCompose = false
    @State private var inviteUID: String = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Username search
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search by username", text: $searchText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: searchText) { _, _ in scheduleSearch() }
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let user = searchResult {
                    Section("Search Result") {
                        UserRow(
                            user: user,
                            currentUID: currentUID,
                            sentRequests: sentRequests,
                            friendsManager: friendsManager,
                            onSendRequest: { uid in
                                Task {
                                    await friendsManager.sendRequest(to: uid)
                                    sentRequests.insert(uid)
                                }
                            }
                        )
                    }
                } else if let error = searchError {
                    Section {
                        Text(error).foregroundStyle(.secondary).font(.subheadline)
                    }
                }

                // Contact suggestions
                if !friendsManager.contactSuggestions.isEmpty {
                    Section("People You May Know") {
                        ForEach(friendsManager.contactSuggestions) { user in
                            UserRow(
                                user: user,
                                currentUID: currentUID,
                                sentRequests: sentRequests,
                                friendsManager: friendsManager,
                                onSendRequest: { uid in
                                    Task {
                                        await friendsManager.sendRequest(to: uid)
                                        sentRequests.insert(uid)
                                    }
                                }
                            )
                        }
                    }
                }

                // Invite non-users via text
                Section {
                    Button {
                        showingMessageCompose = true
                    } label: {
                        Label("Invite a Friend via Text", systemImage: "message.fill")
                    }
                }
            }
            .navigationTitle("Add Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await friendsManager.loadContactSuggestions()
            }
            .sheet(isPresented: $showingMessageCompose) {
                if MessageComposeView.canSendText {
                    MessageComposeView(
                        recipients: nil,
                        messageBody: "Join me on PourChoices! pourchocies://invite?from=\(currentUID)"
                    ) {
                        showingMessageCompose = false
                    }
                    .ignoresSafeArea()
                } else {
                    Text("Messaging is not available on this device.")
                        .padding()
                }
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchResult = nil
        searchError = nil
        guard !searchText.isEmpty else { return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            guard !Task.isCancelled else { return }
            let result = await friendsManager.searchByUsername(searchText)
            await MainActor.run {
                isSearching = false
                if let user = result {
                    searchResult = user
                } else {
                    searchError = "No user found with username \"@\(searchText)\""
                }
            }
        }
    }
}

// MARK: - User Row

private struct UserRow: View {
    let user: FirestoreUser
    let currentUID: String
    let sentRequests: Set<String>
    let friendsManager: FriendsManager
    let onSendRequest: (String) -> Void

    private var isFriend: Bool { friendsManager.friends.contains(where: { $0.uid == user.uid }) }
    private var isPending: Bool {
        friendsManager.outgoingRequests.contains(where: { $0.participantUIDs.contains(user.uid) })
        || sentRequests.contains(user.uid)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(user.username ?? user.uid)")
                    .font(.headline)
                if let name = user.displayName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if user.uid == currentUID {
                Text("You").foregroundStyle(.secondary).font(.subheadline)
            } else if isFriend {
                Label("Friends", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else if isPending {
                Text("Requested").foregroundStyle(.secondary).font(.subheadline)
            } else {
                Button("Add") { onSendRequest(user.uid) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}
