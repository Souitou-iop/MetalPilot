import Foundation
import Testing
@testable import MacGameToolboxCore

@Test func pathValidationNormalizesAndRejectsRoot() throws {
    #expect(try InputValidation.normalizedAbsolutePath("~/Games", home: "/Users/test") == "/Users/test/Games")
    #expect(throws: ToolboxError.invalidPath("/")) { try InputValidation.normalizedAbsolutePath("/") }
    #expect(InputValidation.diskIdentifier("disk12s3"))
    #expect(!InputValidation.diskIdentifier("disk0"))
}

@Test func legacyConfigurationImportsValues() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configURL = root.appendingPathComponent("new/configuration.json")
    let defaultDirectory = root.appendingPathComponent("Library/Disk Setup")
    let presetDirectory = root.appendingPathComponent("Library/Application Support/DiskUtilHelper")
    try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: presetDirectory, withIntermediateDirectories: true)
    try "/tmp/a\n/tmp/b\n/tmp/a\n/tmp/c\n/tmp/d\n".write(to: defaultDirectory.appendingPathComponent("default_paths.txt"), atomically: true, encoding: .utf8)
    try "disk2s1\ndisk3s1\ninvalid\n".write(to: presetDirectory.appendingPathComponent("presetDiskIdentifiers.txt"), atomically: true, encoding: .utf8)
    try "disk2s1:/tmp/game:bottle\n".write(to: presetDirectory.appendingPathComponent("presetMappings.txt"), atomically: true, encoding: .utf8)

    let store = ConfigurationStore(configurationURL: configURL)
    let configuration = try await store.load(homeURL: root)
    #expect(configuration.didImportLegacyConfiguration)
    #expect(configuration.defaultPaths == ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"])
    #expect(configuration.diskPresets.count == 2)
    #expect(configuration.diskPresets.first?.mountPath == "/tmp/game:bottle")
}

@Test func diskParserExcludesBootDisk() throws {
    let plist: [String: Any] = [
        "AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk0", "Partitions": [["DeviceIdentifier": "disk0s1", "VolumeName": "System", "Size": 10]]],
            ["DeviceIdentifier": "disk4", "Internal": false, "Partitions": [["DeviceIdentifier": "disk4s2", "Content": "Apple_APFS", "APFSVolumes": [["DeviceIdentifier": "disk5s1", "VolumeName": "Games", "Content": "APFS", "MountPoint": "/Volumes/Games", "Size": 1234]]]]]
        ]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let volumes = try DiskService.parseVolumes(data, excludingWholeDisk: "disk0")
    #expect(volumes.map(\.id) == ["disk5s1"])
    #expect(volumes.first?.mountPoint == "/Volumes/Games")
}

@Test func configurationRoundTripsHostnameBackupAndSpecialPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.defaultPaths = ["/tmp/Game Bottle's Data"]
    configuration.hostnameBackup = HostnameBackup(computerName: "Iven Mac", hostName: "iven-mac", localHostName: "iven-mac")
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded == configuration)
    #expect(try InputValidation.normalizedAbsolutePath("/tmp/Game Bottle's Data") == "/tmp/Game Bottle's Data")
}

@Test func olderConfigurationDefaultsAutomaticMountRestorationToOff() throws {
    let data = Data(#"{"schemaVersion":1,"diskPresets":[{"diskIdentifier":"disk4s1","mountPath":"/tmp/Games"}]}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(!configuration.automaticallyRestoreMountsOnLaunch)
    #expect(configuration.restorableDiskMounts.isEmpty)
    #expect(configuration.recentMetalHUDApps.isEmpty)
    #expect(configuration.hoYoWaitSeconds == 15)
    #expect(configuration.excludesSensitiveCacheFiles)
    #expect(configuration.diskPresets.first?.diskIdentifier == "disk4s1")
}

@Test func configurationRoundTripsAutomaticMountRestorationState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.automaticallyRestoreMountsOnLaunch = true
    configuration.restorableDiskMounts = [DiskPreset(diskIdentifier: "disk8s1", mountPath: "/tmp/Games")]
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.automaticallyRestoreMountsOnLaunch)
    #expect(loaded.restorableDiskMounts == configuration.restorableDiskMounts)
    #expect(loaded.schemaVersion == 3)
}

@Test func configurationPreservesAllRestorableMounts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.restorableDiskMounts = (1...1_000).map {
        DiskPreset(diskIdentifier: "disk\($0)s1", mountPath: "/tmp/Games-\($0)")
    }

    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)

    #expect(DiskService.maximumBatchMounts == Int.max)
    #expect(loaded.restorableDiskMounts.count == configuration.restorableDiskMounts.count)
    #expect(loaded.restorableDiskMounts.first?.diskIdentifier == "disk1s1")
    #expect(loaded.restorableDiskMounts.last?.diskIdentifier == "disk1000s1")
}

@Test func configurationPreservesAllDefaultPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.defaultPaths = (1...1_000).map { "/tmp/Games-\($0)" }

    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)

    #expect(ConfigurationStore.maxDefaultPaths == Int.max)
    #expect(loaded.defaultPaths.count == configuration.defaultPaths.count)
    #expect(loaded.defaultPaths.first == "/tmp/Games-1")
    #expect(loaded.defaultPaths.last == "/tmp/Games-1000")
}

@Test func automaticMountMatchingPrefersStableVolumeUUIDAndFallsBackToIdentifier() {
    let oldIdentifier = DiskPreset(diskIdentifier: "disk4s1", volumeUUID: "VOLUME-UUID", mountPath: "/tmp/Games")
    let renumberedVolume = DiskVolume(id: "disk8s2", volumeUUID: "volume-uuid", name: "Games", fileSystem: "apfs", mountPoint: nil, size: 1, wholeDisk: "disk8", isInternal: false)
    #expect(DiskService.matchingVolume(for: oldIdentifier, in: [renumberedVolume])?.id == "disk8s2")

    let legacyPreset = DiskPreset(diskIdentifier: "disk4s1", mountPath: "/tmp/Games")
    let legacyVolume = DiskVolume(id: "disk4s1", name: "Games", fileSystem: "apfs", mountPoint: nil, size: 1, wholeDisk: "disk4", isInternal: false)
    #expect(DiskService.matchingVolume(for: legacyPreset, in: [legacyVolume])?.id == "disk4s1")
}

@Test func hostsEditorIsIdempotentAndRollsBack() {
    let original = "127.0.0.1 localhost\n0.0.0.0 example.com\n"
    let domains = ["a.example", "b.example"]
    let enabled = HostsFileEditor.replacingManagedBlock(in: original, domains: domains, enabled: true)
    #expect(HostsFileEditor.replacingManagedBlock(in: enabled, domains: domains, enabled: true) == enabled)
    #expect(HostsFileEditor.replacingManagedBlock(in: enabled, domains: domains, enabled: false) == original)
}

@Test func hoYoDomainsIncludeAllLaunchAssistanceEndpoints() {
    let expectedDomains = [
        "globaldp-prod-cn01.juequling.com",
        "globaldp-prod-cn02.juequling.com",
        "globaldp-prod-os01.zenlesszonezero.com",
        "globaldp-prod-os02.zenlesszonezero.com",
    ]
    #expect(expectedDomains.allSatisfy(GamingService.hoyoDomains.contains))
}

@Test func processParserFiltersCrossOver() {
    let text = "  100 1 1.5 /Applications/CrossOver 25.app/Contents/MacOS/CrossOver\n  110 100 0.5 /Applications/CrossOver 25.app/Contents/SharedSupport/CrossOver/bin/cxoffice\n  120 110 3.0 /Applications/CrossOver 25.app/Contents/SharedSupport/CrossOver/bin/wine64-preloader\n  200 1 2.0 /usr/local/bin/wine game.exe\n  300 1 0.0 unrelated"
    let processes = GamingService.parseProcessTable(text)
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: false).map(\.pid) == [120, 200])
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: true).map(\.pid) == [100, 110, 120])
}

@Test func processParserFindsDetachedCrossOverWineServices() {
    let text = "  3949 1 0.1 C:\\windows\\system32\\winedevice.exe\n  3950 1 0.2 C:\\windows\\system32\\wineserver.exe"
    let processes = GamingService.parseProcessTable(text)
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: true).map(\.pid) == [3949, 3950])
}

@Test func processParserReadsCPUUsageAndSortsDescending() {
    let text = "  100 1 18.7 /Applications/Game.app/Contents/MacOS/Game\n  101 1 75.2 /Applications/Launcher.app/Contents/MacOS/Launcher\n  102 1 18.7 /Applications/Another.app/Contents/MacOS/Another"
    let processes = GamingService.parseProcessTable(text)

    #expect(processes.map(\.cpuUsage) == [18.7, 75.2, 18.7])
    // Equal usage falls back to command, then PID for a stable order.
    #expect(GamingService.sortedRunningProcesses(processes).map(\.pid) == [101, 102, 100])
}

@Test func processParserFallsBackToZeroForMissingOrInvalidCPUUsage() {
    let text = "  100 1 invalid /Applications/Game.app/Contents/MacOS/Game\n  101 1 /Applications/Legacy.app/Contents/MacOS/Legacy"
    let processes = GamingService.parseProcessTable(text)

    // Three-column legacy rows and unparsable CPU columns both degrade to 0.
    #expect(processes.map(\.cpuUsage) == [0, 0])
    #expect(processes.map(\.command) == [
        "/Applications/Game.app/Contents/MacOS/Game",
        "/Applications/Legacy.app/Contents/MacOS/Legacy"
    ])
}

@Test func processSortingIsStableForIdenticalUsageAndCommand() {
    let processes = [
        SystemProcess(pid: 300, parentPID: 1, command: "/usr/bin/shared", cpuUsage: 5),
        SystemProcess(pid: 200, parentPID: 1, command: "/usr/bin/shared", cpuUsage: 0),
        SystemProcess(pid: 100, parentPID: 1, command: "/usr/bin/shared", cpuUsage: 5)
    ]

    #expect(GamingService.sortedRunningProcesses(processes).map(\.pid) == [100, 300, 200])
}

@Test func processSearchMatchesCommandDirectoryAndPID() {
    let process = SystemProcess(
        pid: 9527,
        parentPID: 1,
        command: "X6Game",
        applicationPath: "/Applications/无限暖暖.app"
    )

    #expect(process.matches(searchText: "无限暖暖"))
    #expect(process.matches(searchText: "x6game"))
    #expect(process.matches(searchText: "9527"))
    #expect(!process.matches(searchText: "unrelated"))
    #expect(process.locationPath == "/Applications/无限暖暖.app")
    #expect(process.displayName == "X6Game")
}

@Test func processSearchUsesAppBundlePathEmbeddedInCommand() {
    let process = SystemProcess(
        pid: 9528,
        parentPID: 1,
        command: "/Applications/无限暖暖.app/Contents/MacOS/X6Game -fullscreen"
    )

    #expect(process.matches(searchText: "无限暖暖"))
    #expect(process.locationPath == "/Applications/无限暖暖.app")
    #expect(process.displayName == "X6Game")
}

@Test func favoriteProcessMatchingRequiresExactCaseSensitiveDisplayName() {
    let processes = [
        SystemProcess(pid: 10, parentPID: 1, command: "X6Game"),
        SystemProcess(pid: 11, parentPID: 1, command: "x6game"),
        SystemProcess(pid: 12, parentPID: 1, command: "/Applications/无限暖暖.app/Contents/MacOS/X6Game -fullscreen"),
        SystemProcess(pid: 13, parentPID: 1, command: "X6GameHelper")
    ]

    #expect(GamingService.matchingFavoriteProcesses(processes, favoriteNames: ["X6Game"]).map(\.pid) == [10, 12])
    #expect(GamingService.matchingFavoriteProcesses(processes, favoriteNames: ["x6game"]).map(\.pid) == [11])
    #expect(GamingService.matchingFavoriteProcesses(processes, favoriteNames: []).isEmpty)
}

@Test func volumeInfoFilteringUsesPhysicalBootStoresAndKeepsUnmountedExternalVolumes() {
    let boot: [String: Any] = [
        "ParentWholeDisk": "disk3",
        "DeviceIdentifier": "disk3s3s1",
        "BooterDeviceIdentifier": "disk3s4",
        "RecoveryDeviceIdentifier": "disk3s5",
        "APFSVolumeGroupID": "SYSTEM-GROUP",
        "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]
    ]
    let excluded = DiskService.systemWholeDisks(from: boot)
    #expect(excluded == ["disk0", "disk3"])

    let external: [String: Any] = [
        "DeviceIdentifier": "disk8s1", "ParentWholeDisk": "disk8", "WholeDisk": false,
        "VolumeName": "Games", "FilesystemType": "exfat", "MountPoint": "", "TotalSize": 2_000,
        "Internal": false
    ]
    #expect(DiskService.parseVolumeInfo(external, bootInfo: boot)?.id == "disk8s1")

    var system = external
    system["DeviceIdentifier"] = "disk3s7"
    system["ParentWholeDisk"] = "disk3"
    system["APFSVolumeGroupID"] = "USER-CREATED-GROUP"
    #expect(DiskService.parseVolumeInfo(system, bootInfo: boot)?.id == "disk3s7")

    var systemGroupVolume = system
    systemGroupVolume["APFSVolumeGroupID"] = "SYSTEM-GROUP"
    #expect(DiskService.parseVolumeInfo(systemGroupVolume, bootInfo: boot) == nil)

    var cryptex = external
    cryptex["MountPoint"] = "/private/var/run/com.apple.security.cryptexd/mnt/toolchain"
    #expect(DiskService.parseVolumeInfo(cryptex, bootInfo: boot) == nil)
}

actor RecordingPrivilegedOperator: PrivilegedOperating {
    private(set) var operations: [PrivilegedOperation] = []
    func perform(_ operation: PrivilegedOperation) async throws { operations.append(operation) }
}

actor RecordingCommandRunner: CommandRunning {
    private(set) var calls: [(String, [String])] = []

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append((executable, arguments))
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

@Test func perAppMetalHUDLaunchUsesScopedEnvironment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(applicationPath: application.path)

    let calls = await runner.calls
    let openCall = try #require(calls.first(where: { $0.0 == "/usr/bin/open" }))
    let args = openCall.1
    #expect(args.contains("MTL_HUD_ENABLED=1"))
    #expect(args.contains("MTL_HUD_SCALE=0.2"))
    #expect(args.contains("MTL_HUD_ALIGNMENT=topright"))
    #expect(args.contains("MTL_HUD_OPACITY=1"))
}

@Test func metalHUDOptionsRoundTripAndClampsOpacity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.metalHUDOptions = MetalHUDOptions(
        opacity: 1.5,
        scale: 1.4,
        alignment: "bogus",
        positionX: -10,
        positionY: 20,
        elements: ["fps", "gputime", "fps", ""],
        logEnabled: true,
        shaderLogEnabled: true,
        encoderGpuTimelineFrameCount: -2,
        metricTimeout: -5,
        reportURL: "",
        configFilePath: ""
    )
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.metalHUDOptions.opacity == 1.0)
    #expect(loaded.metalHUDOptions.scale == 1.0)
    #expect(loaded.metalHUDOptions.alignment == "topright")
    #expect(loaded.metalHUDOptions.positionX == nil)
    #expect(loaded.metalHUDOptions.positionY == 20)
    #expect(loaded.metalHUDOptions.elements == ["fps", "gputime"])
    #expect(loaded.metalHUDOptions.logEnabled)
    #expect(loaded.metalHUDOptions.shaderLogEnabled)
    #expect(loaded.metalHUDOptions.encoderGpuTimelineFrameCount == nil)
    #expect(loaded.metalHUDOptions.metricTimeout == nil)
    #expect(loaded.metalHUDOptions.configFilePath == nil)
    #expect(loaded.metalHUDOptions.reportURL == nil)
}

@Test func metalHUDOptionsDefaultsWhenMissing() throws {
    let data = Data(#"{"schemaVersion":3}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(configuration.metalHUDOptions == MetalHUDOptions())
    #expect(configuration.metalHUDOptions.opacity == 1.0)
    #expect(configuration.metalHUDOptions.scale == 0.2)
    #expect(configuration.metalHUDOptions.alignment == "topright")
    #expect(configuration.metalHUDOptions.positionX == nil)
    #expect(configuration.metalHUDOptions.positionY == nil)
    #expect(configuration.metalHUDOptions.elements.isEmpty)
    #expect(!configuration.metalHUDOptions.logEnabled)
    #expect(!configuration.metalHUDOptions.shaderLogEnabled)
    #expect(!configuration.metalHUDOptions.encoderTimingEnabled)
    #expect(configuration.metalHUDOptions.encoderGpuTimelineFrameCount == nil)
    #expect(configuration.metalHUDOptions.encoderGpuTimelineSwapDelta == nil)
    #expect(!configuration.metalHUDOptions.showZeroMetrics)
    #expect(!configuration.metalHUDOptions.showMetricsRange)
    #expect(configuration.metalHUDOptions.metricTimeout == nil)
    #expect(!configuration.metalHUDOptions.insightsEnabled)
    #expect(configuration.metalHUDOptions.insightTimeout == nil)
    #expect(configuration.metalHUDOptions.insightReportInterval == nil)
    #expect(configuration.metalHUDOptions.rusageUpdateInterval == nil)
    #expect(configuration.metalHUDOptions.reportURL == nil)
    #expect(!configuration.metalHUDOptions.disableMenuBar)
    #expect(configuration.metalHUDOptions.configFilePath == nil)
}

@Test func perAppMetalHUDLaunchInjectsOptions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(
        applicationPath: application.path,
        options: MetalHUDOptions(
            opacity: 0.6,
            scale: 0.3,
            alignment: "bottomleft",
            elements: ["fps", "gputime"],
            logEnabled: true,
            shaderLogEnabled: false,
            encoderTimingEnabled: true,
            encoderGpuTimelineFrameCount: 8,
            insightsEnabled: true,
            disableMenuBar: true
        )
    )

    let calls = await runner.calls
    let openCall = try #require(calls.first(where: { $0.0 == "/usr/bin/open" }))
    let arguments = openCall.1
    #expect(arguments.contains("MTL_HUD_ENABLED=1"))
    #expect(arguments.contains("MTL_HUD_OPACITY=0.6"))
    #expect(arguments.contains("MTL_HUD_SCALE=0.3"))
    #expect(arguments.contains("MTL_HUD_ALIGNMENT=bottomleft"))
    #expect(arguments.contains("MTL_HUD_ELEMENTS=fps,gputime"))
    #expect(arguments.contains("MTL_HUD_LOG_ENABLED=1"))
    #expect(arguments.contains("MTL_HUD_ENCODER_TIMING_ENABLED=1"))
    #expect(arguments.contains("MTL_HUD_INSIGHTS_ENABLED=1"))
    #expect(arguments.contains("MTL_HUD_DISABLE_MENU_BAR=1"))
    #expect(arguments.contains("MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT=8"))
    #expect(!arguments.contains(where: { $0.hasPrefix("MTL_HUD_LOG_SHADER_ENABLED=") }))
    #expect(!arguments.contains(where: { $0.hasPrefix("MTL_HUD_POSITION_X=") }))
    #expect(!arguments.contains(where: { $0.hasPrefix("MTL_HUD_METRIC_TIMEOUT=") }))
}

@Test func perAppMetalHUDLaunchDefaultsInjectsConfiguredStyles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(applicationPath: application.path, options: MetalHUDOptions())

    let calls = await runner.calls
    let openCall = try #require(calls.first(where: { $0.0 == "/usr/bin/open" }))
    let args = openCall.1
    #expect(args.contains("MTL_HUD_ENABLED=1"))
    #expect(args.contains("MTL_HUD_SCALE=0.2"))
    #expect(args.contains("MTL_HUD_ALIGNMENT=topright"))
    #expect(args.contains("MTL_HUD_OPACITY=1"))
}

@Test func globalSetMetalHUDClearsUnusedKeysAndSetsSpecifiedOptions() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    let options = MetalHUDOptions(
        opacity: 0.8,
        scale: 0.3,
        alignment: "topleft",
        elements: ["fps", "gputime"]
    )
    try await service.setMetalHUD(enabled: true, options: options)

    let calls = await runner.calls
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_ENABLED", "1"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_OPACITY", "0.8"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_SCALE", "0.3"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_ALIGNMENT", "topleft"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_ELEMENTS", "fps,gputime"] }))
    // Keys not specified should be unset
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_POSITION_X"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_LOG_ENABLED"] }))
}

@Test func globalSetMetalHUDDisabledUnsetsAllKeys() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.setMetalHUD(enabled: false)

    let calls = await runner.calls
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_ENABLED"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_OPACITY"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_SCALE"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_ALIGNMENT"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["unsetenv", "MTL_HUD_ELEMENTS"] }))
}

@Test func identifyInterferingProcessesCategorizesLaunchersAndWineAndGames() {
    let processes = [
        SystemProcess(pid: 100, parentPID: 1, command: "/Applications/Steam.app/Contents/MacOS/steam_osx"),
        SystemProcess(pid: 101, parentPID: 1, command: "/Applications/CrossOver.app/Contents/MacOS/CrossOver"),
        SystemProcess(pid: 102, parentPID: 1, command: "/Applications/Whisky.app/Contents/MacOS/Whisky"),
        SystemProcess(pid: 103, parentPID: 1, command: "/Applications/Heroic.app/Contents/MacOS/Heroic"),
        SystemProcess(pid: 200, parentPID: 101, command: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineserver -p"),
        SystemProcess(pid: 201, parentPID: 200, command: "C:\\windows\\system32\\winedevice.exe"),
        SystemProcess(pid: 300, parentPID: 100, command: "/Users/demo/Library/Application Support/Steam/steamapps/common/MiSide/MiSide.exe"),
        SystemProcess(pid: 400, parentPID: 1, command: "/Applications/Hades.app/Contents/MacOS/Hades"),
        SystemProcess(pid: 999, parentPID: 1, command: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
        SystemProcess(pid: 998, parentPID: 1, command: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
        SystemProcess(pid: 997, parentPID: 1, command: "/usr/bin/login")
    ]

    let results = GamingService.identifyInterferingProcesses(processes, recentAppPaths: ["/Applications/Hades.app"])

    let steam = results.first { $0.pid == 100 }
    #expect(steam?.name == "Steam")
    #expect(steam?.category == .launcher)

    let crossover = results.first { $0.pid == 101 }
    #expect(crossover?.name == "CrossOver")
    #expect(crossover?.category == .launcher)

    let whisky = results.first { $0.pid == 102 }
    #expect(whisky?.name == "Whisky")
    #expect(whisky?.category == .launcher)

    let heroic = results.first { $0.pid == 103 }
    #expect(heroic?.name == "Heroic Games Launcher")
    #expect(heroic?.category == .launcher)

    let wineserver = results.first { $0.pid == 200 }
    #expect(wineserver?.category == .wineRuntime)

    let winedevice = results.first { $0.pid == 201 }
    #expect(winedevice?.category == .wineRuntime)

    let miside = results.first { $0.pid == 300 }
    #expect(miside?.category == .gameOrApp)

    let hades = results.first { $0.pid == 400 }
    #expect(hades?.category == .gameOrApp)

    // System and Dev tools should be excluded
    let pids = Set(results.map(\.pid))
    #expect(!pids.contains(999))
    #expect(!pids.contains(998))
    #expect(!pids.contains(997))
}

@Test func terminateProcessesSendsSignalsViaRunner() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    let result = await service.terminateProcesses(pids: [1234, 5678], force: false)
    #expect(result.succeeded == [1234, 5678])

    let calls = await runner.calls
    #expect(calls.contains(where: { $0.0 == "/bin/kill" && $0.1 == ["-15", "1234"] }))
    #expect(calls.contains(where: { $0.0 == "/bin/kill" && $0.1 == ["-15", "5678"] }))

    _ = await service.terminateProcess(pid: 9999, force: true)
    let updatedCalls = await runner.calls
    #expect(updatedCalls.contains(where: { $0.0 == "/bin/kill" && $0.1 == ["-9", "9999"] }))
}

actor HostnameRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        switch arguments.last {
        case "ComputerName": return CommandResult(exitCode: 0, standardOutput: Data("MacBook Pro\n".utf8), standardError: Data())
        case "LocalHostName": return CommandResult(exitCode: 0, standardOutput: Data("MacBook-Pro\n".utf8), standardError: Data())
        case "HostName": throw ToolboxError.commandFailed("HostName: not set")
        default: throw ToolboxError.commandFailed("unexpected fixture")
        }
    }
}

@Test func missingHostNameFallsBackToLocalHostName() async throws {
    let service = HostnameService(runner: HostnameRunner(), privileged: RecordingPrivilegedOperator())
    let names = try await service.current()
    #expect(names == HostnameBackup(computerName: "MacBook Pro", hostName: "MacBook-Pro", localHostName: "MacBook-Pro"))
    #expect(InputValidation.computerName(names.computerName))
}

@Test func privilegedHealthCheckRoundTripsThroughCodableRequest() throws {
    let data = try JSONEncoder().encode(PrivilegedRequest.healthCheck)
    let decoded = try JSONDecoder().decode(PrivilegedRequest.self, from: data)
    guard case .healthCheck = decoded else {
        Issue.record("Unexpected request case")
        return
    }
}

@Test func allPrivilegedRequestsRoundTripThroughCodable() throws {
    let requests: [PrivilegedRequest] = [
        .healthCheck,
        .addHoYoHosts,
        .removeHoYoHosts,
        .renice([42, 84]),
        .clearSystemCaches,
        .setHostnames(HostnameBackup(computerName: "steamdeck", hostName: "steamdeck", localHostName: "steamdeck")),
        .createDirectory("/Users/test/Games")
    ]
    for request in requests {
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(PrivilegedRequest.self, from: data) == request)
    }
}

@Test func helperRegistrationStatesChooseExpectedActions() {
    #expect(helperRegistrationDecision(for: .enabled) == .connect)
    #expect(helperRegistrationDecision(for: .notRegistered) == .register)
    #expect(helperRegistrationDecision(for: .requiresApproval) == .requestApproval)
    #expect(helperRegistrationDecision(for: .notFound) == .unavailable)
}

actor RejectingPrivilegedOperator: PrivilegedOperating {
    private(set) var operations: [PrivilegedOperation] = []
    func perform(_ operation: PrivilegedOperation) async throws {
        operations.append(operation)
        throw ToolboxError.authorizationCancelled
    }
}

@Test func cacheClearAuthorizesBeforeDeletingUserFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("keep-me.cache")
    try Data("important".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: root) }

    let privileged = RejectingPrivilegedOperator()
    let service = CacheService(privileged: privileged)
    do {
        _ = try await service.clear(CacheScan(userTargets: [root], systemTargets: [URL(fileURLWithPath: "/Library/Caches")], estimatedBytes: 9))
        Issue.record("Expected authorization failure")
    } catch {
        #expect(error as? ToolboxError == .authorizationCancelled)
    }
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(await privileged.operations == [.healthCheck])
}

@Test func sensitiveCacheExclusionScansAndClearsOnlyUserCachesAndLogs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let logs = root.appendingPathComponent("Library/Logs", isDirectory: true)
    let sensitive = root.appendingPathComponent("Library/Application Support/Game/Caches", isDirectory: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sensitive, withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: caches.appendingPathComponent("user.cache"))
    try Data("log".utf8).write(to: logs.appendingPathComponent("user.log"))
    try Data("keep".utf8).write(to: sensitive.appendingPathComponent("sensitive.cache"))
    defer { try? FileManager.default.removeItem(at: root) }

    let privileged = RecordingPrivilegedOperator()
    let service = CacheService(privileged: privileged)
    let scan = await service.scan(excludingSensitiveFiles: true, homeURL: root)
    #expect(scan.userTargets.map(\.standardizedFileURL.path) == [caches, logs].map(\.standardizedFileURL.path))
    #expect(scan.systemTargets.isEmpty)
    _ = try await service.clear(scan)

    #expect(!FileManager.default.fileExists(atPath: caches.appendingPathComponent("user.cache").path))
    #expect(!FileManager.default.fileExists(atPath: logs.appendingPathComponent("user.log").path))
    #expect(FileManager.default.fileExists(atPath: sensitive.appendingPathComponent("sensitive.cache").path))
    #expect(await privileged.operations.isEmpty)
}

@Test func cacheCleanupContinuesAfterAnInaccessibleEntry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let blocked = root.appendingPathComponent("com.apple.HomeKit")
    let removable = root.appendingPathComponent("removable.cache")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try Data("remove".utf8).write(to: removable)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CacheService(privileged: RecordingPrivilegedOperator()) { url in
        if url.lastPathComponent == blocked.lastPathComponent {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }
    _ = try await service.clear(CacheScan(userTargets: [root], systemTargets: [], estimatedBytes: 6))

    #expect(FileManager.default.fileExists(atPath: blocked.path))
    #expect(!FileManager.default.fileExists(atPath: removable.path))
}

@Test func cacheCleanupPreservesHiddenEntriesAndReportsVisibleResults() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let hidden = caches.appendingPathComponent(".hidden.cache")
    let visible = caches.appendingPathComponent("visible.cache")
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 11).write(to: hidden)
    try Data(repeating: 2, count: 7).write(to: visible)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CacheService(privileged: RecordingPrivilegedOperator()) { url in
        if url.lastPathComponent == hidden.lastPathComponent {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }
    let scan = await service.scan(homeURL: root)
    #expect(scan.estimatedBytes >= 7)

    let result = try await service.clear(scan)
    #expect(result.removedCount == 1)
    #expect(result.failedItems.isEmpty)
    #expect(FileManager.default.fileExists(atPath: hidden.path))
    #expect(!FileManager.default.fileExists(atPath: visible.path))
}

@Test func incompleteScanIsReportedAndClearStillRemovesUserTargets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let logs = root.appendingPathComponent("Library/Logs", isDirectory: true)
    let blocked = caches.appendingPathComponent("protected", isDirectory: true)
    let removable = logs.appendingPathComponent("user.log")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: blocked.appendingPathComponent("protected.cache"))
    try Data("log".utf8).write(to: removable)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CacheService(privileged: RecordingPrivilegedOperator()) { url in
        if ["protected", "protected.cache"].contains(url.lastPathComponent) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }

    let clean = await service.scan(excludingSensitiveFiles: true, homeURL: root)
    #expect(clean.inaccessibleTargets.isEmpty)

    // A readable user target where one entry cannot be removed still clears the rest and reports the failure.
    let partial = try await service.clear(CacheScan(userTargets: [blocked], systemTargets: [], estimatedBytes: 0))
    #expect(partial.removedCount == 0)
    #expect(partial.failedItems.map(\.path.lastPathComponent) == ["protected.cache"])
    #expect(FileManager.default.fileExists(atPath: blocked.appendingPathComponent("protected.cache").path))

    // A scan that could not read a directory is reported to the caller rather than silently under-counted.
    let incomplete = CacheScan(userTargets: [blocked], systemTargets: [], estimatedBytes: 0, inaccessibleTargets: [CacheScanIssue(path: blocked, reason: "Directory contents could not be read")])
    #expect(!incomplete.inaccessibleTargets.isEmpty)
    #expect(incomplete.inaccessibleTargets.first?.path == blocked)
    #expect(FileManager.default.fileExists(atPath: removable.path))
}

@Test func cacheScanReportsInaccessibleTargetsAndKeepsReadableContent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let missing = root.appendingPathComponent("Library/Logs", isDirectory: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 5).write(to: caches.appendingPathComponent("user.cache"))
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CacheService(privileged: RecordingPrivilegedOperator())
    let scan = await service.scan(excludingSensitiveFiles: true, homeURL: root)
    // Only existing targets are scanned; the missing Logs directory is dropped, never counted as an issue.
    #expect(scan.userTargets.map(\.lastPathComponent) == ["Caches"])
    #expect(scan.inaccessibleTargets.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    #expect(scan.estimatedBytes >= 5)
}

@Test func configurationNormalizesNewVersionThreePreferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.hoYoWaitSeconds = 99
    configuration.doesNotRaiseHoYoPriority = true
    configuration.excludesSensitiveCacheFiles = false
    configuration.recentMetalHUDApps = [
        RecentMetalHUDApp(path: "/Applications/A.app", displayName: "A"),
        RecentMetalHUDApp(path: "/Applications/A.app", displayName: "Duplicate")
    ]
    configuration.favoriteProcessNames = [" X6Game ", "", "X6Game", "x6game"]
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.schemaVersion == 3)
    #expect(loaded.hoYoWaitSeconds == 15)
    #expect(loaded.doesNotRaiseHoYoPriority)
    #expect(!loaded.excludesSensitiveCacheFiles)
    #expect(loaded.recentMetalHUDApps == [RecentMetalHUDApp(path: "/Applications/A.app", displayName: "A")])
    // Favorites are trimmed, de-duplicated and case-sensitive.
    #expect(loaded.favoriteProcessNames == ["X6Game", "x6game"])
}

@Test func favoriteProcessNamesAreCappedAtSixtyFour() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.favoriteProcessNames = (0..<80).map { "Process\($0)" }
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.favoriteProcessNames.count == ConfigurationStore.maxFavoriteProcessNames)
    #expect(loaded.favoriteProcessNames.first == "Process0")
}

@Test func schemaThreeConfigurationWithoutPhaseTwoFieldsStillLoads() throws {
    // A schema 3 payload written before this phase must not fail to decode, and
    // the new fields must fall back to their opt-out defaults.
    let data = Data(#"{"schemaVersion":3,"hoYoWaitSeconds":10,"excludesSensitiveCacheFiles":true,"languagePreference":"en"}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(configuration.schemaVersion == 3)
    #expect(configuration.hoYoWaitSeconds == 10)
    #expect(configuration.favoriteProcessNames.isEmpty)
    #expect(!configuration.doesNotRaiseHoYoPriority)
}

@Test func hoyoOptOutSkipsReniceButKeepsHostsRestore() {
    let wineProcesses: [(pid: Int32, command: String)] = [(42, "wine64-preloader"), (84, "wineserver")]

    // Opt-out returns no PIDs, so the assistant restores hosts without renice.
    #expect(GamingService.hoYoPriorityPIDs(doesNotRaisePriority: true, wineProcesses: wineProcesses) == nil)
    // Normal path still returns every detected Wine PID for the existing level.
    #expect(GamingService.hoYoPriorityPIDs(doesNotRaisePriority: false, wineProcesses: wineProcesses) == [42, 84])
    #expect(GamingService.hoYoPriorityPIDs(doesNotRaisePriority: false, wineProcesses: [])?.isEmpty == true)
}

@Test func processRunnerDrainsOutputLargerThanPipeBuffer() async throws {
    let result = try await ProcessCommandRunner().run("/usr/bin/seq", arguments: ["1", "30000"])
    #expect(result.outputString.hasPrefix("1\n2\n3"))
    #expect(result.outputString.hasSuffix("30000"))
    #expect(result.standardOutput.count > 65_536)
}

actor MockRunner: CommandRunning {
    var calls: [[String]] = []
    var failingMount: String?
    var staleInfoReads: [String: Int]
    var reportedMountPaths: [String: String]

    init(failingMount: String? = nil, staleInfoReads: [String: Int] = [:], reportedMountPaths: [String: String] = [:]) {
        self.failingMount = failingMount
        self.staleInfoReads = staleInfoReads
        self.reportedMountPaths = reportedMountPaths
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append(arguments)
        if arguments.contains("mount"), let failingMount, arguments.contains(where: { $0.contains(failingMount) }) {
            throw ToolboxError.commandFailed("fixture failure")
        }
        if arguments.first == "info" {
            let identifier = arguments.last ?? ""
            if let remaining = staleInfoReads[identifier], remaining > 0 {
                staleInfoReads[identifier] = remaining - 1
                let data = try PropertyListSerialization.data(fromPropertyList: ["MountPoint": "/Volumes/Stale"], format: .xml, options: 0)
                return CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
            }
            let path = reportedMountPaths[identifier]
                ?? calls.last(where: { $0.contains("-mountPoint") && $0.last?.contains(identifier) == true })?.dropFirst(2).first
                ?? "/Volumes/Test"
            let data = try PropertyListSerialization.data(fromPropertyList: ["MountPoint": path], format: .xml, options: 0)
            return CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
        }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

@Test func batchMountRollsBackEarlierVolumeOnFailure() async {
    let runner = MockRunner(failingMount: "disk5s1")
    let service = DiskService(runner: runner)
    _ = await service.mountBatch([("disk4s1", "/tmp/one"), ("disk5s1", "/tmp/two")])
    let calls = await runner.calls
    #expect(calls.contains(["mount", "disk4s1"]))
    #expect(calls.filter { $0 == ["unmount", "disk5s1"] }.count == 2)
}

@Test func mountWaitsForDiskutilInfoToReflectTheRequestedPath() async throws {
    let runner = MockRunner(staleInfoReads: ["disk4s1": 2])
    let service = DiskService(runner: runner)

    try await service.mount("disk4s1", at: "/tmp/delayed")

    let calls = await runner.calls
    #expect(calls.filter { $0 == ["info", "-plist", "disk4s1"] }.count == 3)
}

@Test func mountAcceptsEquivalentCanonicalMountPaths() async throws {
    let mountPath = "/tmp/mac-game-toolbox-canonical-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: mountPath) }
    let runner = MockRunner(reportedMountPaths: ["disk4s1": "/private\(mountPath)"])
    let service = DiskService(runner: runner)

    try await service.mount("disk4s1", at: mountPath)
}

@Test func batchMountProcessesAllVolumesWithoutANumericalCap() async {
    let runner = MockRunner()
    let service = DiskService(runner: runner)
    let assignments = (1...1_000).map { ("disk\($0)s1", "/tmp/volume-\($0)") }

    let results = await service.mountBatch(assignments)

    #expect(results.count == assignments.count)
    #expect(results["disk4s1"] != nil)
    #expect(results["disk1000s1"] != nil)
}

@Test func gameSaveFinderScansAppDataAndSavedGames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bottlePath = root.appendingPathComponent("TestBottle")
    let appDataLocal = bottlePath.appendingPathComponent("drive_c/users/crossover/AppData/Local/EldenRing")
    let savedGames = bottlePath.appendingPathComponent("drive_c/users/crossover/Saved Games/Cyberpunk2077")
    try FileManager.default.createDirectory(at: appDataLocal, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: savedGames, withIntermediateDirectories: true)
    try "save data 1".write(to: appDataLocal.appendingPathComponent("save.dat"), atomically: true, encoding: .utf8)
    try "save data 2".write(to: savedGames.appendingPathComponent("manualsave_0.sav"), atomically: true, encoding: .utf8)

    defer { try? FileManager.default.removeItem(at: root) }

    let finder = GameSaveFinderService()
    let bottle = WineBottle(name: "TestBottle", type: .crossover, path: bottlePath.path)
    let saves = await finder.scanSaveDirectories(in: bottle)

    #expect(saves.count == 2)
    let gameNames = Set(saves.map(\.gameName))
    #expect(gameNames.contains("EldenRing"))
    #expect(gameNames.contains("Cyberpunk2077"))
}

@Test func perAppProfilesRoundTripThroughConfiguration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var config = AppConfiguration()
    let customOpts = MetalHUDOptions(scale: 0.8, alignment: "bottomleft", elements: ["fps", "gputime"])
    config.perAppHUDProfiles = [
        PerAppMetalHUDProfile(appPath: "/Applications/Cyberpunk.app", appName: "Cyberpunk", options: customOpts)
    ]
    try await store.save(config)

    let loaded = try await store.load(homeURL: root)
    #expect(loaded.perAppHUDProfiles.count == 1)
    #expect(loaded.perAppHUDProfiles.first?.appPath == "/Applications/Cyberpunk.app")
    #expect(loaded.perAppHUDProfiles.first?.options.scale == 0.8)
    #expect(loaded.perAppHUDProfiles.first?.options.alignment == "bottomleft")
}

@Test func performanceSnapshotGeneratesValidMarkdown() async throws {
    let snapshotService = PerformanceSnapshotService()
    let opts = MetalHUDOptions(scale: 0.5, alignment: "topright", elements: ["fps", "memory"])
    let report = await snapshotService.generateSnapshotReport(metalHUDOptions: opts, activeApp: "MiSide.app")

    #expect(report.contains("# MetalPilot - 性能诊断快照报告"))
    #expect(report.contains("MiSide.app"))
    #expect(report.contains("MTL_HUD_ENABLED=1"))
    #expect(report.contains("0.50"))
    #expect(report.contains("Apple Silicon"))
}

@Test func wineBottleTypesHaveAppropriateIcons() {
    #expect(WineBottleType.crossover.iconName == "shippingbox.fill")
    #expect(WineBottleType.whisky.iconName == "wineglass.fill")
    #expect(WineBottleType.heroic.iconName == "gamecontroller.fill")
    #expect(WineBottleType.customWine.iconName == "folder.fill.badge.gearshape")
}

@Test func systemHealthInspectorGathersDiagnosticItems() async throws {
    let inspector = SystemHealthInspector()
    let report = await inspector.performFullHealthCheck(privileged: nil)

    #expect(!report.items.isEmpty)
    let names = report.items.map(\.nameZh)
    #expect(names.contains("特权辅助服务 (Privileged Helper)"))
    #expect(names.contains("Metal HUD 注入环境"))
    #expect(names.contains("缓存与本地存储访问权限"))
}

@Test func healthReportModelsRoundTrip() throws {
    let item = HealthCheckItem(nameZh: "测试服务", nameEn: "Test Service", nameJa: "テストサービス", status: .healthy, detailZh: "一切正常", detailEn: "All good", detailJa: "すべて正常")
    let report = SystemHealthReport(items: [item], legacyHelpersFound: [], checkedAt: Date())
    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(SystemHealthReport.self, from: data)

    #expect(decoded.allHealthy)
    #expect(decoded.items.count == 1)
    #expect(decoded.items.first?.nameZh == "测试服务")
    #expect(decoded.items.first?.nameJa == "テストサービス")
    #expect(decoded.items.first?.detailJa == "すべて正常")
}

@Test func languagePreferenceEnumAndConfigurationRoundTrip() async throws {
    #expect(AppLanguagePreference.allCases.count == 4)
    #expect(AppLanguagePreference.system.rawValue == "system")
    #expect(AppLanguagePreference.chinese.rawValue == "zh-Hans")
    #expect(AppLanguagePreference.english.rawValue == "en")
    #expect(AppLanguagePreference.japanese.rawValue == "ja")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var config = AppConfiguration()
    config.languagePreference = .japanese
    try await store.save(config)

    let loaded = try await store.load(homeURL: root)
    #expect(loaded.languagePreference == .japanese)
}

@Test func navigationCategoryProvidesJapaneseTitles() {
    #expect(NavigationCategory.overview.titleJa == "概要とステータス")
    #expect(NavigationCategory.frameGen.titleJa == "超解像と補フレーム")
    #expect(NavigationCategory.metalHUD.titleJa == "Metal HUD 設定")
    #expect(NavigationCategory.gameBoost.titleJa == "ゲーム高速化・起動")
    #expect(NavigationCategory.storage.titleJa == "ストレージとセーブ")
    #expect(NavigationCategory.system.titleJa == "システムと設定")
    #expect(NavigationCategory.about.titleJa == "情報と謝辞")
}

@Test func scalingModelsAndSettingsRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var config = AppConfiguration()
    config.scalingSettings = ScalingSettings(
        enabled: true,
        frameGenMode: .extrapolation3x,
        renderScale: .scale67,
        qualityProfile: .ultra,
        aaMode: .smaa,
        casEnabled: true,
        sharpness: 0.75,
        sceneCutDetectionEnabled: true,
        dynamicResolutionScaling: true,
        syntheticCursorEnabled: true,
        hudEnabled: true,
        targetWindowBundleID: "com.example.game",
        targetWindowName: "Demo Game"
    )
    try await store.save(config)

    let loaded = try await store.load(homeURL: root)
    #expect(loaded.scalingSettings.frameGenMode == .extrapolation3x)
    #expect(loaded.scalingSettings.frameGenMode.isExtrapolation)
    #expect(loaded.scalingSettings.frameGenMode.multiplier == 3)
    #expect(loaded.scalingSettings.renderScale == .scale67)
    #expect(loaded.scalingSettings.aaMode == .smaa)
    #expect(ScalingAAMode.allCases.contains(.taa))
    #expect(ScalingAAMode.taa.titleEn == "TAA (Temporal)")
    #expect(loaded.scalingSettings.sharpness == 0.75)
    #expect(loaded.scalingSettings.targetWindowName == "Demo Game")
}

@Test func privilegedHelperConstantsValidateCurrentLaunchDaemonPlist() {
    let validPlist: [String: Any] = [
        "Label": "macgametoolbox.helper",
        "ProgramArguments": ["/Library/PrivilegedHelperTools/macgametoolbox.helper"],
        "AssociatedBundleIdentifiers": ["com.iven.macgametoolbox"],
        "MachServices": ["macgametoolbox.helper": true]
    ]
    #expect(PrivilegedHelperConstants.isPlistCurrent(validPlist) == true)

    // Legacy plist with RunAtLoad=true must be rejected so it gets upgraded
    var legacyPlist = validPlist
    legacyPlist["RunAtLoad"] = true
    #expect(PrivilegedHelperConstants.isPlistCurrent(legacyPlist) == false)

    // Missing MachServices must be rejected
    var noMachServices = validPlist
    noMachServices.removeValue(forKey: "MachServices")
    #expect(PrivilegedHelperConstants.isPlistCurrent(noMachServices) == false)

    // Wrong service name must be rejected
    var wrongLabel = validPlist
    wrongLabel["Label"] = "wrong.service"
    #expect(PrivilegedHelperConstants.isPlistCurrent(wrongLabel) == false)

    // Wrong bundle identifier must be rejected
    var wrongBundle = validPlist
    wrongBundle["AssociatedBundleIdentifiers"] = ["com.wrong.bundle"]
    #expect(PrivilegedHelperConstants.isPlistCurrent(wrongBundle) == false)
}

@Test func bundledLaunchDaemonPlistIsOnDemandAndOmitsRunAtLoad() throws {
    let sourceFileURL = URL(fileURLWithPath: #filePath)
    let repoRoot = sourceFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let plistURL = repoRoot.appendingPathComponent("Config/com.iven.macgametoolbox.helper.plist")
    let data = try Data(contentsOf: plistURL)
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        Issue.record("Failed to parse Config/com.iven.macgametoolbox.helper.plist")
        return
    }

    #expect(plist["RunAtLoad"] == nil)
    #expect(plist["Label"] as? String == PrivilegedHelperConstants.serviceName)
    #expect(plist["ProgramArguments"] as? [String] == [PrivilegedHelperConstants.installedHelperPath])
    #expect(PrivilegedHelperConstants.isPlistCurrent(plist) == true)
}


// MARK: - Stage 3: Imported external Metal HUD presets

actor FailingLaunchCommandRunner: CommandRunning {
    private let failingExecutable: String
    private let failingArgumentsContain: String?
    private(set) var calls: [(String, [String])] = []

    init(failingExecutable: String, failingArgumentsContain: String? = nil) {
        self.failingExecutable = failingExecutable
        self.failingArgumentsContain = failingArgumentsContain
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append((executable, arguments))
        if executable == failingExecutable,
           failingArgumentsContain == nil || arguments.contains(where: { $0.contains(failingArgumentsContain!) }) {
            throw ToolboxError.commandFailed("fixture launch failure")
        }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

@Test func importedHUDPresetParsesValidPropertyList() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let preset = root.appendingPathComponent("my-hud.plist")
    let properties: [String: Any] = [
        "MTL_HUD_ALIGNMENT": "bottomleft",
        "MTL_HUD_ELEMENTS": "fps,gputime",
        "MTL_HUD_ENABLED": true,
        "MTL_HUD_LOG_ENABLED": false,
        "MTL_HUD_OPACITY": 0.5,
        "UNRELATED_KEY": "ignored"
    ]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)

    let environment = try GamingService.metalHUDEnvironment(fromPresetAt: preset.path)
    #expect(environment.contains("MTL_HUD_ALIGNMENT=bottomleft"))
    #expect(environment.contains("MTL_HUD_ELEMENTS=fps,gputime"))
    #expect(environment.contains("MTL_HUD_ENABLED=1"))
    #expect(environment.contains("MTL_HUD_LOG_ENABLED=0"))
    #expect(environment.contains("MTL_HUD_OPACITY=0.5"))
    // Only MTL_HUD_ prefixed keys survive.
    #expect(!environment.contains(where: { $0.hasPrefix("UNRELATED_KEY") }))
}

@Test func importedHUDPresetRejectsCorruptAndUnsupportedValues() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // Corrupt / non-plist payload
    let corrupt = root.appendingPathComponent("corrupt.plist")
    try Data("this is not a plist".utf8).write(to: corrupt)
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: corrupt.path) }

    // Missing file
    let missing = root.appendingPathComponent("missing.plist")
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: missing.path) }

    // Top-level is not a dictionary
    let arrayPlist = root.appendingPathComponent("array.plist")
    try PropertyListSerialization.data(fromPropertyList: ["a", "b"], format: .xml, options: 0).write(to: arrayPlist)
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: arrayPlist.path) }

    // Unsupported value type (a nested array) for an MTL_HUD_ key
    let badValue = root.appendingPathComponent("badvalue.plist")
    try PropertyListSerialization.data(fromPropertyList: ["MTL_HUD_ELEMENTS": ["fps", "gputime"]], format: .xml, options: 0).write(to: badValue)
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: badValue.path) }
}

@Test func importedHUDPresetConvertsLegacyNumericAlignment() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let preset = root.appendingPathComponent("hud.plist")
    let properties: [String: Any] = [
        "MTL_HUD_ALIGNMENT": 18,
        "MTL_HUD_ENABLED": true
    ]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)

    #expect(try GamingService.metalHUDEnvironment(fromPresetAt: preset.path) == ["MTL_HUD_ALIGNMENT=bottomleft", "MTL_HUD_ENABLED=1"])

    // String form of a legacy numeric alignment is also translated.
    let stringPreset = root.appendingPathComponent("hud-string.plist")
    try PropertyListSerialization.data(fromPropertyList: ["MTL_HUD_ALIGNMENT": "10"], format: .xml, options: 0).write(to: stringPreset)
    #expect(try GamingService.metalHUDEnvironment(fromPresetAt: stringPreset.path).contains("MTL_HUD_ALIGNMENT=topleft"))

    // Numeric value without a known alignment mapping falls back to its text form,
    // and other numeric values are passed through as-is.
    let unknownPreset = root.appendingPathComponent("hud-unknown.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["MTL_HUD_ALIGNMENT": 99, "MTL_HUD_POSITION_X": 120] as [String: Any],
        format: .xml,
        options: 0
    ).write(to: unknownPreset)
    let unknownEnv = try GamingService.metalHUDEnvironment(fromPresetAt: unknownPreset.path)
    #expect(unknownEnv.contains("MTL_HUD_ALIGNMENT=99"))
    #expect(unknownEnv.contains("MTL_HUD_POSITION_X=120"))
}

@Test func managedHUDPresetStoreCopiesValidatedFileIntoManagedDirectory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exports/game-hud.plist")
    let managedDirectory = root.appendingPathComponent("managed/MetalHUDPresets")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    let properties: [String: Any] = ["MTL_HUD_ENABLED": true, "MTL_HUD_SCALE": 0.4]
    let data = try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
    try data.write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ManagedHUDPresetStore(directoryURL: managedDirectory)
    let preset = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")

    #expect(preset.path.hasPrefix(managedDirectory.path))
    #expect(preset.displayName == "game-hud")
    #expect(preset.importedAt != nil)
    // Content of the managed copy matches the original byte for byte.
    #expect(try Data(contentsOf: URL(fileURLWithPath: preset.path)) == data)
    // Importing the same source twice does not overwrite the earlier copy.
    let second = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")
    #expect(second.path != preset.path)
    #expect(FileManager.default.fileExists(atPath: preset.path))
}

@Test func managedHUDPresetStoreLeavesNoCopyForInvalidFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exports/broken.plist")
    let managedDirectory = root.appendingPathComponent("managed/MetalHUDPresets")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a plist".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ManagedHUDPresetStore(directoryURL: managedDirectory)
    await #expect(throws: ToolboxError.self) {
        _ = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")
    }
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: managedDirectory.path)) ?? []
    #expect(leftovers.isEmpty)

    // Removing an unknown path is a no-op and must not throw.
    await store.removeManagedPreset(atPath: root.appendingPathComponent("outside.plist").path)
}

@Test func managedHUDPresetRemovalDeletesOnlyManagedCopies() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exports/game-hud.plist")
    let managedDirectory = root.appendingPathComponent("managed/MetalHUDPresets")
    let outside = root.appendingPathComponent("outside.plist")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: ["MTL_HUD_ENABLED": true], format: .xml, options: 0)
    try data.write(to: source)
    try data.write(to: outside)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ManagedHUDPresetStore(directoryURL: managedDirectory)
    let preset = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")
    await store.removeManagedPreset(atPath: preset.path)
    #expect(!FileManager.default.fileExists(atPath: preset.path))
    // A path outside the managed directory must never be deleted.
    await store.removeManagedPreset(atPath: outside.path)
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func recentMetalHUDAppWithImportedPresetRoundTripsAndAcceptsLegacyConfiguration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var config = AppConfiguration()
    let imported = ImportedHUDPreset(path: "/tmp/managed/game-hud.plist", displayName: "game-hud", importedAt: Date(timeIntervalSince1970: 1_700_000_000))
    config.recentMetalHUDApps = [RecentMetalHUDApp(path: "/Applications/Example Game.app", displayName: "Example Game", importedPreset: imported)]
    try await store.save(config)

    let loaded = try await store.load(homeURL: root)
    #expect(loaded.schemaVersion == 3)
    #expect(loaded.recentMetalHUDApps.first?.importedPreset == imported)

    // Legacy schema 3 entry without the new key still decodes, with no preset.
    let legacy = Data(#"{"schemaVersion":3,"recentMetalHUDApps":[{"path":"/Applications/Old.app","displayName":"Old"}]}"#.utf8)
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacy)
    #expect(decoded.recentMetalHUDApps.count == 1)
    #expect(decoded.recentMetalHUDApps.first?.importedPreset == nil)
}

@Test func importedPresetOverridesPerAppOptionsForThatLaunchOnly() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    let preset = root.appendingPathComponent("my-hud.plist")
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    let properties: [String: Any] = [
        "MTL_HUD_ALIGNMENT": 18,
        "MTL_HUD_ELEMENTS": "fps,gputime",
        "MTL_HUD_ENABLED": true
    ]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    // Options that would otherwise be injected; they must NOT appear when a preset is used.
    try await service.launchWithMetalHUD(
        applicationPath: application.path,
        options: MetalHUDOptions(scale: 0.9, alignment: "topright", elements: ["memory"]),
        importedPresetPath: preset.path
    )

    let calls = await runner.calls
    let openCall = try #require(calls.first(where: { $0.0 == "/usr/bin/open" }))
    let args = openCall.1
    #expect(args.prefix(2) == ["-n", "-a"])
    #expect(args.contains("MTL_HUD_ALIGNMENT=bottomleft"))
    #expect(args.contains("MTL_HUD_ELEMENTS=fps,gputime"))
    #expect(args.contains("MTL_HUD_ENABLED=1"))
    // Preset values own the launch: no per-app option values leak in.
    #expect(!args.contains("MTL_HUD_SCALE=0.9"))
    #expect(!args.contains("MTL_HUD_ALIGNMENT=topright"))
    #expect(!args.contains("MTL_HUD_ELEMENTS=memory"))
    // An imported preset must not rewrite the unrelated global profile.
    #expect(!calls.contains(where: { $0.0 == "/bin/launchctl" }))
}

@Test func launchWithMetalHUDStillUsesOpenDashNAndEnvFlags() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(applicationPath: application.path, options: MetalHUDOptions())

    let calls = await runner.calls
    let openCall = try #require(calls.first(where: { $0.0 == "/usr/bin/open" }))
    #expect(openCall.1.prefix(2) == ["-n", "-a"])
    #expect(openCall.1.filter { $0 == "--env" }.count == openCall.1.filter { $0.hasPrefix("MTL_HUD_") }.count)
    // The global scope-setup path is still exercised first.
    #expect(calls.contains(where: { $0.0 == "/bin/launchctl" && $0.1 == ["setenv", "MTL_HUD_ENABLED", "1"] }))
}

@Test func launchWithMetalHUDRejectsBrokenPresetWithoutLaunching() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    let preset = root.appendingPathComponent("broken.plist")
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    try Data("not a plist".utf8).write(to: preset)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    await #expect(throws: ToolboxError.self) {
        try await service.launchWithMetalHUD(applicationPath: application.path, options: MetalHUDOptions(), importedPresetPath: preset.path)
    }
    let calls = await runner.calls
    // A malformed preset must fail before the app is opened.
    #expect(!calls.contains(where: { $0.0 == "/usr/bin/open" }))
}

@Test func singleLaunchFailureSurfacesAsError() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Fails.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = FailingLaunchCommandRunner(failingExecutable: "/usr/bin/open")
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    await #expect(throws: ToolboxError.self) {
        try await service.launchWithMetalHUD(applicationPath: application.path, options: MetalHUDOptions())
    }
}

@Test func batchLaunchReportsPartialFailureWithoutCountingFailuresAsLaunched() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let good = root.appendingPathComponent("Good.app", isDirectory: true)
    let bad = root.appendingPathComponent("Bad.app", isDirectory: true)
    try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = FailingLaunchCommandRunner(failingExecutable: "/usr/bin/open", failingArgumentsContain: "Bad.app")
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    var succeeded: [String] = []
    var failed: [String] = []
    for path in [good.path, bad.path] {
        do {
            try await service.launchWithMetalHUD(applicationPath: path, options: MetalHUDOptions())
            succeeded.append(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
        } catch {
            failed.append(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
        }
    }

    #expect(succeeded == ["Good"])
    #expect(failed == ["Bad"])
}

// MARK: - Stage 3 gap coverage: preset parsing edge cases

@Test func importedHUDPresetExtractsOnlyPrefixedKeysAndConvertsScalarTypes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let preset = root.appendingPathComponent("scalars.plist")
    let properties: [String: Any] = [
        // Non-prefixed keys must be dropped entirely, including near-miss names.
        "mtl_hud_opacity": 0.9,
        "MTLHUD_SCALE": 0.9,
        "MTL_HUDX_SCALE": 0.9,
        "UNRELATED": true,
        // Scalar conversions under the prefix.
        "MTL_HUD_ENABLED": true,
        "MTL_HUD_SHOW_ZERO_METRICS": false,
        "MTL_HUD_POSITION_X": 120,
        "MTL_HUD_OPACITY": 0.5,
        "MTL_HUD_ELEMENTS": "fps,gputime"
    ]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)

    let environment = try GamingService.metalHUDEnvironment(fromPresetAt: preset.path)

    // Exactly the prefixed scalar keys, sorted by key.
    #expect(environment == [
        "MTL_HUD_ELEMENTS=fps,gputime",
        "MTL_HUD_ENABLED=1",
        "MTL_HUD_OPACITY=0.5",
        "MTL_HUD_POSITION_X=120",
        "MTL_HUD_SHOW_ZERO_METRICS=0"
    ])
    // Booleans become 1/0 and integers keep their plain text form.
    #expect(environment.contains("MTL_HUD_SHOW_ZERO_METRICS=0"))
    #expect(environment.contains("MTL_HUD_POSITION_X=120"))
    #expect(!environment.contains("MTL_HUD_POSITION_X=120.0"))
    // Case-sensitive prefixing and near misses are not accepted.
    #expect(!environment.contains(where: { $0.hasPrefix("mtl_hud_") }))
    #expect(!environment.contains(where: { $0.hasPrefix("MTLHUD_") }))
    #expect(!environment.contains(where: { $0.hasPrefix("MTL_HUDX_") }))
}

@Test func importedHUDPresetInsertsEnabledWhenAbsentAndRespectsExplicitValue() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // No MTL_HUD_ENABLED in the source: it is prepended, not appended.
    let implicit = root.appendingPathComponent("implicit.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["MTL_HUD_SCALE": 0.4] as [String: Any],
        format: .xml,
        options: 0
    ).write(to: implicit)
    let implicitEnvironment = try GamingService.metalHUDEnvironment(fromPresetAt: implicit.path)
    #expect(implicitEnvironment == ["MTL_HUD_ENABLED=1", "MTL_HUD_SCALE=0.4"])
    #expect(implicitEnvironment.filter { $0.hasPrefix("MTL_HUD_ENABLED=") }.count == 1)

    // An explicit enabled value is preserved as-is and never duplicated.
    let explicit = root.appendingPathComponent("explicit.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["MTL_HUD_ENABLED": false, "MTL_HUD_SCALE": 0.4] as [String: Any],
        format: .xml,
        options: 0
    ).write(to: explicit)
    let explicitEnvironment = try GamingService.metalHUDEnvironment(fromPresetAt: explicit.path)
    #expect(explicitEnvironment.contains("MTL_HUD_ENABLED=0"))
    #expect(explicitEnvironment.filter { $0.hasPrefix("MTL_HUD_ENABLED=") }.count == 1)
}

@Test func importedHUDPresetRejectsDirectoryEmptyFileAndUnsupportedTypes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    // A directory is not a readable preset, even when it exists.
    let directory = root.appendingPathComponent("preset-dir.plist", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: directory.path) }

    // An empty file is not a valid property list.
    let empty = root.appendingPathComponent("empty.plist")
    try Data().write(to: empty)
    #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: empty.path) }

    // Unsupported scalar-ish types under an MTL_HUD_ key must fail loudly.
    let unsupportedValues: [String: Any] = [
        "data": Data([0x01, 0x02]),
        "date": Date(timeIntervalSince1970: 0)
    ]
    for (name, value) in unsupportedValues {
        let preset = root.appendingPathComponent("unsupported-\(name).plist")
        try PropertyListSerialization.data(
            fromPropertyList: ["MTL_HUD_ELEMENTS": value] as [String: Any],
            format: .xml,
            options: 0
        ).write(to: preset)
        #expect(throws: ToolboxError.self) { _ = try GamingService.metalHUDEnvironment(fromPresetAt: preset.path) }
    }

    // Unsupported values on non-prefixed keys are irrelevant and must not fail the import.
    let unrelated = root.appendingPathComponent("unrelated.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["UNRELATED_BLOB": Data([0x01, 0x02]), "MTL_HUD_SCALE": 0.4] as [String: Any],
        format: .xml,
        options: 0
    ).write(to: unrelated)
    #expect(try GamingService.metalHUDEnvironment(fromPresetAt: unrelated.path) == ["MTL_HUD_ENABLED=1", "MTL_HUD_SCALE=0.4"])
}

@Test func managedHUDPresetStoreValidatesBeforeCreatingManagedDirectory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exports/broken.plist")
    let managedDirectory = root.appendingPathComponent("managed/MetalHUDPresets")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a plist".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ManagedHUDPresetStore(directoryURL: managedDirectory)
    await #expect(throws: ToolboxError.self) {
        _ = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")
    }
    // Validation runs before any filesystem mutation: no managed copy, and the
    // managed directory itself is not created as a side effect of a failed import.
    #expect(!FileManager.default.fileExists(atPath: managedDirectory.path))

    // A missing source is rejected the same way.
    await #expect(throws: ToolboxError.self) {
        _ = try await store.importPreset(from: root.appendingPathComponent("nope.plist"), forApplicationPath: "/Applications/Example Game.app")
    }
    #expect(!FileManager.default.fileExists(atPath: managedDirectory.path))
}

@Test func managedHUDPresetRemovalIgnoresManagedSubdirectoriesAndEmptyPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exports/game-hud.plist")
    let managedDirectory = root.appendingPathComponent("managed/MetalHUDPresets")
    let nestedDirectory = managedDirectory.appendingPathComponent("nested", isDirectory: true)
    let nestedFile = nestedDirectory.appendingPathComponent("inner.plist")
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: ["MTL_HUD_ENABLED": true], format: .xml, options: 0)
    try data.write(to: source)
    try data.write(to: nestedFile)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ManagedHUDPresetStore(directoryURL: managedDirectory)

    // An empty path is a silent no-op.
    await store.removeManagedPreset(atPath: "")
    #expect(FileManager.default.fileExists(atPath: nestedFile.path))

    // A file nested one level inside the managed directory is not a direct managed
    // copy, so removal must leave it (and its parent) untouched.
    await store.removeManagedPreset(atPath: nestedFile.path)
    #expect(FileManager.default.fileExists(atPath: nestedFile.path))
    #expect(FileManager.default.fileExists(atPath: nestedDirectory.path))

    // A sibling directory whose path merely shares the managed directory prefix
    // must never be treated as managed content.
    let prefixTrapDirectory = root.appendingPathComponent("managed/MetalHUDPresets-other", isDirectory: true)
    try FileManager.default.createDirectory(at: prefixTrapDirectory, withIntermediateDirectories: true)
    let prefixTrapFile = prefixTrapDirectory.appendingPathComponent("trap.plist")
    try data.write(to: prefixTrapFile)
    await store.removeManagedPreset(atPath: prefixTrapFile.path)
    #expect(FileManager.default.fileExists(atPath: prefixTrapFile.path))

    // The genuine managed copy is still removable.
    let preset = try await store.importPreset(from: source, forApplicationPath: "/Applications/Example Game.app")
    await store.removeManagedPreset(atPath: preset.path)
    #expect(!FileManager.default.fileExists(atPath: preset.path))
}

@Test func recentMetalHUDAppPresetSurvivesFileStoreRoundTripAndAllowsNilImportedAt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configurationURL = root.appendingPathComponent("configuration.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let withTimestamp = ImportedHUDPreset(
        path: "/tmp/managed/with-time.plist",
        displayName: "with-time",
        importedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    // `importedAt` is optional, so a preset without a timestamp must round-trip too.
    let withoutTimestamp = ImportedHUDPreset(path: "/tmp/managed/no-time.plist", displayName: "no-time")
    var config = AppConfiguration()
    config.recentMetalHUDApps = [
        RecentMetalHUDApp(path: "/Applications/One.app", displayName: "One", importedPreset: withTimestamp),
        RecentMetalHUDApp(path: "/Applications/Two.app", displayName: "Two"),
        RecentMetalHUDApp(path: "/Applications/Three.app", displayName: "Three", importedPreset: withoutTimestamp)
    ]

    let store = ConfigurationStore(configurationURL: configurationURL)
    try await store.save(config)

    // Reload through the real store to prove the optional key is persisted, not just decodable.
    let loaded = try await store.load(homeURL: root)
    #expect(loaded.schemaVersion == 3)
    #expect(loaded.recentMetalHUDApps.count == 3)
    #expect(loaded.recentMetalHUDApps.first { $0.path == "/Applications/One.app" }?.importedPreset == withTimestamp)
    #expect(loaded.recentMetalHUDApps.first { $0.path == "/Applications/Two.app" }?.importedPreset == nil)
    let reloadedWithoutTimestamp = try #require(loaded.recentMetalHUDApps.first { $0.path == "/Applications/Three.app" }?.importedPreset)
    #expect(reloadedWithoutTimestamp.importedAt == nil)

    // A schema 3 payload carrying both preset-bearing and preset-free entries decodes unchanged.
    let mixed = Data(
        #"{"schemaVersion":3,"recentMetalHUDApps":[{"path":"/Applications/Old.app","displayName":"Old"},{"path":"/Applications/New.app","displayName":"New","importedPreset":{"path":"/tmp/managed/new.plist","displayName":"new"}}]}"#.utf8
    )
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: mixed)
    #expect(decoded.recentMetalHUDApps.count == 2)
    #expect(decoded.recentMetalHUDApps.first { $0.path == "/Applications/Old.app" }?.importedPreset == nil)
    let decodedPreset = try #require(decoded.recentMetalHUDApps.first { $0.path == "/Applications/New.app" }?.importedPreset)
    #expect(decodedPreset.path == "/tmp/managed/new.plist")
    #expect(decodedPreset.displayName == "new")
    #expect(decodedPreset.importedAt == nil)
}

// MARK: - Stage 4: iOS Metal HUD launcher

/// A realistic `devicectl list devices --json-output -` capture, trimmed to the
/// fields the parser walks through, plus non-iOS hardware that must be dropped.
private let iosDeviceInventoryJSON = #"""
{
  "info": { "outcome": "success", "jsonVersion": 5 },
  "result": {
    "devices": [
      {
        "identifier": "F594DDA4-C119-5C35-B5F3-46C86C90F6CC",
        "properties": {
          "hardware": { "deviceType": "iPhone", "platform": "iOS", "productType": "iPhone18,3" },
          "software": { "osVersionNumber": { "stringValue": "27.2" } },
          "connection": { "state": "connected" },
          "state": { "name": "Ebato的iPhone", "bootState": "booted" },
          "capabilities": [{ "name": "Acquire Usage Assertion" }],
          "hardwareDetails": { "cpuType": { "name": "arm64e" } },
          "softwareDetails": { "osBuildVersions": [{ "name": "24B5089g" }] }
        }
      },
      {
        "identifier": "00008110-000A1B2C3D4E5F6G",
        "properties": {
          "hardware": { "deviceType": "iPad", "platform": "iPadOS", "productType": "iPad14,5" },
          "software": { "osVersionNumber": { "stringValue": "18.1" } },
          "connection": { "state": "disconnected" },
          "state": { "name": "Studio iPad" }
        }
      },
      {
        "identifier": "8A2F0C4A-1111-2222-3333-444455556666",
        "properties": {
          "hardware": { "deviceType": "Mac", "platform": "macOS", "productType": "Mac16,1" },
          "state": { "name": "Some Mac" }
        }
      },
      {
        "identifier": "5C2B0D99-7777-8888-9999-AAAABBBBCCCC",
        "properties": {
          "hardware": { "deviceType": "Apple TV", "platform": "tvOS", "productType": "AppleTV14,1" },
          "state": { "name": "Living Room" }
        }
      },
      {
        "identifier": "9F0E1D2C-4444-5555-6666-777788889999",
        "properties": {
          "hardware": { "deviceType": "Watch", "platform": "watchOS", "productType": "Watch7,5" },
          "state": { "name": "My Watch" }
        }
      }
    ]
  }
}
"""#

/// Same inventory, but in the older `hardwareProperties` / `deviceProperties`
/// shape that pre-`properties` devicectl versions emit.
private let legacyIOSDeviceInventoryJSON = #"""
{
  "result": {
    "devices": [
      {
        "identifier": "11111111-AAAA-BBBB-CCCC-222222222222",
        "hardwareProperties": { "deviceType": "iPhone", "platform": "iOS", "productType": "iPhone17,1" },
        "deviceProperties": { "name": "Legacy iPhone", "bootState": "booted", "osVersionNumber": "18.6" }
      },
      {
        "identifier": "33333333-AAAA-BBBB-CCCC-444444444444",
        "hardwareProperties": { "deviceType": "Mac", "platform": "macOS", "productType": "Mac15,3" },
        "deviceProperties": { "name": "Legacy Mac" }
      }
    ]
  }
}
"""#

private let iosInstalledAppsJSON = #"""
{
  "result": {
    "apps": [
      { "bundleIdentifier": "com.example.zeta", "displayName": "Zeta Game", "version": "2.1.0" },
      { "bundleIdentifier": "com.example.alpha", "displayName": "Alpha Game", "shortVersion": "1.0.4" },
      { "bundleIdentifier": "com.example.alpha", "displayName": "Alpha Game (duplicate)" },
      { "bundleIdentifier": "com.example.alpha", "displayName": "Alpha Game" },
      { "bundleIdentifier": "not a bundle id", "displayName": "Malformed" },
      { "displayName": "Missing bundle id" }
    ]
  }
}
"""#

@Test func iosDeviceInventoryParsesAndFiltersNonIOSPlatforms() throws {
    let devices = try GamingService.parseIOSDevices(iosDeviceInventoryJSON)
    // Only the iPhone and iPad survive; Mac / Apple TV / Watch are dropped.
    #expect(devices.count == 2)
    #expect(devices.allSatisfy { $0.model.hasPrefix("iPhone") || $0.model.hasPrefix("iPad") })

    let iPhone = try #require(devices.first { $0.id == "F594DDA4-C119-5C35-B5F3-46C86C90F6CC" })
    #expect(iPhone.name == "Ebato的iPhone")
    #expect(iPhone.model == "iPhone18,3")
    #expect(iPhone.osVersion == "27.2")
    #expect(iPhone.displayName == "Ebato的iPhone")

    let identifiers = Set(devices.map(\.id))
    #expect(!identifiers.contains("8A2F0C4A-1111-2222-3333-444455556666")) // Mac
    #expect(!identifiers.contains("5C2B0D99-7777-8888-9999-AAAABBBBCCCC")) // Apple TV
    #expect(!identifiers.contains("9F0E1D2C-4444-5555-6666-777788889999")) // Watch
}

@Test func iosDeviceInventoryAcceptsIPadOSSpelling() throws {
    // Regression guard: `"ipados".contains("ios")` is false, so a naive
    // substring check silently drops iPads. iPadOS must be matched explicitly.
    let ipadOnly = #"{"result":{"devices":[{"identifier":"IPAD-1","properties":{"hardware":{"deviceType":"iPad","platform":"iPadOS","productType":"iPad14,5"},"state":{"name":"Studio iPad"}}}]}}"#
    let devices = try GamingService.parseIOSDevices(ipadOnly)
    #expect(devices.count == 1)
    #expect(devices.first?.id == "IPAD-1")

    // Combined platform spellings that include iPadOS still qualify...
    let combined = #"{"result":{"devices":[{"identifier":"IPAD-2","properties":{"hardware":{"platform":"iOS, iPadOS"}}}]}}"#
    #expect(try GamingService.parseIOSDevices(combined).count == 1)

    // ...but a platform that also names another Apple OS does not.
    let mixedTV = #"{"result":{"devices":[{"identifier":"TV-1","properties":{"hardware":{"platform":"iOS, tvOS"}}}]}}"#
    #expect(try GamingService.parseIOSDevices(mixedTV).isEmpty)
}

@Test func iosDeviceInventoryFiltersMacOSAndMissingPlatformRows() throws {
    // A row with no platform/deviceType at all must not be presented as an iOS device.
    let ambiguous = #"{"result":{"devices":[{"identifier":"AAAA-BBBB","properties":{"state":{"name":"Mystery"}}}]}}"#
    #expect(try GamingService.parseIOSDevices(ambiguous).isEmpty)

    // platform says iOS but deviceType is a Mac: reject on the deviceType guard.
    let contradictory = #"{"result":{"devices":[{"identifier":"AAAA-CCCC","properties":{"hardware":{"deviceType":"Mac","platform":"iOS"}}}]}}"#
    #expect(try GamingService.parseIOSDevices(contradictory).isEmpty)

    // A hypothetical combined platform string that also mentions macOS is rejected.
    let combined = #"{"result":{"devices":[{"identifier":"AAAA-DDDD","properties":{"hardware":{"deviceType":"iPhone","platform":"iOS, macOS"}}}]}}"#
    #expect(try GamingService.parseIOSDevices(combined).isEmpty)
}

@Test func iosDeviceInventoryReadsLegacyDeprecatedFieldShape() throws {
    let devices = try GamingService.parseIOSDevices(legacyIOSDeviceInventoryJSON)
    #expect(devices.count == 1)
    let device = try #require(devices.first)
    #expect(device.id == "11111111-AAAA-BBBB-CCCC-222222222222")
    #expect(device.name == "Legacy iPhone")
    #expect(device.model == "iPhone17,1")
    #expect(device.osVersion == "18.6")
    #expect(device.state == "booted")
}

@Test func iosDeviceParsingRejectsMalformedJSON() {
    #expect(throws: ToolboxError.self) { try GamingService.parseIOSDevices("not json at all") }
    #expect(throws: ToolboxError.self) { try GamingService.parseIOSApps("<html>error</html>") }
}

@Test func iosInstalledAppsParsesDeduplicatesAndSorts() throws {
    let apps = try GamingService.parseIOSApps(iosInstalledAppsJSON)
    // Duplicated bundle IDs collapse, malformed / incomplete rows are dropped.
    #expect(apps.map(\.bundleIdentifier) == ["com.example.alpha", "com.example.zeta"])
    let alpha = try #require(apps.first)
    #expect(alpha.displayName == "Alpha Game")
    // `shortVersion` is preferred over the plain `version` key.
    #expect(alpha.version == "1.0.4")
}

@Test func iosLaunchArgumentsRejectNULNewlineAndExcessCount() throws {
    // Clean arguments of every awkward-but-legal shape still pass.
    #expect(throws: Never.self) {
        try GamingService.validateIOSLaunchArguments(["", "  ", "-Flag", "value with spaces", "quote\"inside", "a\nb\n".isEmpty ? "" : "x"])
    }
    #expect(throws: ToolboxError.self) { try GamingService.validateIOSLaunchArguments(["bad\0arg"]) }
    #expect(throws: ToolboxError.self) { try GamingService.validateIOSLaunchArguments(["bad\narg"]) }
    #expect(throws: ToolboxError.self) { try GamingService.validateIOSLaunchArguments(["bad\rarg"]) }

    let atCap = Array(repeating: "-x", count: GamingService.maxIOSLaunchArgumentCount)
    #expect(throws: Never.self) { try GamingService.validateIOSLaunchArguments(atCap) }
    let overCap = atCap + ["-extra"]
    #expect(throws: ToolboxError.self) { try GamingService.validateIOSLaunchArguments(overCap) }
}

@Test func iosLaunchCommandUsesStandaloneArgumentsAndSeparator() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    try await service.launchIOSAppWithMetalHUD(
        deviceID: "F594DDA4-C119-5C35-B5F3-46C86C90F6CC",
        bundleIdentifier: "com.example.game",
        launchArguments: ["-windowed", "a value with spaces"]
    )

    let calls = await runner.calls
    let call = try #require(calls.last)
    #expect(call.0 == "/usr/bin/xcrun")
    // Every piece is its own argv entry: nothing is joined or shell-quoted.
    #expect(call.1 == [
        "devicectl", "device", "process", "launch",
        "--device", "F594DDA4-C119-5C35-B5F3-46C86C90F6CC",
        "--environment-variables", #"{"MTL_HUD_ENABLED":"1"}"#,
        "--terminate-existing",
        "com.example.game",
        "--",
        "-windowed",
        "a value with spaces"
    ])
    #expect(!call.1.contains { $0.contains(" ") && $0.hasPrefix("-") && $0 != "-windowed" && $0 != "a value with spaces" })
}

@Test func iosLaunchCommandOmitsSeparatorWhenNoExtraArguments() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    try await service.launchIOSAppWithMetalHUD(
        deviceID: "F594DDA4-C119-5C35-B5F3-46C86C90F6CC",
        bundleIdentifier: "com.example.game"
    )

    let call = try #require(await runner.calls.last)
    #expect(!call.1.contains("--"))
    #expect(call.1.last == "com.example.game")
}

@Test func iosLaunchRejectsInvalidIdentifiersAndArgumentsBeforeRunning() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    // Empty / NUL-bearing device identifiers never reach the runner.
    await #expect(throws: ToolboxError.self) {
        try await service.launchIOSAppWithMetalHUD(deviceID: "", bundleIdentifier: "com.example.game")
    }
    await #expect(throws: ToolboxError.self) {
        try await service.launchIOSAppWithMetalHUD(deviceID: "dev\0ice", bundleIdentifier: "com.example.game")
    }
    // Malformed bundle identifiers are refused.
    await #expect(throws: ToolboxError.self) {
        try await service.launchIOSAppWithMetalHUD(deviceID: "DEVICE-1", bundleIdentifier: "not-a-bundle-id")
    }
    // A NUL inside a launch argument is refused.
    await #expect(throws: ToolboxError.self) {
        try await service.launchIOSAppWithMetalHUD(deviceID: "DEVICE-1", bundleIdentifier: "com.example.game", launchArguments: ["oops\0"])
    }
    // Nothing was ever executed for the rejected calls.
    #expect(await runner.calls.isEmpty)
}

@Test func iosDeviceEnumerationMapsMissingToolchainToActionableError() async throws {
    let runner = MissingXcodeCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    do {
        _ = try await service.iosDevices()
        Issue.record("Expected iosDevices() to throw when xcrun is unavailable")
    } catch let error as ToolboxError {
        guard case .commandFailed(let message) = error else {
            Issue.record("Expected .commandFailed, got \(error)")
            return
        }
        // The raw `xcrun` text must be replaced by actionable guidance.
        #expect(message.localizedCaseInsensitiveContains("Xcode"))
        #expect(message.localizedCaseInsensitiveContains("xcode-select"))
    }
}

@Test func iosDeviceEnumerationSurfacesRawJSONThroughTheRunner() async throws {
    let runner = StaticOutputCommandRunner(output: iosDeviceInventoryJSON)
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    let devices = try await service.iosDevices()
    #expect(devices.count == 2)
    let call = try #require(await runner.calls.last)
    #expect(call.0 == "/usr/bin/xcrun")
    #expect(call.1 == ["devicectl", "list", "devices", "--json-output", "-"])
}

actor MissingXcodeCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        throw ToolboxError.commandFailed("xcrun: error: unable to find utility \"devicectl\", not a developer tool or in PATH")
    }
}

actor StaticOutputCommandRunner: CommandRunning {
    private let output: String
    private(set) var calls: [(String, [String])] = []

    init(output: String) { self.output = output }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append((executable, arguments))
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}
