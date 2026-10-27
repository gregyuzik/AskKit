# AskKit design research: OS 27 guidance and 2026 AI-chat practice

What Apple's Human Interface Guidelines, as revised on June 8, 2026, and the 2025–2026 research on chat
interfaces ask of a screen like Ask, and what AskKit does with each. §1 to §3 are the findings, §4 how
AskKit applies them. The full passages are in the sources, listed at the end. How the design works is
in [ARCHITECTURE.md](ARCHITECTURE.md).

## 1. Apple: what the HIG says

- **Separate the model from the experience.** "You may want to separate your model from your user
  experience so you can swap out the model for other models over time." That is AskKit's seam
  (`AskModelSeam`).
- **Hallucinations.** "Clearly communicate that AI-generated content may contain errors … Avoid
  requesting factual information unless you're confident the model has access to verified and
  up-to-date information." The grounding rule, that an answer with no retrieval behind it is never
  shown, is the strongest reading of this guideline, which is why it is a house rule and the default
  grounding policy, not a disclaimer. A domain whose answers needn't rest on the reader's data may keep
  answers nothing grounded (`AskGroundingPolicy.notRequired`), and each such answer records that
  nothing did (`AskAnswer.grounding`).
- **Non-AI fallback.** "Ensure a great experience even when generative features aren't available or
  people opt not to use them." The can't-serve screen with its reason is the minimum; a host's
  deterministic answers (`AskDomain.deterministicAnswer(for:)`), which need no model, are a real
  fallback.
- **Specific, reassuring feedback during generation.** "Instead of 'Processing…', say 'Finding
  substitutions for ingredients'." The wait row names the turn's real tool events ("Searching your
  records…"). The same paragraph endorses a "Writing…" label, and **AskKit has none on purpose**: the
  wait row is gone by the time the first words land, and the reveal's caret says the writing goes on
  ([ARCHITECTURE.md](ARCHITECTURE.md#the-thread-the-reveal-and-the-waves)). The caret already does the
  label's job.
- **Irreversible actions.** "Generally, ask for confirmation before performing a significant action on
  someone's behalf." An action tool proposes, and the reader's tap on a confirmation card commits
  (`AskProposal`).
- **Searching.** "In apps that use tab bars … search is a dedicated tab." A host that puts search in its
  library's own field and gives the tab to Ask has a defensible reading: one place to search, the field
  on the content it filters. Asking is a different verb from searching, so Ask stays a tab of its own,
  and the two meet where a search finds nothing, with an offer to ask instead
  (`AskConversationStore.prefill(_:scope:send:)`).
- **Apple Intelligence's visual grammar.** The multicolor shimmer border is the system's signature, Siri's
  and Writing Tools', and a third-party surface doesn't imitate it. The spectrum look's glass rod round
  the composer is the host's own colors, opt-in, and is the field's edge rather than a sign of the
  system at work: it stands still at rest, marking where to type, and while a turn is in flight its
  colors only drift slowly round it. With no spectrum there is none. The `apple.intelligence` symbol
  belongs on the first screen's disclosure and the settings card, **not on every message**. The host's
  own mark is the identity.

## 2. Research on chat UX (NN/g, 2025–2026)

- Users want "quick answers, not a conversation": "direct, scannable, and easy to expand." Suggestions
  are **buttons, not text**, updated through the conversation, and a declined one is removed.
  **Images, not links.** **Don't autoscroll users to the end of a response**: "users expect to start at
  the beginning of messages". AskKit follows a growing answer only for a reader already at its foot,
  and never pulls one who has scrolled away (§4 #1).
- "Half of all conversations contained a follow-up action": the datum the chips stand on. Use
  **standard icons with labels** (a magic wand confuses), name features plainly, and group controls by
  function.
- Multi-turn support needs follow-ups of different shapes (narrowing, deepening, broadening, relaxing),
  and an expansion "should meaningfully differ from initial responses". Two of the same shape is the
  failure §4 #5 addresses.

## 3. Practice in 2026 products

Plain prose, no assistant bubble, an honest wait and no pacing is the tool-first shape the survey
favors. Its **pitfall list** reads as a review checklist for any change here:

- fake typing that throttles a fast model; a missing stop; autoscroll that fights the reader; no
  persistent history; a disclaimer repeated on every message; bubbles that read as a casual messenger;
  **silent context truncation**; chips that can't be dismissed. "AI chat is a tool first and a
  conversation second."
- Every 2026 product (ChatGPT, Claude, Gemini, Perplexity, Siri 27) streams and has a stop, an edit on
  the user's message, regenerate, a persistent searchable history, and attachments. Perplexity made
  **citations the receipt**; Gemini and Siri show **cards** inside the answer; follow-up suggestions are
  Gemini's and Siri's convention, not ChatGPT's.
- **Shape of AI**'s pattern names are worth using in reviews: wayfinders (suggestions, nudges, follow
  up), governors (citations, controls, stream of thought, verification, action plan), trust builders
  (disclosure, footprints, caveat, consent) and identifiers (name, avatar, color, iconography,
  personality).

## 4. How AskKit applies it

| # | The finding | What AskKit does | Source |
|---|---|---|---|
| 1 | Never pull the reader down a streaming answer. | The follow keeps the foot in view only while the reader is at the foot, and "Jump to latest" shows otherwise. The new question lands at the foot rather than pinned to the top; why not the top is in ARCHITECTURE.md §6. | NN/g #7; Setproduct |
| 2 | Per-answer actions, and a visible acknowledgment when a re-ask replaces an answer. | Copy, Copy answer, Edit & Resend and Ask again on the question's menu and as VoiceOver actions, and "Another pick" leading the follow-ups where the answer's kind can be rerolled. A re-ask is a new turn below, so nothing is replaced. | HIG "refine or revert … acknowledge"; every 2026 product |
| 3 | Disclose what leaves the device, without a toggle. | The first screen carries the host's disclosure sentence (`AskBrand.disclosureSentence`) beside the `apple.intelligence` symbol, the settings card says where answers come from, and the tier caption names the tier answering. | HIG privacy and transparency |
| 4 | Attribution, never a percentage. | The evidence line ("From N items") and the domain's basis line under tiles, written from what the tools read. | HIG attribution and confidence; Perplexity's receipts |
| 5 | Follow-ups that cover the conversation's shapes. | `AskReply` asks for two of different shapes, one narrowing and one broadening, shown under the last answer only. A starter or coaching chip the reader asked or passed over doesn't come back in the thread. | NN/g's six types and guideline #4 |
| 6 | A persistent, searchable history. | The History button's list of past chats, titled by their first question, with search, swipe to delete, and a recap when an earlier chat goes on. | Siri 27; Setproduct's "no persistent history" |
| 7 | No silent context truncation. | A hairline, "Earlier in this chat is summarized", where a fresh session started with a recap. | Setproduct |
| 8 | Voluntary, low-emphasis feedback. | Thumbs under answers where diagnostics are on; a verdict on the newest saves its session's feedback attachment on the device, shared only by hand. | HIG feedback |
| 9 | Say what Ask can't do. | The host's scope caveat on the first screen (`AskBrand.scopeCaveat`), such as the demo's "Ask reads only what you own — it can't search the web, and it can be wrong." | HIG hallucinations and limitations; NN/g capability statements |
| 10 | Help a blocked request along. | Two coaching chips under a refused or ungrounded failure. | HIG "help people improve requests when blocked" |
| 11 | Attachments. | A photo in the composer, read only by Private Cloud Compute: when the next answer is on device, the photo's chip says so, and VoiceOver hears when an answer read only the words. | Siri 27; Shape of AI "attachments" |
| 12 | Voice. | The keyboard's dictation. A microphone in the composer waits until readers expect one. | NN/g #10; Siri 27 |
| 13 | Siri parity. | `AskEngine.answerOnce(_:)` answers a one-shot question, such as an intent's, outside the thread; the snippet is the host's, under 400 pt, with the visual carrying the meaning. | HIG Snippets |
| 14 | Confirm an action before taking it. | `AskProposal`: the model proposes, the reader confirms, the app performs. | HIG irreversible actions |
| 15 | Glass that holds at the extremes. | Real glass only, never a `Material` imitation, and nothing meant only by translucency; text on glass is held to a contrast bar, and Increase Contrast takes it to primary. | iOS 27's Liquid Glass |
| 16 | Labels on controls, conventional icons only. | Done, New Chat and Ask again are named; there is no wand. | NN/g prompt controls |

Not taken from the research: an assistant bubble or avatar beside every answer (the tool-first
finding); a visible "thinking" transcript for Private Cloud Compute's reasoning, which Apple keeps in
intermediate segments the app never receives as prose, so a collapsible box would show nothing honest;
a model picker (one policy, one tier caption); per-message disclaimers; and any imitation of the Apple
Intelligence shimmer, which the spectrum look's glass rod, still at rest and in the host's colors, is
not (§1).

## Sources

- Apple HIG, *Generative AI*: developer.apple.com/design/human-interface-guidelines/generative-ai
  (revised June 8, 2026)
- Apple HIG, *Machine learning*: …/machine-learning (explicit and implicit feedback, calibration,
  mistakes, corrections, multiple options, confidence, attribution, limitations)
- Apple HIG, *Snippets*: …/snippets (new, June 8, 2026)
- Apple HIG, *Searching*: …/searching (revised June 8, 2026)
- Apple's WWDC26 Apple Intelligence guide: developer.apple.com/wwdc26/guides/apple-intelligence/
- MacRumors, *How Liquid Glass Is Changing in iOS 27* (June 10, 2026) and *iOS 27 Getting Major Siri
  Redesign With Chat Interface and Dedicated App* (May 12, 2026)
- Nielsen Norman Group: *10 Guidelines for Designing Your Site's AI Chatbots* (April 2026); *Prompt
  Controls in GenAI Chatbots* (September 2025); *The 6 Types of Conversations with Generative AI*
  (September 2025)
- Setproduct, *Designing AI chat interfaces: Anatomy, patterns, pitfalls* (2026)
- IntuitionLabs, *Comparing Conversational AI Tool User Interfaces* (2025)
- The Shape of AI pattern library: shapeof.ai
- Art of Styleframe, *Designing for Apple Intelligence: AI UI Patterns 2026*, used only for its
  description of the system shimmer, which AskKit doesn't imitate
- Microsoft's *Guidelines for Human-AI Interaction* (HAX) and Google's *People + AI Guidebook*, the older
  sources behind the NN/g and Apple guidance above, consulted for framing only
