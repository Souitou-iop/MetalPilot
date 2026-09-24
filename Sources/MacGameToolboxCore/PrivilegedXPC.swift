import Foundation

public enum PrivilegedRequest: Codable, Equatable, Sendable {
    case healthCheck
    case addHoYoHosts
    case removeHoYoHosts
    case renice([Int32])
    case clearSystemCaches
    case setHostnames(HostnameBackup)
    case createDirectory(String)
}

public enum HelperRegistrationState: Sendable {
    case enabled, notRegistered, requiresApproval, notFound
}

public enum HelperRegistrationDecision: Equatable, Sendable {
    case connect, register, requestApproval, unavailable
}

public func helperRegistrationDecision(for state: HelperRegistrationState) -> HelperRegistrationDecision {
    switch state {
    case .enabled: .connect
    case .notRegistered: .register
    case .requiresApproval: .requestApproval
    case .notFound: .unavailable
    }
}

@objc(PrivilegedHelperXPCProtocol) public protocol PrivilegedHelperXPCProtocol {
    func perform(request: Data, withReply reply: @escaping (Bool, String?) -> Void)
}

public enum PrivilegedHelperConstants {
    public static let serviceName = "macgametoolbox.helper"
    public static let appBundleIdentifier = "com.iven.macgametoolbox"
    public static let installedHelperPath = "/Library/PrivilegedHelperTools/macgametoolbox.helper"
    public static let installedPlistPath = "/Library/LaunchDaemons/macgametoolbox.helper.plist"
    public static let idleTimeoutSeconds: TimeInterval = 15.0

    public static func isPlistCurrent(_ plist: [String: Any]) -> Bool {
        guard plist["Label"] as? String == serviceName,
              let identifiers = plist["AssociatedBundleIdentifiers"] as? [String],
              identifiers.contains(appBundleIdentifier),
              let machServices = plist["MachServices"] as? [String: Any],
              machServices[serviceName] != nil,
              (plist["RunAtLoad"] == nil || (plist["RunAtLoad"] as? Bool) == false) else {
            return false
        }
        return true
    }
}
