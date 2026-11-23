import AppKit
import SwiftUI
import YouTubeMacCore

/// Sleek collapsible Liquid Glass Continue Watching card shared between the compact Home Shelf and Populated Home Dashboard.
private struct ContinueWatchingCardView: View {
    let item: ContinueWatchingItem
    let onResume: () -> Void
    let onOpenNewTab: () -> Void
    let onOpenInMultiview: () -> Void
    let onCopyLink: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                CachedThumbnailImage(url: item.thumbnailURL, placeholderIconSize: 20)
                    .frame(width: 212, height: 119)
                    .clipped()

                // Subtle bottom gradient for badge legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 52)
                .allowsHitTesting(false)

                if isHovered {
                    ZStack {
                        Color.black.opacity(0.18)
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .appleGlass(in: Circle(), tint: .black.opacity(0.35), interactive: true)
                            .environment(\.colorScheme, .dark)
                    }
                    .frame(width: 212, height: 119)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                // Remaining time pill
                if !item.remainingTimeText.isEmpty {
                    Text(item.remainingTimeText)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(.leading, 7)
                        .padding(.bottom, 9)
                        .allowsHitTesting(false)
                }

                // Bottom red playback progress bar
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.28))
                        Rectangle()
                            .fill(AppleTheme.accent)
                            .frame(width: proxy.size.width * item.progressFraction)
                    }
                }
                .frame(height: 3.5)
                .allowsHitTesting(false)
            }
            .frame(width: 212, height: 119)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.08), lineWidth: 0.75)
            )
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .appleGlass(in: Circle(), tint: .black.opacity(0.45), interactive: true)
                            .environment(\.colorScheme, .dark)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Remove from Continue Watching")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !item.channel.isEmpty {
                    Text(item.channel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: 212, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onResume)
        .contextMenu {
            Button("Open in New Tab", action: onOpenNewTab)
            Button("Open in Multiview", action: onOpenInMultiview)
            Button("Copy Link at Saved Time", action: onCopyLink)
            Divider()
            Button("Remove from Continue Watching", role: .destructive, action: onDismiss)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Interactive Suggested Content card for the Populated Home Dashboard.
private struct SuggestedVideoCardView: View {
    let video: SuggestedVideoItem
    let onPlay: () -> Void
    let onOpenNewTab: () -> Void
    let onOpenInMultiview: () -> Void
    let onCopyLink: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedThumbnailImage(url: video.thumbnailURL, placeholderIconSize: 24)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipped()

                if isHovered {
                    ZStack {
                        Color.black.opacity(0.16)
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .appleGlass(in: Circle(), tint: .black.opacity(0.36), interactive: true)
                            .environment(\.colorScheme, .dark)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                Text(video.durationText)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(7)
                    .allowsHitTesting(false)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.20 : 0.08), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(isHovered ? 0.16 : 0.05), radius: isHovered ? 12 : 4, y: isHovered ? 5 : 2)
            .scaleEffect(isHovered ? 1.015 : 1.0)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(video.channel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(video.topic.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture(perform: onPlay)
        .contextMenu {
            Button("Open in New Tab", action: onOpenNewTab)
            Button("Open in Multiview", action: onOpenInMultiview)
            Button("Copy Link", action: onCopyLink)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }
}

/// Compact Liquid Glass pill button for quick feed filters & channels.
private struct LiquidGlassFilterPill: View {
    let title: String
    var systemImage: String? = nil
    var badgeText: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? AppleTheme.accent : .secondary)
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.84))
                    .lineLimit(1)
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 29)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: isSelected ? AppleTheme.accent.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : nil),
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Slim collapsible Liquid Glass Home Shelf shown above YouTube's live populated Home grid.
struct HomeShelfBarView: View {
    @Bindable var controller: AppController

    private var continueItems: [ContinueWatchingItem] {
        controller.settings.continueWatching
    }

    private var topChannels: [WatchedChannelStat] {
        Array(controller.settings.watchedChannels.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LiquidGlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            LiquidGlassFilterPill(title: "For You", systemImage: "sparkles", isSelected: true) {
                                controller.navigateSelectedTab(to: .home)
                            }
                            LiquidGlassFilterPill(title: "Subscriptions", systemImage: "rectangle.stack.badge.play") {
                                controller.navigateSelectedTab(to: .subscriptions)
                            }
                            LiquidGlassFilterPill(title: "Watch Later", systemImage: "clock") {
                                controller.navigateSelectedTab(to: .watchLater)
                            }
                            LiquidGlassFilterPill(title: "History", systemImage: "clock.arrow.circlepath") {
                                controller.navigateSelectedTab(to: .history)
                            }
                            LiquidGlassFilterPill(title: "Liked", systemImage: "hand.thumbsup") {
                                controller.navigateSelectedTab(to: .likedVideos)
                            }

                            if !topChannels.isEmpty {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 1, height: 16)
                                    .padding(.horizontal, 3)

                                ForEach(topChannels) { channel in
                                    LiquidGlassFilterPill(
                                        title: channel.name,
                                        systemImage: "person.crop.circle",
                                        badgeText: channel.watchCount > 1 ? "\(channel.watchCount)" : nil
                                    ) {
                                        if let url = channel.url {
                                            controller.navigateSelectedTab(to: url)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !continueItems.isEmpty {
                    LiquidGlassFilterPill(
                        title: "Continue Watching",
                        systemImage: controller.isContinueWatchingExpanded ? "chevron.up" : "chevron.down",
                        badgeText: "\(continueItems.count)",
                        isSelected: controller.isContinueWatchingExpanded
                    ) {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            controller.isContinueWatchingExpanded.toggle()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)

            if controller.isContinueWatchingExpanded && !continueItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(continueItems) { item in
                            ContinueWatchingCardView(
                                item: item,
                                onResume: {
                                    if let url = item.resumeURL {
                                        controller.navigateSelectedTab(to: url)
                                    }
                                },
                                onOpenNewTab: {
                                    if let url = item.resumeURL {
                                        controller.createTab(url: url, select: true)
                                    }
                                },
                                onOpenInMultiview: {
                                    if let url = item.resumeURL {
                                        controller.addTileToMultiview(url: url)
                                    }
                                },
                                onCopyLink: {
                                    if let url = item.resumeURL {
                                        let pb = NSPasteboard.general
                                        pb.clearContents()
                                        pb.setString(url.absoluteString, forType: .string)
                                        controller.showHUD(icon: "link", message: "Link Copied")
                                    }
                                },
                                onDismiss: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        controller.dismissContinueWatching(videoID: item.videoID)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
    }
}

/// Full Apple TV–grade Liquid Glass Populated Home Dashboard displayed whenever YouTube's signed-out or paused-history
/// Home page renders 0 video cards, ensuring the Home screen is always richly populated and immediately playable.
struct PopulatedHomeDashboardView: View {
    @Bindable var controller: AppController

    private var continueItems: [ContinueWatchingItem] {
        controller.settings.continueWatching
    }

    private var topChannels: [WatchedChannelStat] {
        Array(controller.settings.watchedChannels.prefix(10))
    }

    private var filteredSuggestions: [SuggestedVideoItem] {
        let all = SuggestedVideoItem.curatedCatalog
        if controller.selectedHomeTopic == .all {
            return all
        }
        return all.filter { $0.topic == controller.selectedHomeTopic }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 228, maximum: 310), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                // Top Liquid Glass Topic & Quick Feeds Bar
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LiquidGlassGroup(spacing: 6) {
                            HStack(spacing: 6) {
                                ForEach(SuggestedTopic.allCases) { topic in
                                    LiquidGlassFilterPill(
                                        title: topic.title,
                                        systemImage: topic.systemImage,
                                        isSelected: controller.selectedHomeTopic == topic
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.16)) {
                                            controller.selectedHomeTopic = topic
                                        }
                                    }
                                }

                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 1, height: 16)
                                    .padding(.horizontal, 3)

                                LiquidGlassFilterPill(title: "Subscriptions", systemImage: "rectangle.stack.badge.play") {
                                    controller.navigateSelectedTab(to: .subscriptions)
                                }
                                LiquidGlassFilterPill(title: "Watch Later", systemImage: "clock") {
                                    controller.navigateSelectedTab(to: .watchLater)
                                }
                                LiquidGlassFilterPill(title: "History", systemImage: "clock.arrow.circlepath") {
                                    controller.navigateSelectedTab(to: .history)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    LiquidGlassFilterPill(title: "Sign In", systemImage: "person.crop.circle.badge.plus") {
                        controller.openSignIn()
                    }
                    .help("Sign in to YouTube for your personalized live feed")
                }

                // Continue Watching Shelf
                if !continueItems.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Label("Continue Watching", systemImage: "play.circle.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Clear") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    controller.clearContinueWatching()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(continueItems) { item in
                                    ContinueWatchingCardView(
                                        item: item,
                                        onResume: {
                                            if let url = item.resumeURL {
                                                controller.navigateSelectedTab(to: url)
                                            }
                                        },
                                        onOpenNewTab: {
                                            if let url = item.resumeURL {
                                                controller.createTab(url: url, select: true)
                                            }
                                        },
                                        onOpenInMultiview: {
                                            if let url = item.resumeURL {
                                                controller.addTileToMultiview(url: url)
                                            }
                                        },
                                        onCopyLink: {
                                            if let url = item.resumeURL {
                                                let pb = NSPasteboard.general
                                                pb.clearContents()
                                                pb.setString(url.absoluteString, forType: .string)
                                                controller.showHUD(icon: "link", message: "Link Copied")
                                            }
                                        },
                                        onDismiss: {
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                controller.dismissContinueWatching(videoID: item.videoID)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Most Watched & Subscriptions Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Most Watched & Subscriptions", systemImage: "rectangle.stack.badge.play.fill")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Open Subscriptions") {
                            controller.navigateSelectedTab(to: .subscriptions)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppleTheme.accent)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        LiquidGlassGroup(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(topChannels) { channel in
                                    LiquidGlassFilterPill(
                                        title: channel.name,
                                        systemImage: "person.crop.circle.fill",
                                        badgeText: channel.watchCount > 1 ? "\(channel.watchCount)×" : nil
                                    ) {
                                        if let url = channel.url {
                                            controller.navigateSelectedTab(to: url)
                                        }
                                    }
                                }

                                ForEach(controller.settings.pinnedItems) { pin in
                                    LiquidGlassFilterPill(title: pin.title, systemImage: "pin.fill") {
                                        if let url = pin.url {
                                            controller.navigateSelectedTab(to: url)
                                        }
                                    }
                                }

                                if topChannels.isEmpty && controller.settings.pinnedItems.isEmpty {
                                    LiquidGlassFilterPill(title: "Jacob + Katie Schwarz", systemImage: "4k.tv") {
                                        controller.navigateSelectedTab(to: URL(string: "https://www.youtube.com/results?search_query=Jacob+Katie+Schwarz+4K+HDR")!)
                                    }
                                    LiquidGlassFilterPill(title: "3Blue1Brown", systemImage: "atom") {
                                        controller.navigateSelectedTab(to: URL(string: "https://www.youtube.com/results?search_query=3Blue1Brown")!)
                                    }
                                    LiquidGlassFilterPill(title: "NASA Goddard", systemImage: "sparkles") {
                                        controller.navigateSelectedTab(to: URL(string: "https://www.youtube.com/results?search_query=NASA+4K")!)
                                    }
                                    LiquidGlassFilterPill(title: "Blender Studio", systemImage: "film") {
                                        controller.navigateSelectedTab(to: URL(string: "https://www.youtube.com/results?search_query=Blender+Open+Movie+4K")!)
                                    }
                                    LiquidGlassFilterPill(title: "freeCodeCamp.org", systemImage: "cpu") {
                                        controller.navigateSelectedTab(to: URL(string: "https://www.youtube.com/results?search_query=freeCodeCamp")!)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Suggested Content Video Grid
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            controller.selectedHomeTopic == .all ? "Suggested Content" : controller.selectedHomeTopic.title,
                            systemImage: controller.selectedHomeTopic.systemImage
                        )
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                        Spacer()

                        Text("Click any video to start watching")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(filteredSuggestions) { video in
                            SuggestedVideoCardView(
                                video: video,
                                onPlay: {
                                    if let url = video.watchURL {
                                        controller.navigateSelectedTab(to: url)
                                    }
                                },
                                onOpenNewTab: {
                                    if let url = video.watchURL {
                                        controller.createTab(url: url, select: true)
                                    }
                                },
                                onOpenInMultiview: {
                                    if let url = video.watchURL {
                                        controller.addTileToMultiview(url: url)
                                    }
                                },
                                onCopyLink: {
                                    if let url = video.watchURL {
                                        let pb = NSPasteboard.general
                                        pb.clearContents()
                                        pb.setString(url.absoluteString, forType: .string)
                                        controller.showHUD(icon: "link", message: "Link Copied")
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
    }
}

/// Native Liquid Glass recovery card shown when the user has enabled `Hide Home Feed` in Distraction-Free Settings.
struct HiddenHomeFeedRecoveryView: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "eye.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
            }

            VStack(spacing: 4) {
                Text("Home Feed Hidden")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Distraction-Free mode is hiding the Home feed. Use Search, Subscriptions, or restore the feed below.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            LiquidGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        controller.settings.hideHomeFeed = false
                        controller.showHUD(icon: "eye", message: "Home Feed Restored")
                    } label: {
                        Label("Show Home Feed", systemImage: "eye")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(AppleTheme.accent, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.navigateSelectedTab(to: .subscriptions)
                    } label: {
                        Label("Open Subscriptions", systemImage: "rectangle.stack.badge.play")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(28)
        .appleGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
    }
}
