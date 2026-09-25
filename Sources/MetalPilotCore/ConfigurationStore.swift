import Foundation

public actor ConfigurationStore {
    public static let maxDefaultPaths = Int.max
    public static let maxPresets = 5
    public static let maxRecentMetalHUDApps = 12
    public static let maxFavoriteProcessNames = 64

    private let configurationURL: URL
    private let fileManager: FileManager

    public init(configurationURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let configurationURL {
            self.configurationURL = configurationURL
        } else {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.iven.macgametoolbox", isDirectory: true)
            self.configurationURL = root.appendingPathComponent("configuration.json")
        }
    }

    public func load(importLegacy: Bool = true, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> AppConfiguration {
        if fileManager.fileExists(atPath: configurationURL.path) {
            return try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: configurationURL))
        }
        var configuration = AppConfiguration()
        if importLegacy {
            configuration = importLegacyConfiguration(homeURL: homeURL)
            configuration.didImportLegacyConfiguration = true
        }
        try save(configuration)
        return configuration
    }

    public func save(_ configuration: AppConfiguration) throws {
        var normalized = configuration
        normalized.schemaVersion = 3
        normalized.defaultPaths = Array(unique(configuration.defaultPaths).prefix(Self.maxDefaultPaths))
        normalized.diskPresets = Array(uniquePresets(configuration.diskPresets).prefix(Self.maxPresets))
        normalized.restorableDiskMounts = uniquePresets(configuration.restorableDiskMounts)
        normalized.recentMetalHUDApps = Array(uniqueRecentApps(configuration.recentMetalHUDApps).prefix(Self.maxRecentMetalHUDApps))
        normalized.favoriteProcessNames = Array(uniqueFavoriteProcessNames(configuration.favoriteProcessNames).prefix(Self.maxFavoriteProcessNames))
        if ![10, 15, 20].contains(normalized.hoYoWaitSeconds) { normalized.hoYoWaitSeconds = 15 }
        normalized.metalHUDOptions = Self.normalizedMetalHUDOptions(normalized.metalHUDOptions)
        try fileManager.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalized).write(to: configurationURL, options: .atomic)
    }

    private func importLegacyConfiguration(homeURL: URL) -> AppConfiguration {
        var result = AppConfiguration()
        let defaultFile = homeURL.appendingPathComponent("Library/Disk Setup/default_paths.txt")
        let importedPaths = readLines(defaultFile).compactMap { try? InputValidation.normalizedAbsolutePath($0, home: homeURL.path) }
        result.defaultPaths = Array(unique(importedPaths).prefix(Self.maxDefaultPaths))

        let helperDirectory = homeURL.appendingPathComponent("Library/Application Support/DiskUtilHelper")
        let identifiers = readLines(helperDirectory.appendingPathComponent("presetDiskIdentifiers.txt"))
            .filter(InputValidation.diskIdentifier)
        let mappingPairs: [(String, String)] = readLines(helperDirectory.appendingPathComponent("presetMappings.txt")).compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let identifier = String(line[..<separator])
            let path = String(line[line.index(after: separator)...])
            guard InputValidation.diskIdentifier(identifier), let normalized = try? InputValidation.normalizedAbsolutePath(path, home: homeURL.path) else { return nil }
            return (identifier, normalized)
        }
        let mappings = mappingPairs.reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        result.diskPresets = Array(identifiers.prefix(Self.maxPresets)).map { DiskPreset(diskIdentifier: $0, mountPath: mappings[$0]) }
        return result
    }

    private func readLines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static let validAlignments: Set<String> = [
        "topleft", "topcenter", "topright",
        "centerleft", "centered", "centerright",
        "bottomleft", "bottomcenter", "bottomright"
    ]

    private static func normalizedMetalHUDOptions(_ x: MetalHUDOptions) -> MetalHUDOptions {
        var result = x
        result.opacity = min(1.0, max(0.0, x.opacity))
        result.scale = min(1.0, max(0.0, x.scale))
        if let px = result.positionX, px < 0 { result.positionX = nil }
        if let py = result.positionY, py < 0 { result.positionY = nil }
        if let v = result.encoderGpuTimelineFrameCount, v < 0 { result.encoderGpuTimelineFrameCount = nil }
        if let v = result.encoderGpuTimelineSwapDelta, v < 0 { result.encoderGpuTimelineSwapDelta = nil }
        if let v = result.metricTimeout, v < 0 { result.metricTimeout = nil }
        if let v = result.insightTimeout, v < 0 { result.insightTimeout = nil }
        if let v = result.insightReportInterval, v < 0 { result.insightReportInterval = nil }
        if let v = result.rusageUpdateInterval, v < 0 { result.rusageUpdateInterval = nil }
        if let s = result.reportURL, s.isEmpty { result.reportURL = nil }
        if let s = result.configFilePath, s.isEmpty { result.configFilePath = nil }
        if !validAlignments.contains(result.alignment) { result.alignment = "topright" }
        var seenElements = Set<String>()
        result.elements = result.elements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenElements.insert($0).inserted }
        return result
    }

    private func uniquePresets(_ values: [DiskPreset]) -> [DiskPreset] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.diskIdentifier).inserted }
    }

    private func uniqueRecentApps(_ values: [RecentMetalHUDApp]) -> [RecentMetalHUDApp] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.path).inserted }
    }

    private func uniqueFavoriteProcessNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
