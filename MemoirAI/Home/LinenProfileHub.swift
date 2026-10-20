import SwiftUI

struct LinenProfileHub: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileVM: ProfileViewModel
    @State private var showEdit = false
    @State private var showSwitcher = false
    @State private var showOrders = false
    @State private var showSettings = false
    @State private var showEmail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 24) {
                        Group {
                            if let image = profileVM.selectedProfile.uiImage {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.rectangle").resizable().scaledToFit().padding(16)
                            }
                        }
                        .frame(width: 80, height: 90)
                        .background(LinenTheme.surface)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 15, bottomTrailingRadius: 15, topTrailingRadius: 40))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profileVM.selectedProfile.name.isEmpty ? "Your profile" : profileVM.selectedProfile.name)
                                .font(LinenTheme.heading(27))
                            Button("Edit profile") { showEdit = true }
                                .font(LinenTheme.body(14)).frame(minHeight: 44)
                        }
                    }
                    Button { showSwitcher = true } label: { LinenHubRow(title: "Switch profile", symbol: "arrow.left.arrow.right") }
                    Button { showOrders = true } label: { LinenHubRow(title: "Orders", symbol: "shippingbox") }
                    NavigationLink { PendingRequestsView().navigationTitle("Family access") } label: {
                        LinenHubRow(title: "Family access", symbol: "person.2")
                    }
                    Button { showSettings = true } label: { LinenHubRow(title: "Settings", symbol: "slider.horizontal.3") }
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text("Keep your memories backed up and access them on another device.")
                                    .font(LinenTheme.body(14)).foregroundStyle(LinenTheme.secondary)
                                LinkedAccountsView()
                                Button("Use email") { showEmail = true }
                                    .font(LinenTheme.body(16, weight: .semibold)).frame(minHeight: 48)
                            }
                            .padding(24)
                            .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
                        }
                        .linenScreen()
                        .navigationTitle("Account & backup")
                    } label: { LinenHubRow(title: "Account & backup", symbol: "icloud") }
                }
                .padding(24)
                .adaptiveContentWidth(AdaptiveLayoutPolicy.formMaxWidth)
            }
            .linenScreen()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Done")
            } }
            .buttonStyle(.plain)
            .tint(LinenTheme.accent)
            .sheet(isPresented: $showSwitcher) { ProfileSwitcherView().environmentObject(profileVM) }
            .fullScreenCover(isPresented: $showEdit) { ProfileEditView(profileVM: profileVM) }
            .sheet(isPresented: $showOrders) { OrderHistoryView() }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(profileVM).environmentObject(RCSubscriptionManager.shared)
            }
            .sheet(isPresented: $showEmail) { EmailAuthSheet() }
        }
    }
}

private struct LinenHubRow: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(LinenTheme.body(16, weight: .medium))
            Spacer(minLength: 12)
            Image(systemName: symbol).font(.system(size: 19))
        }
        .foregroundStyle(LinenTheme.ink)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(LinenTheme.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}
