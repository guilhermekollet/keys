import SwiftUI

/// What the project's list shows: everything, or one kind of item.
enum ProjectSection: String, CaseIterable, Identifiable {
    case all, credentials, variables, links
    var id: Self { self }

    var title: String {
        switch self {
        case .all: localized("Tudo")
        case .credentials: localized("Acessos")
        case .variables: localized("Variáveis")
        case .links: localized("Links")
        }
    }
}

/// One project: its name on top, its context pinned under it, then a single list of its accesses,
/// variables and links, filtered and searchable.
struct ProjectView: View {
    static let contentWidth: CGFloat = 860
    @Binding var project: Project
    @EnvironmentObject private var vault: Vault
    /// The access open in the panel on the right.
    @State private var editing: Credential.ID?
    @State private var deletingCredential: Credential.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectHeader(project: $project)
                .padding(.horizontal, 24)
                .padding(.top, 22)
            ContextCard(project: $project)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            ProjectItemsView(project: $project, editing: $editing, deletingCredential: $deletingCredential, moveCredential: move)
                // Whatever the list holds, it fits the room left and never makes the window's
                // content taller than the window (which pushed the sidebar and the header off
                // screen once). It scrolls instead.
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        // A column that reads well: on a wide window the rows don't stretch from edge to edge,
        // with their buttons far from their names.
        .frame(maxWidth: Self.contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Floats over the project rather than pushing it aside, so the list keeps its width and
        // another access can be opened with a click while this one is showing.
        .overlay(alignment: .trailing) {
            if let id = editing, let credential = credentialBinding(id) {
                CredentialEditor(
                    credential: credential,
                    close: close,
                    destinations: { vault.projects.credentialDestinations(from: project.id) },
                    move: { move(id, to: $0) }
                ) {
                    deletingCredential = id
                }
                .id(id)
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Theme.shadow, radius: 24, x: -4, y: 8)
                .padding(10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: editing == nil)
        // An access closed without anything typed in it isn't kept.
        .onChange(of: editing) { old, _ in dropIfEmpty(old) }
        .onDisappear { dropIfEmpty(editing) }
        .confirmationDialog(
            localized("Apagar o acesso \(project.credentials.first { $0.id == deletingCredential }?.displayTitle ?? "")?"),
            isPresented: Binding(get: { deletingCredential != nil }, set: { if !$0 { deletingCredential = nil } })
        ) {
            Button(localized("Apagar acesso"), role: .destructive) {
                if editing == deletingCredential { editing = nil }
                project.credentials.removeAll { $0.id == deletingCredential }
            }
        }
        .navigationTitle(project.name)
    }

    private func close() {
        editing = nil
    }

    private func move(_ id: Credential.ID, to destination: Project.ID) {
        if editing == id { editing = nil }
        vault.moveCredential(id, from: project.id, to: destination)
    }

    private func dropIfEmpty(_ id: Credential.ID?) {
        guard let id, let credential = project.credentials.first(where: { $0.id == id }), credential.isEmpty else { return }
        project.credentials.removeAll { $0.id == id }
    }

    /// The access with `id`, looked up on every read and write rather than by position.
    private func credentialBinding(_ id: Credential.ID) -> Binding<Credential>? {
        guard let current = project.credentials.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { project.credentials.first { $0.id == id } ?? current },
            set: { new in
                if let index = project.credentials.firstIndex(where: { $0.id == id }) { project.credentials[index] = new }
            }
        )
    }
}

struct ProjectHeader: View {
    @Binding var project: Project
    @EnvironmentObject private var vault: Vault
    @State private var tags = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var tagsFocused: Bool
    @State private var choosingLook = false
    @State private var hovering = false

    private var children: [Project] {
        ProjectTree.children(of: project.id, in: vault.projects).filter { $0.isArchived == project.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identity
            if !children.isEmpty {
                // Lined up with the name. It scrolls sideways only when there are more chips
                // than fit.
                ScrollView(.horizontal, showsIndicators: false) {
                    subprojects
                }
                // As tall as the chips: a horizontal scroll view would otherwise take any height
                // it's offered.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 46 + 14)
            }
        }
        .onHover { hovering = $0 }
        .onAppear {
            tags = project.tags.joined(separator: ", ")
            // A project just created opens with its name selected, ready to be typed over.
            if Date().timeIntervalSince(project.createdAt) < 2 {
                DispatchQueue.main.async { nameFocused = true }
            }
        }
    }

    /// The tags field shows when there are tags, or while the pointer is over the header to add
    /// some, so an empty project doesn't greet you with two lines of placeholders.
    private var showsTags: Bool {
        !tags.isEmpty || hovering || tagsFocused
    }

    /// Symbol, name, summary and tags, with its status and a menu of what else can be done on the right.
    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                choosingLook = true
            } label: {
                ProjectBadge(project: project, size: 46)
            }
            .buttonStyle(.plain)
            .help(localized("Trocar o ícone e a cor"))
            .accessibilityLabel(localized("Trocar o ícone e a cor"))
            .popover(isPresented: $choosingLook, arrowEdge: .bottom) {
                ProjectLookPicker(symbol: $project.symbol, tint: $project.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                path
                TextField(localized("Nome do projeto"), text: $project.name)
                    .font(Theme.display(26))
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                TextField(localized("Uma linha sobre o projeto"), text: $project.summary)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.muted)
                TextField(localized("Etiquetas, separadas por vírgula"), text: $tags)
                    .font(.system(size: 11.5))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.paper.opacity(0.45))
                    .focused($tagsFocused)
                    .onChange(of: tags) { commitTags() }
                    .opacity(showsTags ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showsTags)
            }

            Spacer(minLength: 12)

            if let archivedAt = project.archivedAt {
                HStack(spacing: 6) {
                    Badge(text: localized("Arquivado"), symbol: "archivebox")
                        .help(localized("Arquivado em \(archivedAt.formatted(date: .abbreviated, time: .omitted))"))
                    Button(localized("Desarquivar")) { vault.setArchived(project.id, false) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .help(children.isEmpty ? localized("Volta a usar o projeto") : localized("Volta a usar o projeto e os subprojetos dele"))
                }
                .fixedSize()
            }

            moreMenu
        }
    }

    /// "Grupo Fazolli ›" above the name of a subproject, each step a way back up.
    @ViewBuilder
    private var path: some View {
        let ancestors = ProjectTree.ancestors(of: project, in: vault.projects)
        if !ancestors.isEmpty {
            HStack(spacing: 4) {
                ForEach(ancestors) { ancestor in
                    Button(ancestor.name) { vault.selection = ancestor.id }
                        .buttonStyle(.plain)
                        .help(localized("Abrir \(ancestor.name)"))
                    Text("›")
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
    }

    /// The projects inside this one, as chips that open them.
    private var subprojects: some View {
        HStack(spacing: 6) {
            ForEach(children) { child in
                Button {
                    vault.selection = child.id
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: child.symbol)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        Text(child.name.isEmpty ? localized("Sem nome") : child.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.paper.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(localized("Abrir \(child.name)"))
            }
        }
    }

    /// Where the project sits, a new subproject and archiving, out of the way until needed.
    private var moreMenu: some View {
        Menu {
            Button(localized("Novo subprojeto"), systemImage: "plus") {
                vault.addProject(inside: project.id)
            }
            Picker(selection: $project.parentID) {
                Text(localized("Nenhum: projeto principal")).tag(Project.ID?.none)
                Divider()
                ForEach(ProjectTree.possibleParents(for: project.id, in: vault.projects)) { candidate in
                    Text(ProjectTree.path(of: candidate, in: vault.projects)).tag(Optional(candidate.id))
                }
            } label: {
                Label(localized("Mover para dentro de outro projeto"), systemImage: "folder")
            }
            .pickerStyle(.menu)
            if !project.isArchived {
                Divider()
                Button(localized("Arquivar"), systemImage: "archivebox") {
                    vault.setArchived(project.id, true)
                }
                .help(children.isEmpty
                    ? localized("Guarda o projeto em Arquivados, fora da barra lateral e da barra de menus. Nada é apagado.")
                    : localized("Guarda o projeto e os subprojetos dele em Arquivados, fora da barra lateral e da barra de menus. Nada é apagado."))
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.paper.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(Theme.paper.opacity(0.07), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(localized("Mais opções do projeto"))
        .accessibilityLabel(localized("Mais opções do projeto"))
    }

    private func commitTags() {
        let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if list != project.tags { project.tags = list }
    }
}

/// Where the code is and the free text that explains the project, pinned above the list. It folds
/// down to one line, showing the start of the text, to leave the room to the list.
struct ContextCard: View {
    @Binding var project: Project
    @AppStorage("contextExpanded") private var expanded = true

    /// Headings that cover what is usually missing when a project is picked up again.
    static var outline: String {
        [localized("Como rodar"), localized("Deploy"), localized("Onde está o quê"), localized("Decisões"), localized("Armadilhas"), localized("Contatos")]
            .map { "## \($0)\n\n" }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.paper.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(localized("Contexto"))
                        .font(.system(size: 12.5, weight: .semibold))
                    if !expanded {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? localized("Recolher o contexto") : localized("Mostrar o contexto"))

            if expanded {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18)
                    TextField(localized("Pasta do projeto neste Mac"), text: $project.localPath)
                        .textFieldStyle(.code)
                    Button(localized("Escolher…"), action: chooseFolder)
                        .buttonStyle(PillButtonStyle(prominent: false))
                    IconButton(symbol: "folder.badge.gearshape", help: localized("Abrir no Finder")) {
                        if let folderURL { NSWorkspace.shared.open(folderURL) }
                    }
                    .disabled(!folderExists)
                    IconButton(symbol: "terminal", help: localized("Abrir no Terminal"), action: openInTerminal)
                        .disabled(!folderExists)
                }

                TextEditor(text: $project.context)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 150)
                    .background(Theme.paper.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // An overlay, not a sibling in a stack: the hint must never decide how tall the
                    // editor is. Measured as part of the layout, its wrapped text once made the
                    // whole window taller than the screen for a new, empty project.
                    .overlay(alignment: .topLeading) {
                        if project.context.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(localized("Tudo o que você vai querer saber quando voltar a este projeto: como rodar, como publicar, onde está cada coisa, por que foi feito assim e com quem falar."))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.muted)
                                Button(localized("Começar com um roteiro")) { project.context = Self.outline }
                                    .buttonStyle(PillButtonStyle())
                            }
                            .padding(12)
                            .frame(maxWidth: 460, alignment: .leading)
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, expanded ? 12 : 9)
        // Folded, it's a quiet line; open, a card to write in.
        .background(Theme.surface.opacity(expanded ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The first line of the context with words in it, without Markdown's heading marks.
    private var preview: String {
        let line = project.context
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .first { !$0.isEmpty }
        return line ?? localized("Vazio")
    }

    private var folderURL: URL? {
        let path = (project.localPath as NSString).expandingTildeInPath
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private var folderExists: Bool {
        guard let folderURL else { return false }
        return FileManager.default.fileExists(atPath: folderURL.path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = localized("Escolher")
        if let folderURL { panel.directoryURL = folderURL }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Kept with "~" so the path still reads well (and works) on a Mac with another user name.
        project.localPath = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func openInTerminal() {
        guard let folderURL, let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([folderURL], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// An address that goes with the project: repository, production, a dashboard, docs.
struct LinkRow: View {
    @Binding var link: ProjectLink
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(localized("Nome"), text: $link.title)
                .textFieldStyle(.field)
                .frame(width: 170)
            TextField("https://", text: $link.url)
                .textFieldStyle(.code)
            CopyButton(value: link.url, help: localized("Copiar o endereço"))
            IconButton(symbol: "arrow.up.right", help: localized("Abrir")) {
                if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
            }
            .disabled(URL(string: link.url)?.scheme == nil)
            IconButton(symbol: "trash", help: localized("Remover"), action: remove)
        }
        .padding(.vertical, 6)
    }
}

/// A hairline between the rows of a card.
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// What an empty tab shows: what goes there.
struct EmptyTab: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

/// The project's color, on a row of swatches, and its icon, on a grid, each choice applied as it's
/// made and shown in the project's color.
struct ProjectLookPicker: View {
    @Binding var symbol: String
    @Binding var tint: Project.Tint
    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Cor"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(Project.Tint.allCases) { option in
                    let selected = option == tint
                    Button {
                        tint = option
                    } label: {
                        Circle()
                            .fill(Theme.color(option))
                            .frame(width: 20, height: 20)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Theme.paper.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Text(localized("Ícone"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Project.symbols, id: \.self) { option in
                        let selected = option == symbol
                        let color = Theme.color(tint)
                        Button {
                            symbol = option
                        } label: {
                            Image(systemName: option)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selected ? color : Theme.paper.opacity(0.75))
                                .frame(width: 32, height: 32)
                                .background(selected ? color.opacity(0.18) : Theme.paper.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(selected ? 0.6 : 0), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .frame(height: 6 * 38)
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(width: 9 * 32 + 8 * 6 + 32)
        .keysSurface()
    }
}
