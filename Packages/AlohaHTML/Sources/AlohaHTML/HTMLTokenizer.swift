// SPDX-License-Identifier: MIT

import Foundation

/// A single pass over the bytes, producing tags and text.
///
/// Deliberately small: Mastodon's status content is a restricted subset, and
/// anything this does not understand is stripped to its text content rather
/// than being an error. It never throws and never loops — a malformed tag
/// consumes at least one character.
struct HTMLTokenizer {
    enum Token: Equatable {
        case text(String)
        case openTag(name: String, attributes: [String: String], selfClosing: Bool)
        case closeTag(name: String)
    }

    private let source: [Character]
    private var index: Int = 0

    init(_ html: String) {
        source = Array(html)
    }

    mutating func next() -> Token? {
        guard index < source.count else { return nil }

        if source[index] == "<" {
            if let token = readTag() { return token }
            // A stray `<` that is not a tag is text, which is what a server that
            // failed to escape one leaves behind.
            index += 1
            return .text("<")
        }
        return readText()
    }

    private mutating func readText() -> Token {
        var text = ""
        while index < source.count, source[index] != "<" {
            text.append(source[index])
            index += 1
        }
        return .text(HTMLEntities.decode(text))
    }

    private mutating func readTag() -> Token? {
        let start = index
        index += 1  // consume '<'

        // Comments and doctypes are skipped whole.
        if matches("!--") {
            index += 3
            while index < source.count {
                if matches("-->") {
                    index += 3
                    return .text("")
                }
                index += 1
            }
            return .text("")
        }
        if index < source.count, source[index] == "!" {
            while index < source.count, source[index] != ">" { index += 1 }
            if index < source.count { index += 1 }
            return .text("")
        }

        let isClosing = index < source.count && source[index] == "/"
        if isClosing { index += 1 }

        var name = ""
        while index < source.count, source[index].isLetter || source[index].isNumber {
            name.append(source[index])
            index += 1
        }

        guard !name.isEmpty else {
            index = start
            return nil
        }

        var attributes: [String: String] = [:]
        var selfClosing = false

        while index < source.count, source[index] != ">" {
            if source[index] == "/" {
                selfClosing = true
                index += 1
                continue
            }
            if source[index].isWhitespace {
                index += 1
                continue
            }
            if let (key, value) = readAttribute() {
                attributes[key] = value
            } else {
                index += 1
            }
        }
        if index < source.count { index += 1 }  // consume '>'

        let lowered = name.lowercased()
        if isClosing { return .closeTag(name: lowered) }
        return .openTag(name: lowered, attributes: attributes, selfClosing: selfClosing)
    }

    private mutating func readAttribute() -> (String, String)? {
        var key = ""
        while index < source.count,
            !source[index].isWhitespace, source[index] != "=", source[index] != ">"
        {
            key.append(source[index])
            index += 1
        }
        guard !key.isEmpty else { return nil }

        while index < source.count, source[index].isWhitespace { index += 1 }
        guard index < source.count, source[index] == "=" else { return (key.lowercased(), "") }
        index += 1
        while index < source.count, source[index].isWhitespace { index += 1 }

        var value = ""
        if index < source.count, source[index] == "\"" || source[index] == "'" {
            let quote = source[index]
            index += 1
            while index < source.count, source[index] != quote {
                value.append(source[index])
                index += 1
            }
            if index < source.count { index += 1 }
        } else {
            while index < source.count, !source[index].isWhitespace, source[index] != ">" {
                value.append(source[index])
                index += 1
            }
        }
        return (key.lowercased(), HTMLEntities.decode(value))
    }

    private func matches(_ text: String) -> Bool {
        let characters = Array(text)
        guard index + characters.count <= source.count else { return false }
        for offset in characters.indices where source[index + offset] != characters[offset] {
            return false
        }
        return true
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•", "copy": "©",
        "reg": "®", "trade": "™", "deg": "°", "euro": "€", "pound": "£", "laquo": "«",
        "raquo": "»", "times": "×", "divide": "÷", "shy": "", "zwj": "\u{200D}",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.startIndex

        while iterator < text.endIndex {
            guard text[iterator] == "&" else {
                result.append(text[iterator])
                iterator = text.index(after: iterator)
                continue
            }
            // An entity is short; anything longer is a literal ampersand.
            let limit =
                text.index(iterator, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text[iterator..<limit].firstIndex(of: ";") else {
                result.append("&")
                iterator = text.index(after: iterator)
                continue
            }

            let body = String(text[text.index(after: iterator)..<semicolon])
            if let replacement = resolve(body) {
                result.append(replacement)
            } else {
                result.append("&\(body);")
            }
            iterator = text.index(after: semicolon)
        }
        return result
    }

    private static func resolve(_ body: String) -> String? {
        if let named = named[body.lowercased()] { return named }
        guard body.hasPrefix("#") else { return nil }

        let digits = String(body.dropFirst())
        let scalarValue: UInt32?
        if digits.lowercased().hasPrefix("x") {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits)
        }
        guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else { return nil }
        return String(Character(scalar))
    }
}
