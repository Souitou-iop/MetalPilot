import Foundation

public enum HostsFileEditor {
    public static let markerStart = "# BEGIN METALPILOT HOYO"
    public static let markerEnd = "# END METALPILOT HOYO"
    // Blocks written before the MetalPilot rebrand must stay recognized so
    // older managed blocks are always cleaned up or rolled back precisely.
    public static let legacyMarkerStart = "# BEGIN MAC GAME TOOLBOX HOYO"
    public static let legacyMarkerEnd = "# END MAC GAME TOOLBOX HOYO"
    private static let recognizedStarts = [markerStart, legacyMarkerStart]
    private static let recognizedEnds = [markerEnd, legacyMarkerEnd]

    public static func replacingManagedBlock(in original: String, domains: [String], enabled: Bool) -> String {
        var lines: [String] = []
        var insideBlock = false
        let managedLines = Set(domains.map { "0.0.0.0 \($0)" })
        for line in original.components(separatedBy: .newlines) {
            if recognizedStarts.contains(line) { insideBlock = true; continue }
            if recognizedEnds.contains(line) { insideBlock = false; continue }
            if !insideBlock && !managedLines.contains(line.trimmingCharacters(in: .whitespaces)) { lines.append(line) }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if enabled {
            lines.append(markerStart)
            lines.append(contentsOf: domains.map { "0.0.0.0 \($0)" })
            lines.append(markerEnd)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
