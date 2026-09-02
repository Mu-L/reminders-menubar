import SwiftUI

struct CreateReminderButton: View {
    @EnvironmentObject var remindersData: RemindersData
    @EnvironmentObject var newReminderTypingCoordinator: NewReminderTypingCoordinator
    @State private var showingCreateView = false

    var body: some View {
        Button {
            showingCreateView = true
        } label: {
            ToolbarButtonLabel {
                HStack {
                    Image(rmbSymbol: .plus)
                    Text(String("⌘N"))
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
                .padding(.trailing, 2)
            }
        }
        .keyboardShortcut("n", modifiers: .command)
        .modifier(ConfirmButtonModifier())
        .help(rmbLocalized(.newReminderButtonHelp))
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSPopover.didCloseNotification,
                object: AppDelegate.shared.popover
            )
        ) { _ in
            resetCreateReminderSheetState()
        }
        .onChange(of: newReminderTypingCoordinator.isHandoffActive) { isActive in
            guard isActive, !showingCreateView else { return }
            showingCreateView = true
        }
        .sheet(isPresented: $showingCreateView, onDismiss: resetCreateReminderSheetState) {
            ReminderEditView(isPresented: $showingCreateView)
        }
    }

    private func resetCreateReminderSheetState() {
        showingCreateView = false
        newReminderTypingCoordinator.reset()
    }
}

#Preview {
    CreateReminderButton()
        .environmentObject(RemindersData())
        .environmentObject(NewReminderTypingCoordinator())
}
