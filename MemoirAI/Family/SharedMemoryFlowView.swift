import SwiftUI
import FirebaseFirestore

/// Entry point for a scanned memory that is not in the local store. Decides between
/// playback (owner or granted) and the request access flow, and live-updates when
/// the owner approves while the screen is open.
struct SharedMemoryFlowView: View {
    let route: SharedMemoryRoute

    @State private var status: SharedAccessService.GrantStatus? = nil
    @State private var requestListener: ListenerRegistration? = nil

    private let cream = LinenTheme.paper

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            switch status {
            case nil:
                ProgressView("Checking access…")
            case .some(.owner), .some(.granted):
                SharedMemoryView(route: route)
            case .some(.pending), .some(.denied), .some(.none):
                RequestAccessView(route: route, initialStatus: status ?? .none)
            }
        }
        .linenScreen()
        .navigationTitle("Shared memory")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            status = await SharedAccessService.shared.grantStatus(
                ownerId: route.ownerId,
                memoryId: route.memoryId
            )
            // While the request screen is up, flip to playback the moment the owner approves.
            if status == .some(.pending) || status == .some(.none) || status == .some(.denied) {
                requestListener = SharedAccessService.shared.observeMyRequestStatus(
                    ownerId: route.ownerId,
                    memoryId: route.memoryId
                ) { newStatus in
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

    private let darkText = LinenTheme.ink
    private let terracotta = LinenTheme.accent

    private var isPending: Bool { didSubmit || initialStatus == .pending }

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            Image(systemName: isPending ? "hourglass" : "person.2.fill")
                .font(.system(size: 52))
                .foregroundColor(terracotta)

            if isPending {
                VStack(spacing: 10) {
                    Text("Request sent")
                        .font(LinenTheme.heading(25))
                        .foregroundColor(darkText)
                    Text("The owner of this memoir will see your request in their app. This screen updates the moment they approve.")
                        .font(LinenTheme.body(15))
                        .foregroundColor(darkText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    Text("This memory belongs to someone else")
                        .font(LinenTheme.heading(25))
                        .foregroundColor(darkText)
                        .multilineTextAlignment(.center)
                    Text("Ask for access to hear their recorded memories. Tell them who you are so they recognize you.")
                        .font(LinenTheme.body(15))
                        .foregroundColor(darkText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                TextField("Your name", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(LinenTheme.body(16))
                    .padding(14)
                    .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(LinenTheme.body(13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Request access")
                            .font(LinenTheme.body(16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(canSubmit ? darkText : darkText.opacity(0.4), in: Capsule())
                .foregroundColor(LinenTheme.onAccent)
                .disabled(!canSubmit || isSubmitting)
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)
        }
        .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .linenScreen()
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
