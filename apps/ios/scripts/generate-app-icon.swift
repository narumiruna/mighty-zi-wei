import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 深紫底、暖金牛角與一顆主星；不加文字、外框或預裁圓角。
// 僅使用 macOS 系統框架，圖片由建置流程產生，不保存於 repository。
enum IconGenerationError: Error, LocalizedError {
  case invalidOutput
  case renderingFailed
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .invalidOutput:
      return "請指定 repository 外的 .xcassets 輸出路徑。"
    case .renderingFailed:
      return "無法建立 App icon 繪圖環境。"
    case .encodingFailed:
      return "無法輸出 App icon PNG。"
    }
  }
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
  CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func drawBackground(in context: CGContext, colorSpace: CGColorSpace) throws {
  let colors = [
    color(0.27, 0.20, 0.36),
    color(0.17, 0.12, 0.25),
    color(0.10, 0.07, 0.16),
  ]
  guard
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)
  else {
    throw IconGenerationError.renderingFailed
  }
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 128, y: 1024),
    end: CGPoint(x: 850, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
}

func bullSilhouette() -> CGPath {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: 210, y: 736))
  path.addCurve(
    to: CGPoint(x: 332, y: 536),
    control1: CGPoint(x: 216, y: 591), control2: CGPoint(x: 246, y: 520)
  )
  path.addLine(to: CGPoint(x: 350, y: 402))
  path.addCurve(
    to: CGPoint(x: 512, y: 240),
    control1: CGPoint(x: 374, y: 316), control2: CGPoint(x: 440, y: 260)
  )
  path.addCurve(
    to: CGPoint(x: 674, y: 402),
    control1: CGPoint(x: 584, y: 260), control2: CGPoint(x: 650, y: 316)
  )
  path.addLine(to: CGPoint(x: 692, y: 536))
  path.addCurve(
    to: CGPoint(x: 814, y: 736),
    control1: CGPoint(x: 778, y: 520), control2: CGPoint(x: 808, y: 591)
  )
  path.addCurve(
    to: CGPoint(x: 596, y: 584),
    control1: CGPoint(x: 776, y: 672), control2: CGPoint(x: 692, y: 620)
  )
  path.addCurve(
    to: CGPoint(x: 428, y: 584),
    control1: CGPoint(x: 548, y: 612), control2: CGPoint(x: 476, y: 612)
  )
  path.addCurve(
    to: CGPoint(x: 210, y: 736),
    control1: CGPoint(x: 332, y: 620), control2: CGPoint(x: 248, y: 672)
  )
  path.closeSubpath()
  return path
}

func guidingStar() -> CGPath {
  let path = CGMutablePath()
  path.move(to: CGPoint(x: 512, y: 850))
  path.addCurve(
    to: CGPoint(x: 594, y: 752),
    control1: CGPoint(x: 526, y: 780), control2: CGPoint(x: 536, y: 768)
  )
  path.addCurve(
    to: CGPoint(x: 512, y: 654),
    control1: CGPoint(x: 536, y: 736), control2: CGPoint(x: 526, y: 724)
  )
  path.addCurve(
    to: CGPoint(x: 430, y: 752),
    control1: CGPoint(x: 498, y: 724), control2: CGPoint(x: 488, y: 736)
  )
  path.addCurve(
    to: CGPoint(x: 512, y: 850),
    control1: CGPoint(x: 488, y: 768), control2: CGPoint(x: 498, y: 780)
  )
  path.closeSubpath()
  return path
}

func drawEmblem(in context: CGContext, colorSpace: CGColorSpace) throws {
  let colors = [color(0.99, 0.91, 0.72), color(0.86, 0.75, 0.56)]
  guard
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)
  else {
    throw IconGenerationError.renderingFailed
  }
  context.saveGState()
  context.addPath(bullSilhouette())
  context.addPath(guidingStar())
  context.clip()
  context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: 850),
    end: CGPoint(x: 512, y: 240),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
  context.restoreGState()

  // 眼部保留兩筆短線，避免縮小後依賴細節辨識。
  context.setStrokeColor(color(0.17, 0.12, 0.25))
  context.setLineWidth(20)
  context.setLineCap(.round)
  context.move(to: CGPoint(x: 414, y: 461))
  context.addLine(to: CGPoint(x: 450, y: 447))
  context.move(to: CGPoint(x: 610, y: 461))
  context.addLine(to: CGPoint(x: 574, y: 447))
  context.strokePath()
}

func renderIcon() throws -> CGImage {
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  else {
    throw IconGenerationError.renderingFailed
  }
  try drawBackground(in: context, colorSpace: colorSpace)
  try drawEmblem(in: context, colorSpace: colorSpace)
  guard let image = context.makeImage() else {
    throw IconGenerationError.renderingFailed
  }
  return image
}

func resolvedDestination(_ url: URL) -> URL {
  let standardized = url.standardizedFileURL
  if FileManager.default.fileExists(atPath: standardized.path) {
    return standardized.resolvingSymlinksInPath()
  }
  return resolvedDestination(standardized.deletingLastPathComponent())
    .appendingPathComponent(standardized.lastPathComponent)
}

func generateCatalog(at output: URL) throws {
  let fileManager = FileManager.default
  let repository = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
    url.deletingLastPathComponent()
  }.resolvingSymlinksInPath()
  let resolvedOutput = resolvedDestination(output)
  guard output.pathExtension == "xcassets",
    !resolvedOutput.path.hasPrefix(repository.path + "/"),
    resolvedOutput.path != repository.path
  else {
    throw IconGenerationError.invalidOutput
  }

  let iconSet = output.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
  try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)
  let imageURL = iconSet.appendingPathComponent("AppIcon.png")
  let image = try renderIcon()
  guard
    let destination = CGImageDestinationCreateWithURL(
      imageURL as CFURL, UTType.png.identifier as CFString, 1, nil
    )
  else {
    throw IconGenerationError.encodingFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw IconGenerationError.encodingFailed
  }

  let info: [String: Any] = ["author": "xcode", "version": 1]
  let imageEntry = [
    "filename": "AppIcon.png", "idiom": "universal", "platform": "ios",
    "size": "1024x1024",
  ]
  let contents: [String: Any] = ["images": [imageEntry], "info": info]
  let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
  try JSONSerialization.data(withJSONObject: contents, options: options)
    .write(to: iconSet.appendingPathComponent("Contents.json"), options: .atomic)
  try JSONSerialization.data(withJSONObject: ["info": info], options: options)
    .write(to: output.appendingPathComponent("Contents.json"), options: .atomic)
  print("已產生 App icon：\(imageURL.path)")
}

do {
  guard CommandLine.arguments.count == 2 else {
    throw IconGenerationError.invalidOutput
  }
  try generateCatalog(at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
