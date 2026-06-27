//
//  ContactsService.swift
//  PourChoices
//
//  Fetches device contacts, normalizes phone numbers to E.164,
//  and produces SHA-256 hashes for privacy-safe friend matching.
//

import Foundation
import Contacts
import CryptoKit

struct ContactMatch: Identifiable {
    let id = UUID()
    let name: String
    let phoneHash: String
    let phoneNumber: String // kept locally, never sent to Firestore
}

enum ContactsService {

    /// Requests access to Contacts and returns hashed phone numbers.
    /// Never returns the raw phone numbers for remote use — only the hash.
    static func fetchContactHashes() async -> [ContactMatch] {
        let store = CNContactStore()

        // Request permission if needed
        let granted: Bool
        do {
            granted = try await store.requestAccess(for: .contacts)
        } catch {
            print("[ContactsService] Permission error: \(error)")
            return []
        }
        guard granted else {
            print("[ContactsService] Contacts access denied")
            return []
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        var matches: [ContactMatch] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                for phoneValue in contact.phoneNumbers {
                    let raw = phoneValue.value.stringValue
                    guard let e164 = normalizeToE164(raw) else { continue }
                    let hash = sha256(e164)
                    matches.append(ContactMatch(name: name.isEmpty ? raw : name, phoneHash: hash, phoneNumber: e164))
                }
            }
        } catch {
            print("[ContactsService] Fetch error: \(error)")
        }
        return matches
    }

    // MARK: - Helpers

    /// Very simple E.164 normalizer: strips non-digits, prepends +1 for 10-digit US numbers.
    private static func normalizeToE164(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        switch digits.count {
        case 11 where digits.hasPrefix("1"):
            return "+\(digits)"
        case 10:
            return "+1\(digits)"
        default:
            if digits.count > 11 { return "+\(digits)" }
            return nil
        }
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
