import SwiftUI

/// Static Phase 1 content. Replaced by the real data layer in M2.
struct SampleSpace: Identifiable, Hashable {
    let name: String
    let symbol: String
    let tint: Color
    var id: String { name }
}

struct SampleTask: Identifiable {
    let id = UUID()
    let title: String
    let space: SampleSpace
    var due: String? = nil
    var important = false
    var hasAction = false
}

struct SampleNote: Identifiable {
    let id = UUID()
    let title: String
    let preview: String
    let space: SampleSpace
    var pinned = false
}

struct SampleLink: Identifiable {
    let id = UUID()
    let title: String
    let domain: String
    let space: SampleSpace
    var symbol = "globe"
}

enum Sample {
    static let clients = SampleSpace(name: "Clients", symbol: "briefcase", tint: Tokens.Tint.clients)
    static let work = SampleSpace(name: "Work", symbol: "building.2", tint: Tokens.Tint.work)
    static let personal = SampleSpace(name: "Personal", symbol: "house", tint: Tokens.Tint.personal)
    static let learning = SampleSpace(name: "Learning", symbol: "book", tint: Tokens.Tint.learning)
    static let homeReno = SampleSpace(name: "Home Reno", symbol: "magnifyingglass", tint: Tokens.Tint.homeReno)
    static let spaces = [clients, work, personal, learning, homeReno]

    static let overdue = [
        SampleTask(title: "Reply to Dana about the project timeline", space: work, due: "Yesterday"),
    ]
    static let today = [
        SampleTask(title: "Record Loom intro for invoice", space: clients, important: true, hasAction: true),
        SampleTask(title: "Send design dashboard invoice", space: clients, hasAction: true),
        SampleTask(title: "Prepare sprint review notes", space: work),
        SampleTask(title: "Book dentist appointment", space: personal),
    ]
    static let later = [
        SampleTask(title: "Tidy the shared drive", space: clients, due: "Fri", hasAction: true),
        SampleTask(title: "Finish SwiftUI layout module", space: learning, due: "Tomorrow"),
        SampleTask(title: "Plan the garden beds", space: homeReno, due: "Mon"),
    ]
    static let notes = [
        SampleNote(title: "Invoice opening lines", preview: "Start with their problem, then one proof point", space: clients, pinned: true),
        SampleNote(title: "Q4 priorities", preview: "Reporting cleanup, onboarding flow, vendor review", space: work),
        SampleNote(title: "Loom checklist", preview: "Close tabs, check mic, keep it under two minutes", space: clients),
        SampleNote(title: "Trip ideas", preview: "Lisbon in December, ask about flights", space: personal),
    ]
    static let saved = [
        SampleLink(title: "Team handbook", domain: "example.com", space: clients, symbol: "person.crop.circle"),
        SampleLink(title: "Invoice tracker", domain: "docs.google.com", space: clients, symbol: "doc.text"),
        SampleLink(title: "Team dashboard", domain: "linear.app", space: work, symbol: "chart.bar"),
    ]
    static let watchLater = [
        SampleLink(title: "How to write invoices that win", domain: "youtube.com", space: clients, symbol: "play.rectangle"),
        SampleLink(title: "SwiftUI layout, explained", domain: "youtube.com", space: learning, symbol: "play.rectangle"),
    ]
}
