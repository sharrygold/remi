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
}
