import Foundation
import Testing
@testable import RelayBrain

struct RelayContractsTests {
    @Test
    func taskSummaryIsEquatableAndEncodesAllFields() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_721_234_567)
        let summary = RelayTaskSummary(
            id: "task-1",
            title: "Repair onboarding",
            project: "/Projects/Relay",
            status: "running",
            updatedAt: updatedAt
        )

        #expect(
            summary
                == RelayTaskSummary(
                    id: "task-1",
                    title: "Repair onboarding",
                    project: "/Projects/Relay",
                    status: "running",
                    updatedAt: updatedAt
                )
        )

        let data = try JSONEncoder().encode(summary)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["id"] as? String == "task-1")
        #expect(object["title"] as? String == "Repair onboarding")
        #expect(object["project"] as? String == "/Projects/Relay")
        #expect(object["status"] as? String == "running")
        #expect(object["updatedAt"] != nil)
    }

    @Test
    func defaultControllerConfigurationUsesTheLiaisonInstructionsAndTools() {
        let configuration = RelayControllerConfiguration.default

        #expect(
            configuration.developerInstructions
                == RelayControllerInstructions.developer
        )
        #expect(configuration.dynamicTools == RelayDynamicTools.definitions)
        #expect(configuration.dynamicTools.count == 7)

        let instructions = configuration.developerInstructions.lowercased()
        #expect(instructions.contains("liaison"))
        #expect(instructions.contains("must delegate"))
        #expect(instructions.contains("must not do worker work"))
        #expect(instructions.contains("relay_list_tasks"))
        #expect(instructions.contains("relay_send_to_task"))
        #expect(instructions.contains("succinct"))
        #expect(instructions.contains("quietly confident"))
        #expect(instructions.contains("generic assistant phrases"))
        #expect(instructions.contains("surface what needs you"))
        #expect(instructions.contains("one to four short sentences"))
        #expect(instructions.contains("sole authority for current activity"))
        #expect(instructions.contains("historical context, not live evidence"))
        #expect(instructions.contains("does not mean inactive"))
    }

    @Test
    func controllerEventsCarryFinalTextAndDynamicToolCalls() {
        let call = RelayControllerToolCall(
            id: "call-1",
            toolName: "relay_list_tasks",
            argumentsJSON: Data("{}".utf8)
        )

        #expect(
            RelayControllerEvent.dynamicToolCall(call)
                == .dynamicToolCall(call)
        )
        #expect(
            RelayControllerEvent.finalText("Delegated.")
                == .finalText("Delegated.")
        )
    }

    @Test
    func toolCallResultCarriesAResponseSafeSuccessFlagAndText() throws {
        let result = RelayToolCallResult(
            success: true,
            text: #"{"ok":true}"#
        )

        #expect(result.success)
        #expect(result.text == #"{"ok":true}"#)
        #expect(
            String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
                .contains(#""success":true"#)
        )
    }
}
