import Foundation

public enum ZiWeiCalculationError: Error, Equatable, Sendable {
    case missingPalace
    case missingStar(Star)
}

public struct ZiWeiCalculator: Sendable {
    public init() {}

    public func normalize(_ profile: BirthProfile) throws -> NormalizedBirth {
        try CalendarNormalizer.normalize(profile)
    }

    public func calculate(_ profile: BirthProfile) throws -> ZiWeiChart {
        let normalized = try CalendarNormalizer.normalize(profile)
        let lunarDate = try CalendarNormalizer.lunarDate(from: normalized)
        let hourBranch = try CalendarNormalizer.hourBranch(for: profile.localTime)
        let palaces = ZiWeiRules.palaces(
            chartMonth: lunarDate.chartMonth,
            hourBranch: hourBranch,
            yearStem: lunarDate.yearStem
        )
        guard let lifePalace = palaces.first(where: { $0.kind == .life }) else {
            throw ZiWeiCalculationError.missingPalace
        }
        let bureau = ZiWeiRules.fiveElementBureau(lifeStemBranch: lifePalace.stemBranch)
        let main = ZiWeiRules.mainStars(lunarDay: lunarDate.day, bureau: bureau)
        let auxiliary = ZiWeiRules.auxiliaryStars(
            chartMonth: lunarDate.chartMonth,
            hourBranch: hourBranch,
            yearStem: lunarDate.yearStem,
            yearBranch: lunarDate.yearBranch
        )
        let allBranches = main.merging(auxiliary) { current, _ in current }
        let palaceByBranch = Dictionary(uniqueKeysWithValues: palaces.map {
            ($0.stemBranch.branch, $0.kind)
        })

        let placements = try Star.allCases.map { star -> StarPlacement in
            guard let branch = allBranches[star] else {
                throw ZiWeiCalculationError.missingStar(star)
            }
            guard let palace = palaceByBranch[branch] else {
                throw ZiWeiCalculationError.missingPalace
            }
            return StarPlacement(star: star, branch: branch, palace: palace)
        }

        let placementsByStar = Dictionary(uniqueKeysWithValues: placements.map { ($0.star, $0) })
        let transformationStars = ZiWeiRules.transformationStars(yearStem: lunarDate.yearStem)
        let transformations = try TransformationKind.allCases.map { kind -> Transformation in
            guard let star = transformationStars[kind], let placement = placementsByStar[star] else {
                throw ZiWeiCalculationError.missingStar(transformationStars[kind] ?? .ziWei)
            }
            return Transformation(
                kind: kind,
                star: star,
                branch: placement.branch,
                palace: placement.palace
            )
        }

        return ZiWeiChart(
            ruleSet: .taiwanTraditionalSanheV1,
            birthProfile: profile,
            lunarDate: lunarDate,
            hourBranch: hourBranch,
            fiveElementBureau: bureau,
            palaces: palaces,
            stars: placements,
            transformations: transformations,
            relations: ZiWeiRules.relations(palaces: palaces)
        )
    }
}
