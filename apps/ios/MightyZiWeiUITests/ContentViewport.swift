import XCTest

extension XCUIApplication {
  func scrollToVisibleContent(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for _ in 0..<30 {
      if isVisibleInContent(element) { return }
      scrollToward(element)
    }
    XCTAssertTrue(
      isVisibleInContent(element),
      "目標仍被導覽列、分頁列或鍵盤遮住。目標：\(element.frame)，可視區域：\(contentViewport)，可點選：\(element.isHittable)。",
      file: file, line: line)
  }

  func assertVisibleInContentViewport(
    _ element: XCUIElement,
    navigationTitle: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
    let navigationBar = navigationBars[navigationTitle]
    let bottom = tabBars.firstMatch.exists ? tabBars.firstMatch.frame.minY : frame.maxY
    XCTAssertGreaterThanOrEqual(
      element.frame.minY, navigationBar.frame.maxY, file: file, line: line)
    XCTAssertLessThanOrEqual(element.frame.maxY, bottom, file: file, line: line)
    XCTAssertTrue(element.isHittable, file: file, line: line)
  }

  private func scrollToward(_ element: XCUIElement) {
    let viewport = contentViewport
    let offset = element.exists ? element.frame.midY - viewport.midY : viewport.height
    // 在內容上半部拖移，避免手勢從固定底部操作列開始而無法捲動。
    // 接近目標時縮短距離，避免整屏 swipe 越過目標後反覆上下捲動。
    let distance = min(max(abs(offset), 44), viewport.height * 0.45)
    let direction: CGFloat = offset < 0 ? 1 : -1
    let startY = viewport.minY + 8 + (direction < 0 ? distance : 0)
    let start = coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: viewport.midX, dy: startY))
    let end = start.withOffset(CGVector(dx: 0, dy: direction * distance))
    start.press(forDuration: 0.05, thenDragTo: end)
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
