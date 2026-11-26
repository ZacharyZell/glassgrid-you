import Foundation
import Testing
@testable import YouTubeMacCore

@Suite("Holiday Theme & Calendar Tests")
struct HolidayThemeTests {
    private static func utcGregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func pacificGregorianCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        return calendar
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: second
                )
            )
        )
    }

    @Test("21-year calendar audit (2020-2040, all 7,671 days) resolves deterministically with zero overlapping windows")
    func twentyOneYearZeroOverlapAudit() throws {
        let calendar = Self.utcGregorianCalendar()
        let startDate = try Self.makeDate(year: 2020, month: 1, day: 1, calendar: calendar)
        let endDate = try Self.makeDate(year: 2040, month: 12, day: 31, calendar: calendar)

        var easterBoundsByYear: [Int: (start: Date, end: Date)] = [:]
        var thanksgivingBoundsByYear: [Int: (start: Date, end: Date)] = [:]
        for year in 2020...2040 {
            let easter = try #require(HolidayCalendarEngine.easterSunday(year: year, calendar: calendar))
            let easterStart = calendar.startOfDay(for: easter)
            let easterWindowStart = try #require(calendar.date(byAdding: .day, value: -4, to: easterStart))
            let easterWindowEnd = try #require(calendar.date(byAdding: .day, value: 1, to: easterStart))
            easterBoundsByYear[year] = (easterWindowStart, easterWindowEnd)

            let thanksgiving = try #require(HolidayCalendarEngine.thanksgivingDay(year: year, calendar: calendar))
            let thanksgivingStart = calendar.startOfDay(for: thanksgiving)
            let thanksgivingWindowStart = try #require(calendar.date(byAdding: .day, value: -6, to: thanksgivingStart))
            let thanksgivingWindowEnd = try #require(calendar.date(byAdding: .day, value: 3, to: thanksgivingStart))
            thanksgivingBoundsByYear[year] = (thanksgivingWindowStart, thanksgivingWindowEnd)

            // Verify Easter never collides with St. Patrick's Day (Mar 14-17) even in earliest-Easter years (Mar 22 -> E-4d = Mar 18)
            let stPatricksEnd = try Self.makeDate(year: year, month: 3, day: 17, hour: 0, calendar: calendar)
            #expect(easterWindowStart > stPatricksEnd, "Year \(year) Easter window overlaps St. Patrick's")
        }

        var current = startDate
        var totalDays = 0
        var countsByHoliday: [HolidayThemeID: Int] = [:]

        while current <= endDate {
            totalDays += 1
            let dayStart = calendar.startOfDay(for: current)
            let comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let year = try #require(comps.year)
            let month = try #require(comps.month)
            let day = try #require(comps.day)

            var matchingHolidays: [HolidayThemeID] = []
            if (month == 12 && day >= 29) || (month == 1 && day <= 3) {
                matchingHolidays.append(.newYear)
            }
            if month == 12 && (12...28).contains(day) {
                matchingHolidays.append(.winter)
            }
            if month == 2 && (11...15).contains(day) {
                matchingHolidays.append(.valentines)
            }
            if month == 3 && (14...17).contains(day) {
                matchingHolidays.append(.stPatricks)
            }
            if let easterBounds = easterBoundsByYear[year],
               dayStart >= easterBounds.start && dayStart <= easterBounds.end {
                matchingHolidays.append(.springEaster)
            }
            if month == 7 && (1...5).contains(day) {
                matchingHolidays.append(.independence)
            }
            if month == 10 && (24...31).contains(day) {
                matchingHolidays.append(.halloween)
            }
            if let thanksgivingBounds = thanksgivingBoundsByYear[year],
               dayStart >= thanksgivingBounds.start && dayStart <= thanksgivingBounds.end {
                matchingHolidays.append(.thanksgiving)
            }

            #expect(
                matchingHolidays.count <= 1,
                "Overlapping holiday windows on \(year)-\(month)-\(day): \(matchingHolidays)"
            )

            let expected = matchingHolidays.first ?? .classic
            let resolved = HolidayCalendarEngine.activeHoliday(for: current, calendar: calendar)
            #expect(resolved == expected, "Mismatch on \(year)-\(month)-\(day): got \(resolved), expected \(expected)")
            countsByHoliday[resolved, default: 0] += 1

            current = try #require(calendar.date(byAdding: .day, value: 1, to: current))
        }

        #expect(totalDays == 7_671)
        #expect(countsByHoliday[.newYear] == 21 * 6)
        #expect(countsByHoliday[.winter] == 21 * 17)
        #expect(countsByHoliday[.valentines] == 21 * 5)
        #expect(countsByHoliday[.stPatricks] == 21 * 4)
        #expect(countsByHoliday[.springEaster] == 21 * 6)
        #expect(countsByHoliday[.independence] == 21 * 5)
        #expect(countsByHoliday[.halloween] == 21 * 8)
        #expect(countsByHoliday[.thanksgiving] == 21 * 10)
    }

    @Test("Exact known holiday dates, boundaries, Computus Easter 2024-2032, and local noon anchors resolve accurately")
    func exactHolidayDatesAndBoundaries() throws {
        let utc = Self.utcGregorianCalendar()
        let pacific = try Self.pacificGregorianCalendar()

        for calendar in [utc, pacific] {
            // Thursday, November 26, 2026 -> Thanksgiving window Nov 20-29, 2026
            let thanksgiving2026 = try #require(HolidayCalendarEngine.thanksgivingDay(year: 2026, calendar: calendar))
            let tgComps = calendar.dateComponents([.year, .month, .day, .weekday], from: thanksgiving2026)
            #expect(tgComps.year == 2026)
            #expect(tgComps.month == 11)
            #expect(tgComps.day == 26)
            #expect(tgComps.weekday == 5) // Thursday

            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 11, day: 19, calendar: calendar), calendar: calendar) == .classic)
            for day in 20...29 {
                let d = try Self.makeDate(year: 2026, month: 11, day: day, calendar: calendar)
                #expect(HolidayCalendarEngine.activeHoliday(for: d, calendar: calendar) == .thanksgiving)
            }
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 11, day: 30, calendar: calendar), calendar: calendar) == .classic)

            // Winter Holidays: Dec 12-28
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 11, calendar: calendar), calendar: calendar) == .classic)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 12, calendar: calendar), calendar: calendar) == .winter)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 25, calendar: calendar), calendar: calendar) == .winter)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 28, calendar: calendar), calendar: calendar) == .winter)

            // New Year's: Dec 29-Jan 3
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 29, calendar: calendar), calendar: calendar) == .newYear)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 12, day: 31, calendar: calendar), calendar: calendar) == .newYear)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2027, month: 1, day: 1, calendar: calendar), calendar: calendar) == .newYear)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2027, month: 1, day: 3, calendar: calendar), calendar: calendar) == .newYear)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2027, month: 1, day: 4, calendar: calendar), calendar: calendar) == .classic)

            // Valentine's Day: Feb 11-15
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 2, day: 10, calendar: calendar), calendar: calendar) == .classic)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 2, day: 14, calendar: calendar), calendar: calendar) == .valentines)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 2, day: 15, calendar: calendar), calendar: calendar) == .valentines)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 2, day: 16, calendar: calendar), calendar: calendar) == .classic)

            // St. Patrick's Day: Mar 14-17
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 3, day: 13, calendar: calendar), calendar: calendar) == .classic)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 3, day: 17, calendar: calendar), calendar: calendar) == .stPatricks)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 3, day: 18, calendar: calendar), calendar: calendar) == .classic)

            // Independence Day: Jul 1-5
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 6, day: 30, calendar: calendar), calendar: calendar) == .classic)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 7, day: 4, calendar: calendar), calendar: calendar) == .independence)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 7, day: 6, calendar: calendar), calendar: calendar) == .classic)

            // Halloween: Oct 24-31
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 10, day: 23, calendar: calendar), calendar: calendar) == .classic)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 10, day: 31, calendar: calendar), calendar: calendar) == .halloween)
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 11, day: 1, calendar: calendar), calendar: calendar) == .classic)

            // Non-holiday baseline
            #expect(HolidayCalendarEngine.activeHoliday(for: try Self.makeDate(year: 2026, month: 8, day: 15, calendar: calendar), calendar: calendar) == .classic)

            // Anonymous Gregorian Computus Easter Sundays 2024-2032 ([E-4d, E+1d]) + zero collision with Mar 17
            let expectedEasters: [(year: Int, month: Int, day: Int)] = [
                (2024, 3, 31),
                (2025, 4, 20),
                (2026, 4, 5),
                (2027, 3, 28),
                (2028, 4, 16),
                (2029, 4, 1),
                (2030, 4, 21),
                (2031, 4, 13),
                (2032, 3, 28)
            ]
            for expected in expectedEasters {
                let computed = try #require(HolidayCalendarEngine.easterSunday(year: expected.year, calendar: calendar))
                let comps = calendar.dateComponents([.year, .month, .day], from: computed)
                #expect(comps.year == expected.year)
                #expect(comps.month == expected.month)
                #expect(comps.day == expected.day)

                let noonEaster = try Self.makeDate(year: expected.year, month: expected.month, day: expected.day, calendar: calendar)
                for offset in -4...1 {
                    let windowDate = try #require(calendar.date(byAdding: .day, value: offset, to: noonEaster))
                    #expect(HolidayCalendarEngine.activeHoliday(for: windowDate, calendar: calendar) == .springEaster)
                }
                let beforeWindow = try #require(calendar.date(byAdding: .day, value: -5, to: noonEaster))
                let afterWindow = try #require(calendar.date(byAdding: .day, value: 2, to: noonEaster))
                #expect(HolidayCalendarEngine.activeHoliday(for: beforeWindow, calendar: calendar) != .springEaster)
                #expect(HolidayCalendarEngine.activeHoliday(for: afterWindow, calendar: calendar) != .springEaster)

                let stPatricks = try Self.makeDate(year: expected.year, month: 3, day: 17, calendar: calendar)
                #expect(HolidayCalendarEngine.activeHoliday(for: stPatricks, calendar: calendar) == .stPatricks)
            }
        }
    }

    @Test("All 9 holiday palettes satisfy WCAG 2.1 AA >= 4.5:1 contrast across Day/Night surfaces, pills, and gradients")
    func allNinePalettesWCAGContrastMatrix() {
        #expect(HolidayThemeCatalog.allPalettes.count == 9)
        #expect(Set(HolidayThemeCatalog.allPalettes.map(\.id)) == Set(HolidayThemeID.allCases))

        // .classic must match DesignSystemMetrics verbatim
        let classic = HolidayThemeCatalog.classic
        #expect(classic.accentFill == DesignSystemMetrics.accentFill)
        #expect(classic.accentFillHover == DesignSystemMetrics.accentFillHover)
        #expect(classic.accentTextLight == DesignSystemMetrics.accentTextLight)
        #expect(classic.accentTextDark == DesignSystemMetrics.accentTextDark)
        #expect(classic.brandGradientStart == DesignSystemMetrics.brandGradientStart)
        #expect(classic.brandGradientEnd == DesignSystemMetrics.brandGradientEnd)
        #expect(classic.particleShape == .none)
        #expect(classic.particleHexesLight.isEmpty)
        #expect(classic.particleHexesDark.isEmpty)

        for palette in HolidayThemeCatalog.allPalettes {
            // White text against accent fills and brand gradients
            let whiteTargets: [(label: String, hex: String)] = [
                ("accentFill", palette.accentFill),
                ("accentFillHover", palette.accentFillHover),
                ("brandGradientStart", palette.brandGradientStart),
                ("brandGradientEnd", palette.brandGradientEnd)
            ]
            for target in whiteTargets {
                let ratio = DesignSystemMetrics.contrastRatio(foregroundHex: "#FFFFFF", backgroundHex: target.hex)
                #expect(
                    ratio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                    "\(palette.id.rawValue).\(target.label) (\(target.hex)) white contrast \(ratio)"
                )
            }

            // Light surface + 12% pill contrast
            for surface in DesignSystemMetrics.lightSurfaces {
                let directRatio = DesignSystemMetrics.contrastRatio(
                    foregroundHex: palette.accentTextLight,
                    backgroundHex: surface
                )
                #expect(
                    directRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                    "\(palette.id.rawValue).accentTextLight (\(palette.accentTextLight)) on \(surface) contrast \(directRatio)"
                )
            }
            let lightPillBg = DesignSystemMetrics.compositedHex(
                foregroundHex: palette.accentTextLight,
                alpha: 0.12,
                over: "#EBEBF0"
            )
            let lightPillRatio = DesignSystemMetrics.contrastRatio(
                foregroundHex: palette.accentTextLight,
                backgroundHex: lightPillBg
            )
            #expect(
                lightPillRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "\(palette.id.rawValue) 12% light pill (\(lightPillBg)) contrast \(lightPillRatio)"
            )

            // Dark surface + 14% pill contrast
            for surface in DesignSystemMetrics.darkSurfaces {
                let directRatio = DesignSystemMetrics.contrastRatio(
                    foregroundHex: palette.accentTextDark,
                    backgroundHex: surface
                )
                #expect(
                    directRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                    "\(palette.id.rawValue).accentTextDark (\(palette.accentTextDark)) on \(surface) contrast \(directRatio)"
                )
            }
            let darkPillBg = DesignSystemMetrics.compositedHex(
                foregroundHex: palette.accentTextDark,
                alpha: 0.14,
                over: "#242429"
            )
            let darkPillRatio = DesignSystemMetrics.contrastRatio(
                foregroundHex: palette.accentTextDark,
                backgroundHex: darkPillBg
            )
            #expect(
                darkPillRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "\(palette.id.rawValue) 14% dark pill (\(darkPillBg)) contrast \(darkPillRatio)"
            )

            if palette.id != .classic {
                #expect(palette.particleShape != .none)
                #expect(!palette.particleHexesLight.isEmpty)
                #expect(!palette.particleHexesDark.isEmpty)
                for hex in palette.particleHexesLight + palette.particleHexesDark {
                    #expect(DesignSystemMetrics.rgbComponents(fromHex: hex) != nil, "Invalid particle hex \(hex)")
                }
            }
        }
    }

    @Test("Midnight rollover lands strictly on next calendar day at 00:00:05 including DST boundaries")
    func midnightRolloverScheduling() throws {
        let pacific = try Self.pacificGregorianCalendar()

        let samples: [(y: Int, m: Int, d: Int, h: Int, min: Int, s: Int, expY: Int, expM: Int, expD: Int)] = [
            (2026, 11, 26, 14, 30, 0, 2026, 11, 27),
            (2026, 11, 26, 23, 59, 59, 2026, 11, 27),
            (2026, 11, 26, 0, 0, 0, 2026, 11, 27),
            (2026, 12, 31, 22, 15, 0, 2027, 1, 1),
            // DST spring-forward night (2026-03-08) & fall-back night (2026-11-01)
            (2026, 3, 7, 20, 0, 0, 2026, 3, 8),
            (2026, 10, 31, 23, 30, 0, 2026, 11, 1)
        ]

        for sample in samples {
            let input = try Self.makeDate(
                year: sample.y,
                month: sample.m,
                day: sample.d,
                hour: sample.h,
                minute: sample.min,
                second: sample.s,
                calendar: pacific
            )
            let rollover = HolidayCalendarEngine.nextMidnightRollover(after: input, calendar: pacific)
            let comps = pacific.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rollover)
            #expect(rollover > input)
            #expect(comps.year == sample.expY)
            #expect(comps.month == sample.expM)
            #expect(comps.day == sample.expD)
            #expect(comps.hour == 0)
            #expect(comps.minute == 0)
            #expect(comps.second == 5)
        }
    }

    @Test("HolidayThemeSelection resolves auto vs manual overrides and HolidayEffectsIntensity scales birthRate")
    func selectionResolutionAndEffectIntensity() {
        for holiday in HolidayThemeID.allCases {
            #expect(HolidayThemeSelection.auto.resolvedThemeID(calendarHoliday: holiday) == holiday)
        }

        #expect(HolidayThemeSelection.classic.resolvedThemeID(calendarHoliday: .thanksgiving) == .classic)
        #expect(HolidayThemeSelection.thanksgiving.resolvedThemeID(calendarHoliday: .classic) == .thanksgiving)
        #expect(HolidayThemeSelection.winter.resolvedThemeID(calendarHoliday: .halloween) == .winter)
        #expect(HolidayThemeSelection.newYear.resolvedThemeID(calendarHoliday: .classic) == .newYear)
        #expect(HolidayThemeSelection.valentines.resolvedThemeID(calendarHoliday: .classic) == .valentines)
        #expect(HolidayThemeSelection.stPatricks.resolvedThemeID(calendarHoliday: .classic) == .stPatricks)
        #expect(HolidayThemeSelection.springEaster.resolvedThemeID(calendarHoliday: .classic) == .springEaster)
        #expect(HolidayThemeSelection.independence.resolvedThemeID(calendarHoliday: .classic) == .independence)
        #expect(HolidayThemeSelection.halloween.resolvedThemeID(calendarHoliday: .winter) == .halloween)

        #expect(HolidayEffectsIntensity.off.birthRateScale == 0.0)
        #expect(HolidayEffectsIntensity.subtle.birthRateScale == 1.0)
        #expect(HolidayEffectsIntensity.festive.birthRateScale > HolidayEffectsIntensity.subtle.birthRateScale)
    }

    @Test("CommandPaletteEngine surfaces toggleHolidayEffects and cycleHolidayTheme for holiday and thanksgiving queries")
    func commandPaletteRanksHolidayActions() {
        let actions: [CommandPaletteActionDescriptor] = [
            CommandPaletteActionDescriptor(
                action: .toggleDayNightMode,
                title: "Switch to Night Mode",
                keywords: "dark light theme appearance",
                systemImage: "moon.stars",
                shortcutHint: "⌘⇧L",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .cycleHolidayTheme,
                title: "Cycle Holiday Theme (Thanksgiving)",
                keywords: "holiday theme seasonal thanksgiving winter halloween valentine patrick easter july4 new year color accent",
                systemImage: "leaf.fill",
                isFeaturedWhenEmpty: false
            ),
            CommandPaletteActionDescriptor(
                action: .toggleHolidayEffects,
                title: "Turn Off Holiday Ambient Effects",
                keywords: "holiday effects snow leaves hearts particles ambient festive subtle",
                systemImage: "sparkles.slash",
                isFeaturedWhenEmpty: false
            )
        ]

        let holidayResults = CommandPaletteEngine.rank(
            query: "holiday",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            actions: actions,
            suggestions: []
        )
        let holidayActions = holidayResults.filter { $0.section == .actions }.map(\.payload)
        #expect(holidayActions.contains(.runAction(.cycleHolidayTheme)))
        #expect(holidayActions.contains(.runAction(.toggleHolidayEffects)))

        let thanksgivingResults = CommandPaletteEngine.rank(
            query: "thanksgiving",
            openTabs: [],
            presets: [],
            continueWatching: [],
            pinnedItems: [],
            watchedChannels: [],
            actions: actions,
            suggestions: []
        )
        let thanksgivingActions = thanksgivingResults.filter { $0.section == .actions }
        #expect(thanksgivingActions.first?.payload == .runAction(.cycleHolidayTheme))
    }
}
