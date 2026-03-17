import Cocoa
import Foundation
import ServiceManagement

// MARK: - Data Models

struct SessionFile: Codable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Double
}

struct MessageUsage: Codable {
    let input_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
    let output_tokens: Int?
}

struct MessageContent: Codable {
    let model: String?
    let usage: MessageUsage?
    let role: String?
}

struct ConversationLine: Codable {
    let message: MessageContent?
    let type: String?
    let timestamp: String?
}

struct ModelTokens {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

struct UsagePeriod {
    var messageCount: Int = 0
    var sessionCount: Int = 0
    var tokensByModel: [String: ModelTokens] = [:]
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheReadTokens: Int = 0
    var totalCacheCreationTokens: Int = 0

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheReadTokens + totalCacheCreationTokens
    }

    mutating func add(model: String, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) {
        messageCount += 1
        totalInputTokens += input
        totalOutputTokens += output
        totalCacheReadTokens += cacheRead
        totalCacheCreationTokens += cacheCreation

        var mt = tokensByModel[model] ?? ModelTokens()
        mt.inputTokens += input
        mt.outputTokens += output
        mt.cacheReadTokens += cacheRead
        mt.cacheCreationTokens += cacheCreation
        tokensByModel[model] = mt
    }
}

struct PeriodUsage {
    var today = UsagePeriod()
    var thisWeek = UsagePeriod()
}

struct ActiveSession {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Date
    let model: String
    let inputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let outputTokens: Int

    var totalContextTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens
    }

    var contextPercentage: Double {
        Double(totalContextTokens) / 1_000_000.0 * 100.0
    }

    var sessionDuration: String {
        let elapsed = Date().timeIntervalSince(startedAt)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedTokens: String {
        let total = totalContextTokens
        if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000.0)
        } else if total >= 1_000 {
            return String(format: "%.1fK", Double(total) / 1_000.0)
        }
        return "\(total)"
    }

    var projectName: String {
        let url = URL(fileURLWithPath: cwd)
        return url.lastPathComponent
    }
}

// MARK: - Session Discovery

class SessionMonitor {
    private let claudeDir: String
    private let sessionsDir: String
    private let projectsDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        claudeDir = "\(home)/.claude"
        sessionsDir = "\(claudeDir)/sessions"
        projectsDir = "\(claudeDir)/projects"
    }

    func findActiveSessions() -> [ActiveSession] {
        let fm = FileManager.default
        guard let sessionFiles = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return [] }

        var sessions: [ActiveSession] = []

        for file in sessionFiles where file.hasSuffix(".json") {
            let path = "\(sessionsDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let session = try? JSONDecoder().decode(SessionFile.self, from: data) else { continue }

            // Check if process is still running
            if kill(Int32(session.pid), 0) != 0 { continue }

            // Find the JSONL conversation file
            let projectDirName = session.cwd.replacingOccurrences(of: "/", with: "-")
            let jsonlPath = "\(projectsDir)/\(projectDirName)/\(session.sessionId).jsonl"

            guard fm.fileExists(atPath: jsonlPath) else { continue }

            // Read last assistant message with usage data
            if let sessionData = readLastUsage(from: jsonlPath) {
                let startDate = Date(timeIntervalSince1970: session.startedAt / 1000.0)
                sessions.append(ActiveSession(
                    pid: session.pid,
                    sessionId: session.sessionId,
                    cwd: session.cwd,
                    startedAt: startDate,
                    model: sessionData.model,
                    inputTokens: sessionData.inputTokens,
                    cacheReadTokens: sessionData.cacheRead,
                    cacheCreationTokens: sessionData.cacheCreation,
                    outputTokens: sessionData.outputTokens
                ))
            }
        }

        // Sort by most recent (highest startedAt)
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    func computePeriodUsage() -> PeriodUsage {
        let fm = FileManager.default
        var result = PeriodUsage()

        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return result
        }
        let todayStart = calendar.startOfDay(for: now)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        var weekSessionIds = Set<String>()
        var todaySessionIds = Set<String>()

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsDir) else {
            return result
        }

        for projectDir in projectDirs {
            let projectPath = "\(projectsDir)/\(projectDir)"
            guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = "\(projectPath)/\(file)"

                // Skip files not modified this week
                guard let attrs = try? fm.attributesOfItem(atPath: filePath),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate >= weekStart else { continue }

                guard let data = fm.contents(atPath: filePath),
                      let content = String(data: data, encoding: .utf8) else { continue }

                let sessionId = String(file.dropLast(6))

                for line in content.components(separatedBy: "\n") where !line.isEmpty {
                    guard let lineData = line.data(using: .utf8),
                          let conv = try? JSONDecoder().decode(ConversationLine.self, from: lineData),
                          let message = conv.message,
                          message.role == "assistant",
                          let msgUsage = message.usage,
                          let timestamp = conv.timestamp else { continue }

                    guard let date = isoFormatter.date(from: timestamp) ?? isoFormatterNoFrac.date(from: timestamp) else { continue }
                    guard date >= weekStart else { continue }

                    let model = message.model ?? "unknown"
                    let input = msgUsage.input_tokens ?? 0
                    let output = msgUsage.output_tokens ?? 0
                    let cacheRead = msgUsage.cache_read_input_tokens ?? 0
                    let cacheCreation = msgUsage.cache_creation_input_tokens ?? 0

                    result.thisWeek.add(model: model, input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
                    weekSessionIds.insert(sessionId)

                    if date >= todayStart {
                        result.today.add(model: model, input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
                        todaySessionIds.insert(sessionId)
                    }
                }
            }
        }

        result.thisWeek.sessionCount = weekSessionIds.count
        result.today.sessionCount = todaySessionIds.count
        return result
    }

    private func readLastUsage(from path: String) -> (model: String, inputTokens: Int, cacheRead: Int, cacheCreation: Int, outputTokens: Int)? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").reversed()

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let conv = try? JSONDecoder().decode(ConversationLine.self, from: lineData),
                  let message = conv.message,
                  message.role == "assistant",
                  let usage = message.usage else { continue }

            return (
                model: message.model ?? "unknown",
                inputTokens: usage.input_tokens ?? 0,
                cacheRead: usage.cache_read_input_tokens ?? 0,
                cacheCreation: usage.cache_creation_input_tokens ?? 0,
                outputTokens: usage.output_tokens ?? 0
            )
        }

        return nil
    }
}

// MARK: - Menu Bar App

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let monitor = SessionMonitor()
    private var lastSessions: [ActiveSession] = []
    private var periodUsage = PeriodUsage()
    private var lastUsageUpdate: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateDisplay()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDisplay()
            }
        }
    }

    private func updateDisplay() {
        lastSessions = monitor.findActiveSessions()

        // Refresh usage stats every 60 seconds (expensive scan)
        if Date().timeIntervalSince(lastUsageUpdate) > 60 {
            periodUsage = monitor.computePeriodUsage()
            lastUsageUpdate = Date()
        }

        guard let button = statusItem.button else { return }

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)

        if lastSessions.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.5)
            ]
            button.attributedTitle = NSAttributedString(string: "CTX --", attributes: attrs)
        } else {
            let primary = lastSessions[0]
            let pct = Int(primary.contextPercentage)
            let color = colorForPercentage(primary.contextPercentage)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            button.attributedTitle = NSAttributedString(string: "CTX \(pct)%", attributes: attrs)
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if lastSessions.isEmpty {
            let noSession = NSMenuItem(title: "No active Claude Code sessions", action: nil, keyEquivalent: "")
            noSession.isEnabled = false
            menu.addItem(noSession)
        } else {
            for (index, session) in lastSessions.enumerated() {
                if index > 0 {
                    menu.addItem(NSMenuItem.separator())
                }

                // Use a custom NSView for each session so it's always fully readable
                let viewItem = NSMenuItem()
                viewItem.view = createSessionView(session)
                menu.addItem(viewItem)
            }
        }

        // Usage stats sections
        menu.addItem(NSMenuItem.separator())
        let todayItem = NSMenuItem()
        todayItem.view = createUsagePeriodView(periodUsage.today, title: "Today")
        menu.addItem(todayItem)

        menu.addItem(NSMenuItem.separator())
        let weekItem = NSMenuItem()
        weekItem.view = createUsagePeriodView(periodUsage.thisWeek, title: "This Week")
        menu.addItem(weekItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login toggle
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        if #available(macOS 13.0, *) {
            launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        let aboutItem = NSMenuItem(title: "About Claude Monitor", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Claude Monitor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func createSessionView(_ session: ActiveSession) -> NSView {
        let width: CGFloat = 280
        let padding: CGFloat = 16
        let pct = Int(session.contextPercentage)
        let color = colorForPercentage(session.contextPercentage)
        let modelName = formatModelName(session.model)

        // Container
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))

        // Project name (header)
        let nameLabel = NSTextField(labelWithString: session.projectName)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.frame = NSRect(x: padding, y: 72, width: width - padding * 2, height: 18)
        container.addSubview(nameLabel)

        // Progress bar background
        let barY: CGFloat = 56
        let barWidth = width - padding * 2
        let barHeight: CGFloat = 6

        let barBg = NSView(frame: NSRect(x: padding, y: barY, width: barWidth, height: barHeight))
        barBg.wantsLayer = true
        barBg.layer?.backgroundColor = NSColor.separatorColor.cgColor
        barBg.layer?.cornerRadius = 3
        container.addSubview(barBg)

        // Progress bar fill
        let fillWidth = max(barWidth * CGFloat(session.contextPercentage) / 100.0, 0)
        let barFill = NSView(frame: NSRect(x: padding, y: barY, width: min(fillWidth, barWidth), height: barHeight))
        barFill.wantsLayer = true
        barFill.layer?.backgroundColor = color.cgColor
        barFill.layer?.cornerRadius = 3
        container.addSubview(barFill)

        // Context line
        let contextLabel = NSTextField(labelWithString: "\(session.formattedTokens) / 1M tokens  (\(pct)%)")
        contextLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        contextLabel.textColor = NSColor.labelColor
        contextLabel.frame = NSRect(x: padding, y: 34, width: barWidth, height: 16)
        container.addSubview(contextLabel)

        // Model + Duration on same line
        let detailLabel = NSTextField(labelWithString: "\(modelName)  ·  \(session.sessionDuration)  ·  PID \(session.pid)")
        detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.frame = NSRect(x: padding, y: 14, width: barWidth, height: 14)
        container.addSubview(detailLabel)

        return container
    }

    private func createUsagePeriodView(_ usage: UsagePeriod, title: String) -> NSView {
        let width: CGFloat = 280
        let padding: CGFloat = 16
        let contentWidth = width - padding * 2

        // Compute layout height based on content
        let headerHeight: CGFloat = 18
        let lineHeight: CGFloat = 16
        let smallLineHeight: CGFloat = 14
        let sectionGap: CGFloat = 8
        let modelCount = usage.tokensByModel.count

        // Header + summary lines + gap + per-model lines + bottom padding
        let summaryLines: CGFloat = 4 // messages, input, output, cache
        let totalHeight = 10 + headerHeight + sectionGap
            + summaryLines * lineHeight + sectionGap
            + (modelCount > 0 ? smallLineHeight + CGFloat(modelCount) * smallLineHeight : 0)
            + 6

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        var y = totalHeight - 10 - headerHeight

        // Header
        let header = NSTextField(labelWithString: title)
        header.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        header.textColor = NSColor.labelColor
        header.frame = NSRect(x: padding, y: y, width: contentWidth, height: headerHeight)
        container.addSubview(header)
        y -= sectionGap

        // Summary stats
        let lines: [(String, String)] = [
            ("Messages", "\(usage.messageCount) across \(usage.sessionCount) sessions"),
            ("Input tokens", formatTokenCount(usage.totalInputTokens)),
            ("Output tokens", formatTokenCount(usage.totalOutputTokens)),
            ("Cache read / write", "\(formatTokenCount(usage.totalCacheReadTokens)) / \(formatTokenCount(usage.totalCacheCreationTokens))"),
        ]

        for (label, value) in lines {
            y -= lineHeight
            let labelField = NSTextField(labelWithString: label)
            labelField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            labelField.textColor = NSColor.secondaryLabelColor
            labelField.frame = NSRect(x: padding, y: y, width: 110, height: lineHeight)
            container.addSubview(labelField)

            let valueField = NSTextField(labelWithString: value)
            valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            valueField.textColor = NSColor.labelColor
            valueField.frame = NSRect(x: padding + 114, y: y, width: contentWidth - 114, height: lineHeight)
            container.addSubview(valueField)
        }

        // Per-model breakdown
        if !usage.tokensByModel.isEmpty {
            y -= sectionGap
            y -= smallLineHeight
            let modelHeader = NSTextField(labelWithString: "By Model")
            modelHeader.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            modelHeader.textColor = NSColor.secondaryLabelColor
            modelHeader.frame = NSRect(x: padding, y: y, width: contentWidth, height: smallLineHeight)
            container.addSubview(modelHeader)

            let sortedModels = usage.tokensByModel.sorted { $0.value.totalTokens > $1.value.totalTokens }
            for (model, tokens) in sortedModels {
                y -= smallLineHeight
                let modelName = formatModelName(model)
                let modelLabel = NSTextField(labelWithString: modelName)
                modelLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                modelLabel.textColor = NSColor.secondaryLabelColor
                modelLabel.frame = NSRect(x: padding, y: y, width: 110, height: smallLineHeight)
                container.addSubview(modelLabel)

                let tokenStr = "\(formatTokenCount(tokens.inputTokens)) in / \(formatTokenCount(tokens.outputTokens)) out"
                let tokenLabel = NSTextField(labelWithString: tokenStr)
                tokenLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
                tokenLabel.textColor = NSColor.labelColor
                tokenLabel.frame = NSRect(x: padding + 114, y: y, width: contentWidth - 114, height: smallLineHeight)
                container.addSubview(tokenLabel)
            }
        }

        return container
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func colorForPercentage(_ pct: Double) -> NSColor {
        switch pct {
        case ..<30:
            return NSColor.systemGreen
        case 30..<60:
            return NSColor.systemBlue
        case 60..<80:
            return NSColor.systemYellow
        case 80..<90:
            return NSColor.systemOrange
        default:
            return NSColor.systemRed
        }
    }

    private func formatModelName(_ model: String) -> String {
        model.replacingOccurrences(of: "claude-", with: "Claude ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // Silently ignore — user can manage via System Settings
            }
            buildMenu()
        }
    }

    @objc private func checkForUpdates() {
        if let url = URL(string: "https://github.com/Spidey28/claude-menu-bar/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        let alert = NSAlert()
        alert.messageText = "Claude Monitor"
        alert.informativeText = "Version \(version) (\(build))\n\nA lightweight macOS menu bar app that shows your Claude Code context window usage in real-time.\n\nMIT License"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func refreshNow() {
        updateDisplay()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
