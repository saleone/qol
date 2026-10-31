import Foundation
import Testing
@testable import DisplaySplitCore

struct ConfigTests {
    private func parse(_ json: String) throws -> Config {
        try Config(json: Data(json.utf8))
    }

    @Test func missingKeysTakeDefaultsAndUnknownKeysAreIgnored() throws {
        #expect(try parse("{}") == Config())
        let config = try parse(#"{"split": "1:3:2", "someFutureKey": 1}"#)
        #expect(config.split == ColumnSplit(left: 1, center: 3, right: 2))
        #expect(config.centerNewWindows == true)
    }

    @Test func roundTripsThroughFileFormat() throws {
        var config = Config()
        config.centerNewWindows = false
        config.split = ColumnSplit(left: 1, center: 2.5, right: 1)!
        #expect(try Config(json: config.json()) == config)
    }

    @Test func fileIsStableForVersionControl() {
        let text = String(decoding: Config().json(), as: UTF8.self)
        #expect(text == """
        {
          "centerNewWindows" : true,
          "split" : "1:2:1"
        }

        """)
    }

    @Test(arguments: [
        (#"{"split": "1:2"}"#, "split"),
        (#"{"split": 121}"#, "must be a string"),
        (#"{"centerNewWindows": "yes"}"#, "true or false"),
        (#"{"split": "1:2:1""#, "Not valid JSON"),
        ("", "Not valid JSON"),
    ])
    func rejectsInvalidFilesWithReadableReason(json: String, reason: String) {
        #expect {
            try parse(json)
        } throws: { error in
            String(describing: error).contains(reason)
        }
    }
}
