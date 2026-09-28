// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try AlohaJSON.decoder.decode(T.self, from: Data(json.utf8))
}

@Suite("Your year")
struct AnnualReportTests {

    /// Exactly what `AnnualReportService::forYear` builds, wrapped the way
    /// `ApiController::wrapReports` wraps it.
    private let payload = """
        {
          "annual_reports": [
            {
              "year": 2025,
              "data": {
                "archetype": "oracle",
                "time_series": [
                  {"month": 1, "statuses": 3, "followers": 1},
                  {"month": 2, "statuses": 11, "followers": 0}
                ],
                "top_hashtags": [{"name": "nextcloud", "count": 7}],
                "top_statuses": {
                  "by_reblogs": "110",
                  "by_replies": null,
                  "by_favourites": "110"
                }
              },
              "schema_version": 1,
              "share_url": null,
              "account_id": "42"
            }
          ],
          "accounts": [],
          "statuses": []
        }
        """

    @Test("A wrapped report decodes whole")
    func decodesWrapped() throws {
        let wrapped = try decode(WrappedAnnualReports.self, payload)
        let report = try #require(wrapped.annualReports.first)
        #expect(report.year == 2025)
        #expect(report.data.archetype == .oracle)
        #expect(report.data.totalStatuses == 14)
        #expect(report.data.totalFollowers == 1)
        #expect(report.data.busiestMonth?.month == 2)
        #expect(report.data.topHashtags.first?.name == "nextcloud")
        #expect(report.accountID == "42")
    }

    @Test("A null share_url is no URL rather than a decoding failure")
    func nullShareURL() throws {
        let wrapped = try decode(WrappedAnnualReports.self, payload)
        #expect(wrapped.annualReports.first?.shareURL == nil)
    }

    @Test("The three best posts are distinct ids, in order, without the absent one")
    func topStatusIDs() throws {
        let wrapped = try decode(WrappedAnnualReports.self, payload)
        let top = try #require(wrapped.annualReports.first?.data.topStatuses)
        #expect(top.byReplies == nil)
        #expect(top.ids == ["110"])
    }

    @Test("An archetype nobody has heard of does not fail the report")
    func unknownArchetype() throws {
        let report = try decode(
            AnnualReport.self,
            #"{"year": 2024, "data": {"archetype": "sphinx"}, "account_id": 9}"#)
        #expect(report.data.archetype == .unknownCase)
        // A numeric account id is still an id.
        #expect(report.accountID == "9")
    }

    @Test("State decodes the four words, and an unknown fifth")
    func state() throws {
        #expect(try decode(AnnualReportState.self, #"{"state":"available"}"#).state == .available)
        #expect(
            try decode(AnnualReportState.self, #"{"state":"ineligible"}"#).state == .ineligible)
        #expect(try decode(AnnualReportState.self, #"{"state":"melting"}"#).state == .unknownCase)
    }
}

@Suite("Moderation entities")
struct ModerationEntityTests {

    @Test("An admin account's standing is the strongest thing true of it")
    func standing() throws {
        let suspended = try decode(
            AdminAccount.self,
            #"{"id":"1","username":"bob","domain":"other.example","silenced":true,"suspended":true}"#
        )
        #expect(suspended.standing == .suspended)
        #expect(!suspended.isLocal)
        #expect(suspended.handle == "@bob@other.example")

        let silenced = try decode(
            AdminAccount.self, #"{"id":"2","username":"eve","domain":"","silenced":true}"#)
        #expect(silenced.standing == .silenced)
        #expect(silenced.isLocal)
        #expect(silenced.handle == "@eve")

        let active = try decode(AdminAccount.self, #"{"id":"3","username":"ada"}"#)
        #expect(active.standing == .active)
    }

    @Test("A report carries who, what and whether anybody has taken it")
    func report() throws {
        let report = try decode(
            AdminReport.self,
            """
            {
              "id": "7",
              "action_taken": false,
              "action_taken_at": null,
              "category": "spam",
              "comment": "posting the same link everywhere",
              "forwarded": true,
              "created_at": "2026-01-02T03:04:05.000Z",
              "updated_at": "2026-01-02T03:04:05.000Z",
              "account": {"id": "1", "username": "ada", "acct": "ada"},
              "target_account": {"id": "2", "username": "bob", "acct": "bob@other.example"},
              "assigned_account": null,
              "action_taken_by_account": null,
              "statuses": [],
              "rules": []
            }
            """)
        #expect(report.id == "7")
        #expect(!report.actionTaken)
        #expect(report.forwarded)
        #expect(!report.isAssigned)
        #expect(report.targetAccount?.acct == "bob@other.example")
        #expect(report.createdAt != nil)
    }

    @Test("Weekly activity decodes the strings the server actually sends")
    func activity() throws {
        let weeks = try decode(
            [InstanceActivityWeek].self,
            #"[{"week":"1767139200","statuses":"41","logins":"0","registrations":"0"}]"#)
        #expect(weeks.first?.statuses == 41)
        #expect(weeks.first?.week == 1_767_139_200)
        #expect(weeks.first?.registrations == 0)
    }

    @Test("A published domain block keys off its digest")
    func domainBlock() throws {
        let blocks = try decode(
            [PublicDomainBlock].self,
            #"[{"domain":"bad.example","digest":"abc","severity":"suspend","comment":""}]"#)
        #expect(blocks.first?.id == "abc")
        #expect(blocks.first?.severity == "suspend")
    }
}

@Suite("The colour a Nextcloud wears")
struct NextcloudThemeTests {

    /// The shape Nextcloud actually sends, envelope and all.
    private let payload = """
        {
          "ocs": {
            "meta": {"status": "ok", "statuscode": 200},
            "data": {
              "capabilities": {
                "theming": {
                  "name": "Example Cloud",
                  "slogan": "a safe home for your data",
                  "url": "https://nextcloud.com",
                  "color": "#0082C9",
                  "color-text": "#ffffff",
                  "color-element": "#0082c9",
                  "color-element-bright": "#0082c9",
                  "color-element-dark": "#3ea4e4",
                  "background": "#0082c9",
                  "background-plain": true
                },
                "files": {"bigfilechunking": true}
              }
            }
          }
        }
        """

    @Test("The theming capability is found inside the OCS envelope")
    func decodesEnvelope() throws {
        let theme = try #require(decode(OCSCapabilities.self, payload).theming)
        #expect(theme.name == "Example Cloud")
        #expect(theme.hasColour)
        // Normalised on the way in, so nothing downstream has to care.
        #expect(theme.colourHex == "#0082c9")
        #expect(theme.textHex == "#ffffff")
    }

    @Test("Each background gets the variant the server computed for it")
    func picksTheVariant() throws {
        let theme = try #require(decode(OCSCapabilities.self, payload).theming)
        #expect(theme.hex(onDarkBackground: false) == "#0082c9")
        #expect(theme.hex(onDarkBackground: true) == "#3ea4e4")
    }

    @Test("A server with only the raw colour uses it for both")
    func fallsBackToTheRawColour() throws {
        // Two `#` on the delimiter: a hex colour contains `"#`, which closes a
        // single-hash raw string in the middle of the JSON.
        let theme = try decode(
            NextcloudTheme.self, ##"{"name": "Plain", "color": "#abc"}"##)
        #expect(theme.colourHex == "#aabbcc")
        #expect(theme.hex(onDarkBackground: false) == "#aabbcc")
        #expect(theme.hex(onDarkBackground: true) == "#aabbcc")
    }

    @Test("Theming switched off is no colour, not a broken one")
    func nothingToSay() throws {
        let capabilities = try decode(
            OCSCapabilities.self,
            #"{"ocs":{"meta":{},"data":{"capabilities":{"files":{}}}}}"#)
        #expect(capabilities.theming == nil)

        let empty = try decode(NextcloudTheme.self, #"{"name":"Plain","color":""}"#)
        #expect(!empty.hasColour)
        #expect(empty.hex(onDarkBackground: false) == nil)
    }

    @Test("Anything that is not a colour is dropped rather than guessed at")
    func rejectsNonColours() throws {
        for bad in [##""nope""##, ##""#12345""##, ##""rgb(1,2,3)""##] {
            let theme = try decode(NextcloudTheme.self, ##"{"color": \##(bad)}"##)
            #expect(!theme.hasColour, "\(bad) was taken for a colour")
        }
    }
}
