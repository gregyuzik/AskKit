# Security

## Reporting a vulnerability

Report it privately, with **Report a vulnerability** on the repository's Security tab (GitHub's private
vulnerability reporting), rather than in an issue. A report that shows the problem in the demo app, or
in a test, is the quickest to act on.

## Supported versions

AskKit is at 0.x, and fixes land in the newest minor version only.

| Version | Supported |
| --- | --- |
| 0.2 | Yes |
| 0.1 | No |

## In scope

- **Text the host didn't write, speaking as the host.** AskKit fences what it composes: the reader's
  question, the recap of earlier turns, and the rows its grounded retry reads. It redacts its own fence
  tags inside them in any spelling that compatibility decomposition (NFKD) maps to the tag once marks
  are dropped, and it strips links and images from the rendered answer. A question, a title or a row
  that escapes its fence in such a spelling is a vulnerability, and so is an answer that renders a
  link. `docs/ARCHITECTURE.md` lists the fences under "Prompts and fences", and its house rule 3 says
  why.
- **Words sent that the reader didn't see.** An Ask link's question and a follow-up chip lose what draws
  nothing (tag characters, the other invisible format characters and bidi controls) before the reader
  sees them, so what is sent is what was shown. Text that reaches the model from either without showing
  in the composer or on the chip is a vulnerability.
- **What AskKit keeps on disk.** The thread, the earlier chats and the feedback attachments live in the
  app's Application Support folder. They're written atomically, with complete file protection everywhere
  except macOS, where that option fails the write, and they're excluded from backup. Anything that
  weakens that is in scope.

## Out of scope

- **What the model says.** An answer can be wrong, and Apple's guardrails decide what the model refuses.
  A wrong answer is a bug to report in an issue, unless text the host didn't write steered it.
- **What a host's own tools return.** A tool clamps each field with `AskPrompt.clamp` and returns its
  lines bare, and a field it leaves unclamped is the host's to fix. A gap in `clamp` or in the fence
  sanitizer is in scope.
- **Spellings outside the sanitizer's reading,** such as a tag in letters of another script that only
  look Latin, which normalize to no ASCII.
- **Apple's frameworks and Private Cloud Compute.** Report those to Apple.
