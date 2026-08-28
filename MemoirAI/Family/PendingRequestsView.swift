import SwiftUI

/// Owner-side list of pending family and friends access requests, with approve/deny.
struct PendingRequestsView: View {
    @State private var requests: [SharedAccessService.MemoryAccessRequest] = []
    @State private var grants: [SharedAccessService.MemoryAccessGrant] = []
    @State private var isLoading = true
    @State private var actingOn: Set<String> = []
    @State private var errorMessage: String? = nil

    private let cream = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let darkText = Color(red: 0.25, green: 0.2, blue: 0.15)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()
            if isLoading {
                ProgressView("Loading requests…")
            } else if requests.isEmpty && grants.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40))
                        .foregroundColor(terracotta)
                    Text("No pending requests")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(darkText)
                    Text("When someone scans a page of your book and asks to hear your memories, their request shows up here.")
                        .font(.system(size: 14))
                        .foregroundColor(darkText.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        ForEach(requests) { request in
                            requestRow(request)
                        }
                        if !grants.isEmpty {
                            Text("Currently shared")
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            ForEach(grants) { grant in
                                grantRow(grant)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Access Requests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func grantRow(_ grant: SharedAccessService.MemoryAccessGrant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared memory")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundColor(darkText)
            Text("Recipient \(grant.requesterId.prefix(8))… · Memory \(grant.memoryId.prefix(8))…")
                .font(.system(size: 12))
                .foregroundColor(darkText.opacity(0.6))
            Button(role: .destructive) {
                revoke(grant)
            } label: {
                Text("Revoke access")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(actingOn.contains(grant.id))
        }
        .padding(16)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }

    private func requestRow(_ request: SharedAccessService.MemoryAccessRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requesterDisplayName)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(darkText)
                Text("wants to hear your shared memories")
                    .font(.system(size: 13))
                    .foregroundColor(darkText.opacity(0.6))
            }
            HStack(spacing: 12) {
                Button {
                    respond(to: request, approve: true)
                } label: {
                    Text("Approve")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(darkText, in: Capsule())
                        .foregroundColor(.white)
                }
                Button {
                    respond(to: request, approve: false)
                } label: {
                    Text("Decline")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(darkText.opacity(0.35), lineWidth: 1))
                        .foregroundColor(darkText)
                }
            }
            .disabled(actingOn.contains(request.id))
            .opacity(actingOn.contains(request.id) ? 0.5 : 1)
        }
        .padding(16)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
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
