import SwiftUI

/// The start page, shown while no project is open: a bento of cards. A welcome with what the vault
/// holds and how old the last backup is, what is worth a look, then a card per project, the ones
/// changed last larger, and one to start a new project.
struct HomeView: View {
    @EnvironmentObject private var vault: Vault
    @AppStorage(Preferences.lastBackupKey) private var lastBackupSeconds: Double = 0
    @State private var exporting = false

    private static let spacing: CGFloat = 10
    /// The height of a small card; a large one takes two and the space between.
    private static let rowHeight: CGFloat = 92

    var body: some View {
        let summary = VaultSummary(vault.projects)
        let featured = Array(summary.projects.prefix(2))
        let rest = Array(summary.projects.dropFirst(2))
        GeometryReader { geometry in
            // Four columns of the same width, from the room there is; a card spans one or more.
            let width = min(geometry.size.width, ProjectView.contentWidth) - 48
            let column = max((width - Self.spacing * 3) / 4, 60)
            let span = { (columns: Int) in column * CGFloat(columns) + Self.spacing * CGFloat(columns - 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    HStack(alignment: .top, spacing: Self.spacing) {
                        welcome(summary)
                            .frame(width: span(2))
                        MissingPasswordsCard(missing: summary.withoutPassword)
                            .frame(width: column)
                        MissingContextCard(projects: summary.withoutContext)
                            .frame(width: column)
                    }
                    .frame(height: Self.rowHeight + 18)

                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(featured) { project in
                            HomeProjectCard(project: project, large: true)
                                .frame(width: column, height: Self.rowHeight * 2 + Self.spacing)
                        }
                        // Beside the large cards: up to four small ones, and the card to add a
                        // project; with fewer large cards, they take the room left.
                        let side = (span(4 - featured.count) - Self.spacing) / 2
                        VStack(spacing: Self.spacing) {
                            HStack(spacing: Self.spacing) {
                                smallSlot(0, rest).frame(width: side)
                                smallSlot(1, rest).frame(width: side)
                            }
                            HStack(spacing: Self.spacing) {
                                smallSlot(2, rest).frame(width: side)
                                smallSlot(3, rest).frame(width: side)
                            }
                        }
                    }

                    // The rest, four to a row, and the new project card after the last of them.
                    if rest.count >= 4 {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(column), spacing: Self.spacing), count: 4), alignment: .leading, spacing: Self.spacing) {
                            ForEach(rest.dropFirst(4)) { project in
                                HomeProjectCard(project: project, large: false)
                                    .frame(height: Self.rowHeight)
                            }
                            NewProjectCard()
                                .frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $exporting) { ExportBackupSheet() }
        .navigationTitle(localized("Início"))
    }

    /// The small card at `index` beside the large ones: a project, the new project card right
    /// after the last project, or nothing.
    @ViewBuilder
    private func smallSlot(_ index: Int, _ rest: [Project]) -> some View {
        Group {
            if index < rest.count {
                HomeProjectCard(project: rest[index], large: false)
            } else if index == rest.count {
                NewProjectCard()
            } else {
                Color.clear
            }
        }
        .frame(height: Self.rowHeight)
    }

    private func welcome(_ summary: VaultSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VaultSummary.greeting(at: Date()))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(Self.totals(summary))
                .font(Theme.display(19))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: backupIsOld ? "exclamationmark.triangle" : "checkmark.shield")
                    .foregroundStyle(backupIsOld ? Theme.color(.amber) : Theme.muted)
                Text(backupText)
                    .foregroundStyle(backupIsOld ? Theme.color(.amber) : Theme.muted)
                    .lineLimit(1)
                Button(localized("Exportar backup…")) { exporting = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.paper.opacity(0.85))
                    .underline()
            }
            .font(.system(size: 11.5))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "12 projetos, 34 acessos e 96 variáveis".
    static func totals(_ summary: VaultSummary) -> String {
        localized("\(Count.projects(summary.projects.count)), \(Count.credentials(summary.credentialCount)) e \(Count.variables(summary.variableCount))")
    }

    private var lastBackup: Date? {
        lastBackupSeconds > 0 ? Date(timeIntervalSinceReferenceDate: lastBackupSeconds) : Preferences.lastBackup()
    }

    /// No backup, or one more than a month old: worth a reminder.
    private var backupIsOld: Bool {
        guard let lastBackup else { return true }
        return Date().timeIntervalSince(lastBackup) > 30 * 24 * 3600
    }

    private var backupText: String {
        guard let lastBackup else { return localized("Nenhum backup exportado ainda.") }
        return localized("Último backup \(Count.ago(lastBackup))")
    }
}

/// Counted nouns and how long ago, in the interface's language.
enum Count {
    static func projects(_ n: Int) -> String { n == 1 ? localized("1 projeto") : localized("\(n) projetos") }
    static func credentials(_ n: Int) -> String { n == 1 ? localized("1 acesso") : localized("\(n) acessos") }
    static func variables(_ n: Int) -> String { n == 1 ? localized("1 variável") : localized("\(n) variáveis") }
    static func links(_ n: Int) -> String { n == 1 ? localized("1 link") : localized("\(n) links") }

    /// "há 2 horas", "ontem".
    static func ago(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(Interface.locale))
    }
}

/// A card of the bento: the app's quiet surface, a little brighter under the pointer when it
/// does something.
struct BentoCard<Content: View>: View {
    var interactive = true
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.paper.opacity(interactive && hovering ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A project's card. Large: its summary, what it holds and when it changed; small: its name, how
/// many accesses and when. Either opens it.
struct HomeProjectCard: View {
    let project: Project
    let large: Bool
    @EnvironmentObject private var vault: Vault

    var body: some View {
        Button {
            vault.section = .all
            vault.selection = project.id
        } label: {
            BentoCard {
                if large { largeContent } else { smallContent }
            }
        }
        .buttonStyle(.plain)
        .help(localized("Abrir \(name)"))
    }

    private var name: String { project.name.isEmpty ? localized("Sem nome") : project.name }

    private var path: String {
        ProjectTree.ancestors(of: project, in: vault.projects).map(\.name).joined(separator: " › ")
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProjectBadge(project: project, size: 34)
                .padding(.bottom, 4)
            if !path.isEmpty {
                Text(path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(holds)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.paper.opacity(0.75))
                .lineLimit(1)
            Text(Count.ago(project.updatedAt))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProjectBadge(project: project, size: 24)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(holds.components(separatedBy: " · ").first ?? holds) · \(Count.ago(project.updatedAt))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    /// "2 acessos · 6 variáveis · 3 links", leaving out what it has none of.
    private var holds: String {
        let variables = project.environments.reduce(0) { $0 + $1.variables.count }
        var parts: [String] = []
        if !project.credentials.isEmpty { parts.append(Count.credentials(project.credentials.count)) }
        if variables > 0 { parts.append(Count.variables(variables)) }
        if !project.links.isEmpty { parts.append(Count.links(project.links.count)) }
        return parts.isEmpty ? localized("Vazio por enquanto") : parts.joined(separator: " · ")
    }
}

struct NewProjectCard: View {
    @EnvironmentObject private var vault: Vault
    @State private var hovering = false

    var body: some View {
        Button { vault.addProject() } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text(localized("Novo projeto"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.paper.opacity(hovering ? 0.85 : 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.paper.opacity(hovering ? 0.3 : 0.16), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A number worth a look, and the list behind it on a click. With nothing to show, it says so and
/// does nothing.
struct AttentionCard<Item: Identifiable, Row: View>: View {
    let title: String
    let symbol: String
    let items: [Item]
    let unit: String
    let allClear: String
    @ViewBuilder let row: (Item, @escaping () -> Void) -> Row
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            BentoCard(interactive: !items.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: items.isEmpty ? "checkmark.circle" : symbol)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(items.isEmpty ? Theme.muted : Theme.color(.amber))
                    Spacer(minLength: 0)
                    if items.isEmpty {
                        Text(allClear)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text("\(items.count)")
                            .font(Theme.display(28))
                            .monospacedDigit()
                        Text(unit)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    row(item) { showing = false }
                }
            }
            .padding(8)
            .frame(width: 300)
            .keysSurface()
        }
    }
}

struct MissingPasswordsCard: View {
    let missing: [VaultSummary.MissingPassword]
    @EnvironmentObject private var vault: Vault

    var body: some View {
        AttentionCard(
            title: localized("Sem senha"),
            symbol: "exclamationmark.triangle",
            items: missing,
            unit: missing.count == 1 ? localized("acesso") : localized("acessos"),
            allClear: localized("Todos com senha")
        ) { item, close in
            AttentionRow(symbol: item.credential.displaySymbol, title: item.credential.displayTitle, detail: item.project.name) {
                vault.section = .credentials
                vault.selection = item.project.id
                close()
            }
        }
    }
}

struct MissingContextCard: View {
    let projects: [Project]
    @EnvironmentObject private var vault: Vault

    var body: some View {
        AttentionCard(
            title: localized("Sem contexto"),
            symbol: "text.page",
            items: projects,
            unit: projects.count == 1 ? localized("projeto") : localized("projetos"),
            allClear: localized("Todos com contexto")
        ) { project, close in
            AttentionRow(symbol: project.symbol, title: project.name, detail: nil) {
                vault.section = .context
                vault.selection = project.id
                close()
            }
        }
    }
}

/// A line in an attention card's list, opening where the thing to fix is.
struct AttentionRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text(title.isEmpty ? localized("Sem nome") : title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.paper.opacity(hovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
