import Foundation
import Testing
@testable import RelayBrain

struct RelayDynamicToolDefinitionsTests {
    @Test
    func exposesExactlyTheFiveRelayTaskTools() {
        #expect(
            RelayDynamicTools.definitions.map(\.name)
                == [
                    "relay_list_tasks",
                    "relay_get_task",
                    "relay_start_task",
                    "relay_send_to_task",
                    "relay_interrupt_task",
                ]
        )
        #expect(
            RelayDynamicTools.definitions.allSatisfy {
                $0.type == "function" && !$0.description.isEmpty
            }
        )
    }

    @Test
    func everyToolUsesAStrictJSONObjectSchema() throws {
        for definition in RelayDynamicTools.definitions {
            let data = try JSONEncoder().encode(definition)
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let schema = try #require(
                object["inputSchema"] as? [String: Any]
            )

            #expect(schema["type"] as? String == "object")
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(schema["properties"] is [String: Any])
            #expect(schema["required"] is [String])
        }
    }

    @Test(
        arguments: [
            ("relay_list_tasks", []),
            ("relay_get_task", ["id"]),
            ("relay_start_task", ["cwd", "prompt"]),
            ("relay_send_to_task", ["id", "prompt"]),
            ("relay_interrupt_task", ["id"]),
        ]
    )
    func schemaRequiresExactlyItsDeclaredArguments(
        toolName: String,
        requiredArguments: [String]
    ) throws {
        let definition = try #require(
            RelayDynamicTools.definitions.first { $0.name == toolName }
        )
        let propertyNames = definition.inputSchema.properties.keys.sorted()

        #expect(propertyNames == requiredArguments)
        #expect(definition.inputSchema.required.sorted() == requiredArguments)
        #expect(
            definition.inputSchema.properties.values.allSatisfy {
                $0.type == "string" && !$0.description.isEmpty
            }
        )
    }
}
