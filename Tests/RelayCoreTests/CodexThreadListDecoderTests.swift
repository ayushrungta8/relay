import Foundation
import Testing
@testable import RelayCore

struct CodexThreadListDecoderTests {
    @Test
    func decodesARealisticThreadListResponse() throws {
        let data = Data(
            """
            {
              "id": 2,
              "result": {
                "data": [
                  {
                    "id": "019f6759-d236-7962-9f6d-5f533fe1fc6e",
                    "preview": "Inspect the Concierge changes",
                    "cwd": "/Users/ayushrungta/Work/Concierge",
                    "updatedAt": 1784210400,
                    "status": { "type": "notLoaded" }
                  }
                ],
                "nextCursor": null
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            CodexThreadListEnvelope.self,
            from: data
        )

        let thread = try #require(response.result.data.first)
        #expect(thread.id == "019f6759-d236-7962-9f6d-5f533fe1fc6e")
        #expect(thread.preview == "Inspect the Concierge changes")
        #expect(thread.cwd == "/Users/ayushrungta/Work/Concierge")
        #expect(thread.status == .notLoaded)
        #expect(response.result.nextCursor == nil)
    }
}
