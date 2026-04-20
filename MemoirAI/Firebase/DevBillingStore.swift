import Foundation
import FirebaseAuth
import FirebaseFirestore

actor DevBillingStore {
    static let shared = DevBillingStore()
    private let db = Firestore.firestore()

    private init() {}

    func upsertEntry(day: Date, providerTotal: Double, manualTotal: Double, note: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let dayKey = DevBillingStore.dayKey(from: day)
        let ref = db.collection("users").document(userId)
            .collection("devBilling")
            .document(dayKey)

        let payload: [String: Any] = [
            "dayKey": dayKey,
            "dateStart": Timestamp(date: Calendar.current.startOfDay(for: day)),
            "providerTotal": providerTotal,
            "manualTotal": manualTotal,
            "note": note,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await ref.setData(payload, merge: true)
        } catch {
            print("⚠️ DevBillingStore upsert failed: \(error.localizedDescription)")
        }
    }

    func fetchEntries(start: Date, end: Date) async -> [DevBillingEntry] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        let query = db.collection("users").document(userId)
            .collection("devBilling")
            .whereField("dateStart", isGreaterThanOrEqualTo: Timestamp(date: startDay))
            .whereField("dateStart", isLessThanOrEqualTo: Timestamp(date: endDay))
            .order(by: "dateStart", descending: true)

        do {
            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { doc in
                let data = doc.data()
                let date = (data["dateStart"] as? Timestamp)?.dateValue() ?? Date()
                return DevBillingEntry(
                    id: doc.documentID,
                    dayKey: data["dayKey"] as? String ?? doc.documentID,
                    date: date,
                    providerTotal: (data["providerTotal"] as? NSNumber)?.doubleValue ?? 0,
                    manualTotal: (data["manualTotal"] as? NSNumber)?.doubleValue ?? 0,
                    note: data["note"] as? String ?? "",
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
                )
            }
        } catch {
            print("⚠️ DevBillingStore fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    static func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
