import AskCore
import Foundation
import FoundationModels

// MARK: - The reminders

/// A reminder the reader confirmed: what to remember, and when, in the words
/// the card showed them.
///
/// The proposal's payload, so it is the intent the card offered and nothing
/// else (`AskProposal.payload`). `id` is the proposal's own, so a tap that
/// reaches `perform` twice adds it once.
nonisolated struct DemoReminder: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let when: String?
}

/// The reminders confirmed this launch, which the assistant's Reminders
/// sheet lists.
///
/// **In memory, on purpose.** No EventKit and no permission prompt: the
/// demo shows the shape of an action the model proposes and the reader
/// confirms, and a real calendar would put a system alert in front of every
/// UI test. A host's `perform` writes to its own store.
@MainActor
@Observable
final class DemoReminderList {
    private(set) var reminders: [DemoReminder] = []

    /// Adds a reminder once, however many times its card is confirmed.
    func add(_ reminder: DemoReminder) {
        guard !reminders.contains(where: { $0.id == reminder.id }) else { return }
        reminders.append(reminder)
    }
}

// MARK: - The converter

/// The converter's arguments, which the model fills in.
///
/// **The units are a list the model chooses from** (`.anyOf`), not words it
/// writes: what the converter can't resolve, the model never asks for.
@Generable
nonisolated struct DemoConversionArguments: Sendable {
    @Guide(description: "The amount to convert.")
    var amount: Double
    @Guide(description: "The unit the amount is in.", .anyOf(DemoConversion.unitNames))
    var from: String
    @Guide(description: "The unit to convert it to, of the same kind: a length, a weight, a volume or a temperature.", .anyOf(DemoConversion.unitNames))
    var to: String
}

/// The arithmetic behind `convert_units`, shared by the tool and the scripted
/// answer that stands in for it.
nonisolated enum DemoConversion {
    /// Each unit by the name the model picks, with the kind it converts within.
    private static let units: [(name: String, unit: Dimension, kind: String)] = [
        ("millimeters", UnitLength.millimeters, "length"), ("centimeters", UnitLength.centimeters, "length"),
        ("meters", UnitLength.meters, "length"), ("kilometers", UnitLength.kilometers, "length"),
        ("inches", UnitLength.inches, "length"), ("feet", UnitLength.feet, "length"),
        ("yards", UnitLength.yards, "length"), ("miles", UnitLength.miles, "length"),
        ("grams", UnitMass.grams, "mass"), ("kilograms", UnitMass.kilograms, "mass"),
        ("ounces", UnitMass.ounces, "mass"), ("pounds", UnitMass.pounds, "mass"),
        ("milliliters", UnitVolume.milliliters, "volume"), ("liters", UnitVolume.liters, "volume"),
        ("cups", UnitVolume.cups, "volume"), ("gallons", UnitVolume.gallons, "volume"),
        ("celsius", UnitTemperature.celsius, "temperature"), ("fahrenheit", UnitTemperature.fahrenheit, "temperature")
    ]

    /// The names `DemoConversionArguments` offers the model.
    static var unitNames: [String] { units.map(\.name) }

    /// One line for the model: "10 mi = 16.0934 km", or why there is none.
    ///
    /// **The model's words come back clamped.** The `.anyOf` list keeps them
    /// to the table's names, and a session that didn't constrain them could
    /// write anything, so a name the table doesn't hold goes back through
    /// `AskPrompt.clamp`, like any field, in no fence of the tool's own.
    static func line(_ arguments: DemoConversionArguments) -> String {
        let from = units.first { $0.name == arguments.from.lowercased() }
        let to = units.first { $0.name == arguments.to.lowercased() }
        guard let from, let to else {
            let asked = "\(AskPrompt.clamp(arguments.from, AskPrompt.shortClamp)) to \(AskPrompt.clamp(arguments.to, AskPrompt.shortClamp))"
            return "No conversion from \(asked)."
        }
        guard from.kind == to.kind else { return "No conversion from a \(from.kind) to a \(to.kind)." }
        let result = Measurement(value: arguments.amount, unit: from.unit).converted(to: to.unit).value
        return String(format: "%g %@ = %g %@", arguments.amount, from.unit.symbol, result, to.unit.symbol)
    }
}

/// `convert_units`: a tool that reads none of the reader's data and returns
/// text. The call grounds the turn, and it records no rows.
nonisolated struct DemoConvertTool: Tool {
    let name = "convert_units"
    let description = "Convert an amount from one unit to another: lengths, weights, volumes and temperatures. Returns one line, such as 10 mi = 16.0934 km."

    typealias Arguments = DemoConversionArguments

    let context: AskToolContext<AskNoRow>

    /// `@concurrent`, as every tool body in this main-actor target is
    /// (`DemoSearchTool.call(arguments:)` says why).
    @concurrent func call(arguments: DemoConversionArguments) async throws -> String {
        await context.withToolCall { _ in
            (DemoConversion.line(arguments), report: nil)
        }
    }
}

// MARK: - The reminder

/// What a reminder is proposed with.
@Generable
nonisolated struct DemoReminderArguments: Sendable {
    @Guide(description: "What to remind the reader of, in a few words, as they said it: \"water the plants\".")
    var what: String
    @Guide(description: "When, as the reader said it: \"at 6 PM\", \"tomorrow morning\". Omit it when they named no time.")
    var when: String?
}

/// `propose_reminder`: a proposing tool. It records an `AskProposal` and
/// returns `AskProposal.modelReceipt`; nothing is added until the reader
/// confirms the card, which reaches `DemoAssistantDomain.perform(_:)`.
///
/// Offered only in a conversation (`DemoAssistantDomain.makeTools(_:)`): a
/// standalone turn has no card to confirm on.
nonisolated struct DemoReminderTool: Tool {
    let name = "propose_reminder"
    let description = "Offer the reader a reminder, which they confirm on a card under your answer. Call it whenever they ask to be reminded of something."

    typealias Arguments = DemoReminderArguments

    let context: AskToolContext<AskNoRow>

    @concurrent func call(arguments: DemoReminderArguments) async throws -> String {
        await context.withToolCall { collector in
            guard let reminder = DemoReminder(arguments) else {
                return ("Nothing to remind about: ask the reader what the reminder should say.", report: nil)
            }
            guard await collector.record(proposal: DemoAssistantDomain.proposal(for: reminder)) else {
                return ("The reminder couldn't be offered.", report: nil)
            }
            return (AskProposal.modelReceipt, report: nil)
        }
    }
}

nonisolated extension DemoReminder {
    /// The reminder the model's arguments describe, or nil when they name
    /// nothing to remember.
    ///
    /// **The card shows what will be kept, as it will be kept.** A
    /// reminder has no row of the app's to be written from, so its words are
    /// the model's reading of the request: cut to a line and flattened
    /// (`AskPrompt.clamp`), and shown on the card verbatim, so the reader
    /// confirms the reminder itself rather than a description of it.
    init?(_ arguments: DemoReminderArguments) {
        let text = AskPrompt.clamp(arguments.what, AskPrompt.shortClamp)
        guard !text.isEmpty else { return nil }
        let when = arguments.when.map { AskPrompt.clamp($0, AskPrompt.shortClamp) }
        self.init(id: UUID(), text: text, when: when?.isEmpty == false ? when : nil)
    }
}

// MARK: - The domain

/// An assistant over no data of the app's: a domain without rows.
///
/// It names neither associated type, so its rows are `AskNoRow` and its
/// search arguments `AskNoSearchArguments`, and it leaves `overview()` and
/// `search(_:context:)` to their defaults. It answers from the model alone,
/// converts with one tool and proposes reminders with another: what a host
/// with tools and actions, and no library, writes. `-askAssistant` shows it
/// in place of the library (`DemoDomain`).
///
/// Its copy is English literals, as `DemoDomain`'s is: the demo carries no
/// catalog.
nonisolated struct DemoAssistantDomain: AskDomain {
    /// Where confirmed reminders go. Made on the main actor and handed in, so
    /// the screen that lists them and `perform` share one list.
    let reminders: DemoReminderList

    /// `.notRequired`: an answer no tool grounded is kept. Most of what an
    /// assistant is asked ("a name for a houseplant", "thanks") needs no
    /// tool, and under `.retrieval` or `.toolCall` every such answer would
    /// fail with coaching. What keeps it honest is the line under it, "Not
    /// from this app's data" (`evidence(for:)`).
    var grounding: AskGroundingPolicy { .notRequired }

    /// `.prose`: the answer and its follow-ups alone. The assistant has no
    /// rows to show as tiles, so its model spends none of the on-device
    /// window on a question kind or a tile choice: the prose schema is 192
    /// tokens where the full one is 704.
    var replyShape: AskReplyShape { .prose }

    /// `.perLaunch` under the reset launch argument, `.thread` otherwise, as
    /// `DemoDomain.persistence` is.
    var persistence: AskPersistence {
        CommandLine.arguments.contains(DemoLaunchArgument.resetThread) ? .perLaunch : .thread
    }

    /// The ready first screen whatever the overview counts, since there is
    /// nothing to own, and, under `-askScriptedAnswer`, starters that answer
    /// without a model, as `DemoDomain.firstScreenPolicy` says.
    var firstScreenPolicy: AskFirstScreenPolicy {
        AskFirstScreenPolicy(answersWithoutModel: implementsDeterministicAnswer, needsOwnedRows: false)
    }

    /// The thread is kept in a folder of its own: a thread the library wrote
    /// holds `DemoRow`s, which an `AskNoRow` thread can't read, and would be
    /// set aside as unreadable.
    var brand: AskBrand {
        AskBrand(
            title: "Ask the Assistant",
            shortLabel: "Ask",
            appDirectory: "AskKitDemoAssistant",
            logSubsystem: "com.example.askkitdemo",
            help: "Ask anything",
            firstScreenHeadline: "Ask anything",
            firstScreenSentence: "Convert a measurement, set a reminder, or ask a question. This assistant has no data of its own.",
            disclosureSentence: "Questions are answered on this device.",
            scopeCaveat: "Answers come from the model and two small tools, and they can be wrong."
        )
    }

    /// The reminder only in a conversation, where there is a card to confirm
    /// it on (`AskProposal`).
    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] {
        let convert = DemoConvertTool(context: context)
        return context.isConversation ? [convert, DemoReminderTool(context: context)] : [convert]
    }

    /// Three sentences, short as house rule 3 asks, naming only the tools the
    /// session holds. The units live in the converter's `@Guide`s.
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        var text = """
            You are a helpful assistant in a demo app. Answer in two or three sentences of plain prose, with no headings and no lists.
            To convert an amount between units, call convert_units and give its result.
            """
        if isConversation { text += "\nWhen the reader asks to be reminded of something, call propose_reminder." }
        if let answerLanguage { text += "\nWrite the answer in \(answerLanguage)." }
        return text
    }

    /// Byte-stable, for the reason `DemoDomain.promptPrefix` gives.
    var promptPrefix: String { "Answer a question asked of an assistant.\n" }

    /// One of each thing it does: a conversion, a reminder and a question
    /// for the model alone.
    func starters(overview: AskOverview, window: Int) -> [AskStarter] {
        [
            AskStarter(id: "convert", text: "How many kilometers is 10 miles?"),
            AskStarter(id: "remind", text: "Remind me to water the plants at 6 PM"),
            AskStarter(id: "ask", text: "What's a good name for a houseplant?")
        ]
    }

    /// The line under an answer one of its tools grounded is the domain's
    /// own: AskKit's count reads rows, and a conversion or a reminder reads
    /// none, so under `.counted` that answer would have no line at all. An
    /// answer nothing grounded keeps the default, so AskKit says it isn't
    /// from the app's data.
    func evidence(for answer: AskAnswer<AskNoRow>) -> AskEvidencePresentation {
        answer.grounding == .toolCall ? .line(DemoAssistantWords.fromItsTools) : .counted
    }

    /// What the card offers, in the app's words around the reminder's own.
    static func proposal(for reminder: DemoReminder) -> AskProposal {
        AskProposal(
            id: reminder.id,
            title: "Remind you to \(reminder.text)",
            detail: (reminder.when.map { "\($0.prefix(1).uppercased() + $0.dropFirst()). " } ?? "")
                + "Kept in this demo until it quits.",
            actionLabel: "Add Reminder",
            systemImage: "bell",
            payload: (try? JSONEncoder().encode(reminder)) ?? Data()
        )
    }

    /// Adds the reminder the card offered, once, and says so in the app's
    /// words.
    func perform(_ proposal: AskProposal) async throws -> String? {
        guard let reminder = proposal.payload(as: DemoReminder.self) else {
            throw AskProposalFailure(line: "That reminder couldn't be read.")
        }
        await reminders.add(reminder)
        return "Reminder added: \(reminder.text)" + (reminder.when.map { ", \($0)." } ?? ".")
    }

    // MARK: Scripted answers

    /// A fixed answer under `-askScriptedAnswer`, so the UI smoke suite can
    /// assert on the card and the evidence line without a model.
    var implementsDeterministicAnswer: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.scriptedAnswer)
    }

    /// Each scripted answer records the grounding a turn the model wrote
    /// would, so the line under it reads as it would then: `.toolCall` where
    /// a tool would have run, `AskGrounding.nothing` where none would. An answer
    /// the domain gives itself otherwise records none (`AskAnswer.grounding`).
    ///
    /// The English phrases matched here choose which fixture stands in for
    /// the model, before anything is generated, as `DemoDomain`'s do.
    func deterministicAnswer(for question: String) async -> AskAnswer<AskNoRow>? {
        guard implementsDeterministicAnswer else { return nil }
        if question.localizedCaseInsensitiveContains("remind") {
            let reminder = DemoReminder(id: UUID(), text: "water the plants", when: "at 6 PM")
            return AskAnswer(
                text: "I can remind you to water the plants at 6 PM. Add it with the card below.",
                questionKind: AskQuestionKind.lookup,
                proposal: Self.proposal(for: reminder),
                grounding: .toolCall
            )
        }
        if question.localizedCaseInsensitiveContains("miles") {
            let line = DemoConversion.line(DemoConversionArguments(amount: 10, from: "miles", to: "kilometers"))
            return AskAnswer(
                text: "Ten miles is about 16.09 kilometers (\(line)).",
                questionKind: AskQuestionKind.lookup,
                grounding: .toolCall
            )
        }
        return AskAnswer(
            text: "A scripted answer, standing in for one the model would write from what it knows.",
            grounding: AskGrounding.nothing
        )
    }
}

// MARK: - The eval

extension DemoAssistantDomain {
    /// What "Run Ask eval on this device" puts through the real engine for
    /// the assistant: whether each answer was grounded, by a tool, or not,
    /// and the card where one is asked for. Five, as `DemoDomain.scenarios`
    /// says.
    static let scenarios: [AskScenario] = [
        AskScenario(id: "miles", question: "How many kilometers is 10 miles?", expectsGrounding: true),
        AskScenario(id: "fahrenheit", question: "What is 100 degrees Fahrenheit in Celsius?", expectsGrounding: true),
        AskScenario(id: "remind", question: "Remind me to water the plants at 6 PM", expectsProposal: true, expectsGrounding: true),
        AskScenario(id: "houseplant", question: "What's a good name for a houseplant?", expectsGrounding: false),
        AskScenario(id: "thanks", question: "Thanks!", expectsGrounding: false)
    ]
}
