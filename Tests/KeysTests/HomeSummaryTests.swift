import Testing
@testable import Keys

@Suite("Start page")
struct HomeSummaryTests {
    private func project(_ name: String, changed: Double, archived: Bool = false, parent: Project? = nil) -> Project {
        var project = Project(name: name)
        project.updatedAt = .init(timeIntervalSinceReferenceDate: changed)
        if archived { project.archivedAt = .init(timeIntervalSinceReferenceDate: changed) }
        project.parentID = parent?.id
        return project
    }

    @Test func listsProjectsInUseFromTheOneChangedLast() {
        let old = project("Old", changed: 100)
        let new = project("New", changed: 300)
        let gone = project("Gone", changed: 500, archived: true)
        let child = project("Child", changed: 200, parent: old)
        let summary = VaultSummary([old, new, gone, child])
        #expect(summary.projects.map(\.name) == ["New", "Child", "Old"])
        #expect(summary.subprojectCount == 1)
    }

    @Test func countsWhatProjectsInUseHold() {
        var shop = project("Shop", changed: 1)
        shop.credentials = [Credential(title: "Vercel", password: "x"), Credential(title: "DB", password: "y")]
        shop.links = [ProjectLink(title: "Repo", url: "https://example.com")]
        shop.environments = [EnvironmentSet(name: "development", variables: [
            Variable(key: "PORT", value: "3000"),
            Variable(key: "TOKEN", value: "t", isSecret: true),
        ])]
        var archived = project("Archived", changed: 2, archived: true)
        archived.credentials = [Credential(title: "Old")]
        let summary = VaultSummary([shop, archived])
        #expect(summary.credentialCount == 2)
        #expect(summary.variableCount == 2)
        #expect(summary.secretCount == 1)
        #expect(summary.linkCount == 1)
    }

    @Test func pointsOutAccessesWithoutPasswordAndEmptyContexts() {
        var shop = project("Shop", changed: 2)
        shop.context = "## Como rodar\nnpm run dev"
        shop.credentials = [Credential(title: "With", password: "x"), Credential(title: "Without"), Credential()]
        var blank = project("Blank", changed: 1)
        blank.context = "  \n "
        let summary = VaultSummary([shop, blank])
        #expect(summary.withoutPassword.map(\.credential.title) == ["Without"])
        #expect(summary.withoutPassword.map(\.project.name) == ["Shop"])
        #expect(summary.withoutContext.map(\.name) == ["Blank"])
    }

    @Test func greetsByThePartOfTheDay() {
        #expect(greeting(atHour: 8) == VaultSummary.greeting(at: dateAt(hour: 8)))
        #expect(greeting(atHour: 8) != greeting(atHour: 15))
        #expect(greeting(atHour: 15) != greeting(atHour: 22))
        #expect(greeting(atHour: 2) == greeting(atHour: 22))
    }

    private func greeting(atHour hour: Int) -> String {
        VaultSummary.greeting(at: dateAt(hour: hour))
    }
}
