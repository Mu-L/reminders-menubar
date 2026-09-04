import SwiftUI

struct ReminderTagsEditView: View {
    let tagNames: [String]
    let onCommitTag: (String) -> Void
    var onCommitEmpty: (() -> Void)?
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
                    .frame(minWidth: 60, maxWidth: 120)
                    .frame(height: 20)
                }
            }
        }
    }

    private func commitTag() {
        onCommitTag(newTagText)
        newTagText = ""
    }
}

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

#Preview {
    ReminderTagsEditView(
        tagNames: ["sample", "review", "important"],
        onCommitTag: { _ in },
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
    var onCommitEmpty: (() -> Void)?
    var onDeleteBackward: () -> Void
    var autoCompleteSuggestions: ((_ typingWord: String) -> [String])?
    @Binding var focusTrigger: UUID?
    var onMoveFocus: (FocusDirection) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = .systemFont(ofSize: 11)
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.lineBreakMode = .byClipping
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        updateFocusIfNeeded(in: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateFocusIfNeeded(in nsView: NSTextField, coordinator: Coordinator) {
        guard let trigger = focusTrigger,
              trigger != coordinator.lastFocusTrigger else {
            return
        }

        guard nsView.window?.makeFirstResponder(nsView) == true,
              let textView = nsView.currentEditor() as? NSTextView else {
            return
        }

        coordinator.lastFocusTrigger = trigger
        let textLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: textLength, length: 0))
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TagTextField
        var isAutoCompleting = false
        var lastFocusTrigger: UUID?

        init(_ parent: TagTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let value = textField.stringValue

            if value.last == "," || value.last == " " {
                parent.text = value
                parent.onCommit()
                textField.stringValue = ""
                return
            }

            parent.text = value

            if !isAutoCompleting, parent.autoCompleteSuggestions != nil,
               let fieldEditor = textField.currentEditor() as? NSTextView {
                isAutoCompleting = true
                fieldEditor.complete(nil)
                isAutoCompleting = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if textView.string.isEmpty {
                    parent.onCommitEmpty?()
                } else {
                    parent.onCommit()
                }
                return true
            case #selector(NSResponder.insertTab(_:)):
                return handleFocusMove(.forward, expectedModifiers: [])
            case #selector(NSResponder.insertBacktab(_:)):
                return handleFocusMove(.backward, expectedModifiers: .shift)
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

        private func handleFocusMove(
            _ direction: FocusDirection,
            expectedModifiers: NSEvent.ModifierFlags
        ) -> Bool {
            let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection(relevantModifiers) ?? []
            guard modifiers == expectedModifiers else {
                return false
            }

            parent.onMoveFocus(direction)
            return true
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>
        ) -> [String] {
            guard let autoCompleteSuggestions = parent.autoCompleteSuggestions else {
                return []
            }

            let typingWord = textView.string.substring(in: charRange)
            guard !typingWord.isEmpty else {
                return []
            }

            return autoCompleteSuggestions(typingWord)
        }
    }
}
