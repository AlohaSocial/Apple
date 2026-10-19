// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Filling headers and asking again")
struct SocialFillingTests {

    @Test("The three headers are read, case-insensitively")
    func readsHeaders() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://cloud.test/api/v1/statuses/1/context")!,
                statusCode: 200, httpVersion: nil,
                headerFields: [
                    "X-Social-Thread-Filling": "1", "x-social-hidden-replies": "3",
                    "Content-Type": "application/json",
                ]))
        let headers = RawResponse.socialHeaders(of: response)
        #expect(headers.keys.sorted() == ["x-social-hidden-replies", "x-social-thread-filling"])

        let filling = SocialFilling(headers: headers)
        #expect(filling.isThreadFilling)
        #expect(!filling.isFilling)
        #expect(filling.hiddenReplies == 3)
        #expect(filling.isStillFilling)
    }

    @Test("No header, or a value other than 1, is not filling")
    func notFilling() {
        #expect(!SocialFilling(headers: [:]).isStillFilling)
        #expect(!SocialFilling(headers: ["x-social-filling": "0"]).isStillFilling)
        #expect(SocialFilling(headers: ["x-social-filling": " 1 "]).isFilling)
        #expect(SocialFilling(headers: ["x-social-hidden-replies": "many"]).hiddenReplies == nil)
    }

    @Test("Asks again twice while filling, then stops")
    func retryPolicy() {
        let policy = FillingRetryPolicy()
        let filling = SocialFilling(isThreadFilling: true)
        #expect(policy.delay(after: 1, filling: filling) == .seconds(3))
        #expect(policy.delay(after: 2, filling: filling) == .seconds(6))
        #expect(policy.delay(after: 3, filling: filling) == nil)
    }

    @Test("A finished answer is not asked for again")
    func stopsWhenDone() {
        let policy = FillingRetryPolicy()
        #expect(policy.delay(after: 1, filling: SocialFilling()) == nil)
        #expect(policy.delay(after: 0, filling: SocialFilling(isFilling: true)) == nil)
    }

    @Test("The context route asks for hidden replies only when told to")
    func contextQuery() throws {
        let base = try #require(URL(string: "https://cloud.test/"))
        let hidden = try #require(
            Endpoint.statuses.context("42", includingHidden: true).url(base: base))
        #expect(
            hidden.absoluteString
                == "https://cloud.test/api/v1/statuses/42/context?with_hidden=true")
        let plain = try #require(
            Endpoint.statuses.context("42", includingHidden: false).url(base: base))
        #expect(plain.query() == nil)
    }
}
