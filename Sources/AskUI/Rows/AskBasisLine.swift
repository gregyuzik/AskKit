#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// Why an answer chose what it shows, in one factual line between the tiles and
/// the evidence line: "Your highest-rated jazz record".
///
/// **The domain's words, drawn quietly.** The sentence comes from
/// `AskDomain.basis(for:)`, written from the rows' own fields, and AskUI adds
/// none of its own, so a basis is never a model's claim restated, and never a
/// sentiment or a percentage. De-emphasized like the evidence line under it: it
/// is the reason for the pick, not a second answer.
struct AskBasisLine: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .askDeemphasizedText()
            // Wraps: a basis names a row, and a row's title can be long in any
            // language.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AskAccessibility.basis)
    }
}

#endif
