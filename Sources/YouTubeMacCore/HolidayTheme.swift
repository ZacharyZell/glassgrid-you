import CoreGraphics
import Foundation

/// Seasonal holiday themes for GlassGrid You, each carrying WCAG 2.1 AA–verified Day/Night accent tokens
/// and Core Animation ambient particle configuration.
public enum HolidayThemeID: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case thanksgiving
    case winter
    case newYear
    case valentines
    case stPatricks
    case springEaster
    case independence
    case halloween

    public var id: String { rawValue }
}

/// User-facing theme selection supporting automatic calendar detection or manual holiday pinning.
public enum HolidayThemeSelection: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case classic
    case thanksgiving
    case winter
    case newYear
    case valentines
    case stPatricks
    case springEaster
    case independence
    case halloween

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            return "Auto (Calendar)"
        case .classic:
            return "Classic Crimson (Off)"
        case .thanksgiving:
            return HolidayThemeCatalog.palette(for: .thanksgiving).displayName
        case .winter:
            return HolidayThemeCatalog.palette(for: .winter).displayName
        case .newYear:
            return HolidayThemeCatalog.palette(for: .newYear).displayName
        case .valentines:
            return HolidayThemeCatalog.palette(for: .valentines).displayName
        case .stPatricks:
            return HolidayThemeCatalog.palette(for: .stPatricks).displayName
        case .springEaster:
            return HolidayThemeCatalog.palette(for: .springEaster).displayName
        case .independence:
            return HolidayThemeCatalog.palette(for: .independence).displayName
        case .halloween:
            return HolidayThemeCatalog.palette(for: .halloween).displayName
        }
    }

    public func resolvedThemeID(calendarHoliday: HolidayThemeID) -> HolidayThemeID {
        switch self {
        case .auto:
            return calendarHoliday
        case .classic:
            return .classic
        case .thanksgiving:
            return .thanksgiving
        case .winter:
            return .winter
        case .newYear:
            return .newYear
        case .valentines:
            return .valentines
        case .stPatricks:
            return .stPatricks
        case .springEaster:
            return .springEaster
        case .independence:
            return .independence
        case .halloween:
            return .halloween
        }
    }
}

/// Intensity tier for chrome-scoped Core Animation ambient particle effects.
public enum HolidayEffectsIntensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case subtle
    case festive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:
            return "Off (Colors Only)"
        case .subtle:
            return "Subtle (Chrome)"
        case .festive:
            return "Festive"
        }
    }

    public var birthRateScale: Double {
        switch self {
        case .off:
            return 0.0
        case .subtle:
            return 1.0
        case .festive:
            return 2.1
        }
    }
}

/// Vector sprite shape drawn at 2x into cached CGImages for Core Animation particle layers.
public enum HolidayParticleShape: String, Codable, Sendable {
    case none
    case autumnLeaf
    case snowflake
    case confettiStar
    case heart
    case shamrock
    case blossomPetal
    case starSpark
    case batEmber
}

/// Chrome-only surfaces eligible for ambient glow and particle rendering.
public enum HolidayEffectSurface: String, Sendable {
    case headerBar
    case sidebar
}

/// Complete Day/Night WCAG 2.1 AA palette and ambient effect definition for a single holiday theme.
public struct HolidayThemePalette: Equatable, Sendable {
    public let id: HolidayThemeID
    public let displayName: String
    public let shortName: String
    public let symbolName: String
    public let effectTitle: String
    public let particleShape: HolidayParticleShape
    public let risesUpward: Bool
    public let accentFill: String
    public let accentFillHover: String
    public let accentTextLight: String
    public let accentTextDark: String
    public let brandGradientStart: String
    public let brandGradientEnd: String
    public let ambientGlowLight: String
    public let ambientGlowDark: String
    public let particleHexesLight: [String]
    public let particleHexesDark: [String]

    public init(
        id: HolidayThemeID,
        displayName: String,
        shortName: String,
        symbolName: String,
        effectTitle: String,
        particleShape: HolidayParticleShape,
        risesUpward: Bool,
        accentFill: String,
        accentFillHover: String,
        accentTextLight: String,
        accentTextDark: String,
        brandGradientStart: String,
        brandGradientEnd: String,
        ambientGlowLight: String,
        ambientGlowDark: String,
        particleHexesLight: [String],
        particleHexesDark: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.symbolName = symbolName
        self.effectTitle = effectTitle
        self.particleShape = particleShape
        self.risesUpward = risesUpward
        self.accentFill = accentFill
        self.accentFillHover = accentFillHover
        self.accentTextLight = accentTextLight
        self.accentTextDark = accentTextDark
        self.brandGradientStart = brandGradientStart
        self.brandGradientEnd = brandGradientEnd
        self.ambientGlowLight = ambientGlowLight
        self.ambientGlowDark = ambientGlowDark
        self.particleHexesLight = particleHexesLight
        self.particleHexesDark = particleHexesDark
    }
}

/// Canonical catalog of all 9 WCAG 2.1 AA holiday color palettes.
public enum HolidayThemeCatalog {
    public static let classic = HolidayThemePalette(
        id: .classic,
        displayName: "Classic Crimson",
        shortName: "Classic",
        symbolName: "play.rectangle.fill",
        effectTitle: "None",
        particleShape: .none,
        risesUpward: false,
        accentFill: DesignSystemMetrics.accentFill,
        accentFillHover: DesignSystemMetrics.accentFillHover,
        accentTextLight: DesignSystemMetrics.accentTextLight,
        accentTextDark: DesignSystemMetrics.accentTextDark,
        brandGradientStart: DesignSystemMetrics.brandGradientStart,
        brandGradientEnd: DesignSystemMetrics.brandGradientEnd,
        ambientGlowLight: "#D71920",
        ambientGlowDark: "#FF5C62",
        particleHexesLight: [],
        particleHexesDark: []
    )

    public static let thanksgiving = HolidayThemePalette(
        id: .thanksgiving,
        displayName: "Thanksgiving Harvest",
        shortName: "Thanksgiving",
        symbolName: "leaf.fill",
        effectTitle: "Autumn Leaves",
        particleShape: .autumnLeaf,
        risesUpward: false,
        accentFill: "#B84A0E",
        accentFillHover: "#9C3C08",
        accentTextLight: "#9A3B06",
        accentTextDark: "#FF9A4D",
        brandGradientStart: "#3B1B0B",
        brandGradientEnd: "#B84A0E",
        ambientGlowLight: "#C85A17",
        ambientGlowDark: "#FF8C38",
        particleHexesLight: ["#C4531A", "#B87414", "#A63218", "#9E6A1E"],
        particleHexesDark: ["#D96B27", "#E6952B", "#D1492A", "#E0A43E"]
    )

    public static let winter = HolidayThemePalette(
        id: .winter,
        displayName: "Winter Holidays",
        shortName: "Winter",
        symbolName: "snowflake",
        effectTitle: "Snowfall",
        particleShape: .snowflake,
        risesUpward: false,
        accentFill: "#0F6E5C",
        accentFillHover: "#0B594A",
        accentTextLight: "#0C6151",
        accentTextDark: "#52DFC6",
        brandGradientStart: "#0D2926",
        brandGradientEnd: "#B81D2C",
        ambientGlowLight: "#167D6A",
        ambientGlowDark: "#4DD4BD",
        particleHexesLight: ["#2B7AB8", "#167D6A", "#4A90C4", "#C93242"],
        particleHexesDark: ["#EAF4FF", "#B8DCFF", "#5CD6C0", "#FF6B73"]
    )

    public static let newYear = HolidayThemePalette(
        id: .newYear,
        displayName: "New Year's",
        shortName: "New Year",
        symbolName: "sparkles",
        effectTitle: "Confetti & Stars",
        particleShape: .confettiStar,
        risesUpward: false,
        accentFill: "#8A6200",
        accentFillHover: "#735000",
        accentTextLight: "#7A5500",
        accentTextDark: "#FFD057",
        brandGradientStart: "#1B1E38",
        brandGradientEnd: "#8A6200",
        ambientGlowLight: "#B58518",
        ambientGlowDark: "#F7C948",
        particleHexesLight: ["#B5820E", "#3B5EA8", "#C48E18", "#6B7B99"],
        particleHexesDark: ["#F7D154", "#E6ECF5", "#99B7FF", "#F5B841"]
    )

    public static let valentines = HolidayThemePalette(
        id: .valentines,
        displayName: "Valentine's Day",
        shortName: "Valentine's",
        symbolName: "heart.fill",
        effectTitle: "Floating Hearts",
        particleShape: .heart,
        risesUpward: true,
        accentFill: "#C41E5A",
        accentFillHover: "#A6164A",
        accentTextLight: "#A8164B",
        accentTextDark: "#FF78A8",
        brandGradientStart: "#3D1025",
        brandGradientEnd: "#C41E5A",
        ambientGlowLight: "#D6336C",
        ambientGlowDark: "#FF6B9D",
        particleHexesLight: ["#C92862", "#D94A82", "#B31D54", "#E06B98"],
        particleHexesDark: ["#F04E85", "#FF85B3", "#E03A76", "#FFB3CE"]
    )

    public static let stPatricks = HolidayThemePalette(
        id: .stPatricks,
        displayName: "St. Patrick's Day",
        shortName: "St. Patrick's",
        symbolName: "leaf.circle.fill",
        effectTitle: "Shamrocks & Gold",
        particleShape: .shamrock,
        risesUpward: false,
        accentFill: "#147A3E",
        accentFillHover: "#0F6331",
        accentTextLight: "#0C6330",
        accentTextDark: "#52E08A",
        brandGradientStart: "#0C2B1B",
        brandGradientEnd: "#147A3E",
        ambientGlowLight: "#1B8A49",
        ambientGlowDark: "#34D975",
        particleHexesLight: ["#158242", "#229E56", "#0F6E36", "#B88814"],
        particleHexesDark: ["#27B863", "#5CE08E", "#1FA658", "#F0C44A"]
    )

    public static let springEaster = HolidayThemePalette(
        id: .springEaster,
        displayName: "Spring & Easter",
        shortName: "Spring",
        symbolName: "camera.macro",
        effectTitle: "Blossom Petals",
        particleShape: .blossomPetal,
        risesUpward: false,
        accentFill: "#7B42BC",
        accentFillHover: "#6532A1",
        accentTextLight: "#6C35AD",
        accentTextDark: "#C296FF",
        brandGradientStart: "#281542",
        brandGradientEnd: "#7B42BC",
        ambientGlowLight: "#8B54CC",
        ambientGlowDark: "#B884FF",
        particleHexesLight: ["#844BC4", "#D14E8C", "#2A9478", "#C49116"],
        particleHexesDark: ["#C499FF", "#FF99C8", "#7CD4B5", "#FFE07D"]
    )

    public static let independence = HolidayThemePalette(
        id: .independence,
        displayName: "Independence Day",
        shortName: "July 4th",
        symbolName: "star.fill",
        effectTitle: "Starlight Sparks",
        particleShape: .starSpark,
        risesUpward: true,
        accentFill: "#1B54B8",
        accentFillHover: "#144296",
        accentTextLight: "#15469E",
        accentTextDark: "#75B0FF",
        brandGradientStart: "#10204A",
        brandGradientEnd: "#B81D2C",
        ambientGlowLight: "#1E5DC8",
        ambientGlowDark: "#5C9EFF",
        particleHexesLight: ["#1E5DC8", "#CC2E3C", "#2C6ED9", "#B8860B"],
        particleHexesDark: ["#5C9EFF", "#FF6673", "#F0F4FF", "#FFD166"]
    )

    public static let halloween = HolidayThemePalette(
        id: .halloween,
        displayName: "Halloween",
        shortName: "Halloween",
        symbolName: "moon.stars.fill",
        effectTitle: "Embers & Bats",
        particleShape: .batEmber,
        risesUpward: true,
        accentFill: "#BD430A",
        accentFillHover: "#9E3606",
        accentTextLight: "#A13706",
        accentTextDark: "#FF8B47",
        brandGradientStart: "#231238",
        brandGradientEnd: "#BD430A",
        ambientGlowLight: "#CC4E12",
        ambientGlowDark: "#FF7A29",
        particleHexesLight: ["#C94D0E", "#6F3BC2", "#B87A14", "#4A2680"],
        particleHexesDark: ["#FF7A29", "#A866FF", "#E8A230", "#8252DB"]
    )

    public static let allPalettes: [HolidayThemePalette] = [
        classic,
        thanksgiving,
        winter,
        newYear,
        valentines,
        stPatricks,
        springEaster,
        independence,
        halloween
    ]

    public static func palette(for id: HolidayThemeID) -> HolidayThemePalette {
        switch id {
        case .classic:
            return classic
        case .thanksgiving:
            return thanksgiving
        case .winter:
            return winter
        case .newYear:
            return newYear
        case .valentines:
            return valentines
        case .stPatricks:
            return stPatricks
        case .springEaster:
            return springEaster
        case .independence:
            return independence
        case .halloween:
            return halloween
        }
    }
}

/// Offline Gregorian seasonal holiday resolver with zero-overlap windows and midnight rollover scheduling.
public enum HolidayCalendarEngine {
    /// Computes US Thanksgiving Day (4th Thursday of November) using Swift's 1-indexed `.weekday` (`Sun=1...Thu=5...Sat=7`).
    public static func thanksgivingDay(year: Int, calendar: Calendar = .current) -> Date? {
        guard let nov1 = calendar.date(from: DateComponents(year: year, month: 11, day: 1)) else {
            return nil
        }
        let weekday = calendar.component(.weekday, from: nov1)
        let offset = (5 - weekday + 7) % 7
        let thanksgivingDay = 1 + offset + 21
        return calendar.date(from: DateComponents(year: year, month: 11, day: thanksgivingDay))
    }

    /// Computes Western Gregorian Easter Sunday using the Anonymous Gregorian Computus.
    public static func easterSunday(year: Int, calendar: Calendar = .current) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Resolves the active seasonal holiday for `date`, falling back to `.classic` outside holiday windows.
    public static func activeHoliday(for date: Date = Date(), calendar: Calendar = .current) -> HolidayThemeID {
        let dayStart = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return .classic
        }

        // Fixed date windows (strictly disjoint across all calendar years)
        if (month == 12 && day >= 29) || (month == 1 && day <= 3) {
            return .newYear
        }
        if month == 12 && (12...28).contains(day) {
            return .winter
        }
        if month == 2 && (11...15).contains(day) {
            return .valentines
        }
        if month == 3 && (14...17).contains(day) {
            return .stPatricks
        }
        if month == 7 && (1...5).contains(day) {
            return .independence
        }
        if month == 10 && (24...31).contains(day) {
            return .halloween
        }

        // Movable holidays: Spring/Easter [Easter - 4d, Easter + 1d] (>= Mar 18) and Thanksgiving [T - 6d, T + 3d]
        if let easter = easterSunday(year: year, calendar: calendar) {
            let easterStart = calendar.startOfDay(for: easter)
            if let windowStart = calendar.date(byAdding: .day, value: -4, to: easterStart),
               let windowEnd = calendar.date(byAdding: .day, value: 1, to: easterStart),
               dayStart >= windowStart && dayStart <= windowEnd {
                return .springEaster
            }
        }

        if let thanksgiving = thanksgivingDay(year: year, calendar: calendar) {
            let thanksgivingStart = calendar.startOfDay(for: thanksgiving)
            if let windowStart = calendar.date(byAdding: .day, value: -6, to: thanksgivingStart),
               let windowEnd = calendar.date(byAdding: .day, value: 3, to: thanksgivingStart),
               dayStart >= windowStart && dayStart <= windowEnd {
                return .thanksgiving
            }
        }

        return .classic
    }

    /// Returns 00:00:05 of the next calendar day for zero-polling midnight theme rollover.
    public static func nextMidnightRollover(after date: Date, calendar: Calendar = .current) -> Date {
        let todayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: todayStart)
            ?? todayStart.addingTimeInterval(86_400)
        return calendar.date(byAdding: .second, value: 5, to: nextDayStart)
            ?? nextDayStart.addingTimeInterval(5)
    }
}
