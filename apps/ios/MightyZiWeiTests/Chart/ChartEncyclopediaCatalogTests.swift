import XCTest
@testable import MightyZiWei

final class ChartEncyclopediaCatalogTests: XCTestCase {
    func test索引現有星曜宮位四化與三方四正() {
        XCTAssertEqual(ChartEncyclopediaCatalog.starEntries.count, 28)
        XCTAssertEqual(ChartEncyclopediaCatalog.palaceEntries.count, 12)
        XCTAssertEqual(ChartEncyclopediaCatalog.transformationEntries.count, 4)
        XCTAssertEqual(ChartEncyclopediaCatalog.allEntries.count, 45)
        XCTAssertEqual(ChartEncyclopediaCatalog.sanFangSiZhengEntry.title, "三方四正")

        let identifiers = ChartEncyclopediaCatalog.allEntries.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(ChartEncyclopediaCatalog.allEntries.allSatisfy { !$0.title.isEmpty })
    }

    func test每個項目附上對應的RULESET排盤章節() {
        for entry in ChartEncyclopediaCatalog.starEntries {
            switch entry.reference {
            case let .star(star) where star.category == .main:
                XCTAssertEqual(entry.placementRuleSection, "RULESET.md 第 10 節〈十四主星〉")
            case .star:
                XCTAssertEqual(entry.placementRuleSection, "RULESET.md 第 11 節〈六吉、六煞、祿存與天馬〉")
            default:
                XCTFail("星曜索引包含非星曜項目")
            }
        }

        XCTAssertTrue(ChartEncyclopediaCatalog.palaceEntries.allSatisfy {
            $0.placementRuleSection == "RULESET.md 第 7 節〈命宮、身宮與十二宮〉"
        })
        XCTAssertTrue(ChartEncyclopediaCatalog.transformationEntries.allSatisfy {
            $0.placementRuleSection == "RULESET.md 第 12 節〈生年四化〉"
        })
        XCTAssertEqual(
            ChartEncyclopediaCatalog.sanFangSiZhengEntry.placementRuleSection,
            "RULESET.md 第 13 節〈三方四正〉"
        )
    }

    func test星曜與宮位說明標示為現行產品文案而非RULESET規則() {
        let editorialEntries = ChartEncyclopediaCatalog.starEntries
            + ChartEncyclopediaCatalog.palaceEntries
        XCTAssertTrue(editorialEntries.allSatisfy {
            $0.explanatorySource == ChartEncyclopediaEntry.currentProductLanguageSource
        })
        XCTAssertTrue(editorialEntries.allSatisfy {
            $0.explanatorySource?.contains("current-product-language") == true
        })
        XCTAssertTrue(ChartEncyclopediaCatalog.transformationEntries.allSatisfy {
            $0.explanatorySource == nil
        })
        XCTAssertNil(ChartEncyclopediaCatalog.sanFangSiZhengEntry.explanatorySource)
    }

    func testCatalog只引用既有Domain項目() {
        XCTAssertEqual(
            ChartEncyclopediaCatalog.starEntries.compactMap { entry -> Star? in
                guard case let .star(star) = entry.reference else { return nil }
                return star
            },
            Star.allCases
        )
        XCTAssertEqual(
            ChartEncyclopediaCatalog.palaceEntries.compactMap { entry -> PalaceKind? in
                guard case let .palace(palace) = entry.reference else { return nil }
                return palace
            },
            PalaceKind.allCases
        )
        XCTAssertEqual(
            ChartEncyclopediaCatalog.transformationEntries.compactMap { entry -> TransformationKind? in
                guard case let .transformation(transformation) = entry.reference else { return nil }
                return transformation
            },
            TransformationKind.allCases
        )
    }
}
