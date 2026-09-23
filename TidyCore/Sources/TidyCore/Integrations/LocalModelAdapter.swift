import Foundation

public struct LocalModelAdapter: ToolAdapter {
    public static let adapterID = "local.models"
    public static let contractVersion = "filesystem-v1"
    static let ecosystemID = "models"

    public init() {}

    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry] {
        let candidates = [
            context.environment.path(".ollama/models"),
            context.environment.path(".cache/huggingface/hub"),
            context.environment.path(".cache/mlx")
        ]
        return AdapterPaths.existing(candidates, context: context).compactMap { path in
            context.entry(adapterID: Self.adapterID,
                adapterVersion: Self.contractVersion, path: path,
                kind: "model-store", disposition: .reportOnly,
                reason: "Model aliases and shared blobs are measured once by file identity; model mutation is permanently unavailable.")
        }
    }
}
