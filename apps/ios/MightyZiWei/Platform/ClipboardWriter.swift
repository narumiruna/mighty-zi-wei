import UIKit

@MainActor
enum ClipboardWriter {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
