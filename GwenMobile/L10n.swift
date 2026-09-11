import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case de
    case en

    var id: String { rawValue }
    var flag: String { self == .de ? "🇩🇪" : "🇬🇧" }
    var label: String { self == .de ? "Deutsch" : "English" }
    var locale: Locale { Locale(identifier: self == .de ? "de_DE" : "en_US") }

    nonisolated static var deviceDefault: AppLanguage {
        Locale.current.language.languageCode?.identifier == "de" ? .de : .en
    }
}

enum L {
    nonisolated(unsafe) private static var current: AppLanguage = persistedLanguage()

    nonisolated static var lang: AppLanguage { current }

    nonisolated static func persistedLanguage() -> AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKey.language) ?? "")
            ?? .deviceDefault
    }

    nonisolated static func apply(_ language: AppLanguage) { current = language }

    nonisolated static func t(_ key: String) -> String {
        strings[key]?[lang] ?? key
    }

    nonisolated static func fmt(_ key: String, _ arg: String) -> String {
        (strings[key]?[lang] ?? key).replacingOccurrences(of: "%@", with: arg)
    }

    nonisolated static func fmt2(_ key: String, _ first: String, _ second: String) -> String {
        let parts = (strings[key]?[lang] ?? key).components(separatedBy: "%@")
        guard parts.count == 3 else { return parts.joined(separator: "%@") }
        return parts[0] + first + parts[1] + second + parts[2]
    }

    nonisolated static func n(_ key: String, _ count: Int) -> String {
        t(key).replacingOccurrences(of: "%d", with: String(count))
    }

    nonisolated static var dayFormat: String { lang == .de ? "d. MMMM yyyy" : "MMMM d, yyyy" }
    nonisolated static var timeFormat: String { lang == .de ? "HH:mm" : "h:mm a" }
    nonisolated static var calStartFormat: String { lang == .de ? "E, d. MMM yyyy HH:mm" : "EEE, MMM d, yyyy h:mm a" }

    struct FriendlyError {
        var message: String
        var detail: String
        var openSettings: Bool
    }

    nonisolated static func friendlyError(_ raw: String, model: String? = nil, status: Int? = nil) -> FriendlyError {
        let low = raw.lowercased()
        let detail = detailLine(raw, status: status)
        func fe(_ key: String, settings: Bool = false) -> FriendlyError {
            FriendlyError(message: t(key), detail: detail, openSettings: settings)
        }
        if low.contains("exceeded maximum duration") { return fe("asr_too_long") }
        if status == 401 || status == 403 || low.contains("invalid_api_key") || low.contains("invalidapikey")
            || low.contains("invalid api-key") || low.contains("invalid api key") {
            return fe("err_bad_key", settings: true)
        }
        if low.contains("model_not_found") || low.contains("model not exist") || low.contains("model not found") {
            return FriendlyError(message: fmt("err_model_gone", model ?? "?"), detail: detail, openSettings: true)
        }
        if status == 429 || low.contains("throttling") || low.contains("rate limit")
            || low.contains("quota") || low.contains("429") {
            return fe("err_rate_limited")
        }
        if low.contains("could not be found") || low.contains("network connection")
            || low.contains("not connected to the internet") || low.contains("wifi appears to be turned off")
            || low.contains("a server with the specified hostname") || low.contains("offline")
            || low.contains("netzwerk") || low.contains("verbindung zum server") {
            return fe("net_error")
        }
        if low.contains("authorized to record") || low.contains("!rec") || low.contains("permission") {
            return fe("mic_denied")
        }
        return FriendlyError(message: raw, detail: "", openSettings: false)
    }

    private static func detailLine(_ raw: String, status: Int?) -> String {
        var head = raw.components(separatedBy: ":").first ?? raw
        head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.count > 60 { head = String(head.prefix(60)) + "…" }
        if head.isEmpty { return status.map { "HTTP \($0)" } ?? "" }
        if let s = status { return "\(head) · HTTP \(s)" }
        return head
    }

    nonisolated static var defaultTitle: String { t("new_conversation") }

    static let defaultTitles: Set<String> = Set((strings["new_conversation"] ?? [:]).values)

    static let strings: [String: [AppLanguage: String]] = [
        "new_conversation": [.de: "Neue Unterhaltung", .en: "New conversation"],
        "new_chat": [.de: "Neuer Chat", .en: "New chat"],
        "message": [.de: "Nachricht", .en: "Message"],
        "empty_hint": [.de: "Frag Qwen etwas — hänge gern ein Foto an.",
                       .en: "Ask Qwen anything — feel free to attach a photo."],
        "today": [.de: "Heute", .en: "Today"],
        "yesterday": [.de: "Gestern", .en: "Yesterday"],
        "read": [.de: "Gelesen", .en: "Read"],
        "error": [.de: "Fehler", .en: "Error"],
        "ok": [.de: "OK", .en: "OK"],
        "no_camera_title": [.de: "Keine Kamera", .en: "No camera"],
        "no_camera_msg": [.de: "Dieses Gerät/Simulator hat keine Kamera. Nutze den Galerie-Knopf.",
                          .en: "This device/simulator has no camera. Use the gallery button."],
        "settings": [.de: "Einstellungen", .en: "Settings"],
        "done": [.de: "Fertig", .en: "Done"],
        "cancel": [.de: "Abbrechen", .en: "Cancel"],
        "conversations_word": [.de: "Unterhaltungen", .en: "conversations"],
        "messages_word": [.de: "Nachrichten", .en: "messages"],
        "images_word": [.de: "Bilder", .en: "images"],
        "api_key": [.de: "Qwen Cloud API-Key", .en: "Qwen Cloud API key"],
        "create_key": [.de: "Key in der QwenCloud-Konsole erstellen →",
                       .en: "Create a key in the QwenCloud console →"],
        "endpoint": [.de: "Endpunkt", .en: "Endpoint"],
        "base_url": [.de: "Basis-URL", .en: "Base URL"],
        "endpoint_footer": [.de: "Wähle den Endpunkt deines Kontos aus der Liste (Token-Plan = eingelesen). Die passende URL steht in der QwenCloud-Konsole; bei Frankfurt zuerst Workspace-ID im Feld unten ersetzen. Änderungen wirken nach „Fertig“ sofort.",
                            .en: "Pick your account's endpoint from the list (Token Plan = detected). The matching URL is shown in the QwenCloud console; for Frankfurt replace the Workspace-ID in the field below first. Changes apply once you tap “Done”."],
        "chat_model": [.de: "Chat-Modell", .en: "Chat model"],
        "vision_model": [.de: "Vision-Modell (mit Bild)", .en: "Vision model (with image)"],
        "models": [.de: "Modelle", .en: "Models"],
        "load_models": [.de: "Modelle vom Konto laden", .en: "Load models from account"],
        "loading_models": [.de: "Lade Modelle…", .en: "Loading models…"],
        "models_footer_empty": [.de: "Modelle erscheinen nach „Modelle vom Konto laden“ (Liste deines Qwen-Accounts).",
                                .en: "Models appear after “Load models from account” (the list of your Qwen account)."],
        "models_footer_count": [.de: "%d Modelle deines Kontos geladen.", .en: "%d account models loaded."],
        "test_connection": [.de: "Verbindung testen", .en: "Test connection"],
        "testing": [.de: "Teste…", .en: "Testing…"],
        "language": [.de: "Sprache", .en: "Language"],
        "language_footer": [.de: "Sprache der App-Oberfläche.", .en: "Language of the app interface."],
        "test_prompt": [.de: "Antworte nur mit: OK", .en: "Reply with only: OK"],
        "connected_empty": [.de: "✔ verbunden (leere Antwort)", .en: "✔ connected (empty response)"],
        "answered": [.de: "✔ Antwort: ", .en: "✔ Response: "],
        "invalid_url": [.de: "Ungültige Basis-URL", .en: "Invalid base URL"],
        "models_error": [.de: "✖ Modelle: ", .en: "✖ Models: "],
        "describe_images": [.de: "Beschreibe das/die Bild(er).", .en: "Describe the image(s)."],
        "image_model": [.de: "Bildmodell (Erstellen/Bearbeiten)", .en: "Image model (create/edit)"],
        "err_data_inspection": [.de: "Deine Anfrage wurde vom Sicherheitsfilter des Bildmodells abgelehnt. Formuliere den Text neutraler (ohne Gewalt, nackte Personen, reale Personen oder Marken) und versuche es erneut.",
                                .en: "Your request was rejected by the image model's safety filter. Reword it neutrally (no violence, nudity, real people, or brands) and try again."],
        "err_content_policy": [.de: "Der Inhalt wurde von der Inhaltsrichtlinie blockiert. Bitte beschreibe das Bild anders.",
                               .en: "The content was blocked by the content policy. Please describe the image differently."],
        "err_invalid_input": [.de: "Ungültige Eingabe an das Bildmodell: ", .en: "Invalid input to the image model: "],
        "err_generic": [.de: "Fehler bei der Bildgenerierung: ", .en: "Image generation failed: "],
        "err_web_generic": [.de: "Fehler bei der Websuche: ", .en: "Web search failed: "],
        "err_cal_generic": [.de: "Fehler bei der Kalenderaktion: ", .en: "Calendar action failed: "],
        "err_rate_limited": [.de: "Zu viele Anfragen in kurzer Zeit. Dein Kontingent ist kurz erschöpft — bitte warte etwa eine Minute und sende erneut.",
                             .en: "Too many requests in a short time. Your quota just ran out — wait about a minute and send again."],
        "err_timeout": [.de: "Zeitüberschreitung bei der Bildgenerierung — bitte erneut versuchen.",
                        .en: "The image request timed out — please try again."],
        "audio_model": [.de: "Audio-Modell (Erkennung)", .en: "Audio model (recognition & speech)"],
        "voice": [.de: "Systemstimme (Vorlesen)", .en: "Voice (read aloud)"],
        "voice_male": [.de: "Männlich", .en: "Male"],
        "voice_female": [.de: "Weiblich", .en: "Female"],
        "system_lang": [.de: "Antworte immer auf Deutsch, unabhängig von der Sprache der Frage.",
                        .en: "Always respond in English, regardless of the language of the question."],
        "format_hint": [.de: "Strukturiere deine Antwort immer übersichtlich: Trenne thematische Abschnitte durch Leerzeilen. Wenn deine Antwort mehrere Punkte, Schritte oder Aspekte enthält, formuliere sie als Aufzählung — entweder mit je einem Gedankenstrich (-) am Zeilenanfang oder als nummerierte Liste (1., 2., ...), niemals beides gemischt. Hebe Schlüsselbegriffe, Namen und Zahlen mit **fett** hervor. Keine Markdown-Überschriften (#). Halte einzelne Absätze kurz (max. 3 Sätze).",
                        .en: "Always structure your answer clearly: separate thematic sections with blank lines. If your answer contains several points, steps or aspects, write them as a list — either one dash (-) per line at the start, or a numbered list (1., 2., ...), never both mixed. Highlight key terms, names and numbers in **bold**. No Markdown headings (#). Keep individual paragraphs short (max. 3 sentences)."],
        "tts_prefix": [.de: "Sprich den folgenden Text wörtlich und vollständig vor, ohne Zusätze oder Kommentare:\n\n",
                       .en: "Read the following text aloud verbatim and completely, without additions or comments:\n\n"],
        "mic_denied": [.de: "Mikrofon-Zugriff verweigert", .en: "Microphone access denied"],
        "asr_empty": [.de: "Keine Sprache erkannt", .en: "No speech detected"],
        "asr_timeout": [.de: "Zeitüberschreitung bei der Spracherkennung", .en: "Speech recognition timed out"],
        "tts_timeout": [.de: "Zeitüberschreitung bei der Sprachausgabe", .en: "Speech synthesis timed out"],
        "tts_empty": [.de: "Die Sprachausgabe lieferte kein Audio.", .en: "The speech synthesis returned no audio."],
        "asr_working": [.de: "Erkenne Sprache…", .en: "Recognizing speech…"],
        "asr_too_long": [.de: "Die Aufnahme war zu lang (max. 28 Sekunden). Bitte in kürzeren Abschnitten diktieren.",
                         .en: "The recording was too long (max 28 seconds). Please dictate in shorter sections."],
        "asr_countdown": [.de: "Aufnahme endet in %d s", .en: "Recording ends in %d s"],
        "err_bad_key": [.de: "Der API-Key ist ungültig oder abgelaufen. Bitte öffne die Einstellungen und setze einen neuen Key ein.",
                        .en: "Your API key is invalid or expired. Open Settings and paste a new key."],
        "err_model_gone": [.de: "Das gewählte Modell %@ existiert nicht mehr in deinem Konto. Bitte wähle ein anderes unter Einstellungen → Modelle.",
                           .en: "The selected model %@ no longer exists in your account. Pick another one under Settings → Models."],
        "open_settings": [.de: "Einstellungen öffnen", .en: "Open Settings"],
        "attach_photo": [.de: "Foto anhängen", .en: "Attach photo"],
        "camera": [.de: "Kamera", .en: "Camera"],
        "read_aloud": [.de: "Vorlesen", .en: "Read aloud"],
        "state_on": [.de: "AN", .en: "ON"],
        "state_off": [.de: "AUS", .en: "OFF"],
        "net_error": [.de: "Keine Verbindung zum Server — bitte Netzwerk prüfen.",
                      .en: "Could not reach the server — please check your network."],
        "image_mode_hint": [.de: "Wird automatisch genutzt, wenn du ein Bild mitschickst und eine Änderung beschreibst oder ein neues Bild erfindest.",
                            .en: "Used automatically when you attach an image and describe a change, or invent a new picture."],
        "no_image": [.de: "Kein Bild in der Antwort erhalten — Bildmodell prüfen.",
                     .en: "No image in the response — check the image model."],
        "generating_image": [.de: "Erzeuge Bild…", .en: "Generating image…"],
        "editing_image": [.de: "Bearbeite dein Bild…", .en: "Editing your image…"],
        "edit_this": [.de: "Bearbeiten", .en: "Edit"],
        "history": [.de: "Verläufe", .en: "Histories"],
        "history_empty": [.de: "Noch keine Verläufe.", .en: "No histories yet."],
        "delete_message": [.de: "Nachricht löschen", .en: "Delete message"],
        "delete_conversation": [.de: "Unterhaltung löschen", .en: "Delete conversation"],
        "delete_all": [.de: "Alle Verläufe löschen", .en: "Delete all histories"],
        "delete_all_title": [.de: "Alle Verläufe löschen?", .en: "Delete all histories?"],
        "delete_all_body": [.de: "%@ Unterhaltungen und %@ werden entfernt. 5 Sekunden rückgängig machbar.",
                            .en: "%@ conversations and %@ will be removed. Undo available for 5 seconds."],
        "fresh_start_note": [.de: "Der aktuell offene Chat wird ebenfalls entfernt; danach beginnt ein frischer Chat.",
                             .en: "The chat you are reading is removed too; a fresh chat starts afterwards."],
        "storage": [.de: "Speicher", .en: "Storage"],
        "storage_images": [.de: "Bilder", .en: "Images"],
        "storage_history": [.de: "Verlauf", .en: "History"],
        "freed": [.de: "%@ freigegeben", .en: "%@ freed"],
        "undo": [.de: "Rückgängig", .en: "Undo"],
        "cal_working": [.de: "Kümmere mich um den Termin…", .en: "Handling the appointment…"],
        "cal_created": [.de: "✔ Termin angelegt: %@", .en: "✔ Appointment created: %@"],
        "cal_updated": [.de: "✔ Termin geändert: %@", .en: "✔ Appointment changed: %@"],
        "cal_deleted": [.de: "✔ Termin gelöscht: %@", .en: "✔ Appointment deleted: %@"],
        "cal_denied": [.de: "Kein Kalender-Zugriff — bitte unter Einstellungen → Datenschutz → Kalender erlauben.",
                       .en: "No calendar access — allow it in Settings → Privacy & Security → Calendars."],
        "cal_not_found": [.de: "Keinen passenden Termin gefunden für: ", .en: "No matching appointment found for: "],
        "cal_no_date": [.de: "Ich habe kein Startdatum verstanden — bitte mit Angabe wie \"morgen 14 Uhr\".",
                        .en: "I couldn't determine a start date — please add one like \"tomorrow 2 pm\"."],
        "cal_default_title": [.de: "Termin", .en: "Appointment"],
        "cal_alerts": [.de: "🔔 Hinweise: %@", .en: "🔔 Notifications: %@"],
        "cal_alert_h": [.de: "%d Std vorher", .en: "%d h before"],
        "cal_alert_min": [.de: "%d Min vorher", .en: "%d min before"],
        "web_search_prompt": [.de: "Prüfe zuerst das heutige Datum: Ein Ereignis, das vor heute liegt, kann ein Ergebnis haben, das du nicht kennst. Wenn die Frage Ergebnisse, Gewinner, Statistiken, Preise oder Neuigkeiten betrifft, die nach deinem Wissensstand liegen könnten, oder du dir nicht sicher bist: antworte ausschließlich mit dem Token [[SEARCH]] und nichts sonst. Behaupte niemals, ein Ereignis habe noch nicht stattgefunden, ohne es sicher zu wissen — im Zweifel [[SEARCH]].",
                              .en: "Check today's date first: an event that lies before today may have a result you do not know. If the question concerns results, winners, statistics, prices or news that may postdate your knowledge, or you are unsure: reply with exactly the token [[SEARCH]] and nothing else. Never claim an event has not happened yet unless you are certain — when in doubt, [[SEARCH]]."],
        "web_sources_head": [.de: "Quellen", .en: "Sources"],
        "web_searching": [.de: "Ich suche im Internet…", .en: "Searching the web…"],
        "web_fetching": [.de: "Quelle wird abgefragt", .en: "Fetching source"],
        "web_no_results": [.de: "Websuche ergab keine verwertbaren Ergebnisse.", .en: "Web search returned no usable results."],
        "web_fetch_failed": [.de: "Webseite konnte nicht gelesen werden.", .en: "Could not read the web page."],
        "web_no_answer": [.de: "Modelle-Antwort auf die Recherche blieb leer.", .en: "The model returned no answer for the research."],
        "web_bad_query": [.de: "Ungültige Suchanfrage.", .en: "Invalid search query."],
        "image_saved": [.de: "✔ Bild in Fotos gespeichert", .en: "✔ Image saved to Photos"],
        "edit_frame": [.de: "Bearbeite ausschließlich das eingefügte Bild. Bewahre Motiv, Komposition, Objektform, Stil und Hintergrund unverändert bei und wende nur diese eine Änderung an: %@",
                       .en: "Edit the attached image only. Keep the subject, composition, object shapes, style and background unchanged; apply exactly this one modification: %@"],
        "edit_done_note": [.de: "Hier ist dein bearbeitetes Bild — tippe auf „In Fotos speichern“, um es zu sichern. Du kannst mir direkt dahinter eine weitere Änderung beschreiben.",
                           .en: "Here is your edited image — tap “Save to Photos” to keep it. You can describe another change right after this."],
        "image_default_prompt": [.de: "Erzeuge ein Bild basierend auf dem eingegangenen Bild.",
                                 .en: "Create an image based on the input image."],
        "save_failed": [.de: "✖ Speichern fehlgeschlagen: ", .en: "✖ Save failed: "],
        "save_to_photos": [.de: "In Fotos speichern", .en: "Save to Photos"],
        "no_sse": [.de: "Antwort ohne SSE-Daten erhalten — Basis-URL und Modell prüfen.",
                   .en: "Response contained no SSE data — check the base URL and model."],
        "bad_url": [.de: "Ungültige Basis-URL", .en: "Invalid base URL"],
    ]
}
