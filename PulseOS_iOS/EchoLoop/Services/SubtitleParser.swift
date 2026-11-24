import Foundation

/// 支持解析 .srt 和 .lrc 字幕文件（自动兼容 UTF-8 / GB18030 / UTF-16 常见编码）
enum SubtitleParser {
    static func parse(url: URL, audioDuration: TimeInterval) -> [SubtitleCue] {
        guard let content = readTextWithFallbackEncoding(url: url) else {
            return []
        }
        let ext = url.pathExtension.lowercased()
        if ext == "lrc" {
            return parseLRC(content, audioDuration: audioDuration)
        } else {
            return parseSRT(content)
        }
    }

    static func convertToSegments(cues: [SubtitleCue]) -> [AudioSegment] {
        cues.map { cue in
            AudioSegment(
                startTime: cue.startTime,
                endTime: max(cue.startTime + 0.3, cue.endTime),
                text: cue.primaryText,
                translation: cue.secondaryText,
                isFavorite: false
            )
        }
    }

    /// 将当前段落导出为标准 SRT 文本
    static func exportSRT(segments: [AudioSegment]) -> String {
        var lines: [String] = []
        for (index, seg) in segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(formatSRTTime(seg.startTime)) --> \(formatSRTTime(seg.endTime))")
            let body = seg.text.isEmpty ? "Segment \(index + 1)" : seg.text
            lines.append(body)
            if !seg.translation.isEmpty {
                lines.append(seg.translation)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - SRT Parser

    static func parseSRT(_ raw: String) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 2 else { continue }

            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }
            let timeParts = lines[timeLineIndex].components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let start = parseSRTTime(timeParts[0]),
                  let end = parseSRTTime(timeParts[1]) else {
                continue
            }

            let textLines = Array(lines[(timeLineIndex + 1)...])
                .map { stripHTMLTags($0) }
                .filter { !$0.isEmpty }
            guard !textLines.isEmpty else { continue }

            let primary = textLines[0]
            let secondary = textLines.count > 1 ? textLines[1...].joined(separator: " ") : ""
            cues.append(SubtitleCue(startTime: start, endTime: max(start + 0.2, end), primaryText: primary, secondaryText: secondary))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - LRC Parser

    static func parseLRC(_ raw: String, audioDuration: TimeInterval) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var entries: [(TimeInterval, String)] = []
        for line in lines {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            let lastRange = matches.last!.range
            let lyricStart = lastRange.location + lastRange.length
            let text = nsLine.substring(from: lyricStart).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                var frac: Double = 0
                if match.range(at: 3).location != NSNotFound {
                    let fStr = nsLine.substring(with: match.range(at: 3))
                    if let val = Double(fStr) {
                        frac = val / pow(10.0, Double(fStr.count))
                    }
                }
                if let m = Double(minStr), let s = Double(secStr) {
                    entries.append((m * 60 + s + frac, text))
                }
            }
        }

        entries.sort { $0.0 < $1.0 }
        guard !entries.isEmpty else { return [] }

        // 合并相同时间戳的双语行
        var grouped: [(TimeInterval, [String])] = []
        for (time, text) in entries {
            if let last = grouped.last, abs(last.0 - time) < 0.05 {
                grouped[grouped.count - 1].1.append(text)
            } else {
                grouped.append((time, [text]))
            }
        }

        var cues: [SubtitleCue] = []
        for idx in 0..<grouped.count {
            let start = grouped[idx].0
            let nextStart = (idx + 1 < grouped.count) ? grouped[idx + 1].0 : max(audioDuration, start + 3.0)
            let end = max(start + 0.3, nextStart)
            let texts = grouped[idx].1
            cues.append(
                SubtitleCue(
                    startTime: start,
                    endTime: end,
                    primaryText: texts.first ?? "",
                    secondaryText: texts.count > 1 ? texts[1...].joined(separator: " ") : ""
                )
            )
        }
        return cues
    }

    // MARK: - Helpers

    private static func parseSRTTime(_ str: String) -> TimeInterval? {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else {
            return nil
        }
        return h * 3600 + m * 60 + s
    }

    private static func formatSRTTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let msTotal = Int((clamped * 1000).rounded())
        let ms = msTotal % 1000
        let secTotal = msTotal / 1000
        let s = secTotal % 60
        let m = (secTotal / 60) % 60
        let h = secTotal / 3600
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private static func stripHTMLTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readTextWithFallbackEncoding(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let gb = String(data: data, encoding: gb18030) {
            return gb
        }
        return String(data: data, encoding: .utf16)
    }
}
