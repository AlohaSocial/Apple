// SPDX-License-Identifier: MIT

import Foundation

/// An array that decodes element-by-element and drops the ones that fail.
///
/// Rule from docs/04 §2: a malformed entity must never fail its page. Nextcloud
/// Social is a partial implementation and the wider fediverse is forks of forks;
/// a strict decoder fails on real data. A timeline page with one bad status
/// shows nineteen.
public struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    public let elements: [Element]
    /// What was dropped, so the caller can log it rather than lose it silently.
    public let failures: [LossyDecodingFailure]

    public init(elements: [Element], failures: [LossyDecodingFailure] = []) {
        self.elements = elements
        self.failures = failures
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        if let count = container.count { elements.reserveCapacity(count) }
        var failures: [LossyDecodingFailure] = []

        while !container.isAtEnd {
            let index = container.currentIndex
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                // The element has to be consumed either way or the container
                // never advances and this loops forever.
                _ = try? container.decode(AnyDecodableSkip.self)
                failures.append(
                    LossyDecodingFailure(
                        index: index,
                        typeName: String(describing: Element.self),
                        description: String(describing: error)
                    )
                )
            }
        }

        self.elements = elements
        self.failures = failures
    }
}

extension LossyArray: Encodable where Element: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in elements { try container.encode(element) }
    }
}

extension LossyArray: RandomAccessCollection {
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public subscript(position: Int) -> Element { elements[position] }
}

public struct LossyDecodingFailure: Sendable, Hashable {
    public let index: Int
    public let typeName: String
    public let description: String
}

/// Consumes one value of any shape so a failed element can be stepped over.
private struct AnyDecodableSkip: Decodable {
    init(from decoder: any Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd { _ = try? unkeyed.decode(AnyDecodableSkip.self) }
            return
        }
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            for key in keyed.allKeys { _ = try? keyed.decode(AnyDecodableSkip.self, forKey: key) }
            return
        }
        _ = try? decoder.singleValueContainer()
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }
}
