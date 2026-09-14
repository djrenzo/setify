import Foundation

struct SubtitleCue: Hashable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// A minimal WebVTT parser used to drive a manual subtitle overlay, rather than handing the
/// track to AVFoundation directly — mixing an HLS video asset with a WebVTT sidecar via
/// `AVMutableComposition` turned out to be unreliable and broke playback (see PlayerSession).
/// This only needs to extract cue timing + plain text, not full WebVTT styling support.
enum WebVTTParser {
    static func parse(_ content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = parseTiming(lines[timingIndex]) else { continue }

            let text = lines[(timingIndex + 1)...]
                .map(stripTags)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !text.isEmpty else { continue }

            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTiming(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        // The end timestamp may be followed by cue settings, e.g. "00:00:04.000 align:start".
        let endText = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        guard let start = parseTimestamp(startText), let end = parseTimestamp(endText) else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ text: String) -> TimeInterval? {
        let components = text.split(separator: ":")
        guard components.count == 2 || components.count == 3 else { return nil }
        guard let seconds = Double(components.last!.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let hours = components.count == 3 ? Double(components[0]) ?? 0 : 0
        let minutes = Double(components[components.count - 2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }

    /// Strips WebVTT inline markup (`<b>`, `<c.classname>`, `<00:00:01.000>` karaoke timestamps, …).
    private static func stripTags(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]*>") else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
