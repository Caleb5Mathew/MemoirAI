import SwiftUI

/// Floating toast for an active cloud storybook job; overlaid in `ContentView` so it appears above every tab and pushed destination without shifting layout.
struct GlobalStorybookProgressBanner: View {
    @ObservedObject private var observer = ActiveStorybookJobObserver.shared
    /// Hides the banner until the job id or status changes (e.g. user dismisses a failed run, then retries and status becomes `running`).
    @State private var dismissedSignature: String?

    private var terracotta: Color { Color(red: 0.82, green: 0.45, blue: 0.32) }

    var body: some View {
        Group {
            if let job = observer.activeJob, !isDismissed(job) {
                ZStack(alignment: .topTrailing) {
                    Button {
                        NotificationCenter.default.post(name: .navigateToCloudStorybookGeneration, object: nil)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: leadingIcon(for: job))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(terracotta)
                                .frame(width: 28, alignment: .center)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(bannerTitle(for: job))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let subtitle = bannerSubtitle(for: job) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                progressBar(for: job)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 28)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismissedSignature = dismissSignature(for: job)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .onChange(of: observer.activeJob?.jobId) { _, newId in
            if newId == nil {
                dismissedSignature = nil
            }
        }
        .onChange(of: observer.activeJob?.status) { oldStatus, newStatus in
            if newStatus == "aiComplete" && oldStatus != "aiComplete" {
                Haptics.success()
            }
        }
    }

    private func dismissSignature(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> String {
        "\(job.jobId):\(job.status)"
    }

    private func isDismissed(_ job: FirestoreSyncService.ActiveStorybookCloudJob) -> Bool {
        guard let dismissedSignature else { return false }
        return dismissSignature(for: job) == dismissedSignature
    }

    private func leadingIcon(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> String {
        switch job.status {
        case "failed":
            return "exclamationmark.triangle.fill"
        case "aiComplete":
            return "checkmark.circle.fill"
        case "running":
            return "sparkles"
        case "queued", "ranking":
            return "arrow.triangle.2.circlepath"
        default:
            return "book.pages.fill"
        }
    }

    /// Server `currentStatus` copy is written for mid-run states; after `aiComplete` the rest
    /// of the work is on-device, so stale server copy ("open app to finalize") is replaced.
    private func bannerSubtitle(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> String? {
        if job.status == "aiComplete" {
            return nil
        }
        return job.currentStatus.isEmpty ? nil : job.currentStatus
    }

    private func bannerTitle(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> String {
        switch job.status {
        case "queued", "ranking":
            return "Preparing your storybook…"
        case "running":
            let m = max(job.progressTotal, 1)
            return "Generating your storybook: \(job.progressCompleted) of \(m) memories"
        case "aiComplete":
            return "Almost done. Tap to finish your book"
        case "failed":
            return "Generation hit a snag. Tap to retry"
        default:
            return "Storybook in progress. Tap to open"
        }
    }

    @ViewBuilder
    private func progressBar(for job: FirestoreSyncService.ActiveStorybookCloudJob) -> some View {
        let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
        switch job.status {
        case "failed":
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Tap to open and retry")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case "running" where job.progressTotal > 0:
            ProgressView(value: Double(job.progressCompleted), total: Double(job.progressTotal))
                .tint(terracotta)
        case "aiComplete":
            ProgressView(value: 1.0, total: 1.0)
                .tint(terracotta)
        case "queued", "ranking":
            ProgressView()
                .tint(terracotta)
        default:
            ProgressView()
                .tint(terracotta)
        }
    }
}
