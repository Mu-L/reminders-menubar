import AppKit

@MainActor
final class NewReminderTypingCoordinator: ObservableObject {
    @Published private(set) var isHandoffActive = false
    private var pendingKeyEvents: [NSEvent] = []

    func enqueue(_ event: NSEvent) {
        pendingKeyEvents.append(event)
        if !isHandoffActive {
            isHandoffActive = true
        }
    }

    func replayPendingEvents(in textView: NSTextView) {
        guard isHandoffActive else { return }

        while !pendingKeyEvents.isEmpty {
            let events = pendingKeyEvents
            pendingKeyEvents.removeAll()
            events.forEach { textView.keyDown(with: $0) }
        }
        isHandoffActive = false
    }

    func reset() {
        pendingKeyEvents.removeAll()
        if isHandoffActive {
            isHandoffActive = false
        }
    }
}
