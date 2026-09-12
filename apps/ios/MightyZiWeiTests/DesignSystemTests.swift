import SwiftUI
import UIKit
import XCTest

@testable import MightyZiWei

@MainActor
final class DesignSystemTests: XCTestCase {
  func test淺色與深色的自訂文字色至少符合一般文字對比() throws {
    for style: UIUserInterfaceStyle in [.light, .dark] {
      for contrast: UIAccessibilityContrast in [.normal, .high] {
        let traits = UITraitCollection {
          $0.userInterfaceStyle = style
          $0.accessibilityContrast = contrast
        }
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
          .resolvedColor(with: traits)
        for name in ["PageBackground", "CardBackground"] {
          let background = try XCTUnwrap(UIColor(named: name))
            .resolvedColor(with: traits)
          let secondaryText = try XCTUnwrap(UIColor(named: "SecondaryText"))
          for foreground in [accent, UIColor.label, secondaryText] {
            XCTAssertGreaterThanOrEqual(
              contrastRatio(
                foreground: foreground.resolvedColor(with: traits),
                background: background
              ),
              4.5,
              "\(name) 的文字對比不足：\(style.rawValue)、\(contrast.rawValue)"
            )
          }
        }
      }
    }
  }

  func test主要操作與首頁裝飾文字維持清楚對比() throws {
    XCTAssertGreaterThanOrEqual(
      contrastRatio(foreground: .white, background: UIColor(AppDesign.ink)),
      4.5
    )
    XCTAssertGreaterThanOrEqual(
      contrastRatio(foreground: UIColor(AppDesign.gold), background: UIColor(AppDesign.ink)),
      4.5
    )
    let darkAccent = try XCTUnwrap(UIColor(named: "AccentColor"))
      .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    XCTAssertGreaterThanOrEqual(
      contrastRatio(foreground: UIColor(AppDesign.ink), background: darkAccent),
      4.5
    )
  }

  private func contrastRatio(foreground: UIColor, background: UIColor) -> Double {
    let foregroundComponents = components(foreground)
    let backgroundComponents = components(background)
    let alpha = foregroundComponents[3]
    let blended = zip(foregroundComponents.prefix(3), backgroundComponents.prefix(3)).map {
      $0 * alpha + $1 * (1 - alpha)
    }
    let foregroundLuminance = luminance(blended)
    let backgroundLuminance = luminance(Array(backgroundComponents.prefix(3)))
    return (max(foregroundLuminance, backgroundLuminance) + 0.05)
      / (min(foregroundLuminance, backgroundLuminance) + 0.05)
  }

  private func components(_ color: UIColor) -> [Double] {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    return [red, green, blue, alpha].map(Double.init)
  }

  private func luminance(_ components: [Double]) -> Double {
    let linear = components.map {
      $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
    }
    return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
  }
}
