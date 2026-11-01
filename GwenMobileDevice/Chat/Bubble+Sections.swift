@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

extension Bubble {
    var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            attachmentArea
            generatedImageArea
            answerArea
            researchArea
            deviceRefArea
            BubbleCardArea(isUser: isUser, messageID: messageID,
                           priceWatchRef: priceWatchRef, dayBriefingRef: dayBriefingRef,
                           weatherRef: weatherRef, onOpenEvent: onOpenEvent,
                           onBriefingDay: onBriefingDay, onBriefingSpeak: onBriefingSpeak,
                           onBriefingNotify: onBriefingNotify, onWeatherDay: onWeatherDay,
                           onWeatherSpeak: onWeatherSpeak)
            signatureArea
            extractionBadge
        }
    }

    @ViewBuilder private var attachmentArea: some View {
        if !images.isEmpty {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                ForEach(images, id: \.file) { att in
                    Button(action: TapProbe.action({ openPreview(att) })) {
                        AttachmentImage(att: att)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("open_image"))
                    .contextMenu { imageActions(att, library: false) }
                }
            }
        }
    }

    @ViewBuilder private var generatedImageArea: some View {
        if !outImages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(outImages, id: \.file) { att in
                    Button(action: TapProbe.action({ openPreview(att) })) {
                        AttachmentImage(att: att, fit: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.t("open_image"))
                    .contextMenu { imageActions(att, library: true) }
                }
                Button(action: TapProbe.action({ saveAllAttachments() })) {
                    Label(L.t("save_to_photos"), systemImage: "square.and.arrow.down")
                        .scaledFont(13)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    @ViewBuilder private var answerArea: some View {
        if streaming && text.isEmpty {
            ProcessingLabel(text: L.t("processing"))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(bubbleColor)
                .clipShape(BubbleShape(isUser: isUser))
        } else if !text.isEmpty {
            answerBody
        }
    }

    @ViewBuilder private var researchArea: some View {
        if let gallery, !gallery.pictures.isEmpty {
            PictureGalleryView(gallery: gallery,
                               owner: messageID,
                               onOpen: { openPicture($0) },
                               onOpenSource: { openPictureSource($0) },
                               onOpenOriginal: { openWebAddress($0.fullURL) },
                               onMore: { onMorePictures?() },
                               onShare: { shareImage($0.attachment) },
                               onSave: { saveAttachment($0.attachment) })
                .padding(.top, 2)
        }
        if !sources.isEmpty {
            sourcesView
        }
        ForEach(Array(placeGroups.enumerated()), id: \.offset) { _, group in
            placesView(group)
        }
    }

    @ViewBuilder private var deviceRefArea: some View {
        if let calendarRef {
            calendarView(calendarRef)
        }
        if let reminderRef {
            reminderView(reminderRef)
        }
        if !isUser, let scanRef {
            scanShareView(scanRef)
        }
        if !isUser, let reminderOffer {
            reminderOfferView(reminderOffer)
        }
        if !liveOCRFiles.isEmpty {
            ocrFilesView
        }
        if !files.isEmpty {
            filesView
        }
        if !isUser && !fileRefs.isEmpty {
            fileRefsView
        }
        if !isUser && !memoryRefs.isEmpty {
            memoryRefsView
        }
    }

    @ViewBuilder private var signatureArea: some View {
        if !isUser && !streaming, let model {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "brain.head.profile").scaledFont(10)
                    Text(verbatim: signatureLine(model: model))
                        .scaledFont(12)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(Color(.tertiaryLabel))
                .frame(maxWidth: .infinity, alignment: .leading)
                if !text.isEmpty {
                    AnswerCopyButton(text: text)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 1)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var extractionBadge: some View {
        if !isUser && !streaming, let key = extractionKey {
            Text(L.t(key))
                .scaledFont(10, weight: .bold)
                .foregroundStyle(Color(.systemGreen))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color(.systemGreen).opacity(0.12)))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder var bubbleContextMenu: some View {
        if !isUser && !text.isEmpty {
            AnswerCopyMenuItem(text: text) { notice.show(L.t("copied")) }
            Button(action: TapProbe.action({ saveAsFile() })) {
                Label(L.t("save_as_file"), systemImage: "arrow.down.doc")
            }
        }
        if let messageID, let onDelete, !streaming {
            Button(role: .destructive, action: TapProbe.action({ onDelete(messageID) })) {
                Label(L.t("delete_message"), systemImage: "trash")
            }
        }
    }
}
