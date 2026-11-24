import Testing
@testable import Keys

@Suite("Sidebar order")
struct SidebarOrderTests {
    private func tree() -> [Project] {
        let alpha = Project(name: "Alpha")
        let beta = Project(name: "Beta")
        var gamma = Project(name: "Gamma")
        gamma.parentID = nil
        var one = Project(name: "One")
        one.parentID = beta.id
        var two = Project(name: "Two")
        two.parentID = beta.id
        var three = Project(name: "Three")
        three.parentID = beta.id
        return [gamma, two, alpha, three, beta, one]
    }

    private func names(_ rows: [ProjectTree.Row]) -> [String] { rows.map { String(repeating: "  ", count: $0.depth) + $0.project.name } }

    private func id(_ name: String, in projects: [Project]) -> Project.ID {
        projects.first { $0.name == name }!.id
    }

    @Test func withoutAnOrderProjectsGoByName() {
        let projects = tree()
        let rows = ProjectTree.visibleRows(unfolded: [id("Beta", in: projects)], in: projects)
        #expect(names(rows) == ["Alpha", "Beta", "  One", "  Three", "  Two", "Gamma"])
    }

    @Test func draggingAProjectUpKeepsItsNewPlace() {
        let projects = tree()
        let rows = ProjectTree.visibleRows(unfolded: [], in: projects)
        // Gamma, the third line, dropped before the first.
        let moved = ProjectTree.moving(2, to: 0, in: rows, projects: projects)
        #expect(names(ProjectTree.visibleRows(unfolded: [], in: moved)) == ["Gamma", "Alpha", "Beta"])
    }

    @Test func draggingDownCountsTheLineBeingMoved() {
        let projects = tree()
        let rows = ProjectTree.visibleRows(unfolded: [], in: projects)
        // Alpha dropped at the end.
        let moved = ProjectTree.moving(0, to: 3, in: rows, projects: projects)
        #expect(names(ProjectTree.visibleRows(unfolded: [], in: moved)) == ["Beta", "Gamma", "Alpha"])
    }

    @Test func aSubprojectMovesWithinItsGroup() {
        let projects = tree()
        let unfolded: Set = [id("Beta", in: projects)]
        let rows = ProjectTree.visibleRows(unfolded: unfolded, in: projects)
        // Two (line 4) dropped before One (line 2).
        let moved = ProjectTree.moving(4, to: 2, in: rows, projects: projects)
        #expect(names(ProjectTree.visibleRows(unfolded: unfolded, in: moved)) == ["Alpha", "Beta", "  Two", "  One", "  Three", "Gamma"])
        #expect(moved.first { $0.name == "Two" }?.parentID == id("Beta", in: projects))
    }

    @Test func droppedAmongAnotherGroupItStaysInItsOwn() {
        let projects = tree()
        let unfolded: Set = [id("Beta", in: projects)]
        let rows = ProjectTree.visibleRows(unfolded: unfolded, in: projects)
        // Gamma (line 5) dropped among Beta's subprojects, before Three (line 3): it stays at the
        // top level, after Beta, the last of its own list above the drop.
        let moved = ProjectTree.moving(5, to: 3, in: rows, projects: projects)
        #expect(moved.first { $0.name == "Gamma" }?.parentID == nil)
        #expect(names(ProjectTree.visibleRows(unfolded: unfolded, in: moved)) == ["Alpha", "Beta", "  One", "  Three", "  Two", "Gamma"])
    }

    @Test func aGroupTakesItsSubprojectsAlong() {
        let projects = tree()
        let unfolded: Set = [id("Beta", in: projects)]
        let rows = ProjectTree.visibleRows(unfolded: unfolded, in: projects)
        // Beta (line 1) dropped before Alpha (line 0).
        let moved = ProjectTree.moving(1, to: 0, in: rows, projects: projects)
        #expect(names(ProjectTree.visibleRows(unfolded: unfolded, in: moved)) == ["Beta", "  One", "  Three", "  Two", "Alpha", "Gamma"])
    }

    @Test func aNewProjectComesAfterThoseInOrder() {
        let projects = tree()
        let rows = ProjectTree.visibleRows(unfolded: [], in: projects)
        var moved = ProjectTree.moving(2, to: 0, in: rows, projects: projects)
        moved.append(Project(name: "Aardvark"))
        #expect(names(ProjectTree.visibleRows(unfolded: [], in: moved)) == ["Gamma", "Alpha", "Beta", "Aardvark"])
    }

    @Test func theOrderSurvivesTheVaultFile() {
        #expect(positionsAfterSaving() == ["B:0.0", "A:1.0", "C:none"])
    }
}
