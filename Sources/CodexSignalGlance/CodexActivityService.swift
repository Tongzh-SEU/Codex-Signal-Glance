import Foundation

final class CodexActivityService: @unchecked Sendable {
    private let sessionDirectory: URL
    private let decoderFormatter: ISO8601DateFormatter
    private let fallbackFormatter: ISO8601DateFormatter
    private let finalAnswerVisibleDuration: TimeInterval = 1.5

    init(sessionDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.sessionDirectory = sessionDirectory
        self.decoderFormatter = ISO8601DateFormatter()
        self.decoderFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fallbackFormatter = ISO8601DateFormatter()
        self.fallbackFormatter.formatOptions = [.withInternetDateTime]
    }

    func latestActivity() -> CodexActivitySnapshot {
        for file in newestSessionFiles(limit: 16) {
            if let snapshot = parseActivity(from: file.url) {
                return snapshot
            }
        }
        return .idle
    }

    private func newestSessionFiles(limit: Int) -> [(url: URL, modifiedAt: Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            files.append((fileURL, values?.contentModificationDate ?? .distantPast))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func parseActivity(from fileURL: URL) -> CodexActivitySnapshot? {
        var activity: CodexActivitySnapshot?
        var isInsideTurn = false
        var isWaitingForPlanChoice = false
        var lastFinalAnswerAt: Date?

        for rawLine in recentLines(from: fileURL, maxBytes: 512 * 1024) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let eventTimestamp = parseTimestamp(event["timestamp"] as? String)
            guard
                let update = activityUpdate(
                    from: event,
                    isInsideTurn: isInsideTurn,
                    isWaitingForPlanChoice: isWaitingForPlanChoice,
                    lastFinalAnswerAt: lastFinalAnswerAt,
                    eventTimestamp: eventTimestamp
                )
            else {
                continue
            }

            isInsideTurn = update.isInsideTurn
            isWaitingForPlanChoice = update.isWaitingForPlanChoice
            if update.clearsFinalAnswer {
                lastFinalAnswerAt = nil
            }
            if update.isFinalAnswer {
                lastFinalAnswerAt = eventTimestamp
            }
            activity = CodexActivitySnapshot(
                status: update.status,
                eventTimestamp: eventTimestamp,
                needsHumanAttention: update.needsHumanAttention
            )
        }

        return activity
    }

    private func activityUpdate(
        from event: [String: Any],
        isInsideTurn: Bool,
        isWaitingForPlanChoice: Bool,
        lastFinalAnswerAt: Date?,
        eventTimestamp: Date?
    ) -> (
        status: CodexActivityStatus,
        isInsideTurn: Bool,
        isWaitingForPlanChoice: Bool,
        isFinalAnswer: Bool,
        clearsFinalAnswer: Bool,
        needsHumanAttention: Bool
    )? {
        let type = event["type"] as? String
        let payload = event["payload"] as? [String: Any]
        let payloadType = payload?["type"] as? String

        if payload?["phase"] as? String == "final_answer" {
            return (.waitingForUser, false, isWaitingForPlanChoice, true, false, false)
        }

        if containsHumanWaitingSignal(in: payload) || containsHumanReviewSignal(in: payload) {
            return (.waitingForUser, true, isWaitingForPlanChoice, false, false, true)
        }

        if containsAutoReviewSignal(in: payload) {
            return (.waitingForUser, true, isWaitingForPlanChoice, false, false, false)
        }

        if isToolStartEvent(type: type, payloadType: payloadType, payload: payload) {
            return (.answering, true, false, false, true, false)
        }

        switch type {
        case "event_msg":
            switch payloadType {
            case "task_started":
                return (.waitingForUser, true, false, false, true, false)
            case "task_complete":
                if shouldKeepFinalAnswerVisible(finalAnswerAt: lastFinalAnswerAt, taskCompleteAt: eventTimestamp) {
                    return (.waitingForUser, false, isWaitingForPlanChoice, false, false, false)
                }
                return isWaitingForPlanChoice
                    ? (.waitingForUser, false, true, false, false, true)
                    : (.finished, false, false, false, false, false)
            case "turn_aborted", "thread_rolled_back":
                return (.finished, false, false, false, true, false)
            case "user_message":
                return (.waitingForUser, true, false, false, true, false)
            case "agent_message":
                if containsPlanChoiceSignal(in: payload) {
                    return (.waitingForUser, false, true, false, false, true)
                }
                if isExecutionCommentary(payload) {
                    return (.answering, true, false, false, true, false)
                }
                return isInsideTurn ? (.answering, true, isWaitingForPlanChoice, false, false, false) : nil
            case "thread_goal_updated":
                return nil
            case "patch_apply_begin", "patch_apply_end":
                return (.answering, true, false, false, true, false)
            case "agent_message_delta":
                return isInsideTurn ? (.answering, true, isWaitingForPlanChoice, false, false, false) : nil
            case "token_count":
                return nil
            default:
                return payloadType == nil || !isInsideTurn ? nil : (.answering, true, isWaitingForPlanChoice, false, false, false)
            }

        case "response_item":
            if containsPlanChoiceSignal(in: payload) {
                return (.waitingForUser, false, true, false, false, true)
            }
            switch payloadType {
            case "function_call":
                let needsUser = functionCallNeedsUser(payload)
                return (needsUser ? .waitingForUser : .answering, true, false, false, true, needsUser)
            case "function_call_output", "custom_tool_call_output":
                return (.answering, true, false, false, true, false)
            case "reasoning":
                return isInsideTurn ? (.waitingForUser, true, isWaitingForPlanChoice, false, false, false) : nil
            case "message":
                if isExecutionCommentary(payload) {
                    return (.answering, true, false, false, true, false)
                }
                return isInsideTurn ? (.answering, true, isWaitingForPlanChoice, false, false, false) : nil
            case "custom_tool_call", "web_search_call":
                return (.answering, true, false, false, true, false)
            default:
                return payloadType == nil || !isInsideTurn ? nil : (.answering, true, isWaitingForPlanChoice, false, false, false)
            }

        case "turn_context", "session_meta", "compacted":
            return nil

        default:
            return nil
        }
    }

    private func functionCallNeedsUser(_ payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        let name = payload["name"] as? String ?? ""
        if name == "request_user_input" || name == "request_plugin_install" {
            return true
        }

        let arguments = payload["arguments"] as? String ?? ""
        return arguments.localizedCaseInsensitiveContains("require_escalated")
            || arguments.localizedCaseInsensitiveContains("sandbox_permissions")
    }

    private func isToolStartEvent(type: String?, payloadType: String?, payload: [String: Any]?) -> Bool {
        guard functionCallNeedsUser(payload) == false else {
            return false
        }

        let structuredTypes = [type, payloadType].compactMap { $0 }
        if structuredTypes.contains(where: isToolStartType) {
            return true
        }

        let name = payload?["name"] as? String ?? ""
        return name == "apply_patch"
            || name == "exec_command"
            || name == "write_stdin"
            || name == "view_image"
    }

    private func isToolStartType(_ value: String) -> Bool {
        switch value {
        case "function_call", "custom_tool_call", "web_search_call", "patch_apply_begin":
            return true
        default:
            return false
        }
    }

    private func containsHumanWaitingSignal(in payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        let type = payload["type"] as? String ?? ""
        let name = payload["name"] as? String ?? ""
        if type.localizedCaseInsensitiveContains("approval")
            || type.localizedCaseInsensitiveContains("permission")
            || type.localizedCaseInsensitiveContains("request_user_input")
            || name.localizedCaseInsensitiveContains("approval")
            || name.localizedCaseInsensitiveContains("permission")
        {
            return true
        }
        return functionCallNeedsUser(payload)
    }

    private func containsAutoReviewSignal(in payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        let structuredValues = [
            payload["type"],
            payload["name"],
            payload["status"],
            payload["reviewer"],
            payload["approval_reviewer"],
            payload["approvals_reviewer"],
        ].compactMap { $0 as? String }

        return structuredValues.contains { value in
            let normalized = value.replacingOccurrences(of: "-", with: "_")
            return normalized.localizedCaseInsensitiveContains("auto_review")
        }
    }

    private func containsHumanReviewSignal(in payload: [String: Any]?) -> Bool {
        guard let payload, !containsAutoReviewSignal(in: payload) else { return false }
        let structuredValues = [
            payload["type"],
            payload["name"],
            payload["status"],
            payload["reviewer"],
            payload["approval_reviewer"],
            payload["approvals_reviewer"],
        ].compactMap { $0 as? String }

        return structuredValues.contains { value in
            let normalized = value.replacingOccurrences(of: "-", with: "_")
            return normalized.localizedCaseInsensitiveContains("review_pending")
                || normalized.localizedCaseInsensitiveContains("reviewing")
                || normalized.localizedCaseInsensitiveContains("reviewer")
        }
    }

    private func containsPlanChoiceSignal(in payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        return stringValues(in: payload).contains { value in
            value.localizedCaseInsensitiveContains("<proposed_plan>")
                || value.localizedCaseInsensitiveContains("实施此计划")
        }
    }

    private func isExecutionCommentary(_ payload: [String: Any]?) -> Bool {
        guard
            let payload,
            (payload["phase"] as? String) == "commentary"
        else {
            return false
        }

        return stringValues(in: payload).contains { value in
            value.localizedCaseInsensitiveContains("正在编辑")
                || value.localizedCaseInsensitiveContains("apply_patch")
                || value.localizedCaseInsensitiveContains("执行")
                || value.localizedCaseInsensitiveContains("运行")
                || value.localizedCaseInsensitiveContains("构建")
                || value.localizedCaseInsensitiveContains("测试")
                || value.localizedCaseInsensitiveContains("正在修改")
                || value.localizedCaseInsensitiveContains("开始修改")
        }
    }

    private func shouldKeepFinalAnswerVisible(finalAnswerAt: Date?, taskCompleteAt: Date?) -> Bool {
        guard let finalAnswerAt, let taskCompleteAt else {
            return false
        }
        guard taskCompleteAt.timeIntervalSince(finalAnswerAt) <= 1 else {
            return false
        }
        return Date().timeIntervalSince(taskCompleteAt) < finalAnswerVisibleDuration
    }

    private func stringValues(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.flatMap { stringValues(in: $0) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap { stringValues(in: $0) }
        }
        return []
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let value = decoderFormatter.date(from: raw) {
            return value
        }
        return fallbackFormatter.date(from: raw)
    }

    private func recentLines(from fileURL: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        let totalBytes = (try? handle.seekToEnd()) ?? 0
        let readOffset = totalBytes > UInt64(maxBytes) ? totalBytes - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: readOffset)

        var data = handle.readDataToEndOfFile()
        if readOffset > 0, let newlineRange = data.range(of: Data([0x0A])) {
            data = data.subdata(in: newlineRange.upperBound..<data.count)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.components(separatedBy: .newlines)
    }
}
