import SwiftUI

/// The switch between the demo's two domains, "Your Things" and "Assistant"
/// (`DemoDomainChoice`), the one on screen checked. Where it is differs by
/// platform, each the closest native place to the title the domain is named
/// by.
///
/// **iOS and iPadOS: a menu on the bar's leading side.** Not the title's menu
/// (`toolbarTitleMenu`), which is where Apple puts a choice of what a screen
/// shows, because under a subtitle it is too small a target: measured on an
/// iPhone 18 Pro (iOS 27.2) with the tier caption under the title, the
/// title's menu took a tap only on the title's own line, 18 pt tall (y 68 to
/// 85 of a bar from 62 to 116), and Apple's audit fails it ("Hit area is too
/// small"), where every target on the screen is 44 pt. The bar item is the
/// bar's own size. It draws the symbol of the domain on screen, and
/// VoiceOver reads its name. It is there under a tab bar at the top too, on
/// an iPad at regular width, where no title is drawn to hang a menu on
/// (`AskTierCaption`); a bar draws it as its symbol alone there as well,
/// whatever label style it is given.
///
/// **It steps aside while the keyboard is up, and Done takes its place.**
/// `AskScreen` adds Done to the bar's leading side while the reader types,
/// and with the switch there too the side holds three items: on an iPhone
/// 18 Pro with New Chat and the chats opposite, the library's title and the
/// tier caption under it left the bar altogether, and the assistant's,
/// beside Reminders as well, came down to "…" and "O…". So the switch is the
/// last of the demo's host items, and goes while the software keyboard is
/// up: Done lands where it stood, nothing else moves, and the bar while
/// typing is the one it was before the switch. The signal is the keyboard's
/// own notifications, since Done keys on the composer's focus, which
/// `AskScreen` keeps to itself, so where no keyboard comes up for the focus,
/// the switch stays beside Done. Done or a send puts the keyboard away, and
/// the switch comes back.
///
/// **visionOS: the title's menu.** visionOS draws a title with a menu as a
/// pill of its own above the window, the app's icon, the title and a
/// chevron, where the title otherwise stands in the window's bar, so its
/// target isn't a line under a subtitle (`AskTierCaption` puts the tier in
/// the bar there, where it leads the bar). Seen on the visionOS 27.2
/// simulator; no tool here drives a visionOS simulator's input, so the menu
/// opening from the pill is SwiftUI's, unwalked.
///
/// **macOS: a pop-up in the toolbar and the View menu.** A Mac window's title
/// takes no title menu here: SwiftUI gives the title a menu only for a
/// document (`navigationDocument`), and the demo's window shows none.
/// Checked on the macOS 27.2 demo: no view in the title bar holds a menu, and
/// a click on the title opens nothing. So the picker is a pop-up button at the
/// toolbar's leading edge, ahead of the title, naming the domain on screen,
/// and the View menu has the two with ⌘1 and ⌘2 (`DemoDomainCommands`).
///
/// **A switch mid-turn keeps the turn.** Each domain's Ask lives as long as
/// the app (`DemoHost`), so a turn in flight goes on in its own thread, and
/// the answer is there when the reader switches back, as it would be over a
/// tab switched away from.
struct DemoDomainSwitch: ViewModifier {
    let host: DemoHost

    #if os(iOS)
    /// Whether the software keyboard is up, from its own notifications.
    @State private var keyboardIsUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    DemoDomainPicker(host: host)
                        .pickerStyle(.menu)
                        // The name as well as the symbol: a toolbar draws a
                        // label as its icon alone, and a pop-up of a symbol
                        // doesn't say what it switches.
                        .labelStyle(.titleAndIcon)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier(DemoAccessibility.domainMenu)
                }
            }
        #elseif os(visionOS)
        content
            .toolbarTitleMenu {
                DemoDomainPicker(host: host)
                    .pickerStyle(.inline)
            }
        #else
        content
            .toolbar {
                if !keyboardIsUp {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            DemoDomainPicker(host: host)
                                .pickerStyle(.inline)
                        } label: {
                            Label {
                                Text(verbatim: host.choice.name)
                            } icon: {
                                Image(systemName: host.choice.systemImage)
                            }
                        }
                        // Monochrome, as the demo's other bar items are.
                        .symbolRenderingMode(.monochrome)
                        .accessibilityIdentifier(DemoAccessibility.domainMenu)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                setKeyboardIsUp(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                setKeyboardIsUp(false)
            }
        #endif
    }
}

#if os(iOS)
extension DemoDomainSwitch {
    /// On the curve Done comes and goes on in `AskScreen`, so the two trade
    /// places in one movement.
    private func setKeyboardIsUp(_ isUp: Bool) {
        guard isUp != keyboardIsUp else { return }
        withAnimation(reduceMotion ? .none : .snappy) { keyboardIsUp = isUp }
    }
}
#endif

/// The two domains as a picker: a menu's items, with the one on screen
/// checked, or on the Mac a pop-up naming it.
struct DemoDomainPicker: View {
    @Bindable var host: DemoHost

    var body: some View {
        Picker(selection: $host.choice) {
            ForEach(DemoDomainChoice.allCases, id: \.self) { choice in
                Label {
                    Text(verbatim: choice.name)
                } icon: {
                    Image(systemName: choice.systemImage)
                }
                .tag(choice)
            }
        } label: {
            Text(verbatim: "Ask About")
        }
    }
}

#if os(macOS)
/// The switch in the Mac's View menu, at its top, where a Mac app switches
/// what its window shows (Finder's views, Xcode's navigators): ⌘1 and ⌘2, in
/// the domains' order, the one on screen checked. The toolbar's pop-up has
/// the same choices (`DemoDomainSwitch`).
struct DemoDomainCommands: Commands {
    let host: DemoHost

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(Array(DemoDomainChoice.allCases.enumerated()), id: \.element) { index, choice in
                Toggle(isOn: isOn(choice)) {
                    Text(verbatim: choice.name)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
        }
    }

    /// A checkmark on the domain on screen. Choosing the one already on
    /// screen leaves it there, rather than unchecking it.
    private func isOn(_ choice: DemoDomainChoice) -> Binding<Bool> {
        Binding {
            host.choice == choice
        } set: { isOn in
            if isOn { host.show(choice) }
        }
    }
}
#endif
