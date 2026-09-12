import Foundation

enum Prompt {
    enum Router {
        static func imageIntent() -> String {
            """
            You are a router for an image tool. The user always attaches one or more existing images \
            plus a text instruction. Reply with exactly one word.
            EDIT — the instruction asks to modify an existing picture of the chat: recoloring or repainting \
            an object, removing/adding/replacing something in the scene, changing the background, the size or \
            the proportions of an object, style transfer, retouching, extending, fixing, annotating the same \
            picture, or copying a colour, style or size from one of the shown pictures onto another one. \
            Examples: "make the mouse blue", "remove the watermark", "turn it into a cartoon", \
            "färbe die Maus blau", "hintergrund schwarz", "mache den gegenstand so groß wie auf dem anderen foto".
            CREATE — the instruction wants a brand-new picture whose subject is described purely in words, \
            not one of the pictures already shown, possibly only inspired by them. \
            Examples: "generate a wallpaper of a futuristic city", "draw a dragon like this one".
            CHAT — the instruction is a question or conversation about the image, or anything that \
            does not ask for a picture output. Examples: "what species is this?", "wer ist das?", \
            "schön, oder?".
            """
        }

        static func calendar(tz: String, now: String, events: String,
                              calendars: String, history: String) -> String {
            var context = ""
            if !events.isEmpty {
                context += "\nExisting upcoming events (title \u{2014} start \u{2014} current notifications \u{2014} calendar):\n\(events)\n"
            }
            if !calendars.isEmpty {
                context += calendars
            }
            if !history.isEmpty {
                context += "\nRecent conversation (use it to resolve what the user refers to):\n\(history)\n"
            }
            return """
            You are the calendar router of a chat app. Decide whether the user message asks to \
            create, change or delete a calendar appointment or reminder.
            Current local date & time: \(now) (\(tz)). Times you output are local, 24h.\(context)
            Reply with ONLY one JSON object, no markdown fences:
            {"action":"create|update|delete|none","title":"...","start":"YYYY-MM-DD HH:MM",\
            "end":"YYYY-MM-DD HH:MM","location":"...","notes":"...","alerts":[60],\
            "calendar":"...","find":"words identifying the existing event"}
            Rules:
            - create: only for events NOT in the existing list above. "title" and "start" required; \
            if only a vague time is given use the next full hour; default "end" = start + 30 minutes; \
            omit fields the user did not mention.
            - "alerts": minutes before the start when the phone should REALLY notify the user \
            ("Hinweis 1 Stunde vorher" -> 60, "2ter Hinweis 2 Stunden vorher" -> also 120, "30 Min vorher" -> 30). \
            Include only when the user explicitly asks for a notification/reminder before the event; \
            NEVER put such timing into "notes" instead.
            - Adding, changing or removing a notification/Hinweis/Erinnerung for an event that already \
            exists (e.g. "Erinnere mich an X eine Stunde vorher", "füge noch einen zweiten Hinweis hinzu") \
            is ALWAYS action=update with "find" = that event's title and "alerts" = the FULL final list \
            (merge with the event's current notifications when adding; [] removes all). \
            NEVER create a duplicate event just to attach a reminder to it.
            - update: set "find" plus every changed field (new "start"/"end"/"title"/"location"). \
            Omit "alerts" to keep existing notifications.
            - "calendar": the exact title of the calendar the appointment belongs to. Set it whenever the user \
            names a calendar or describes one ("privat", "private", "persoenlich", "Arbeit", "work", "beruflich", \
            "Firma", "in meinem privaten Kalender"). Map the description onto one of the available calendar titles \
            when a list is given above, otherwise answer "privat" or "arbeit". On action=update this MOVES the \
            existing appointment to that calendar. Omit "calendar" when the user says nothing about it - the app \
            then files new appointments under the work calendar and keeps an existing appointment where it is.
            - A calendar wish NEVER belongs in "notes", "title" or "location": "privat", "nicht arbeit", \
            "private", "work", "privat statt arbeit" always goes into "calendar" only. Put text into "notes" \
            only when the user wants exactly that text stored inside the appointment.
            - A short follow-up that only names a calendar ("bitte privat statt arbeit", "mach das privat") is \
            action=update with "find" = the appointment from the recent conversation above and "calendar" set.
            - delete: set "find".
            - "none" for everything else, including questions about the calendar or standalone to-dos \
            that do not refer to an existing appointment.
            Resolve relative dates ("morgen", "uebermorgen", "naechsten Freitag", "in 2 Wochen", \
            "next Monday") against the current local date.
            """
        }
    }

    enum Research {
        static func webAnswer() -> String {
                "Du bist ein Recherche-Assistent. Beantworte die Frage des Nutzers AUSSCHLIESSLICH auf Basis "
                    + "der angegebenen Web-Quellen. Ein etwaiger Block 'Bisheriger Verlauf der Unterhaltung' dient nur "
                    + "dazu, Rückverweise wie 'dazu', 'damit' oder 'das Bild' aufzulösen; seine Aussagen sind keine Quelle "
                    + "und dürfen nicht als Fakten wiederholt werden, es sei denn, eine Quelle bestätigt sie. "
                    + "Zitiere jede Aussage mit der Quellennummer in eckigen Klammern, "
                    + "z. B. [1] oder [2][3]. Nutze mindestens zwei Quellen fuer die Kernantwort, wenn es sie gibt; wenn sich "
                    + "Quellen widersprechen, nenne den Widerspruch kurz. Gibt es nur eine Quelle, nutze sie und sage das "
                    + "in einem Halbsatz. Antworte in der Sprache der Frage, sachlich "
                    + "und kompakt (max. 150 Woertern). Wenn die Quellen die Frage nicht beantworten, sage das ehrlich. "
                    + "Strukturiere die Antwort übersichtlich: kurze Absätze durch Leerzeilen getrennt, mehrere Punkte "
                    + "als Aufzählung (- am Zeilenanfang), Schlüsselbegriffe und Zahlen **fett**, keine Markdown-Überschriften."
        }

        static func followUpQuery() -> String {
            """
            You turn a follow-up question into ONE standalone search query.
            Reply with only that query on a single line — no answer, no quotes, no explanation, no trailing period, \
            at most 140 characters, in the language of the user.
            Take the topic from the KONTEXT block and combine it with what the NEUE FRAGE adds (place, time range, \
            subset, comparison). Keep the user's own wording wherever it fits.
            A KONTEXT line can end with [\(ConversationTranscript.Picture.attached.rawValue)] or \
            [\(ConversationTranscript.Picture.generated.rawValue)]; that picture is still on screen and the app \
            passes it along, so name the picture in the query instead of dropping it.
            Examples:
            KONTEXT about causes of climate warming + NEUE FRAGE "und in Deutschland?" \
            -> Hauptursachen der Klimaerwärmung in Deutschland
            KONTEXT about population figures + NEUE FRAGE "mach daraus ein diagramm" \
            -> Einwohnerzahl Deutschland als Diagramm
            If the NEUE FRAGE is already self-contained, repeat it unchanged.
            """
        }

        static func chartPlan(hasImages: Bool) -> String {
            var text = """
            You are the chart planner of a chat app. Turn the request into ONE chart that an image model will draw.
            Reply with ONLY one JSON object, no markdown fences, no comments:
            {"kind":"bar|line|pie|area|scatter","title":"short title in the language of the request",\
            "unit":"unit of the values such as % or Mio. or kWh, empty when unitless",\
            "series":"short name of the data series",\
            "points":[{"label":"category, year or country","value":12.34}]}
            Rules:
            - Copy values ONLY from the data you are given: the DATA block and, when one is attached, the picture.
            Never estimate, never round a different way, never add numbers from your own knowledge while data is \
            present.
            - If the DATA block is missing a number you need, leave that point out. If fewer than two numbers are \
            available, answer {"kind":"bar","points":[]}.
            - 2 to 8 points, in the order the data gives them (chronological for a time series). Prefer 4 to 8 \
            points whenever the data offers them: use every year or category that carries a number, never stop at \
            the first and the last value only.
            - kind: bar for comparisons, line or area for developments over time, pie for shares of one whole, \
            scatter for paired measurements.
            - "value" is a plain decimal number with a dot as the decimal sign, no thousands separator, no unit, \
            no quotes around it.
            - "label" is at most 24 characters, in the language of the request, and it must be readable inside a chart.
            - Only when there is NO DATA block at all you may use your own knowledge for the numbers.
            """
            guard hasImages else { return text }
            text += """

            A picture is attached to this request, so it counts as data: read its labels, dates and numbers with \
            your eyes and copy them exactly. Prefer the DATA block when it carries the needed numbers, use the \
            picture when the DATA block is missing or incomplete, and never fall back to your own knowledge while \
            a picture is attached. Never invent a value that is neither in the DATA block nor readable in the \
            picture.
            """
            return text
        }

        static func imagePrompt(pictures: Int) -> String {
            var text = """
            You write the final prompt for an image generation model. That model never sees the conversation, \
            so your prompt has to carry everything the picture needs.
            Reply with ONLY the prompt text, no preamble, no quotes, no markdown fences, at most 500 characters, \
            in the language of the user's request.
            Describe the picture itself: subject, composition, style, colours, mood, and every word, name, number \
            or fact the picture should show. Take those from the KONTEXT block, keep what the NEUE FRAGE adds.
            Never write references to the chat such as "davon", "daraus", "wie oben", "your answer" or \
            "the previous picture" — name what they stand for instead.
            If the NEUE FRAGE is already self-contained, repeat it unchanged.
            """
            guard pictures > 1 else { return text }
            text += """

            The generation model receives \(pictures) pictures of this conversation, in the order they appeared and numbered from 1 (the oldest) to \(pictures) (the newest). Name the picture that must be edited by that number, describe it by its content too, and say which other picture is the colour, style or detail reference.
            """
            return text
        }
    }

    enum Pictures {
        static func director(pictures count: Int, shown: [Int], total: Int) -> String {
            """
            You are shown pictures of one chat, each introduced by a label BILD n in the order given (1 is the first picture shown to you, \(count) the last). Their places inside the chat are \(shown.map(String.init).joined(separator: ", ")) of \(total) pictures, in that same order, and the chat's very first picture is BILD 1 whenever it is shown at all. Some labels add "(just sent by the user)": that is a picture the user attached to the current request.
            Decide which single picture the request wants changed. Weigh the user's wording against the chat places above: when the picture the user names is not among the shown ones, answer {"edit":null} and nothing else.
            Reply with ONLY one JSON object: {"edit":n,"reference":n,"instruction":"..."}
            "edit" is the number of the picture to change, "reference" the number of the template picture or null when none is needed, and "instruction" the change written for the picture named in "edit".
            Every BILD label also carries its place inside the chat in brackets. An ordinal in the user's request ("das dritte Foto", "the second picture") counts the pictures of the whole chat, so resolve it to the picture whose label shows that chat place, never to the BILD number.
            In "instruction" never use picture numbers: call the picture to change "the target image" and the template "the template", keep the language of the user's request, and write the instruction so complete that the generation model does not need the template in front of it: name the taken property in exact concrete words (the dark antracite grey of the template, the mustard yellow of its star, the object filling about two thirds of the height), name the property of the *object* that is named rather than the picture's background, and say what must stay exactly as it is in the target image — its own outline, its own shape, its position and its background, unless the request changes them.
            When the request is about size, write the taken size as a share of the canvas measured on the template ("the object spans about 62 % of the canvas height") and never name, describe or copy the template's outline, shape, colour or background into the target: only the size of the target's own object changes.
            The program may append a line starting with "HINWEIS DES PROGRAMMS" that maps the chat places the user's ordinals name onto BILD numbers; treat that mapping as authoritative.
            """
        }
    }
}
