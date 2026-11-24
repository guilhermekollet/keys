import Foundation

/// What the start page says about the vault: how much it holds, the projects from the one changed
/// last, and what is worth a look. Only projects in use count; archived ones are out of the way.
struct VaultSummary {
    /// An access that has no password yet, and the project it is in.
    struct MissingPassword: Identifiable {
        let project: Project
        let credential: Credential
        var id: Credential.ID { credential.id }
    }

    /// Projects in use, the one changed last first.
    let projects: [Project]
    let subprojectCount: Int
    let credentialCount: Int
    let variableCount: Int
    let secretCount: Int
    let linkCount: Int
    /// Accesses with something in them but no password, in the order of `projects`.
    let withoutPassword: [MissingPassword]
    /// Projects whose context says nothing yet, in the order of `projects`.
    let withoutContext: [Project]

    init(_ all: [Project]) {
        let active = all.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
        projects = active
        subprojectCount = active.filter { $0.parentID != nil }.count
        credentialCount = active.reduce(0) { $0 + $1.credentials.count }
        let variables = active.flatMap { $0.environments.flatMap(\.variables) }
        variableCount = variables.count
        secretCount = variables.filter(\.isSecret).count
        linkCount = active.reduce(0) { $0 + $1.links.count }
        withoutPassword = active.flatMap { project in
            project.credentials
                .filter { !$0.isEmpty && $0.password.isEmpty }
                .map { MissingPassword(project: project, credential: $0) }
        }
        withoutContext = active.filter { $0.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The part of the day `date` falls in, for the greeting.
    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: localized("Bom dia")
        case 12..<18: localized("Boa tarde")
        default: localized("Boa noite")
        }
    }
}
