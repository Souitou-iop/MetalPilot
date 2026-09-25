import Foundation
#if SWIFT_PACKAGE
import MetalPilotCore
#endif
import OSLog
import Security

public final class PrivilegedHelperClient: PrivilegedOperating, @unchecked Sendable {
    static let serviceName = PrivilegedHelperConstants.serviceName
    static let appBundleIdentifier = PrivilegedHelperConstants.appBundleIdentifier
    static let installedHelperPath = PrivilegedHelperConstants.installedHelperPath
    static let installedPlistPath = PrivilegedHelperConstants.installedPlistPath
    private let coordinator = PrivilegedHelperCoordinator()
    private(set) var preserveLegacyHelper = false

    public init() {}

    public func diagnosticStatus() -> String {
        let installed = FileManager.default.fileExists(atPath: Self.installedHelperPath)
        let signing = Self.teamIdentifier() == nil ? "development signing" : "Developer ID signing"
        return "persistent helper: \(installed ? "installed" : "not installed"), \(signing)"
    }

    /// Records the user's side-by-side choice so every automatic install path
    /// (first privileged use, repairs) keeps the legacy helper untouched.
    public func setLegacyCoexistence(_ enabled: Bool) {
        preserveLegacyHelper = enabled
    }

    public func installOrReinstallHelper(preserveLegacy: Bool = false) async throws {
        try await coordinator.install(preserveLegacy: preserveLegacy)
    }

    public func perform(_ operation: PrivilegedOperation) async throws {
        try await coordinator.perform(Self.request(for: operation), preserveLegacy: preserveLegacyHelper)
    }

    static func request(for operation: PrivilegedOperation) throws -> PrivilegedRequest {
        switch operation {
        case .healthCheck: return .healthCheck
        case .addHoYoHosts: return .addHoYoHosts
        case .removeHoYoHosts: return .removeHoYoHosts
        case .clearSystemCaches: return .clearSystemCaches
        case .renice(let pids):
            if pids.isEmpty || pids.count > 64 || pids.contains(where: { $0 <= 1 }) {
                throw MetalPilotError.commandFailed("Invalid process list")
            }
            return .renice(pids)
        case .setHostnames(let names):
            guard InputValidation.computerName(names.computerName),
                  InputValidation.hostname(names.hostName),
                  InputValidation.hostname(names.localHostName) else {
                throw MetalPilotError.commandFailed("Invalid hostname")
            }
            return .setHostnames(names)
        case .createDirectory(let path):
            return .createDirectory(try InputValidation.normalizedAbsolutePath(path))
        }
    }

    private static func teamIdentifier() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static var hasCurrentRegistration: Bool {
        let bundledHelperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/MetalPilotPrivilegedHelper")
            .path
        guard FileManager.default.fileExists(atPath: installedHelperPath),
              FileManager.default.contentsEqual(atPath: installedHelperPath, andPath: bundledHelperPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: installedPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return false
        }
        return PrivilegedHelperConstants.isPlistCurrent(plist)
    }
}

private actor PrivilegedHelperCoordinator {
    private let logger = Logger(subsystem: "com.iven.macgametoolbox", category: "PrivilegedClient")
    private var installedThisSession = false

    func perform(_ request: PrivilegedRequest, preserveLegacy: Bool = false) async throws {
        if !PrivilegedHelperClient.hasCurrentRegistration {
            try await install(preserveLegacy: preserveLegacy)
        }
        let data = try JSONEncoder().encode(request)
        logger.info("Sending persistent helper request: \(String(describing: request), privacy: .public)")
        DiagnosticFileLogger.write("Sending persistent helper request: \(String(describing: request))")

        do {
            try await sendWithStartupRetries(data)
        } catch let error as MetalPilotError {
            guard case .helperUnavailable = error, !installedThisSession else { throw error }
            try await install(preserveLegacy: preserveLegacy)
            try await sendWithStartupRetries(data)
        }
        DiagnosticFileLogger.write("Persistent helper request completed")
    }

    func install(preserveLegacy: Bool = false) async throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/MetalPilotPrivilegedHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw MetalPilotError.helperUnavailable("The app bundle does not contain the privileged helper")
        }
        DiagnosticFileLogger.write("Requesting one-time persistent helper installation\(preserveLegacy ? " (legacy helper preserved)" : "")")
        let preserveArgument = preserveLegacy ? " --preserve-legacy" : ""
        let script = """
        on run argv
            do shell script quoted form of (item 1 of argv) & " --install " & quoted form of (item 2 of argv) & "\(preserveArgument)" with administrator privileges
        end run
        """
        let result: (Int32, String) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, "--", helperURL.path, Bundle.main.bundleURL.path]
            process.standardOutput = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, message)
        }.value
        guard result.0 == 0 else {
            if result.1.contains("(-128)") { throw MetalPilotError.authorizationCancelled }
            throw MetalPilotError.helperUnavailable(result.1.isEmpty ? "Helper installation failed" : result.1)
        }
        installedThisSession = true
        DiagnosticFileLogger.write("Persistent helper installation completed")
    }

    private func sendWithStartupRetries(_ data: Data) async throws {
        var lastError: Error = MetalPilotError.helperUnavailable("XPC service did not start")
        for attempt in 0..<5 {
            do {
                try await sendOnce(data)
                return
            } catch let error as MetalPilotError {
                lastError = error
                guard case .helperUnavailable = error, attempt < 4 else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw lastError
    }

    private func sendOnce(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: PrivilegedHelperClient.serviceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
            let reply = XPCReply(connection: connection, continuation: continuation)
            connection.interruptionHandler = { reply.finish(.failure(MetalPilotError.helperUnavailable("XPC connection interrupted"))) }
            connection.invalidationHandler = { reply.finish(.failure(MetalPilotError.helperUnavailable("XPC connection invalidated"))) }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                reply.finish(.failure(MetalPilotError.helperUnavailable(error.localizedDescription)))
            }) as? PrivilegedHelperXPCProtocol else {
                reply.finish(.failure(MetalPilotError.helperUnavailable("Invalid XPC proxy")))
                return
            }
            proxy.perform(request: data) { success, message in
                reply.finish(success
                    ? .success(())
                    : .failure(MetalPilotError.commandFailed(message ?? "Privileged operation failed")))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
                reply.finish(.failure(MetalPilotError.helperTimedOut))
            }
        }
    }
}

private final class XPCReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var connection: NSXPCConnection?

    init(connection: NSXPCConnection, continuation: CheckedContinuation<Void, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        continuation.resume(with: result)
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
    }
}
