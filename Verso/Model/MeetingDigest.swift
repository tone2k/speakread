import Foundation
import Observation
import FoundationModels

/// What a meeting came to: the parts a person needs, nothing else.
struct MeetingDigest: Codable, Hashable {
    struct Action: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var owner: String
        var task: String
        var due: String
    }

    var title: String
    var summary: String
    var participants: [String]
    var topics: [String]
    var decisions: [String]
    var actions: [Action]
    var questions: [String]
    var generatedAt: Date

    /// Plain Markdown for sharing.
    var markdown: String {
        var out = "# \(title)\n\n\(summary)\n"
        func section(_ name: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            out += "\n## \(name)\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        section("Decisions", decisions)
        if !actions.isEmpty {
            out += "\n## Actions\n" + actions.map { a in
                var line = "- \(a.task)"
                if !a.owner.isEmpty, a.owner.lowercased() != "unassigned" { line += " · \(a.owner)" }
                if !a.due.isEmpty, a.due.lowercased() != "none" { line += " · \(a.due)" }
                return line
            }.joined(separator: "\n") + "\n"
        }
        section("Open questions", questions)
        section("Topics", topics)
        section("Participants", participants)
        return out
    }
}

/// What kind of recording this is. Only meetings get a digest on their own;
/// anything can be digested by hand.
enum RecordingKind: String, Codable {
    case meeting, lecture, interview, memo, conversation, other

    var label: String { rawValue.uppercased() }
}

// MARK: - Guided generation (Apple's on-device model)

@Generable
enum RecordingKindGuess: String {
    case meeting, lecture, interview, memo, conversation, other
}

@Generable
struct KindDraft {
    @Guide(description: "The kind of recording. A meeting has several people deciding or planning things together.")
    var kind: RecordingKindGuess
    @Guide(description: "How sure you are, from 0 to 100.")
    var confidence: Int
}

@Generable
struct ActionDraft {
    @Guide(description: "Who is responsible, as named in the transcript, or 'unassigned'.")
    var owner: String
    @Guide(description: "The thing to do, as one short imperative sentence.")
    var task: String
    @Guide(description: "When it is due if the transcript says, otherwise 'none'.")
    var due: String
}

@Generable
struct DigestDraft {
    @Guide(description: "A title for the meeting in at most eight words.")
    var title: String
    @Guide(description: "What the meeting was about and what came of it, in two or three plain sentences.")
    var summary: String
    @Guide(description: "People who spoke or were named, as they appear in the transcript.", .maximumCount(8))
    var participants: [String]
    @Guide(description: "The main topics discussed, a few words each.", .maximumCount(8))
    var topics: [String]
    @Guide(description: "Decisions that were made, one sentence each. Empty if none.", .maximumCount(10))
    var decisions: [String]
    @Guide(description: "Things someone agreed to do.", .maximumCount(12))
    var actions: [ActionDraft]
    @Guide(description: "Questions raised and left open.", .maximumCount(8))
    var questions: [String]
}

/// Detects meetings and writes their digest, entirely on the phone with
/// Apple's language model. Long transcripts are digested in windows and the
/// windows are merged, so an hour-long meeting fits the model's context.
@MainActor
@Observable
final class MeetingDigester {
    static let shared = MeetingDigester()

    private(set) var inFlight: Set<UUID> = []
    private(set) var lastError: String?

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Words per window. The on-device model holds about 4k tokens; this
    /// leaves room for the instructions and the structured answer.
    static let windowWords = 1_600

    // MARK: Entry points

    /// After a recording lands: decide what it is, and digest it if it is a meeting.
    func detectAndDigestIfNeeded(for document: Document) {
        guard document.kind == .recording, document.kindLabel == nil, Self.isAvailable else { return }
        guard !inFlight.contains(document.id) else { return }
        let words = document.wordCount
        // Cheap gate first: a meeting is at least a few minutes of several people.
        guard document.duration >= 240, words >= 500, Self.looksLikeMeeting(document.transcript.plain) else {
            document.kindLabel = RecordingKind.memo.rawValue
            try? document.modelContext?.save()
            return
        }
        inFlight.insert(document.id)
        Task {
            defer { inFlight.remove(document.id) }
            let kind = await Self.classify(document.transcript.plain)
            document.kindLabel = kind.rawValue
            try? document.modelContext?.save()
            if kind == .meeting {
                await digestNow(document, markInFlight: false)
            }
        }
    }

    /// Digest on demand, for any recording.
    func digest(_ document: Document) {
        guard !inFlight.contains(document.id) else { return }
        inFlight.insert(document.id)
        Task {
            defer { inFlight.remove(document.id) }
            await digestNow(document, markInFlight: false)
        }
    }

    private func digestNow(_ document: Document, markInFlight: Bool) async {
        if markInFlight { inFlight.insert(document.id) }
        defer { if markInFlight { inFlight.remove(document.id) } }
        lastError = nil
        do {
            let digest = try await Self.makeDigest(from: document.transcript.plain)
            document.digest = digest
            if document.kindLabel == nil || document.kindLabel == RecordingKind.memo.rawValue {
                document.kindLabel = RecordingKind.meeting.rawValue
            }
            try? document.modelContext?.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Detection

    /// Words that cluster in meetings and not in a memo read to oneself.
    private static let meetingCues = ["agenda", "action item", "action items", "next steps", "follow up", "follow-up", "let's", "we should", "we need", "can you", "could you", "by friday", "by monday", "by next week", "deadline", "decision", "decided", "sync", "stand-up", "standup", "okay so", "any questions", "moving on", "circle back", "owner", "assign"]

    static func looksLikeMeeting(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = max(1, lower.split(whereSeparator: { $0.isWhitespace }).count)
        var hits = 0
        for cue in meetingCues {
            hits += lower.components(separatedBy: cue).count - 1
        }
        let questions = lower.filter { $0 == "?" }.count
        // About one cue per 150 words, or a lot of questions, reads as a meeting.
        return Double(hits) / Double(words) >= 1.0 / 150.0 || Double(questions) / Double(words) >= 1.0 / 60.0
    }

    static func classify(_ transcript: String) async -> RecordingKind {
        guard isAvailable else { return .other }
        let sample = Self.sample(transcript, words: 700)
        do {
            let session = LanguageModelSession(instructions: "You classify a transcript of a recording. Answer only with the structured result.")
            let response = try await session.respond(to: "Classify this transcript excerpt:\n\n\(sample)", generating: KindDraft.self)
            let guess = response.content
            if guess.confidence < 40 { return .other }
            return RecordingKind(rawValue: guess.kind.rawValue) ?? .other
        } catch {
            return .other
        }
    }

    /// The opening and a slice from the middle, so a long meeting is judged
    /// by more than its small talk.
    private static func sample(_ text: String, words: Int) -> String {
        let all = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard all.count > words else { return all.joined(separator: " ") }
        let head = all.prefix(words / 2)
        let midStart = all.count / 2
        let middle = all[midStart..<min(all.count, midStart + words / 2)]
        return head.joined(separator: " ") + "\n…\n" + middle.joined(separator: " ")
    }

    // MARK: Digest

    static func makeDigest(from transcript: String) async throws -> MeetingDigest {
        let windows = Self.windows(of: transcript, words: windowWords)
        guard !windows.isEmpty else { throw DigestError.empty }
        var drafts: [DigestDraft] = []
        for (i, window) in windows.enumerated() {
            let session = LanguageModelSession(instructions: Self.digestInstructions)
            let prompt = windows.count > 1
                ? "This is part \(i + 1) of \(windows.count) of a meeting transcript. Digest this part:\n\n\(window)"
                : "Digest this meeting transcript:\n\n\(window)"
            let response = try await session.respond(to: prompt, generating: DigestDraft.self)
            drafts.append(response.content)
        }
        let merged: DigestDraft
        if drafts.count == 1 {
            merged = drafts[0]
        } else {
            let notes = drafts.enumerated().map { i, d in
                "PART \(i + 1)\nTitle: \(d.title)\nSummary: \(d.summary)\nDecisions: \(d.decisions.joined(separator: "; "))\nActions: \(d.actions.map { "\($0.task) (\($0.owner), \($0.due))" }.joined(separator: "; "))\nQuestions: \(d.questions.joined(separator: "; "))\nTopics: \(d.topics.joined(separator: ", "))\nParticipants: \(d.participants.joined(separator: ", "))"
            }.joined(separator: "\n\n")
            let session = LanguageModelSession(instructions: Self.digestInstructions)
            let response = try await session.respond(to: "These are digests of the parts of one meeting, in order. Merge them into one digest for the whole meeting. Keep every decision and action, remove duplicates, and keep the summary to three sentences:\n\n\(notes)", generating: DigestDraft.self)
            merged = response.content
        }
        return MeetingDigest(
            title: merged.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: merged.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            participants: Self.clean(merged.participants),
            topics: Self.clean(merged.topics),
            decisions: Self.clean(merged.decisions),
            actions: merged.actions.map { MeetingDigest.Action(owner: $0.owner, task: $0.task, due: $0.due) }.filter { !$0.task.isEmpty },
            questions: Self.clean(merged.questions),
            generatedAt: .now
        )
    }

    private static let digestInstructions = """
    You digest meeting transcripts for someone who was not there. Be concrete and brief. \
    Use the names the transcript uses. Never invent decisions, owners or dates that the transcript does not state. \
    If there are no decisions, actions or questions, return empty lists.
    """

    private static func windows(of text: String, words: Int) -> [String] {
        let all = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !all.isEmpty else { return [] }
        var out: [String] = []
        var i = 0
        while i < all.count {
            let end = min(all.count, i + words)
            out.append(all[i..<end].joined(separator: " "))
            i = end
        }
        return out
    }

    private static func clean(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    enum DigestError: LocalizedError {
        case empty

        var errorDescription: String? { "There is no transcript to digest." }
    }
}
