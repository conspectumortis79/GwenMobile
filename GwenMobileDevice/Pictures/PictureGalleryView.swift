@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI

enum GalleryGrid {
    static var tilesPerRow: Int { ImagePolicy.galleryTilesPerRow }
    static var side: CGFloat { ImagePolicy.galleryTileSide }
    static var gap: CGFloat { ImagePolicy.galleryTileGap }

    static var width: CGFloat {
        CGFloat(tilesPerRow) * side + CGFloat(tilesPerRow - 1) * gap
    }

    static func rows<Item>(_ items: [Item], perRow: Int = tilesPerRow) -> [[Item]] {
        guard !items.isEmpty, perRow > 0 else { return [] }
        var built: [[Item]] = []
        var start = items.startIndex
        while start < items.endIndex {
            let end = min(items.index(start, offsetBy: perRow), items.endIndex)
            built.append(Array(items[start..<end]))
            start = end
        }
        return built
    }
}

struct PictureGalleryView: View {
    let gallery: PictureGallery
    let owner: UUID?
    let onOpen: (WebPicture) -> Void
    let onOpenSource: (WebPicture) -> Void
    let onOpenOriginal: (WebPicture) -> Void
    let onMore: () -> Void
    let onShare: (WebPicture) -> Void
    let onSave: (WebPicture) -> Void

    @EnvironmentObject private var selection: GallerySelection
    @EnvironmentObject private var operation: GalleryOperation

    private var order: [String] { gallery.visiblePictures.map(\.file) }
    private var picking: Bool { selection.picking(owner) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headLine
            grid
            if !picking {
                Text(verbatim: L.t("pictures_selection_hint"))
                    .scaledFont(11.5)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 2)
            } else {
                Text(verbatim: L.t("pictures_picking_hint"))
                    .scaledFont(11.5)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 2)
            }
        }
    }

    private var headLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: headline)
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button(action: TapProbe.action({ headAction() })) {
                HStack(spacing: 2) {
                    Text(verbatim: L.t(picking ? "pictures_pick_all" : "pictures_pick"))
                        .scaledFont(11.5, weight: .semibold)
                    Image(systemName: "chevron.right")
                        .scaledFont(9, weight: .bold)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut("a", modifiers: .command)
        }
    }

    private var headline: String {
        var parts = [L.t("pictures_head"),
                     "\(gallery.visiblePictures.count)/\(gallery.pictures.count)"]
        if picking, !selection.isEmpty { parts.append(L.n("pictures_selected", selection.count)) }
        return parts.joined(separator: " · ")
    }

    func headAction() {
        guard let owner else { return }
        if picking {
            selection.selectAll(order)
        } else {
            selection.begin(owner: owner)
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: GalleryGrid.gap) {
            ForEach(Array(GalleryGrid.rows(GalleryLayout.cells(gallery, searching: searching))
                            .enumerated()), id: \.offset) { _, row in
                HStack(spacing: GalleryGrid.gap) {
                    ForEach(row) { cell in
                        cellView(cell)
                    }
                }
            }
        }
        .frame(width: GalleryGrid.width, alignment: .leading)
    }

    private var searching: Bool { operation.isSearching(owner) }

    @ViewBuilder private func cellView(_ cell: GalleryCell) -> some View {
        switch cell {
        case .picture(let picture):
            PictureTile(picture: picture,
                        selected: selection.contains(picture.file),
                        showsHandle: picking,
                        onTap: { mode in tapped(picture, mode: mode) },
                        onOpen: { onOpen(picture) },
                        onToggle: { selection.toggle(picture.file) })
                .contextMenu { tileMenu(picture) }
        case .more(let kind):
            GalleryMoreTile(kind: kind, action: onMore)
        case .placeholder:
            GalleryPlaceholderTile()
        case .searching:
            GallerySearchingTile()
        case .endOfResults:
            GalleryEndTile()
        }
    }

    func tapped(_ picture: WebPicture, mode: GalleryTapMode) {
        guard let owner else {
            onOpen(picture)
            return
        }
        switch selection.tap(picture.file, owner: owner, in: order, mode: mode) {
        case .openPreview: onOpen(picture)
        case .saveOne: onSave(picture)
        case .selected, .deselected: break
        }
    }

    @ViewBuilder private func tileMenu(_ picture: WebPicture) -> some View {
        Button(action: TapProbe.action({ pick(picture) })) {
            Label(L.t(selection.contains(picture.file) ? "pictures_deselect" : "pictures_pick"),
                  systemImage: selection.contains(picture.file) ? "xmark.circle" : "checkmark.circle")
        }
        Button(action: TapProbe.action({ onShare(picture) })) {
            Label(L.t("pictures_share"), systemImage: "square.and.arrow.up")
        }
        Button(action: TapProbe.action({ onSave(picture) })) {
            Label(L.t("save_to_photos"), systemImage: "square.and.arrow.down")
        }
        Button(action: TapProbe.action({ onOpenSource(picture) })) {
            Label(L.t("pictures_open_source"), systemImage: "safari")
        }
        Button(action: TapProbe.action({ onOpenOriginal(picture) })) {
            Label(L.t("pictures_open_original"), systemImage: "arrow.up.forward.square")
        }
    }

    func pick(_ picture: WebPicture) {
        guard let owner else { return }
        selection.begin(owner: owner)
        selection.toggle(picture.file)
    }
}

struct PictureTile: View {
    let picture: WebPicture
    let selected: Bool
    let showsHandle: Bool
    let onTap: (GalleryTapMode) -> Void
    let onOpen: () -> Void
    let onToggle: () -> Void

    @EnvironmentObject private var feed: ImageFeed
    @State private var probe = TapModifierProbe()
    @State private var hovering = false

    var body: some View {
        artwork
            .frame(width: GalleryGrid.side, height: GalleryGrid.side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner))
            .overlay { ring }
            #if targetEnvironment(macCatalyst)
            .overlay { GalleryTapModifiers(probe: probe) }
            #endif
            .overlay(alignment: .topTrailing) { handle }
            .contentShape(Rectangle())
            .gesture(singleTap)
            #if targetEnvironment(macCatalyst)
            .highPriorityGesture(doubleTap)
            #endif
            .onHover { hovering = $0 }
            .accessibilityLabel(L.t("open_image"))
            .onAppear { feed.load(picture.file) }
    }

    @ViewBuilder private var artwork: some View {
        if let rendition = feed.rendition(for: picture.file) {
            Image(uiImage: rendition.image)
                .resizable()
                .scaledToFill()
        } else {
            Color(.systemGray5)
        }
    }

    @ViewBuilder private var ring: some View {
        if selected {
            RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
                .strokeBorder(Color.accentColor, lineWidth: 3)
        } else if hovering {
            RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
        }
    }

    @ViewBuilder private var handle: some View {
        if showsHandle {
            Button(action: onToggle) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .scaledFont(ImagePolicy.galleryHandleFont)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(Circle().fill(selected ? Color.accentColor
                                                        : Color.black.opacity(0.28)))
                    .shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(L.t("pictures_pick"))
        }
    }

    private var singleTap: some Gesture {
        TapGesture().onEnded(TapProbe.action({ onTap(probe.mode) }))
    }

    #if targetEnvironment(macCatalyst)
    private var doubleTap: some Gesture {
        TapGesture(count: 2).onEnded { onOpen() }
    }
    #endif
}

struct GalleryMoreTile: View {
    let kind: GalleryMoreKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            tileFace(symbol: "plus",
                     count: L.n(kind.isRound ? "pictures_round_tile" : "pictures_more_tile", kind.count),
                     verb: L.t(kind.isRound ? "pictures_round_tile_hint" : "pictures_more_tile_hint"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.t("pictures_more"))
    }

    private func tileFace(symbol: String, count: String, verb: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).scaledFont(17, weight: .semibold)
            Text(verbatim: count).scaledFont(11, weight: .bold)
            Text(verbatim: verb).scaledFont(9.5, weight: .semibold)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: GalleryGrid.side, height: GalleryGrid.side)
        .background(RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
            .fill(Color(.systemGray6)))
        .overlay(RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
            .strokeBorder(Color(.systemGray4),
                          style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])))
    }
}

struct GalleryPlaceholderTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
            .fill(Color(.systemGray5))
            .frame(width: GalleryGrid.side, height: GalleryGrid.side)
            .accessibilityHidden(true)
    }
}

struct GallerySearchingTile: View {
    var body: some View {
        VStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text(verbatim: L.t("pictures_round_working"))
                .scaledFont(9.5, weight: .semibold)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color(.secondaryLabel))
        .frame(width: GalleryGrid.side, height: GalleryGrid.side)
        .background(RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
            .fill(Color(.systemGray6)))
    }
}

struct GalleryEndTile: View {
    var body: some View {
        Text(verbatim: L.t("pictures_end_of_results"))
            .scaledFont(10, weight: .semibold)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(.tertiaryLabel))
            .padding(6)
            .frame(width: GalleryGrid.side, height: GalleryGrid.side)
            .background(RoundedRectangle(cornerRadius: ImagePolicy.galleryTileCorner)
                .fill(Color(.systemGray6).opacity(0.6)))
    }
}
