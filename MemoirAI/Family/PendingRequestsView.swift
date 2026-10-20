import SwiftUI

/// Owner-side list of pending family and friends access requests, with approve/deny.
struct PendingRequestsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var requests: [SharedAccessService.MemoryAccessRequest] = []
    @State private var grants: [SharedAccessService.MemoryAccessGrant] = []
    @State private var isLoading = true
    @State private var actingOn: Set<String> = []
    @State private var errorMessage: String? = nil

    private let cream = LinenTheme.paper
    private let darkText = LinenTheme.ink
    private let terracotta = LinenTheme.accent

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            if isLoading {
                ProgressView("Loading requests…")
            } else if requests.isEmpty && grants.isEmpty {
                ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40))
                        .foregroundColor(terracotta)
                    Text("No pending requests")
                        .font(LinenTheme.heading(25))
                        .foregroundColor(darkText)
                    Text("When someone scans a page of your book and asks to hear your memories, their request shows up here.")
                        .font(LinenTheme.body(14))
                        .foregroundColor(darkText.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 40)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(LinenTheme.body(13))
                                .foregroundColor(.red)
                        }
                        ForEach(requests) { request in
                            requestRow(request)
                        }
                        if !grants.isEmpty {
                            Text("Currently shared")
                                .font(LinenTheme.body(16, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            ForEach(grants) { grant in
                                grantRow(grant)
                            }
                        }
                    }
                    .padding(24)
                    .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
                }
            }
        }
        .linenScreen()
        .navigationTitle("Family access")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func grantRow(_ grant: SharedAccessService.MemoryAccessGrant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared memory")
                .font(LinenTheme.body(16, weight: .semibold))
                .foregroundColor(darkText)
            Text("Recipient \(grant.requesterId.prefix(8))… · Memory \(grant.memoryId.prefix(8))…")
                .font(LinenTheme.body(12))
                .foregroundColor(darkText.opacity(0.6))
            Button(role: .destructive) {
                revoke(grant)
            } label: {
                Text("Revoke access")
                    .font(LinenTheme.body(14, weight: .semibold))
            }
            .disabled(actingOn.contains(grant.id))
        }
        .padding(16)
        .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func requestRow(_ request: SharedAccessService.MemoryAccessRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requesterDisplayName)
                    .font(LinenTheme.body(16, weight: .semibold))
                    .foregroundColor(darkText)
                Text("wants to hear your shared memories")
                    .font(LinenTheme.body(13))
                    .foregroundColor(darkText.opacity(0.6))
            }
            let actionLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            actionLayout {
                Button {
                    respond(to: request, approve: true)
                } label: {
                    Text("Approve")
                        .font(LinenTheme.body(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: 48)
                        .background(darkText, in: Capsule())
                        .foregroundColor(LinenTheme.onAccent)
                }
                Button {
                    respond(to: request, approve: false)
                } label: {
                    Text("Decline")
                        .font(LinenTheme.body(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: 48)
                        .background(Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(darkText.opacity(0.35), lineWidth: 1))
                        .foregroundColor(darkText)
                }
            }
            .disabled(actingOn.contains(request.id))
            .opacity(actingOn.contains(request.id) ? 0.5 : 1)
        }
        .padding(16)
        .background(LinenTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func refresh() async {
        do {
            async let pending = SharedAccessService.shared.fetchPendingRequests()
            async let active = SharedAccessService.shared.fetchActiveGrants()
            requests = try await pending
            grants = try await active
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func respond(to request: SharedAccessService.MemoryAccessRequest, approve: Bool) {
        actingOn.insert(request.id)
        Task {
            do {
                if approve {
                    try await SharedAccessService.shared.approve(requestDocumentId: request.id)
                    Haptics.success()
                } else {
                    try await SharedAccessService.shared.deny(requestDocumentId: request.id)
                    Haptics.selection()
                }
                requests.removeAll { $0.id == request.id }
            } catch {
                errorMessage = error.localizedDescription
            }
            actingOn.remove(request.id)
        }
    }

    private func revoke(_ grant: SharedAccessService.MemoryAccessGrant) {
        actingOn.insert(grant.id)
        Task {
            do {
                try await SharedAccessService.shared.revoke(grant: grant)
                grants.removeAll { $0.id == grant.id }
                Haptics.selection()
            } catch {
                errorMessage = error.localizedDescription
            }
            actingOn.remove(grant.id)
        }
    }
}
