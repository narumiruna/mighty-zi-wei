import XCTest

extension XCUIApplication {
  func scrollToVisibleContent(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for _ in 0..<10 {
      if isVisibleInContent(element) { return }
      if element.exists, element.frame.midY < contentViewport.midY {
        swipeDown()
      } else {
        swipeUp()
      }
    }
    XCTAssertTrue(isVisibleInContent(element), "目標仍被導覽列、分頁列或鍵盤遮住。", file: file, line: line)
  }

  private func isVisibleInContent(_ element: XCUIElement) -> Bool {
    guard element.isHittable else { return false }
    let viewport = contentViewport
    let elementFrame = element.frame
    // 超過一屏的閱讀內容只需能夠瀏覽，不能要求整個區塊同時出現在畫面上。
    if elementFrame.height > viewport.height {
      return elementFrame.intersection(viewport).height >= 44
    }
    return viewport.contains(CGPoint(x: elementFrame.midX, y: elementFrame.midY))
  }

  private var contentViewport: CGRect {
    let top = navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? frame.minY
    var bottom = frame.maxY
    if tabBars.firstMatch.isHittable {
      bottom = min(bottom, tabBars.firstMatch.frame.minY)
    }
    if keyboards.firstMatch.exists {
      bottom = min(bottom, keyboards.firstMatch.frame.minY)
    }
    return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, bottom - top))
      .insetBy(dx: 0, dy: 8)
  }
}
