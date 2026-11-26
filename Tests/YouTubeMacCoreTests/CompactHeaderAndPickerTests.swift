import CoreGraphics
import Foundation
import Testing
@testable import YouTubeMacCore

@Suite("Compact Single-Row Header & Unified Picker Tests")
struct CompactHeaderAndPickerTests {
    @Test("pickerCompanionSites contains exactly 8 deduplicated HTTPS entries with zero StreamingServiceCatalog overlap")
    func pickerCompanionSitesDeduplicatedAndValid() throws {
        let sites = CompanionQuickSite.pickerCompanionSites
        #expect(sites.count == 8)

        let ids = sites.map(\.id)
        #expect(Set(ids).count == 8)

        let serviceIDs = Set(StreamingServiceCatalog.all.map(\.id))
        #expect(Set(ids).isDisjoint(with: serviceIDs))

        for site in sites {
            let url = try #require(URL(string: site.urlString))
            #expect(url.scheme?.lowercased() == "https")
            #expect(!(url.host ?? "").isEmpty)
        }

        // Ensures Sports/Fantasy/Markets sites remain available without duplicating streaming services.
        let expectedIDs: Set<String> = [
            "espn-scores", "nfl-scores",
            "sleeper", "espn-fantasy", "yahoo-fantasy", "nfl-fantasy",
            "kalshi", "polymarket"
        ]
        #expect(Set(ids) == expectedIDs)
    }

    @Test("GridPickerTargetMode exposes addToGrid and newTab cases")
    func gridPickerTargetModes() {
        #expect(GridPickerTargetMode.allCases.count == 2)
        #expect(GridPickerTargetMode.allCases.contains(.addToGrid))
        #expect(GridPickerTargetMode.allCases.contains(.newTab))
        #expect(GridPickerTargetMode.addToGrid.id == "addToGrid")
        #expect(GridPickerTargetMode.newTab.id == "newTab")
    }

    @Test("CompactHeaderLayout preserves 52pt height, 26pt centerline, drag gutters, and omnibox floor")
    func compactHeaderLayoutBaselineInvariants() {
        #expect(CompactHeaderLayout.headerHeight == WindowChromeLayout.topHeaderBarHeight)
        #expect(CompactHeaderLayout.headerHeight == 52)
        #expect(CompactHeaderLayout.headerHeight / 2.0 == WindowChromeLayout.topHeaderBarCenterY)
        #expect(WindowChromeLayout.topHeaderBarCenterY == 26)
        #expect(CompactHeaderLayout.compactTabHeight == 32)
        #expect(CompactHeaderLayout.minDragGutterWidth >= 16)
        #expect(CompactHeaderLayout.minActiveOmniboxWidth >= 140)
    }

    @Test("CompactHeaderLayout secondary-control folding and inactive-tab collapse thresholds")
    func compactHeaderNarrowThresholds() {
        #expect(CompactHeaderLayout.shouldFoldSecondaryControls(headerWidth: 919) == true)
        #expect(CompactHeaderLayout.shouldFoldSecondaryControls(headerWidth: 920) == false)

        #expect(CompactHeaderLayout.shouldCollapseInactiveTabs(headerWidth: 879, tabCount: 3) == true)
        #expect(CompactHeaderLayout.shouldCollapseInactiveTabs(headerWidth: 879, tabCount: 2) == false)
        #expect(CompactHeaderLayout.shouldCollapseInactiveTabs(headerWidth: 880, tabCount: 4) == false)
    }

    @Test("CompactHeaderLayout leaves ample center rail budget at 780pt and 820pt Split Screen")
    func compactHeaderSplitScreenCenterRailBudget() {
        for width in [CGFloat(780), CGFloat(820)] {
            // Standard Split Screen (sidebar collapsed, no Multiview pill): >= 320pt center rail
            let standard = CompactHeaderLayout.availableCenterRailWidth(
                windowWidth: width,
                isSidebarVisible: false,
                isNativeFullScreen: false,
                isMultiviewActive: false,
                hasLivePulseButton: false
            )
            #expect(standard >= 320)

            let withPulseOnly = CompactHeaderLayout.availableCenterRailWidth(
                windowWidth: width,
                isSidebarVisible: false,
                isNativeFullScreen: false,
                isMultiviewActive: false,
                hasLivePulseButton: true
            )
            #expect(withPulseOnly >= 320)

            // Active Multiview + Live Pulse still preserves >= minActiveOmniboxWidth (140pt) + 100pt for collapsed tabs & [+]
            let withMultiviewAndPulse = CompactHeaderLayout.availableCenterRailWidth(
                windowWidth: width,
                isSidebarVisible: false,
                isNativeFullScreen: false,
                isMultiviewActive: true,
                hasLivePulseButton: true
            )
            #expect(withMultiviewAndPulse >= CompactHeaderLayout.minActiveOmniboxWidth + 100)
        }

        let nativeFullScreenWithAllControls = CompactHeaderLayout.availableCenterRailWidth(
            windowWidth: 780,
            isSidebarVisible: false,
            isNativeFullScreen: true,
            isMultiviewActive: true,
            hasLivePulseButton: true
        )
        #expect(nativeFullScreenWithAllControls >= 320)
    }

    @Test("CommandPaletteEngine ranks toggleCompactHeaderMode for compact and minimize header queries")
    func commandPaletteRanksToggleCompactHeaderMode() {
        let actions: [CommandPaletteActionDescriptor] = [
            CommandPaletteActionDescriptor(
                action: .toggleSidebar,
                title: "Toggle Sidebar",
                keywords: "sidebar navigation collapse",
                systemImage: "sidebar.left",
                shortcutHint: "⌘⌥S",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .toggleCompactHeaderMode,
                title: "Compact Single-Row Header",
                keywords: "compact minimize single row header chrome tabs",
                systemImage: "rectangle.compress.vertical",
                shortcutHint: "⌘⌥\\",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .toggleMultiview,
                title: "Toggle Multiview Grid",
                keywords: "quad grid multiview",
                systemImage: "square.grid.2x2",
                shortcutHint: "⌘⇧G",
                isFeaturedWhenEmpty: true
            )
        ]

        let compactResults = CommandPaletteEngine.rank(
            query: "compact",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            actions: actions,
            suggestions: []
        )
        let compactActionItems = compactResults.filter { $0.section == .actions }
        #expect(compactActionItems.first?.payload == .runAction(.toggleCompactHeaderMode))
        #expect(compactActionItems.first?.shortcutHint == "⌘⌥\\")

        let minimizeResults = CommandPaletteEngine.rank(
            query: "minimize header",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            actions: actions,
            suggestions: []
        )
        #expect(minimizeResults.contains { $0.payload == .runAction(.toggleCompactHeaderMode) })
    }
}
