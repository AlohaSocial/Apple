// SPDX-License-Identifier: MIT

import Foundation

/// The three little games a post can play: `/dice`, `/flip` and `/pick`.
///
/// A port of Nextcloud Social's `src/utils/composerCommands.js`, and
/// deliberately a faithful one — the point is that a post written here and a
/// post written in the web app say the same thing.
///
/// Each command is replaced by its result **before the post is sent**, so what
/// travels is plain text — "🎲 4", "🪙 heads", "🎯 pizza" — and a Mastodon
/// reader sees exactly what a reader here sees. Nothing is rolled on the server
/// and nothing can be re-rolled afterwards: the result is part of what was
/// posted (docs/07 §2).
///
/// A command is only a command at the start of a line or after a space, so a
/// link that happens to contain `/dice` is left alone.
public enum ComposerCommands {
    /// The most sides a die may have: enough for any game, too few to be a
    /// lottery.
    public static let maximumSides = 1000
    /// The most options `/pick` takes.
    public static let maximumOptions = 20

    /// Which game was played, and what it landed on.
    public struct Result: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable {
            case dice, flip, pick

            public var icon: String {
                switch self {
                case .dice: "🎲"
                case .flip: "🪙"
                case .pick: "🎯"
                }
            }
        }

        public let id = UUID()
        public var kind: Kind
        public var result: String
        public var options: [String]
        public var sides: Int?

        public init(kind: Kind, result: String, options: [String] = [], sides: Int? = nil) {
            self.kind = kind
            self.result = result
            self.options = options
            self.sides = sides
        }
    }

    /// Where each command may start and what it takes.
    ///
    /// A die takes an optional number of sides; a coin takes nothing. Only
    /// `/pick` runs to the end of its line, since its options are the rest of
    /// it — so `/flip then /dice` is two games and neither swallows the other.
    ///
    /// Groups: 1 what came before, 2 `dice|roll`, 3 its sides, 4 `flip`,
    /// 5 `pick`, 6 its options.
    private static let pattern =
        #"(^|\s)/(?:(dice|roll)(\s+d?\d{1,4}\b)?|(flip)|(pick)([^\n]*))(?![\w/])"#

    private static let expression = try? NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])

    /// A source of randomness, injected so a test can know what the dice will
    /// say. Returns a value in `[0, 1)`.
    public typealias RandomSource = @Sendable () -> Double

    /// Public because it is a default argument, which is part of the signature.
    public static let systemRandom: RandomSource = { Double.random(in: 0..<1) }

    /// What a post says once its commands have been played.
    public static func resolve(
        _ text: String, random: RandomSource = systemRandom
    ) -> (text: String, results: [Result]) {
        guard let expression else { return (text, []) }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return (text, []) }

        var results: [Result] = []
        var output = ""
        var cursor = 0

        for match in matches {
            output += nsText.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length

            let lead = group(match, 1, in: nsText) ?? ""
            let whole = nsText.substring(with: match.range)

            if group(match, 2, in: nsText) != nil {
                let sides = sidesOf(group(match, 3, in: nsText))
                let face = roll(sides: sides, random: random)
                results.append(.init(kind: .dice, result: String(face), sides: sides))
                output += lead + (sides == 6 ? "🎲 \(face)" : "🎲 \(face) (d\(sides))")
            } else if group(match, 4, in: nsText) != nil {
                let heads = random() < 0.5
                let face =
                    heads
                    ? String(localized: "heads", comment: "Coin flip result")
                    : String(localized: "tails", comment: "Coin flip result")
                results.append(.init(kind: .flip, result: face))
                output += "\(lead)🪙 \(face)"
            } else {
                let options = parseOptions(group(match, 6, in: nsText) ?? "")
                guard options.count >= 2 else {
                    // Nothing to choose between is not a game; leave it as typed.
                    output += whole
                    continue
                }
                let choice = options[index(upTo: options.count, random: random)]
                results.append(.init(kind: .pick, result: choice, options: options))
                let joined = options.joined(separator: ", ")
                output +=
                    lead + "🎯 "
                    + String(
                        localized: "\(choice) (out of \(joined))",
                        comment:
                            "Pick command result: the choice, then the options it was made from")
            }
        }

        output += nsText.substring(from: cursor)
        return (output, results)
    }

    /// Which games a post has to play, for the hint under the box. In order,
    /// without repeats.
    public static func commands(in text: String) -> [Result.Kind] {
        guard let expression else { return [] }
        let nsText = text as NSString
        var kinds: [Result.Kind] = []

        for match in expression.matches(
            in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        {
            let kind: Result.Kind =
                group(match, 2, in: nsText) != nil
                ? .dice : (group(match, 4, in: nsText) != nil ? .flip : .pick)
            if kind == .pick, parseOptions(group(match, 6, in: nsText) ?? "").count < 2 { continue }
            if !kinds.contains(kind) { kinds.append(kind) }
        }

        return kinds
    }

    /// The options `/pick` was given: split on commas, or on " or " when there
    /// are none.
    public static func parseOptions(_ rest: String) -> [String] {
        let line = rest.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return [] }

        let parts = line.contains(",") ? line.components(separatedBy: ",") : splitOnOr(line)

        return
            parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(maximumOptions)
            .map { $0 }
    }

    /// Splits on a standalone " or ", the way the web's `/\s+or\s+/i` does.
    private static func splitOnOr(_ line: String) -> [String] {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"\s+or\s+"#, options: [.caseInsensitive])
        else { return [line] }

        let nsLine = line as NSString
        var parts: [String] = []
        var cursor = 0
        for match in expression.matches(
            in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        {
            parts.append(
                nsLine.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        parts.append(nsLine.substring(from: cursor))
        return parts
    }

    // MARK: - Machinery

    private static func group(
        _ match: NSTextCheckingResult, _ index: Int, in text: NSString
    ) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return text.substring(with: range)
    }

    /// How many sides the die has: what followed `/dice`, clamped, or six.
    private static func sidesOf(_ argument: String?) -> Int {
        guard
            let argument,
            let range = argument.range(of: #"\d+"#, options: .regularExpression),
            let digits = Int(argument[range])
        else { return 6 }
        return min(maximumSides, max(2, digits))
    }

    private static func roll(sides: Int, random: RandomSource) -> Int {
        index(upTo: sides, random: random) + 1
    }

    /// A whole number in `0..<count`, from a source that may hand back exactly
    /// 1.0 however it is documented — clamped rather than trusted, because the
    /// alternative is an index out of range on a post somebody is trying to
    /// send.
    private static func index(upTo count: Int, random: RandomSource) -> Int {
        guard count > 0 else { return 0 }
        return min(count - 1, max(0, Int(random() * Double(count))))
    }
}
