import Contacts
import Foundation

/// Lesender Zugriff auf das Adressbuch.
@MainActor
final class ContactsService {
    static let shared = ContactsService()

    private let store = CNContactStore()

    struct ContactSummary: Sendable {
        let name: String
        let organization: String
        let phones: [String]
        let emails: [String]
    }

    var authorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        #if os(iOS)
        if #available(iOS 18.0, *), status == .limited { return true }
        #endif
        return false
    }

    func requestAccess() async -> Bool {
        if authorized { return true }
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return false }
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    func search(name: String) async -> [ContactSummary] {
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
            ]
            let predicate = CNContact.predicateForContacts(matchingName: name)
            let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            return contacts.prefix(8).map { contact in
                ContactSummary(
                    name: [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                    organization: contact.organizationName,
                    phones: contact.phoneNumbers.map { labeled in
                        let label = labeled.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? ""
                        return label.isEmpty ? labeled.value.stringValue : "\(label): \(labeled.value.stringValue)"
                    },
                    emails: contact.emailAddresses.map { $0.value as String })
            }
        }.value
    }

    /// Erste Telefonnummer bzw. E-Mail-Adresse einer Person – für Nachrichtenentwürfe.
    func firstAddress(for name: String, email: Bool) async -> String? {
        guard authorized else { return nil }
        let match = await search(name: name).first
        if email { return match?.emails.first }
        guard let phone = match?.phones.first else { return nil }
        // Beschriftung („Mobil: …“) entfernen
        return phone.components(separatedBy: ": ").last
    }
}
