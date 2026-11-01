import AskCore
import AskUI
import SwiftUI

/// The assistant's screen, a switch away from the library's
/// (`DemoDomainSwitch`): `AskScreen` in a stack, as every host has it, with
/// the demo's mark and no tiles to draw. Its one host item of its own is the
/// settings card, beside the switch, and the card's Reminders section lists
/// the reminders the reader has added (`DemoReminderSection`).
///
/// Smaller than `ContentView` on purpose. The tabs, the slot, the photo
/// button, the tile routes and the nothing-to-ask screen are about the
/// library's screen, and the assistant has no rows to open or own.
struct DemoAssistantView: View {
    let ask: DemoAsk<DemoAssistantDomain>
    /// The host, for the switch back to the library, and for the link handed
    /// over at launch.
    let host: DemoHost

    @State private var showsSettings = false

    /// Leading on the phone, as `ContentView.settingsPlacement` says, and
    /// secondary on the Mac, which has no top bar to lead.
    private var hostItemPlacement: ToolbarItemPlacement {
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
                // Before the host's item, so the switch stands after it, where
                // Done takes its place while the keyboard is up
                // (`DemoDomainSwitch`).
                .modifier(DemoDomainSwitch(host: host))
                .toolbar {
                    ToolbarItem(placement: hostItemPlacement) {
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
                        .accessibilityIdentifier(DemoAccessibility.settings)
                    }
                }
                .sheet(isPresented: $showsSettings) {
                    DemoSettings(ask: ask) {
                        DemoReminderSection(list: ask.domain.reminders)
                    }
                }
        }
        .onOpenURL { ask.open($0) }
        // The link handed over at launch, once a launch, as `ContentView`
        // takes it.
        .task {
            guard let url = host.takeLaunchLink() else { return }
            ask.open(url)
        }
    }
}

/// The reminders added this launch, as the settings card's Reminders section
/// lists them: what a confirmed card did, where a host's own screen would
/// show it.
struct DemoReminderSection: View {
    let list: DemoReminderList

    var body: some View {
        Section {
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
        } header: {
            Text(verbatim: "Reminders")
        }
    }
}

// On the one host the previews share (`previewHost`), for its one seam.
#Preview {
    DemoAssistantView(ask: previewHost.assistantAsk(), host: previewHost)
}
