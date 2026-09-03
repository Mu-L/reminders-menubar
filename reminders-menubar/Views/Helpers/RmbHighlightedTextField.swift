import SwiftUI

struct RmbHighlightedTextField: NSViewRepresentable {
    struct HighlightedText {
        let range: NSRange
        let color: NSColor
    }

    let placeholder: String
    var text: Binding<String>
    var highlightedTexts: [HighlightedText]
    var textContainerDynamicHeight: Binding<CGFloat>?
    var maximumNumberOfLines: Int
    var allowNewLineAndTab: Bool
    var focusTrigger: Binding<UUID>?

    private var textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private var onSubmit: (() -> Void)?
    private var onDidBecomeFirstResponder: ((NSTextView) -> Void)?
    private var isInitialCharValidToAutoComplete: ((_ initialChar: String?) -> Bool)?
    private var autoCompleteSuggestions: ((_ initialChar: String?, _ typingWord: String) -> [String])?

    // MARK: - NSViewRepresentable

    init(
        placeholder: String,
        text: Binding<String>,
        highlightedTexts: [HighlightedText] = [],
        textContainerDynamicHeight: Binding<CGFloat>? = nil,
        maximumNumberOfLines: Int = 3,
        allowNewLineAndTab: Bool = false,
        focusTrigger: Binding<UUID>? = nil
    ) {
        self.placeholder = placeholder
        self.text = text
        self.highlightedTexts = highlightedTexts
        self.textContainerDynamicHeight = textContainerDynamicHeight
        self.maximumNumberOfLines = maximumNumberOfLines
        self.allowNewLineAndTab = allowNewLineAndTab
        self.focusTrigger = focusTrigger
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PlaceholderNSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? PlaceholderNSTextView else {
            return scrollView
        }

        textView.placeholder = placeholder
        textView.shouldFocus = focusTrigger != nil
        textView.onDidBecomeFirstResponder = onDidBecomeFirstResponder
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.font = textFont
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PlaceholderNSTextView else {
            return
        }

        context.coordinator.parent = self
        textView.onDidBecomeFirstResponder = onDidBecomeFirstResponder

        // AppKit owns marked text until the input method commits its composition.
        if !textView.hasMarkedText() {
            let updatedText = text.wrappedValue
            if updatedText == textView.string {
                // Refresh highlighting without replacing characters, selection, or undo state.
                if let textStorage = textView.textStorage {
                    applyAttributes(to: textStorage)
                }
            } else if textView.window?.firstResponder !== textView {
                // Keep the active editor authoritative so stale text cannot move its insertion point.
                updateTextAndAttributes(in: textView, with: updatedText)
            }
        }

        updateFocusIfNeeded(in: textView, coordinator: context.coordinator)

        textView.scrollRangeToVisible(textView.selectedRange())

        adjustDynamicHeight(for: textView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    // MARK: - Text and attributes

    private func updateTextAndAttributes(in textView: NSTextView, with updatedText: String) {
        let selectedRange = textView.selectedRange()
        let updatedTextLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedTextLength)
        let selectionLength = min(selectedRange.length, updatedTextLength - selectionLocation)

        textView.textStorage?.setAttributedString(getAttributedString(from: updatedText))
        textView.setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))
    }

    private func getAttributedString(from text: String) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        applyAttributes(to: attributedString)
        return attributedString
    }

    private func applyAttributes(to attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.beginEditing()
        attributedString.setAttributes(
            [
                .font: textFont,
                .foregroundColor: NSColor.labelColor
            ],
            range: fullRange
        )
        for highlightedText in highlightedTexts
        where highlightedText.range.location != NSNotFound
            && NSMaxRange(highlightedText.range) <= attributedString.length {
            attributedString.addAttribute(
                .foregroundColor,
                value: highlightedText.color,
                range: highlightedText.range
            )
        }
        attributedString.endEditing()
    }

    // MARK: - Focus

    private func updateFocusIfNeeded(in textView: NSTextView, coordinator: Coordinator) {
        guard let trigger = focusTrigger?.wrappedValue,
              trigger != coordinator.lastFocusTrigger else {
            return
        }

        coordinator.lastFocusTrigger = trigger
        if textView.window?.firstResponder != textView {
            textView.window?.makeFirstResponder(textView)
        }

        let textLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: textLength, length: 0))
    }

    // MARK: - Layout

    private func adjustDynamicHeight(for textView: NSTextView, context: Context) {
        guard let dynamicHeight = context.coordinator.parent.textContainerDynamicHeight,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let lineHeight = layoutManager.defaultLineHeight(for: textFont)
        let maxHeight = lineHeight * CGFloat(max(maximumNumberOfLines, 1))
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let newHeight = min(max(usedHeight, lineHeight), maxHeight)

        guard dynamicHeight.wrappedValue != newHeight else {
            return
        }

        DispatchQueue.main.async {
            dynamicHeight.wrappedValue = newHeight
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RmbHighlightedTextField

        var isAutoCompleting = false
        var isDeletingText = false
        var lastFocusTrigger: UUID?

        init(_ parent: RmbHighlightedTextField) {
            self.parent = parent
        }

        // MARK: - Commands

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return handleNewline()
            default:
                return false
            }
        }

        private func handleNewline() -> Bool {
            let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection(relevantModifiers) ?? []

            if parent.allowNewLineAndTab, !modifiers.isEmpty {
                return false
            }

            guard let onSubmit = parent.onSubmit else {
                return false
            }

            onSubmit()
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else {
                return true
            }

            isDeletingText = replacementString.isEmpty && affectedCharRange.length > 0

            if !parent.allowNewLineAndTab && (replacementString == "\n" || replacementString == "\t") {
                return false
            }

            return true
        }

        // MARK: - Text changes

        func textDidChange(_ obj: Notification) {
            guard let textView = obj.object as? NSTextView else {
                return
            }

            let textMatchesBinding = parent.text.wrappedValue == textView.string
            if !textMatchesBinding {
                parent.text.wrappedValue = textView.string
            }

            if isDeletingText {
                isDeletingText = false
                return
            }

            requestCompletions(in: textView)

            // A same-text completion does not trigger updateNSView, so refresh attributes
            // after AppKit finishes processing the completion request.
            if textMatchesBinding {
                schedulePostCompletionAttributeRefresh(for: textView)
            }
        }

        // MARK: - Autocomplete

        private func requestCompletions(in textView: NSTextView) {
            guard !isAutoCompleting, !textView.hasMarkedText() else { return }

            isAutoCompleting = true
            textView.complete(nil)
            isAutoCompleting = false
        }

        private func schedulePostCompletionAttributeRefresh(for textView: NSTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView,
                      !textView.hasMarkedText(),
                      parent.text.wrappedValue == textView.string,
                      let textStorage = textView.textStorage else {
                    return
                }

                parent.applyAttributes(to: textStorage)
            }
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let autoCompleteSuggestions = parent.autoCompleteSuggestions else {
                return []
            }

            let typingWord = textView.string.substring(in: charRange)
            guard !typingWord.isEmpty,
                  isValidToAutocomplete(textView.string, charRange: charRange) else {
                return []
            }

            let initialChar = textView.string[safe: charRange.lowerBound - 1]
            return autoCompleteSuggestions(initialChar, typingWord)
        }

        private func isValidToAutocomplete(_ string: String, charRange: NSRange) -> Bool {
            guard let isInitialCharValidToAutoComplete = parent.isInitialCharValidToAutoComplete else {
                return false
            }

            let initialChar = string[safe: charRange.lowerBound - 1]
            let beforeInitialChar = string[safe: charRange.lowerBound - 2]

            return isInitialCharValidToAutoComplete(initialChar)
            && (beforeInitialChar == " " || beforeInitialChar == nil)
        }
    }
}

// MARK: - Modifiers

extension RmbHighlightedTextField {
    func onDidBecomeFirstResponder(
        _ action: @escaping (NSTextView) -> Void
    ) -> RmbHighlightedTextField {
        var view = self
        view.onDidBecomeFirstResponder = action
        return view
    }

    func onSubmit(_ onSubmit: @escaping () -> Void) -> RmbHighlightedTextField {
        var view = self
        view.onSubmit = onSubmit
        return view
    }

    func autoComplete(
        isInitialCharValid: @escaping (_ initialChar: String?) -> Bool,
        suggestions: @escaping (_ initialChar: String?, _ typingWord: String) -> [String]
    ) -> RmbHighlightedTextField {
        var view = self
        view.isInitialCharValidToAutoComplete = isInitialCharValid
        view.autoCompleteSuggestions = suggestions
        return view
    }

    func fontStyle(_ fontStyle: NSFont.TextStyle) -> RmbHighlightedTextField {
        var view = self
        view.textFont = .preferredFont(forTextStyle: fontStyle)
        return view
    }
}

// MARK: - AppKit text view

private class PlaceholderNSTextView: NSTextView {
    var placeholder: String = ""
    var shouldFocus: Bool = false
    var onDidBecomeFirstResponder: ((NSTextView) -> Void)?

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        if string.isEmpty && !placeholder.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]

            placeholder.draw(in: rect.insetBy(dx: 4, dy: 0), withAttributes: attributes)
        }
    }

    override func viewDidMoveToWindow() {
        if shouldFocus {
            window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        // Let AppKit finish installing the field editor before replaying captured key events.
        DispatchQueue.main.async { [weak self] in
            guard let self, window?.firstResponder === self else { return }

            window?.contentView?.layoutSubtreeIfNeeded()
            if let layoutManager, let textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }

            onDidBecomeFirstResponder?(self)
        }
        return true
    }
}
