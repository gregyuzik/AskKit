#if os(macOS)

import AppKit
import SwiftUI
import Testing

@testable import AskUI

/// The panes beside iPhone Duo's fold stand where they are put, whatever
/// they hold: read off a render, one point to a pixel.
///
/// A screen 300 wide with the fold from 100 to 140: the leading pane black,
/// the conversation red and 180 wide, 20 more than the 159 its side has once
/// the hairline has its point. The fold is read in the panes' own space
/// (`AskScreen.body`), so a stack that grew to hold the conversation would be
/// centered by whatever holds it, and the reading would move what it reads:
/// `AskFoldPanes` has what that did on the Duo.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskFoldPanesTests {

    private let screen = ProposedViewSize(width: 300, height: 40)

    private func panes(_ arrangement: AskFoldArrangement) -> some View {
        AskFoldPanes(arrangement: arrangement, showsHairline: false) {
            Color.black
        } conversation: {
            Color.red.frame(width: 180)
        }
        .background(Color.white)
    }

    private func render(_ view: some View) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = screen
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    private enum Ink { case black, red, white }

    private func ink(in image: NSBitmapImageRep, at x: Int) -> Ink? {
        guard let colour = image.colorAt(x: x, y: 20)?.usingColorSpace(.sRGB) else { return nil }
        if colour.redComponent < 0.5 { return .black }
        return colour.greenComponent < 0.5 ? .red : .white
    }

    /// Two panes: the stack is the screen's width and no wider, the leading
    /// pane runs from the screen's edge to the fold, and the conversation
    /// starts past the fold and its hairline and runs over on the trailing
    /// side.
    @Test func aConversationWiderThanItsSideLeavesThePanesWhereTheyStand() throws {
        let image = try #require(render(panes(.panes(chats: 100, gap: 40))))
        #expect(image.pixelsWide == 300)
        #expect(ink(in: image, at: 0) == .black)
        #expect(ink(in: image, at: 99) == .black)
        #expect(ink(in: image, at: 100) == .white)
        #expect(ink(in: image, at: 140) == .white)
        #expect(ink(in: image, at: 141) == .red)
        #expect(ink(in: image, at: 299) == .red)
    }

    /// Clear of a bend on the trailing side, the conversation starts at its
    /// inset, and the stack is still the screen's width.
    @Test func aConversationWiderThanTheTrailingSideStartsAtItsInset() throws {
        let image = try #require(render(panes(.trailing(inset: 140))))
        #expect(image.pixelsWide == 300)
        #expect(ink(in: image, at: 139) == .white)
        #expect(ink(in: image, at: 140) == .red)
        #expect(ink(in: image, at: 299) == .red)
    }

    /// One pane, and a conversation narrower than the screen: it keeps to the
    /// leading edge, as it did.
    @Test func theWholeScreenKeepsItsConversationLeading() throws {
        let image = try #require(render(panes(.whole)))
        #expect(image.pixelsWide == 300)
        #expect(ink(in: image, at: 0) == .red)
        #expect(ink(in: image, at: 179) == .red)
        #expect(ink(in: image, at: 180) == .white)
    }
}

#endif
