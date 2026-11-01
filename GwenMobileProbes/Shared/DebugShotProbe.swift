@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import SwiftUI
import UIKit

@MainActor
enum DebugShotProbe {
    static let releaseMarkerName = "shot_release"
    static func chat(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_chat.txt", name: "chat") else { return }
        let question = ChatMessage(role: .user, text: "Which are the three largest cities in Germany?")
        view.store.appendMessage(question, to: id)
        let answer = ChatMessage(role: .assistant,
                                 text: "By population, the three largest cities in Germany are:\n\n"
                                     + "1. **Berlin** — about 3.9 million people [1]\n"
                                     + "2. **Hamburg** — about 1.9 million people [1]\n"
                                     + "3. **Munich** — about 1.5 million people [2]\n\n"
                                     + "Berlin has grown the most over the past decade; the top three itself "
                                     + "has not changed.",
                                 model: "qwen3.8-flash", elapsed: 3.4,
                                 sources: [WebSource(title: "Destatis", url: "https://www.destatis.de/",
                                                     domain: "destatis.de"),
                                           WebSource(title: "Wikipedia", url: "https://de.wikipedia.org/",
                                                     domain: "wikipedia.org"),
                                           WebSource(title: "Statista", url: "https://www.statista.com/",
                                                     domain: "statista.com")],
                                 sourcesHeadingKey: "web_sources_head")
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func plusMenu(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_plus_menu.txt", name: "plus-menu") != nil else { return }
        view.attachMenu = true
        try? await Task.sleep(for: .milliseconds(500))
        await hold()
    }

    static func settings(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_settings.txt", name: "settings") != nil else { return }
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1500))
        await hold()
    }

    static func settingsVoice(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_settings_voice.txt", name: "settings-voice") != nil else { return }
        view.settingsCategory = .voice
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1500))
        _ = await scrollSettings(offset: 330)
        await hold()
    }

    static func settingsModels(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_settings_models.txt", name: "settings-models") != nil else { return }
        view.settingsCategory = .ai
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1500))
        _ = await scrollSettings(offset: 420)
        await hold()
    }

    static func settingsPersonal(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_settings_personal.txt", name: "settings-personal") != nil else { return }
        view.settingsCategory = .data
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1500))
        await hold()
    }

    static func help(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_help.txt", name: "help") != nil else { return }
        view.showHelp = true
        try? await Task.sleep(for: .milliseconds(1500))
        await hold()
    }

    static func settingsMusic(_ view: ChatView) async {
        L.apply(.en)
        guard start(view, file: "shot_settings_music.txt", name: "settings-music") != nil else { return }
        view.settingsCategory = .services
        view.showSettings = true
        try? await Task.sleep(for: .milliseconds(1500))
        await hold()
    }

    static func histories(_ view: ChatView) async {
        L.apply(.en)
        cleanup = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shot-history-\(UUID().uuidString)")
        let paths = StoragePaths(documents: folder)
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        func add(_ question: String, _ answer: String) {
            store.newConversation()
            guard let id = store.currentID else { return }
            store.appendMessage(ChatMessage(role: .user, text: question), to: id)
            store.appendMessage(ChatMessage(role: .assistant, text: answer,
                                             model: "qwen3.8-flash", elapsed: 1.2), to: id)
        }
        add("Read what stands on my receipt photo", "The receipt lists headphones and the total.")
        add("Translate \"I will be late, please start without me\"", "Ich komme später, bitte fangt ohne mich an.")
        add("Compare the prices of a MacBook Pro 14\" and a MacBook Pro 16\"",
            "The 14\" starts lower; the 16\" costs more.")
        add("Which are the three largest cities in Germany?", "Berlin, Hamburg and Munich.")
        let report = SweepReport(file: "shot_histories.txt")
        report.add("SHOT", "histories")
        let appearance = AppSettings.shared.appearance
        let language = AppSettings.shared.language
        AppSettings.shared.appearance = .light
        AppSettings.shared.language = .en
        guard let window = ProbeHosting.host(NavigationStack {
            HistoryView().environmentObject(store).environmentObject(store.cleaner)
        }) else {
            AppSettings.shared.appearance = appearance
            AppSettings.shared.language = language
            try? FileManager.default.removeItem(at: folder)
            return
        }
        window.overrideUserInterfaceStyle = .light
        try? await Task.sleep(for: .milliseconds(1500))
        await hold()
        ProbeHosting.close(window)
        AppSettings.shared.appearance = appearance
        AppSettings.shared.language = language
        try? FileManager.default.removeItem(at: folder)
    }

    static func conversation(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_conversation.txt", name: "conversation") else { return }
        let question = ChatMessage(role: .user, text: "I'll just start talking — no wake word.")
        view.store.appendMessage(question, to: id)
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "Go ahead. I'll stop speaking the moment I hear you, and "
                                                 + "your next sentence becomes the next turn.",
                                             model: "qwen3.8-flash", elapsed: 1.2), to: id)
        view.settings.voice.speakAnswers = true
        view.settings.voice.conversationMode = true
        await focus(view, on: question.id)
        view.voice.state = .recording
        await hold()
    }

    static func weather(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_weather.txt", name: "weather") else { return }
        let date = WeatherDayTabs.stamp(Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let place = WeatherPlace(name: "Munich", latitude: 48.137,
                                 longitude: 11.575, timezone: "Europe/Berlin")
        guard let ref = OpenMeteo.day(from: shotForecastJSON(date: date), date: date,
                                      place: place) else { return }
        let question = ChatMessage(role: .user,
                                   text: "What will the weather be like tomorrow in Munich?")
        view.store.appendMessage(question, to: id)
        let advice = WeatherAdviceRules.advice(for: ref)
        var answer = ChatMessage(role: .assistant, text: WeatherAnswers.text(ref: ref, advice: advice),
                                 model: "qwen3.8-flash", elapsed: 1.4)
        answer.weatherRef = ref
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func reminders(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_reminders.txt", name: "reminders") else { return }
        let nine = day(1, hour: 9)
        let dentist = ReminderRef(reminderID: "shot-dentist", title: "Dentist", list: "Reminders",
                                  due: nine, allDay: false, place: nil)
        let milk = ReminderRef(reminderID: "shot-milk", title: "Milk", list: "Shopping",
                               due: nil, allDay: false, place: nil)
        let question = ChatMessage(role: .user, text: "Remind me tomorrow at 9 about the dentist")
        view.store.appendMessage(question, to: id)
        var first = ChatMessage(role: .assistant,
                                text: L.fmt("rem_created", "Dentist\n"
                                            + L.fmt("rem_due_line", Formatters.eventStart(nine)) + "\n"
                                            + L.fmt("rem_list_line", "Reminders")),
                                model: "qwen3.8-flash", elapsed: 1.2)
        first.reminderRef = dentist
        view.store.appendMessage(first, to: id)
        view.store.appendMessage(ChatMessage(role: .user, text: "Put milk and bread on the shopping list"),
                                 to: id)
        var second = ChatMessage(role: .assistant,
                                 text: L.fmt("rem_created", "Milk\n" + L.fmt("rem_list_line", "Shopping")),
                                 model: "qwen3.8-flash", elapsed: 0.9)
        second.reminderRef = milk
        view.store.appendMessage(second, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func calendar(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_calendar.txt", name: "calendar") else { return }
        let begin = day(1, hour: 11)
        let end = Calendar.current.date(byAdding: .minute, value: 30, to: begin) ?? begin
        let ref = CalendarRef(eventID: "shot-review", title: "Team review", start: begin)
        let question = ChatMessage(role: .user,
                                   text: "Put a team review on my calendar tomorrow at 11")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: L.fmt("cal_created", "Team review — " + Formatters.eventStart(begin)
                                             + "–" + Formatters.time(end) + "\n"
                                             + L.fmt("cal_calendar", "Work")),
                                 model: "qwen3.8-flash", elapsed: 1.3)
        answer.calendarRef = ref
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func places(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_places.txt", name: "places") else { return }
        let places = [
            NearbyPlace(name: "City Pharmacy", latitude: nil, longitude: nil, metres: 220, mode: .walking),
            NearbyPlace(name: "Supermarket", latitude: nil, longitude: nil, metres: 380, mode: .walking),
            NearbyPlace(name: "Central Station", latitude: nil, longitude: nil, metres: 550, mode: .walking)
        ]
        let question = ChatMessage(role: .user, text: "Where is the nearest pharmacy?")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant, text: "Here are the closest places:",
                                 model: "qwen3.8-flash", elapsed: 1.1)
        answer.placeGroups = PlaceGroup.single(places, headingKey: nil)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func code(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_code.txt", name: "code") else { return }
        let question = ChatMessage(role: .user, text: "Write Tetris as a single HTML file")
        view.store.appendMessage(question, to: id)
        let snippet = "<!doctype html>\n<html>\n<body>\n<canvas id=\"g\" width=\"240\" height=\"400\"></canvas>\n"
            + "<script>\nconst c = g.getContext(\"2d\");\nconst P = [[[1,1],[1,1]], [[1,1,1,1]]];\n"
            + "let board = Array.from({length: 20}, () => Array(10).fill(0));\n"
            + "function draw() { c.fillStyle = \"#111\"; c.fillRect(0,0,240,400); }\n"
            + "onkeydown = e => { if (e.key === \"ArrowLeft\") x--; if (e.key === \"ArrowRight\") x++; };\n"
            + "setInterval(() => { y++; draw(); }, 400);\ndraw();\n</script>\n</body>\n</html>"
        let answer = ChatMessage(role: .assistant,
                                 text: "A minimal Tetris in one HTML file:\n\n```html\n" + snippet + "\n```",
                                 model: "qwen3.8-flash", elapsed: 2.1)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func scanner(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_scan.txt", name: "scan"),
              let outcome = scanFixture(view, kind: .receipt,
                                        text: "ELEKTRO KERN\n28.09.2026 17:42\nHEADPHONES AURA X 234.58 EUR\n"
                                            + "VAT 19% 14.42 EUR\nTOTAL 249.00 EUR\nWARRANTY 24 MONTHS")
        else { return }
        let question = ChatMessage(role: .user, text: "Scan the receipt", files: [outcome.attachment])
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "Here is what the receipt says:\n\n"
                                     + "- **Headphones Aura X** — 234.58 €\n"
                                     + "- **VAT 19%** — 14.42 €\n"
                                     + "- **Total** — 249.00 €\n\n"
                                     + "The amounts add up to the printed total. The 24-month warranty runs "
                                     + "until 28 September 2028.",
                                 model: "qwen3.8-flash", elapsed: 1.6)
        answer.scanRef = outcome.attachment
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func scannerReminder(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_scan_reminder.txt", name: "scan-reminder") else { return }
        let deadline = day(11, hour: 9)
        guard let outcome = scanFixture(view, kind: .invoice,
                                        text: "CITY UTILITIES MUNICH\nInvoice 2026-88-421\n"
                                            + "Customer number 713 448 902\nTotal amount 84.20 EUR\n"
                                            + "Payable until \(germanDate(deadline))") else { return }
        let question = ChatMessage(role: .user,
                                   text: "Scan the invoice with the deadline as a reminder",
                                   files: [outcome.attachment])
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "**City Utilities Munich** charges **84.20 €** for the electricity "
                                     + "instalment (customer number 713 448 902). The invoice is **payable until "
                                     + "\(englishDate(deadline))** and names no further actions.",
                                 model: "qwen3.8-flash", elapsed: 1.5)
        answer.scanRef = outcome.attachment
        answer.reminderOffer = ScanReminderOffer(title: "Pay the City Utilities invoice", due: deadline,
                                                 allDay: true)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func priceWatch(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_price_watch.txt", name: "price-watch") else { return }
        let checked = day(0, hour: 7)
        let url = "https://www.mediamarkt.de/de/product/_sony-playstation-5-slim-1tb"
        let watch = PriceWatch(terms: ["PlayStation 5 Slim", "PS5 Slim"], goal: 400,
                               wording: "Let me know when the PlayStation 5 Slim falls below 400 €.",
                               currencyCode: "EUR", regionCode: "DE", createdAt: day(0, hour: 7),
                               updatedAt: checked, lastCheckedAt: checked, lastPrice: 429,
                               lastCurrency: "EUR", lastShop: "MediaMarkt", lastURL: url,
                               lastProduct: "SONY PlayStation 5 Slim — 1 TB")
        let question = ChatMessage(role: .user,
                                   text: "Let me know when the PlayStation 5 Slim falls below 400 €.")
        view.store.appendMessage(question, to: id)
        let offer = PriceWatchOffer(price: 429, currency: "EUR", shop: "MediaMarkt", url: url,
                                    product: "SONY PlayStation 5 Slim — 1 TB")
        let outcome = PriceWatchCheckOutcome(watch: watch, offer: offer, failure: nil)
        var answer = ChatMessage(role: .assistant, text: PriceWatchAnswers.saved(outcome, created: true),
                                 model: "qwen3.8-flash", elapsed: 1.7)
        answer.priceWatchRef = PriceWatchRef(watch: watch)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func priceWatchHit(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_price_watch_hit.txt", name: "price-watch-hit") else { return }
        let checked = day(0, hour: 7)
        let hit = day(0, hour: 6)
        let url = "https://www.elektro-kern.de/sony-playstation-5-slim-1tb"
        let watch = PriceWatch(terms: ["PlayStation 5 Slim", "PS5 Slim"], goal: 400,
                               wording: "Let me know when the PlayStation 5 Slim falls below 400 €.",
                               currencyCode: "EUR", regionCode: "DE", createdAt: day(-1, hour: 18),
                               updatedAt: checked, lastCheckedAt: checked, lastPrice: 379,
                               lastCurrency: "EUR", lastShop: "Elektro Kern", lastURL: url,
                               lastProduct: "SONY PlayStation 5 Slim — 1 TB", hitAt: hit,
                               notifiedPrice: 379)
        let question = ChatMessage(role: .user,
                                   text: "Let me know when the PlayStation 5 Slim falls below 400 €.")
        view.store.appendMessage(question, to: id)
        let first = PriceWatchOffer(price: 429, currency: "EUR", shop: "MediaMarkt",
                                    url: "https://www.mediamarkt.de/de/product/_sony-playstation-5-slim-1tb",
                                    product: "SONY PlayStation 5 Slim — 1 TB")
        let saved = PriceWatchCheckOutcome(watch: watch, offer: first, failure: nil)
        view.store.appendMessage(ChatMessage(role: .assistant, text: PriceWatchAnswers.saved(saved, created: true),
                                             model: "qwen3.8-flash", elapsed: 1.7), to: id)
        let offer = PriceWatchOffer(price: 379, currency: "EUR", shop: "Elektro Kern", url: url,
                                    product: "SONY PlayStation 5 Slim — 1 TB")
        var answer = ChatMessage(role: .assistant, text: PriceWatchAnswers.alarm(watch, offer: offer),
                                 model: "qwen3.8-flash", elapsed: 1.2)
        answer.priceWatchRef = PriceWatchRef(watch: watch)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func briefing(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_briefing.txt", name: "briefing") else { return }
        let hours = (6...22).map { hour in
            WeatherHour(hour: hour, temp: hour < 12 ? 9 : 14, rain: hour < 12 ? 70 : 0,
                        precip: hour < 12 ? 1.2 : 0, wind: 12, gust: 22, uv: hour < 12 ? 0 : 2,
                        kind: hour < 12 ? .rain : .partly)
        }
        let weather = WeatherRef(place: "Munich", latitude: 48.137, longitude: 11.575,
                                 day: Formatters.stamp(day(0, hour: 7)),
                                 timezone: "Europe/Berlin", hours: hours)
        let events = [
            DayBriefingEvent(id: "shot-dentist", title: "Dentist Dr. Berger",
                             start: day(0, hour: 11), end: day(0, hour: 12),
                             location: "Practice at the Ring 12", calendar: "Private",
                             ref: CalendarRef(eventID: "shot-dentist", title: "Dentist Dr. Berger",
                                              start: day(0, hour: 11))),
            DayBriefingEvent(id: "shot-call", title: "Team call website relaunch",
                             start: day(0, hour: 15), end: day(0, hour: 16),
                             location: "Videoconference", calendar: "Work",
                             ref: CalendarRef(eventID: "shot-call", title: "Team call website relaunch",
                                              start: day(0, hour: 15))),
            DayBriefingEvent(id: "shot-school", title: "Parents' evening class 3b",
                             start: day(0, hour: 18), end: day(0, hour: 20), calendar: "Family",
                             ref: CalendarRef(eventID: "shot-school", title: "Parents' evening class 3b",
                                              start: day(0, hour: 18)))
        ]
        let reminders = [
            DayBriefingItem(id: "shot-invoice", title: "Pay the City Utilities invoice",
                            detail: "Tasks", badge: L.t("brief_overdue"), overdue: true),
            DayBriefingItem(id: "shot-shopping", title: "Shopping list", detail: "Milk, bread, coffee, apples")
        ]
        let birthdays = [DayBriefingItem(id: "shot-dad", title: "Dad", detail: "turns 63")]
        var ref = DayBriefingRef(date: Formatters.stamp(day(0, hour: 7)), greetingKey: "brief_greet_morning",
                                 weather: weather, events: events,
                                 travel: DayBriefingTravel(title: "Practice at the Ring 12", carMinutes: 18,
                                                           bikeMinutes: 25),
                                 reminders: reminders, birthdays: birthdays)
        ref.closing = DayBriefingAnswers.closing(ref)
        let question = ChatMessage(role: .user, text: "What is on today?")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant, text: DayBriefingAnswers.text(ref),
                                 model: "qwen3.8-flash", elapsed: 1.9)
        answer.dayBriefingRef = ref
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        try? await Task.sleep(for: .milliseconds(400))
        view.scrollProxy?.scrollTo(ChatScrollAnchors.message(answer.id), anchor: .bottom)
        await hold()
    }

    static func researchFollowup(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_research_followup.txt", name: "research-followup") else {
            return
        }
        view.store.appendMessage(ChatMessage(role: .user,
                                             text: "What is in the news in Berlin today?"), to: id)
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "Berlin approved a new tram line for the east of the city, "
                                                 + "the Charité reported record funding, and the film festival "
                                                 + "named its first jury members. [1][2]",
                                             model: "qwen3.8-flash", elapsed: 2.1), to: id)
        let followUp = ChatMessage(role: .user, text: "Tell me more about each of them")
        view.store.appendMessage(followUp, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "1. **The tram line** runs from Alexanderplatz to Köpenick and is planned "
                                     + "to open in 2031. [1]\n\n"
                                     + "2. **The Charité** receives 480 million euros for a new research "
                                     + "building on the Virchow campus. [2]\n\n"
                                     + "3. **The film festival** starts on 12 February with a jury led by "
                                     + "the director Mia Hansen-Løve. [3]",
                                 model: "qwen3.8-flash", elapsed: 3.4)
        answer.sources = [WebSource(title: "Tram line for the east", url: "https://berlin.de/tram", domain: "berlin.de"),
                          WebSource(title: "Charité building", url: "https://charite.de/news", domain: "charite.de"),
                          WebSource(title: "Berlinale jury", url: "https://berlinale.de/jury", domain: "berlinale.de")]
        answer.sourcesHeadingKey = "web_sources_head"
        view.store.appendMessage(answer, to: id)
        await focus(view, on: followUp.id)
        await hold()
    }

    static func researchSourceCheck(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_research_source_check.txt",
                             name: "research-source-check") else { return }
        let agency = "Parliament passed the law on Wednesday after a long debate. The rules apply to newly "
            + "installed heating systems from 2027. The opposition criticised the schedule as too tight."
        let solar = "The city utility reports a new record in solar power generation. Output rose sharply "
            + "in the third quarter. A spokesman called the figures encouraging."
        let details = "A ministry spokesman said the details are still being reviewed. A final version is "
            + "expected next week."
        let hits = [WebHit(title: "Law passed", url: "https://news-a.example/act",
                           domain: "news-a.example", text: agency),
                    WebHit(title: "Report", url: "https://portal-b.example/news",
                           domain: "portal-b.example", text: agency),
                    WebHit(title: "Solar record", url: "https://xn--mnchen-3ya.de/solar",
                           domain: "xn--mnchen-3ya.de", text: solar),
                    WebHit(title: "Details still open", url: "https://reported.example/article",
                           domain: "reported.example", text: details)]
        SourceReports.shared.report("reported.example")
        let answer = "Parliament passed a law on Wednesday that bans new gas boilers from 2027 [1][2]. "
            + "It applies retroactively from January 2026 [3]. It covers new buildings only [4][3]."
        var review = SourceReview.analyze(answer: answer, hits: hits)
        review = review.applying([
            SourceReview.Claim(claim: "Parliament passed a law that bans new gas boilers from 2027",
                               sources: [1, 2], verdict: .supported),
            SourceReview.Claim(claim: "It applies retroactively from January 2026",
                               sources: [3], verdict: .unsupported),
            SourceReview.Claim(claim: "It covers new buildings only",
                               sources: [4], verdict: .contradicted, contradicts: [3]),
        ])
        let question = ChatMessage(role: .user, text: "What did parliament pass yesterday?")
        view.store.appendMessage(question, to: id)
        view.store.appendMessage(ChatMessage(role: .assistant, text: answer, model: "qwen3.8-flash",
                                             elapsed: 2.4,
                                             sources: WebResearch.sources(from: hits),
                                             sourceReview: review), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func imageGeneration(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_image_generation.txt", name: "image-generation"),
              let file = view.store.media.store(nightLighthouse()) else { return }
        let question = ChatMessage(role: .user, text: "Paint a lighthouse at night.")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "Here is the lighthouse — the beam swings over the sea.",
                                 model: "wan2.7-image", elapsed: 8.6)
        answer.outImages = [Attachment(file: file)]
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func photoEditing(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_photo_editing.txt", name: "photo-editing"),
              let original = view.store.media.store(mountainLake(gray: false)),
              let edited = view.store.media.store(mountainLake(gray: true)) else { return }
        let question = ChatMessage(role: .user, text: "Make this photo black and white.",
                                   images: [Attachment(file: original)])
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant, text: "Done — here is the black-and-white version.",
                                 model: "wan2.7-image", elapsed: 6.2)
        answer.outImages = [Attachment(file: edited)]
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func photoGallery(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_photo_gallery.txt", name: "photo-gallery") else { return }
        var pictures: [WebPicture] = []
        for index in 0..<4 {
            guard let file = view.store.media.store(eiffelTower(index)) else { continue }
            pictures.append(WebPicture(file: file, pageURL: "https://fotos.example/eiffel-\(index)",
                                       fullURL: "https://fotos.example/eiffel-\(index).jpg",
                                       title: "Eiffel Tower", domain: "fotos.example"))
        }
        let question = ChatMessage(role: .user, text: "Show me pictures of the Eiffel Tower.")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant, text: "Here are pictures of the Eiffel Tower:",
                                 model: "qwen3.8-flash", elapsed: 1.5)
        answer.gallery = PictureGallery(query: "Eiffel Tower", pictures: pictures, shown: pictures.count)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func priceComparison(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_price_comparison.txt", name: "price-comparison") else {
            return
        }
        let question = ChatMessage(role: .user,
                                   text: "Find the cheapest MacBook Pro 14″ for me.")
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "I compared the MacBook Pro 14″ (M5 Pro, 24 GB, 1 TB):\n\n"
                                     + "- **MediaMarkt** 1.749,00 € — pickup or delivery [1]\n"
                                     + "- **Cyberport** 1.799,00 € — in stock [2]\n"
                                     + "- **Amazon** 1.824,00 € — Prime delivery [3]\n"
                                     + "- **Otto** 1.899,00 € — delivery in 3–5 days [4]\n\n"
                                     + "MediaMarkt is the cheapest right now.",
                                 model: "qwen3.8-flash", elapsed: 14.3)
        answer.sources = [WebSource(title: "MacBook Pro 14″", url: "https://mediamarkt.de/p",
                                    domain: "mediamarkt.de"),
                          WebSource(title: "MacBook Pro 14″", url: "https://cyberport.de/p", domain: "cyberport.de"),
                          WebSource(title: "MacBook Pro 14″", url: "https://amazon.de/p", domain: "amazon.de"),
                          WebSource(title: "MacBook Pro 14″", url: "https://otto.de/p", domain: "otto.de")]
        answer.sourcesHeadingKey = PriceComparator.headingKey
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func timer(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_timer.txt", name: "timer") else { return }
        let question = ChatMessage(role: .user, text: "Set a timer for ten minutes.")
        view.store.appendMessage(question, to: id)
        let request = TimerRequest(minutes: 10, seconds: nil, title: nil)
        let text = TimerAnswer.result(.set(duration: 600, way: "alarm"),
                                      request: request)
        view.store.appendMessage(ChatMessage(role: .assistant, text: text,
                                             model: "qwen3.8-flash", elapsed: 0.9), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func music(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_music.txt", name: "music") else { return }
        let question = ChatMessage(role: .user, text: "Play my playlist Sport.")
        view.store.appendMessage(question, to: id)
        let pick = MusicPick(kind: .playlist, name: "Sport", artist: nil)
        let text = MusicAnswer.text(.playing(pick), service: .appleMusic)
        view.store.appendMessage(ChatMessage(role: .assistant, text: text,
                                             model: "qwen3.8-flash", elapsed: 1.6), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func message(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_message.txt", name: "message") else { return }
        let question = ChatMessage(role: .user, text: "Text mum that I will be late.")
        view.store.appendMessage(question, to: id)
        let text = L.fmt2("message_sent", "Mum", "I will be late.")
        view.store.appendMessage(ChatMessage(role: .assistant, text: text,
                                             model: "qwen3.8-flash", elapsed: 1.4), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func call(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_call.txt", name: "call") else { return }
        let question = ChatMessage(role: .user, text: "Call Peter Müller on his mobile.")
        view.store.appendMessage(question, to: id)
        let text = L.fmt("call_dialing", "Peter Müller")
        view.store.appendMessage(ChatMessage(role: .assistant, text: text,
                                             model: "qwen3.8-flash", elapsed: 1.1), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func fileReading(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_files.txt", name: "files"),
              let file = leaseFile(view) else { return }
        let question = ChatMessage(role: .user, text: "Summarise this.", files: [file])
        view.store.appendMessage(question, to: id)
        var answer = ChatMessage(role: .assistant,
                                 text: "The lease is for the flat at Lindenstraße 14, 3rd floor. "
                                     + "The monthly rent is 1.240,00 € including utilities, the deposit is "
                                     + "3.720,00 €, and the notice period is three months. The contract starts "
                                     + "on 1 November 2026.",
                                 model: "qwen3.8-flash", elapsed: 3.2)
        answer.fileRefs = [FileRef(file)]
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func translation(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_translation.txt", name: "translation") else { return }
        view.store.appendMessage(ChatMessage(role: .user, text: "What does the note say?"), to: id)
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "The museum opens at nine in the morning.",
                                             model: "qwen3.8-flash", elapsed: 1.2), to: id)
        let question = ChatMessage(role: .user, text: "Translate that into French.")
        view.store.appendMessage(question, to: id)
        let job = TranslationJob(text: "The museum opens at nine in the morning.", targetCode: "fr")
        let signature = TranslationFlow.signature(onDevice: true,
                                                  job: job.withSource(OnDeviceTranslation.sourceCode(for: job)))
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "Le musée ouvre à neuf heures du matin.",
                                             model: signature, elapsed: 0.4), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func memory(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_memory.txt", name: "memory") else { return }
        let question = ChatMessage(role: .user, text: "Remember that I don't eat meat.")
        view.store.appendMessage(question, to: id)
        let entry = MemoryEntry(text: "I don't eat meat", category: .likes, source: .explicit)
        var answer = ChatMessage(role: .assistant, text: MemoryAnswers.saved(entry, merged: false),
                                 model: "qwen3.8-flash", elapsed: 1.0)
        answer.memoryRefs = [MemoryRef(entry: entry)]
        view.store.appendMessage(answer, to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func time(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_time.txt", name: "time") else { return }
        let question = ChatMessage(role: .user, text: "What time is it in Tokyo?")
        view.store.appendMessage(question, to: id)
        let text = ClockAnswer.text(now: Date(), request: ClockRequest(timeZone: "Asia/Tokyo",
                                                                      place: "Tokyo"))
        view.store.appendMessage(ChatMessage(role: .assistant, text: text,
                                             model: "qwen3.8-flash", elapsed: 0.6), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func multiTask(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_multi_task.txt", name: "multi-task") else { return }
        var pictures: [WebPicture] = []
        for index in 0..<3 {
            guard let file = view.store.media.store(aurora(index)) else { continue }
            pictures.append(WebPicture(file: file, pageURL: "https://fotos.example/aurora-\(index)",
                                       fullURL: "https://fotos.example/aurora-\(index).jpg",
                                       title: "Northern Lights", domain: "fotos.example"))
        }
        let question = ChatMessage(role: .user,
                                   text: "Show me pictures of the Northern Lights and add an appointment "
                                       + "tomorrow at 9 called Photo walk.")
        view.store.appendMessage(question, to: id)
        let begin = day(1, hour: 9)
        var answer = ChatMessage(role: .assistant,
                                 text: "Here are pictures of the Northern Lights. I also put “Photo walk” on "
                                     + "your calendar for tomorrow at 9.",
                                 model: "qwen3.8-flash", elapsed: 2.8)
        answer.gallery = PictureGallery(query: "Northern Lights", pictures: pictures, shown: pictures.count)
        answer.calendarRef = CalendarRef(eventID: "shot-photo-walk", title: "Photo walk", start: begin)
        view.store.appendMessage(answer, to: id)
        await focus(view, on: answer.id)
        await hold()
    }

    static func readAloud(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_read_aloud.txt", name: "read-aloud") else { return }
        let question = ChatMessage(role: .user, text: "Read that to me.")
        view.store.appendMessage(question, to: id)
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "The museum opens at nine in the morning and closes at six.",
                                             model: "qwen3.8-flash", elapsed: 1.1), to: id)
        view.settings.voice.speakAnswers = true
        await focus(view, on: question.id)
        view.attachMenu = true
        await hold()
    }

    static func historyUndo(_ view: ChatView) async {
        L.apply(.en)
        cleanup = nil
        let settings = AppSettings.shared
        let baseline = ShotBaseline(settings)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shot-undo-\(UUID().uuidString)")
        let paths = StoragePaths(documents: folder)
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        }
        var pictureFile: String?
        for index in 0..<26 {
            store.newConversation()
            guard let id = store.currentID else { continue }
            store.appendMessage(ChatMessage(role: .user, text: "Question \(index + 1)"), to: id)
            if index == 0, let stored = store.media.store(picture) {
                pictureFile = stored
                store.appendMessage(ChatMessage(role: .assistant, text: "Answer \(index + 1).",
                                                 model: "qwen3.8-flash", elapsed: 0.8,
                                                 outImages: [Attachment(file: stored)]), to: id)
            } else {
                store.appendMessage(ChatMessage(role: .assistant, text: "Answer \(index + 1).",
                                                 model: "qwen3.8-flash", elapsed: 0.8), to: id)
            }
        }
        _ = pictureFile
        guard let window = ProbeHosting.host(ChatView(listenToken: .constant(0)).environmentObject(store)) else {
            baseline.restore(settings)
            try? FileManager.default.removeItem(at: folder)
            return
        }
        window.overrideUserInterfaceStyle = .light
        try? await Task.sleep(for: .milliseconds(1500))
        store.cleaner.deleteAllConversations()
        try? await Task.sleep(for: .milliseconds(400))
        let report = SweepReport(file: "shot_history_undo.txt")
        report.add("SHOT", "history-undo")
        await hold()
        ProbeHosting.close(window)
        baseline.restore(settings)
        try? FileManager.default.removeItem(at: folder)
    }

    static func listening(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_listening.txt", name: "listening") else { return }
        view.settings.voice.listenMode = true
        let question = ChatMessage(role: .user, text: "Tell me a fun fact about Tokyo.")
        view.store.appendMessage(question, to: id)
        view.store.appendMessage(ChatMessage(role: .assistant,
                                             text: "Tokyo's metro is the busiest in the world: more than "
                                                 + "eight million people ride it every day.",
                                             model: "qwen3.8-flash", elapsed: 1.4), to: id)
        await focus(view, on: question.id)
        await hold()
    }

    static func stopRun(_ view: ChatView) async {
        L.apply(.en)
        guard let id = start(view, file: "shot_stop.txt", name: "stop") else { return }
        let question = ChatMessage(role: .user, text: "Write a long story about a lighthouse keeper.")
        view.store.appendMessage(question, to: id)
        view.streamText = "The lighthouse keeper had counted the ships for forty years, and in all that "
            + "time he had never once missed a light. Every evening he climbed the hundred and twelve steps, "
            + "wound the clockwork, and trimmed the wick until the beam swept the water in long, patient arcs."
        view.isStreaming = true
        view.runTask = Task { @MainActor in
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)) }
        }
        await focus(view, on: question.id)
        await hold()
        view.runTask?.cancel()
        view.runTask = nil
        view.isStreaming = false
    }

    private static func leaseFile(_ view: ChatView) -> AttachedFile? {
        let text = "Residential lease agreement\n\nBetween the landlord, Hausverwaltung Linden GmbH, "
            + "and the tenant, Anna Berger.\n\n1. The flat is at Lindenstraße 14, 3rd floor, 10969 Berlin.\n"
            + "2. The monthly rent is 1.240,00 euros including utilities.\n"
            + "3. The deposit is 3.720,00 euros, payable in three parts.\n"
            + "4. The notice period is three months to the end of a month.\n"
            + "5. The contract starts on 1 November 2026."
        let page = documentPage(title: "Residential lease agreement", text: text)
        let workflow = ScanWorkflow(recognize: { _, _ in text })
        guard let outcome = workflow.store(pages: [page, page, page], kind: .letter,
                                           date: day(-1, hour: 17), documents: view.store.documents)
        else { return nil }
        var file = outcome.attachment
        file.name = "Lease agreement.pdf"
        file.kind = .pdf
        file.pages = 3
        file.chars = text.count
        file.via = .textLayer
        return file
    }

}
#endif
