import Foundation
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public enum AppLanguage {
    nonisolated(unsafe) public static var currentPreference: AppLanguagePreference = .system

    public static var resolvedLanguageCode: String {
        switch currentPreference {
        case .chinese:
            return "zh-Hans"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        case .system:
            guard let preferred = Locale.preferredLanguages.first else { return "en" }
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
            if code.hasPrefix("zh") { return "zh-Hans" }
            if code.hasPrefix("ja") { return "ja" }
            return "en"
        }
    }

    public static func text(_ chinese: String, _ english: String, _ japanese: String? = nil) -> String {
        let code = resolvedLanguageCode
        if code == "zh-Hans" { return chinese }
        if code == "ja" { return japanese ?? english }
        return english
    }

    public static func phase(_ phase: TaskPhase) -> String {
        switch phase {
        case .idle: return text("空闲", "Idle", "待機中")
        case .awaitingAuthorization: return text("等待授权", "Awaiting authorization", "認証待機中")
        case .running: return text("进行中", "Running", "実行中")
        case .succeeded: return text("已完成", "Completed", "完了")
        case .failed: return text("失败", "Failed", "失敗")
        case .cancelled: return text("已取消", "Cancelled", "キャンセル済み")
        }
    }
}

@inline(__always)
public func tr(_ chinese: String, _ english: String, _ japanese: String? = nil) -> String {
    AppLanguage.text(chinese, english, japanese)
}
