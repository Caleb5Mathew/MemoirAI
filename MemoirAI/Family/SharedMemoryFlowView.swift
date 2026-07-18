import SwiftUI
import FirebaseFirestore

/// Entry point for a scanned memory that is not in the local store. Decides between
/// playback (owner or granted) and the request access flow, and live-updates when
/// the owner approves while the screen is open.
struct SharedMemoryFlowView: View {
    let route: SharedMemoryRoute

    @State private var status: SharedAccessService.GrantStatus? = nil
    @State private var requestListener: ListenerRegistration? = nil

    private let cream = Color(red: 0.98, green: 0.94, blue: 0.86)

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            switch status {
            case nil:
                ProgressView("Checking access…")
            case .owner, .granted:
                SharedMemoryView(route: route)
            case .pending, .denied, .none:
                RequestAccessView(route: route, initialStatus: status ?? .none)
            }
        }
        .navigationTitle("Shared Memory")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            status = await SharedAccessService.shared.grantStatus(ownerId: route.ownerId)
            // While the request screen is up, flip to playback the moment the owner approves.
            if status == .pending || status == .none || status == .denied {
                requestListener = SharedAccessService.shared.observeMyRequestStatus(ownerId: route.ownerId) { newStatus in
                    if newStatus == .granted {
                        Haptics.success()
                        status = .granted
                    }
                }
            }
        }
        .onDisappear {
            requestListener?.remove()
            requestListener = nil
        }
    }
}

/// Request access to another account's shared memories.
struct RequestAccessView: View {
    let route: SharedMemoryRoute
    let initialStatus: SharedAccessService.GrantStatus

    @State private var displayName: String = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String? = nil

    private let darkText = Color(red: 0.25, green: 0.2, blue: 0.15)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)

    private var isPending: Bool { didSubmit || initialStatus == .pending }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: isPending ? "hourglass" : "person.2.fill")
                .font(.system(size: 52))
                .foregroundColor(terracotta)

            if isPending {
                VStack(spacing: 10) {
                    Text("Request sent")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(darkText)
                    Text("The owner of this memoir will see your request in their app. This screen updates the moment they approve.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(darkText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)
            } else {
                VStack(spacing: 10) {
                    Text("This memory belongs to someone else")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(darkText)
                        .multilineTextAlignment(.center)
                    Text("Ask for access to hear their recorded memories. Tell them who you are so they recognize you.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(darkText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)

                TextField("Your name", text: $displayName)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 36)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 36)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Request access")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(canSubmit ? darkText : darkText.opacity(0.4), in: Capsule())
                .foregroundColor(.white)
                .disabled(!canSubmit || isSubmitting)
                .padding(.horizontal, 36)
            }

            Spacer()
        }
    }

    private var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Haptics.tap()
        Task {
            do {
                try await SharedAccessService.shared.submitAccessRequest(
                    ownerId: route.ownerId,
                    memoryId: route.memoryId,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                didSubmit = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
