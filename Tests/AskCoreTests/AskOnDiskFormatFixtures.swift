/// The forms `AskOnDiskFormatTests` pins, as a build of AskKit wrote them.
///
/// JSON kept in Swift rather than in `.json` files beside the tests: a file a
/// target doesn't declare as a resource is one SwiftPM warns about. Change one
/// only with the form on disk, and only with a decoder that still reads what
/// it held before.
nonisolated enum AskOnDiskFormatFixtures {
    /// `ask-thread.json` holding three turns, and a filing under `threads/`
    /// holding the same: one answered, one failed, one handed to the app.
    static let thread = #"""
    [
      {
        "answer": {
          "basis": "Both came out in 1969.",
          "followUps": ["Which is on vinyl?"],
          "grounding": "tool call",
          "isTruncated": false,
          "matches": [
            {"displayTitle": "Abbey Road", "id": "abbey-road"},
            {"displayTitle": "Let It Be", "id": "let-it-be"}
          ],
          "payload": "eyJzaGVsZiI6Mn0=",
          "proposal": {
            "actionLabel": "Mark as lent",
            "detail": "To Sam, until Friday",
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "kind": "perform",
            "payload": "eyJpZCI6ImFiYmV5LXJvYWQifQ==",
            "systemImage": "arrow.up.forward.circle",
            "title": "Mark Abbey Road as lent"
          },
          "questionKind": "which",
          "text": "Two: Abbey Road and Let It Be.",
          "tiles": [
            {"displayTitle": "Abbey Road", "id": "abbey-road"}
          ]
        },
        "answerSawPhoto": true,
        "askedAt": 783000000.25,
        "failureIsRetryable": false,
        "feedback": "positive",
        "photo": {"label": "A shelf of records", "reference": "photo-1"},
        "proposalOutcome": {"confirmed": {"_0": "Marked Abbey Road as lent."}},
        "question": "Which of my records are from 1969?",
        "stopped": false,
        "summarizedBefore": true,
        "text": "Two: Abbey Road and Let It Be.",
        "tier": "privateCloud"
      },
      {
        "answerSawPhoto": false,
        "askedAt": 783000060.5,
        "failure": {"quotaReached": {"resetDate": 783086400}},
        "failureIsRetryable": true,
        "failureMessage": "You've reached today's limit.",
        "question": "And the oldest?",
        "stopped": false,
        "summarizedBefore": false,
        "text": "The oldest is",
        "tier": "onDevice"
      },
      {
        "answer": {
          "followUps": [],
          "isTruncated": false,
          "matches": [
            {"displayTitle": "Let It Be", "id": "let-it-be"}
          ],
          "proposal": {
            "actionLabel": "Open",
            "id": "0E984725-C51C-4BF4-9960-E1C80E27ABA0",
            "kind": "handOff",
            "payload": "",
            "title": "Add a note to Let It Be"
          },
          "text": "Open it to add one.",
          "tiles": []
        },
        "answerSawPhoto": false,
        "askedAt": 783000120,
        "failureIsRetryable": false,
        "feedback": "negative",
        "proposalOutcome": {"handedOff": {"_0": "Opened in the app."}},
        "question": "Can I add a note to Let It Be?",
        "stopped": false,
        "summarizedBefore": false,
        "text": "Open it to add one.",
        "tier": "privateCloud"
      }
    ]
    """#

    /// `threads/index.json`: the chats filed, newest first, and those whose
    /// deletion hasn't taken yet.
    static let index = #"""
    {
      "deleted": ["F1E2D3C4-B5A6-4978-8695-A4B3C2D1E0F9"],
      "threads": [
        {
          "id": "8D7C6B5A-4E3F-4A1B-9C2D-0E1F2A3B4C5D",
          "startedAt": 783000000.25,
          "title": "Which of my records are from 1969?",
          "turnCount": 3,
          "updatedAt": 783000120
        },
        {
          "id": "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D",
          "title": "What do I own?",
          "turnCount": 1,
          "updatedAt": 782000000
        }
      ]
    }
    """#

    /// Every `AskError`, as a turn's `failure` holds it.
    static let failures = #"""
    [
      {"modelUnavailable": {"_0": "offline"}},
      {"couldNotAnswer": {}},
      {"ungrounded": {}},
      {"refused": {}},
      {"privateCloudUnreachable": {}},
      {"contextTooLarge": {}},
      {"photosNotSupported": {}},
      {"quotaReached": {"resetDate": 783086400}},
      {"quotaReached": {}},
      {"model": {"tag": "offline"}},
      {"stopped": {}}
    ]
    """#

    /// A thread an earlier build wrote, with none of the fields added since:
    /// read only, as installs still hold it.
    static let olderThread = #"""
    [
      {
        "answer": {
          "matches": [{"displayTitle": "Rumours", "id": "rumours"}],
          "proposal": {
            "actionLabel": "Mark as lent",
            "id": "3B2A1C0D-9E8F-4A7B-8C6D-5E4F3A2B1C0D",
            "title": "Mark Rumours as lent"
          },
          "text": "Rumours and Abbey Road."
        },
        "question": "Which records do I own?",
        "text": "Rumours and Abbey Road.",
        "tier": "onDevice"
      },
      {
        "failureMessage": "Couldn't answer that.",
        "question": "And the oldest?"
      }
    ]
    """#

    /// `threads/index.json` as an earlier build wrote it, with no deletions
    /// and summaries without a first turn's date or a count of turns: read
    /// only, as installs still hold it.
    static let olderIndex = #"""
    {
      "threads": [
        {"id": "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D", "title": "What do I own?", "updatedAt": 782000000}
      ]
    }
    """#

    /// Every `AskUnavailability`, as a turn's `failure` holds it.
    static let unavailable = #"""
    [
      {"modelUnavailable": {"_0": "appleIntelligenceOff"}},
      {"modelUnavailable": {"_0": "deviceNotEligible"}},
      {"modelUnavailable": {"_0": "modelNotReady"}},
      {"modelUnavailable": {"_0": "systemNotReady"}},
      {"modelUnavailable": {"_0": "languageNotSupported"}},
      {"modelUnavailable": {"_0": "notEntitled"}},
      {"modelUnavailable": {"_0": "offline"}},
      {"modelUnavailable": {"_0": "unknown"}}
    ]
    """#

    /// Every `AskProposalOutcome`, as a turn's `proposalOutcome` holds it.
    static let outcomes = #"""
    [
      {"confirmed": {"_0": "Marked Abbey Road as lent."}},
      {"confirmed": {}},
      {"handedOff": {"_0": "Opened in the app."}},
      {"handedOff": {}},
      {"declined": {}},
      {"failed": {"_0": "The library couldn't be reached."}},
      {"failed": {}},
      {"performing": {}}
    ]
    """#

    /// A turn whose proposal the reader confirmed and whose perform hadn't
    /// returned when it was written: an answer, its card, and the outcome a
    /// build before `performing` existed has no case for.
    static let proposalInFlight = #"""
    [
      {
        "question": "Can I lend Abbey Road to Sam?",
        "text": "Abbey Road is on your shelf.",
        "answer": {
          "text": "Abbey Road is on your shelf.",
          "matches": [],
          "tiles": [],
          "followUps": [],
          "isTruncated": false,
          "proposal": {
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "kind": "perform",
            "title": "Mark Abbey Road as lent",
            "actionLabel": "Mark as lent",
            "payload": ""
          }
        },
        "failureIsRetryable": false,
        "stopped": false,
        "tier": "privateCloud",
        "askedAt": 783000300.5,
        "summarizedBefore": false,
        "proposalOutcome": {"performing": {}},
        "answerSawPhoto": false
      }
    ]
    """#

    /// Every `AskGrounding`, as an answer's `grounding` holds it.
    static let groundings = #"""
    ["tool call", "app retrieved", "follow-up", "none"]
    """#
}
