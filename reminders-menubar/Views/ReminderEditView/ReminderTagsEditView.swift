import SwiftUI

struct ReminderTagsEditView: View {
    let tagNames: [String]
    let onCommitTag: (String) -> Void
    var onCommitEmpty: () -> Void
    let onRemoveTag: (String) -> Void
    let onRemoveLastTag: () -> Void
    @Binding var focusTrigger: UUID?
    let onMoveFocus: (FocusDirection) -> Void

    @State private var newTagText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(rmbSymbol: .hashtag)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(tagNames, id: \.self) { tag in
                            TagPillView(name: tag, onRemove: { onRemoveTag(tag) })
                        }

                        TagTextField(
                            text: $newTagText,
                            placeholder: rmbLocalized(.editReminderTagsTextFieldPlaceholder),
                            onCommit: commitTag,
                            onCommitEmpty: onCommitEmpty,
                            onDeleteBackward: onRemoveLastTag,
                            autoCompleteSuggestions: { TagParser.autoCompleteSuggestions($0) },
                            focusTrigger: $focusTrigger,
                            onMoveFocus: onMoveFocus
                        )
                        .frame(minWidth: 60)
                        .frame(height: 20)

                        Color.clear
                            .frame(width: 1, height: 1)
                            .id(ScrollAnchor.trailing)
                    }
                }
                .onChange(of: newTagText) { _ in scrollToEnd(using: scrollProxy) }
                .onChange(of: tagNames) { _ in scrollToEnd(using: scrollProxy) }
                .onChange(of: focusTrigger) { _ in scrollToEnd(using: scrollProxy) }
            }
        }
    }

    // MARK: - Actions

    private func commitTag() {
        onCommitTag(newTagText)
        newTagText = ""
    }

    private func scrollToEnd(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(ScrollAnchor.trailing, anchor: .trailing)
        }
    }

    private enum ScrollAnchor {
        case trailing
    }
}

// MARK: - Tag pill

private struct TagPillView: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(name)

            Button(action: onRemove) {
                Image(rmbSymbol: .xmark)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
            }
            .buttonStyle(.borderless)
        }
        .modifier(TagPillModifier(size: .regular))
    }
}

// MARK: - Preview

#Preview {
    ReminderTagsEditView(
        tagNames: ["sample", "review", "important"],
        onCommitTag: { _ in },
        onCommitEmpty: { },
        onRemoveTag: { _ in },
        onRemoveLastTag: {},
        focusTrigger: .constant(nil),
        onMoveFocus: { _ in }
    )
}

// MARK: - TagTextField

private struct TagTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onCommitEmpty: () -> Void
    var onDeleteBackward: () -> Void
    var autoCompleteSuggestions: (_ typingWord: String) -> [String]
    @Binding var focusTrigger: UUID?
    var onMoveFocus: (FocusDirection) -> Void

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> TagNSTextView {
        let textView = TagNSTextView()
        textView.placeholder = placeholder
        textView.textContainer?.maximumNumberOfLines = 1
        textView.font = .systemFont(ofSize: 11)
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: TagNSTextView, context: Context) {
        context.coordinator.parent = self

        if !textView.hasMarkedText(),
           textView.string != text,
           textView.window?.firstResponder !== textView {
            textView.string = text
        }

        updateFocusIfNeeded(in: textView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Focus

    private func updateFocusIfNeeded(in textView: NSTextView, coordinator: Coordinator) {
        guard let trigger = focusTrigger,
              trigger != coordinator.lastFocusTrigger else {
            return
        }

        guard textView.window?.makeFirstResponder(textView) == true else {
            return
        }

        coordinator.lastFocusTrigger = trigger
        let textLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: textLength, length: 0))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TagTextField
        var isAutoCompleting = false
        var isDeletingText = false
        var lastFocusTrigger: UUID?

        init(_ parent: TagTextField) {
            self.parent = parent
        }

        // MARK: - Text changes

        func textDidChange(_ obj: Notification) {
            guard let textView = obj.object as? NSTextView else {
                return
            }

            let value = textView.string
            if parent.text != value {
                parent.text = value
            }

            if value.last == "," || value.last == " " {
                commitValue(from: textView)
                return
            }

            if isDeletingText {
                isDeletingText = false
                return
            }

            requestCompletions(in: textView)
        }

        // MARK: - Commands

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.string.isEmpty else {
                    parent.onCommitEmpty()
                    return true
                }
                commitValue(from: textView)
                return true
            case #selector(NSResponder.insertTab(_:)):
                return handleTab(in: textView, direction: .forward, expectedModifiers: [])
            case #selector(NSResponder.insertBacktab(_:)):
                return handleTab(in: textView, direction: .backward, expectedModifiers: .shift)
            case #selector(NSResponder.deleteBackward(_:)):
                if textView.string.isEmpty {
                    parent.onDeleteBackward()
                    return true
                }
                return false
            default:
                return false
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else { return true }
            guard replacementString.rangeOfCharacter(from: .newlines) == nil else { return false }

            isDeletingText = replacementString.isEmpty && affectedCharRange.length > 0
            return true
        }

        private func handleTab(
            in textView: NSTextView,
            direction: FocusDirection,
            expectedModifiers: NSEvent.ModifierFlags
        ) -> Bool {
            let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection(relevantModifiers) ?? []
            guard modifiers == expectedModifiers else { return false }

            guard textView.string.isEmpty else {
                commitValue(from: textView)
                return true
            }

            parent.onMoveFocus(direction)
            return true
        }

        private func commitValue(from textView: NSTextView) {
            parent.text = textView.string
            parent.onCommit()
            textView.string = ""
        }

        // MARK: - Autocomplete

        private func requestCompletions(in textView: NSTextView) {
            guard !isAutoCompleting,
                  !textView.hasMarkedText(),
                  !textView.string.isEmpty else { return }

            isAutoCompleting = true
            textView.complete(nil)
            isAutoCompleting = false
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let typingWord = textView.string.substring(in: charRange)
            guard !typingWord.isEmpty else {
                return []
            }

            return parent.autoCompleteSuggestions(typingWord)
        }
    }
}

// MARK: - AppKit text view

private final class TagNSTextView: PlaceholderNSTextView {
    private var textFont: NSFont {
        font ?? .systemFont(ofSize: NSFont.systemFontSize)
    }

    override var intrinsicContentSize: NSSize {
        let displayText = string.isEmpty ? placeholder : string
        let textWidth = (displayText as NSString).size(
            withAttributes: [.font: textFont]
        ).width
        let horizontalPadding = (textContainer?.lineFragmentPadding ?? 0) * 2
        let textHeight = layoutManager?.defaultLineHeight(for: textFont) ?? 0
        return NSSize(width: ceil(textWidth + horizontalPadding), height: ceil(textHeight))
    }

    override func layout() {
        super.layout()

        let textHeight = layoutManager?.defaultLineHeight(for: textFont) ?? 0
        textContainerInset.height = max((bounds.height - textHeight) / 2, 0)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
