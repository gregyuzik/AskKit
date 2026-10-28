import AskCore
import AskUI
import SwiftUI

/// The assistant's screen (`DemoLaunchArgument.assistant`): `AskScreen` in a
/// stack, as every host has it, with the demo's mark, no tiles to draw, and
/// two host items: the reminders the reader has added, and the settings card.
///
/// Smaller than `ContentView` on purpose. The tabs, the slot, the photo
/// button, the tile routes and the nothing-to-ask screen are about the
/// library's screen, and the assistant has no rows to open or own.
struct DemoAssistantView: View {
    let ask: DemoAsk<DemoAssistantDomain>

    @State private var showsReminders = false
    @State private var showsSettings = false

    /// Leading on the phone, as `ContentView.settingsPlacement` says, and
    /// secondary on the Mac, which has no top bar to lead.
    private var hostItemsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .secondaryAction
        #else
        .topBarLeading
        #endif
    }

    var body: some View {
        NavigationStack {
            AskScreen(store: ask.store, accent: .accentColor, spectrum: .aurora)
                .mark { DemoMark(isLit: $0) }
                .navigationTitle(ask.store.brand.title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItemGroup(placement: hostItemsPlacement) {
                        Button {
                            showsReminders = true
                        } label: {
                            Label {
                                Text(verbatim: "Reminders")
                            } icon: {
                                Image(systemName: "bell")
                            }
                        }
                        .symbolRenderingMode(.monochrome)
                        .accessibilityIdentifier(DemoAccessibility.reminders)
                        Button {
                            showsSettings = true
                        } label: {
                            Label {
                                Text(verbatim: "Ask settings")
                            } icon: {
                                Image(systemName: "gearshape")
                            }
                        }
                        .symbolRenderingMode(.monochrome)
                    }
                }
                .sheet(isPresented: $showsReminders) {
                    DemoReminderSheet(list: ask.domain.reminders)
                }
                .sheet(isPresented: $showsSettings) {
                    DemoSettings(ask: ask)
                }
        }
        .onOpenURL { ask.open($0) }
        // The link handed over at launch, once a launch, as `ContentView`
        // takes it.
        .task {
            guard let url = ask.takeLaunchLink() else { return }
            ask.open(url)
        }
    }
}

/// The reminders added this launch: what a confirmed card did, where a
/// host's own screen would show it.
struct DemoReminderSheet: View {
    let list: DemoReminderList

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if list.reminders.isEmpty {
                    Text(verbatim: "None yet. Ask to be reminded of something, and add it with the card under the answer.")
                        .askDeemphasizedText()
                } else {
                    ForEach(list.reminders) { reminder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: reminder.text)
                            if let when = reminder.when {
                                Text(verbatim: when)
                                    .font(.footnote)
                                    .askDeemphasizedText()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(DemoAccessibility.reminder)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Reminders"))
            .toolbar {
                // The system's close button, as `DemoRowDetail` says.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DemoAssistantView(ask: DemoAsk())
}
