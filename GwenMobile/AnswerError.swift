import Foundation

enum AnswerError {
    static let marker = "⚠️ "
    static let detailPrefix = "\n\nℹ️ "
    static let rawDetailLimit = 120

    static func model(_ raw: String, model: String?, generic: String) -> String {
        let t = raw.lowercased()
        let detail = String(raw.prefix(rawDetailLimit))
        if IntentHeuristics.safetyRejection.matches(t) {
            return marker + L.t("err_data_inspection") + detailPrefix + detail
        }
        if IntentHeuristics.contentPolicyRejection.matches(t) {
            return marker + L.t("err_content_policy") + detailPrefix + detail
        }
        if IntentHeuristics.invalidInput.matches(t) {
            return marker + L.t("err_invalid_input") + detail
        }
        if IntentHeuristics.timeoutInterruption.matches(t) {
            return marker + L.t("err_timeout")
        }
        return other(raw, model: model, generic: generic)
    }

    static func other(_ raw: String, model: String? = nil, generic: String) -> String {
        let friendly = L.friendlyError(raw, model: model)
        if friendly.message != raw {
            return marker + friendly.message + (friendly.detail.isEmpty ? "" : detailPrefix + friendly.detail)
        }
        return marker + generic + String(raw.prefix(rawDetailLimit))
    }
}
