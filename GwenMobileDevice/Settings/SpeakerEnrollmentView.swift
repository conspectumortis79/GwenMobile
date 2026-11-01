@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

@MainActor
struct SpeakerEnrollmentView: View {
    @StateObject var model = SpeakerEnrollmentModel()
    @Environment(\.dismiss) private var dismiss
    @State var confirmDelete = false
    @State var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L.t("speaker_enroll_intro"))
                        .scaledFont(13)
                }
                if model.isFinished {
                    finishedSection
                } else {
                    recordingSection
                }
                if let profile = model.existing {
                    Section {
                        LabeledContent(L.t("speaker_profile")) {
                            Text(L.counted(profile.sampleCount, one: "speaker_profile_ready_one",
                                           many: "speaker_profile_ready"))
                        }
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text(L.t("speaker_enroll_delete"))
                        }
                    }
                }
                Section {
                    Text(L.t("speaker_enroll_privacy"))
                        .scaledFont(12)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                Section {
                    Text(L.t("speaker_model_license"))
                        .scaledFont(11)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .navigationTitle(L.t("speaker_enroll_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("cancel"), action: TapProbe.action({
                        model.cancel()
                        dismiss()
                    }))
                }
            }
            .alert(L.t("speaker_enroll_delete"), isPresented: $confirmDelete) {
                Button(L.t("cancel"), role: .cancel) {}
                Button(L.t("speaker_enroll_delete"), role: .destructive) {
                    model.deleteProfile()
                }
            } message: {
                Text(L.t("speaker_enroll_delete_confirm"))
            }
            .alert(L.t("speaker_enroll_failed"), isPresented: $saveFailed) {
                Button(L.t("ok"), role: .cancel) {}
            }
            .onDisappear { model.cancel() }
        }
    }

    private var recordingSection: some View {
        Section {
            Text(L.fmt2("speaker_enroll_step", String(model.step + 1),
                        String(model.prompts.count)))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Text(model.currentPrompt)
                .scaledFont(16, weight: .medium)
                .padding(.vertical, 4)
            switch model.phase {
            case .ready:
                Button {
                    model.startStep()
                } label: {
                    Label(L.t("speaker_enroll_start"), systemImage: "mic.fill")
                }
            case .recording:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("speaker_enroll_recording"))
                            .scaledFont(13)
                        Spacer()
                        Text(verbatim: "\(model.remaining) s")
                            .scaledFont(13, weight: .semibold)
                    }
                    ProgressView(value: Double(Int(SpeakerEnrollmentModel.recordingSeconds) - model.remaining),
                                 total: SpeakerEnrollmentModel.recordingSeconds)
                }
            case .analyzing:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L.t("speaker_enroll_analyzing"))
                        .scaledFont(13)
                }
            case .failed(let message):
                Text(message)
                    .scaledFont(13)
                    .foregroundStyle(.red)
                Button(L.t("speaker_enroll_retry")) {
                    model.retry()
                }
            case .finished:
                EmptyView()
            }
            ProgressView(value: model.progress)
        }
    }

    private var finishedSection: some View {
        Section {
            Label(L.t("speaker_enroll_done"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(L.counted(model.embeddings.count, one: "speaker_enroll_count_one", many: "speaker_enroll_count"))
                .scaledFont(12)
                .foregroundStyle(Color(.secondaryLabel))
            Button {
                if model.finish() {
                    dismiss()
                } else {
                    saveFailed = true
                }
            } label: {
                Text(L.t("done"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
