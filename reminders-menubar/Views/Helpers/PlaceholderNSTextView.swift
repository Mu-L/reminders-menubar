import AppKit

class PlaceholderNSTextView: NSTextView {
    var placeholder = ""

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard string.isEmpty, !placeholder.isEmpty else { return }
        let textOrigin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(
            at: textOrigin,
            withAttributes: [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }
}
