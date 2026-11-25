import SwiftUI

/// The main window: the lock screen until the vault opens, then the projects.
struct RootView: View {
    @EnvironmentObject private var vault: Vault

    var body: some View {
        Group {
            if vault.state == .unlocked {
                MainView()
            } else {
                LockScreen()
                    // A toolbar with nothing in it: without one macOS draws the short title bar,
                    // and the window's controls would move each time the vault locks or opens.
                    .toolbar { ToolbarSpacer(.flexible) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vault.state)
        .keysSurface()
        // The title bar takes the window's ink instead of a bar of its own with a divider under
        // it, so the header and the content read as one surface.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Creates the vault on first launch, unlocks it afterwards, and explains when it can't open.
/// Laid out like Mara's introduction: the dotted mark, a title, then what matters.
struct LockScreen: View {
    @EnvironmentObject private var vault: Vault
    @State private var shown = false
    @State private var confirmingNewVault = false
    @State private var importing: BackupFile?

    private let features: [(symbol: String, title: String, text: String)] = [
        ("text.page", localized("O contexto de cada projeto"), localized("Como rodar, como publicar, onde está cada coisa e por que foi feito assim, para retomar meses depois.")),
        ("curlybraces", localized("Variáveis e acessos juntos"), localized("Os .env de cada ambiente, os painéis, os bancos e as chaves de API, a um clique de copiar.")),
        ("lock.laptopcomputer", localized("Só neste Mac"), localized("A chave fica no Secure Enclave e só abre com Touch ID ou a senha do Mac. Nada vai para a internet.")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            KeyMark(shown: shown)
                .frame(height: 72)
            Text(title)
                .font(Theme.display(32))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 6)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: shown)
            content
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.5), value: shown)
            if let problem = vault.problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: 440)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            shown = true
            if vault.state == .locked && !vault.askedOnLaunch {
                vault.askedOnLaunch = true
                Task { await vault.unlock() }
            }
        }
        .sheet(item: $importing) { file in ImportBackupSheet(file: file) }
        .confirmationDialog(localized("Começar um cofre novo?"), isPresented: $confirmingNewVault) {
            Button(localized("Começar de novo"), role: .destructive) { vault.setAsideUnreadable() }
        } message: {
            Text(localized("O cofre atual não é apagado: ele é renomeado e fica na mesma pasta, caso você recupere a chave."))
        }
    }

    private var title: String {
        switch vault.state {
        case .new: localized("Boas-vindas ao Chaves")
        case .unreadable: localized("O cofre não abre aqui")
        default: appName
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vault.state {
        case .new:
            VStack(alignment: .leading, spacing: 20) {
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(feature.text)
                                .font(.system(size: 12.5))
                                .lineSpacing(1.5)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 34)
            Button(localized("Criar cofre")) { vault.create() }
                .buttonStyle(PillButtonStyle(large: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!DeviceKey.isAvailable)
                .padding(.top, 34)
            // Moving from another Mac: the vault comes from a backup instead of starting empty.
            Button(localized("Tenho um backup de outro Mac")) { importing = chooseBackupFile() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.accent)
                .disabled(!DeviceKey.isAvailable)
                .padding(.top, 14)
            if !DeviceKey.isAvailable {
                Text(VaultError.noSecureEnclave.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 10)
            }
        case .locked:
            Text(localized("O cofre está trancado."))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
            Button {
                Task { await vault.unlock() }
            } label: {
                if vault.keyAccessFailed {
                    Label(localized("Tentar de novo"), systemImage: "arrow.clockwise")
                } else {
                    Label(localized("Destrancar com Touch ID"), systemImage: "touchid")
                }
            }
            .buttonStyle(PillButtonStyle(large: true))
            .keyboardShortcut(.defaultAction)
            .disabled(vault.isUnlocking)
            .padding(.top, 28)
            if vault.hasUnsavedEdits {
                Text(localized("As últimas alterações ainda não foram salvas. Deixe o Chaves aberto: elas estão criptografadas na memória e ele continua tentando salvar."))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        case .unreadable(let reason):
            Text(reason)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            // The way back for a vault copied from another Mac: its backup, made there.
            Button(localized("Importar backup…")) { importing = chooseBackupFile() }
                .buttonStyle(PillButtonStyle(large: true))
                .padding(.top, 28)
            HStack(spacing: 10) {
                Button(localized("Mostrar no Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([vault.fileURL])
                }
                Button(localized("Começar um cofre novo…")) { confirmingNewVault = true }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .padding(.top, 12)
        case .unlocked:
            EmptyView()
        }
    }
}

/// The projects in a sidebar and the selected one beside it.
struct MainView: View {
    @EnvironmentObject private var vault: Vault
    @State private var query = ""
    /// The search field shows under the title bar only after its button (or ⌘F) asks for it.
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool
    @State private var deleting: Project.ID?
    /// Projects whose subprojects show in the sidebar. Every group starts folded, so the list
    /// opens short; the open project's groups unfold to show it (see `reveal`).
    @State private var unfolded: Set<Project.ID> = []
    /// The list starts with the keyboard, as in Mail and Notes; otherwise the project's name
    /// field would, with its text selected, one keystroke away from being replaced.
    @FocusState private var listFocused: Bool
    /// Followed, not driven: the sidebar button folds it with AppKit (see toggleSidebar).
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            Group {
                if let id = vault.selection, let project = vault.binding(for: id) {
                    ProjectView(project: project)
                        .id(id)
                } else {
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ink)
        }
        // Beside the window's controls, outside the sidebar, so it is still there to bring it back.
        .background(LeadingTitlebarAccessory {
            HStack(spacing: 2) {
                sidebarButton
                searchButton
            }
        })
        // When the list folds away with the keyboard, AppKit hands the keyboard to the next field,
        // the project's name, with its text selected: one stray key would replace the name. So
        // nothing takes it then, and it goes back to the list when the sidebar returns.
        .onChange(of: columns) {
            if columns == .detailOnly {
                DispatchQueue.main.async {
                    NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }?.makeFirstResponder(nil)
                }
            } else if searchOpen {
                // Back for the search (see openSearch): the field takes the keyboard.
                DispatchQueue.main.async { searchFocused = true }
            } else {
                DispatchQueue.main.async { listFocused = true }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { vault.addProject() } label: {
                    Label(localized("Novo projeto"), systemImage: "plus")
                }
                .help(localized("Novo projeto (⌘N)"))
            }
            ToolbarItem {
                Button { vault.lock() } label: {
                    Label(localized("Trancar"), systemImage: "lock")
                }
                .help(vault.isSample ? localized("O cofre de exemplo não tranca") : localized("Trancar o cofre (⇧⌘L)"))
                .disabled(vault.isSample)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = vault.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.2))
            }
        }
        .confirmationDialog(
            localized("Apagar \(vault.project(deleting)?.name ?? "")?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button(localized("Apagar projeto"), role: .destructive) {
                if let deleting { vault.deleteProject(deleting) }
            }
        } message: {
            if let deleting, !ProjectTree.children(of: deleting, in: vault.projects).isEmpty {
                Text(localized("O contexto, as variáveis e os acessos do projeto saem do cofre. Os subprojetos ficam, um nível acima."))
            } else {
                Text(localized("O contexto, as variáveis e os acessos do projeto saem do cofre. A cópia de segurança de antes desta sessão continua em Backups."))
            }
        }
    }

    private var filtered: [Project] {
        vault.projects.filter { !$0.isArchived && $0.matches(query) }
    }

    /// The projects in the order the sidebar shows them, for moving with the arrow keys.
    private var visibleOrder: [Project.ID] {
        guard Search.words(query).isEmpty else { return searchResults.map(\.id) }
        var order: [Project.ID] = []
        func walk(_ project: Project, archived: Bool) {
            order.append(project.id)
            guard unfolded.contains(project.id) else { return }
            ProjectTree.children(of: project.id, in: vault.projects).filter { $0.isArchived == archived }.forEach { walk($0, archived: archived) }
        }
        ProjectTree.roots(archived: false, in: vault.projects).forEach { walk($0, archived: false) }
        return order
    }

    private var searchResults: [Project] {
        filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Unfolds the projects above `id`, so the open project is never hidden in a folded group.
    private func reveal(_ id: Project.ID?) {
        guard let project = vault.project(id) else { return }
        for ancestor in ProjectTree.ancestors(of: project, in: vault.projects) {
            unfolded.insert(ancestor.id)
        }
    }

    /// ← folds the open group, or goes up to the group of the open project, as in Finder.
    private func foldOrGoUp() -> KeyPress.Result {
        guard let project = vault.project(vault.selection) else { return .ignored }
        let children = ProjectTree.children(of: project.id, in: vault.projects).filter { !$0.isArchived }
        if !children.isEmpty, unfolded.contains(project.id) {
            withAnimation(.easeInOut(duration: 0.18)) { _ = unfolded.remove(project.id) }
        } else if let parent = ProjectTree.ancestors(of: project, in: vault.projects).last {
            vault.selection = parent.id
        }
        return .handled
    }

    /// → unfolds the open group, or goes into its first subproject.
    private func unfoldOrGoIn() -> KeyPress.Result {
        guard let project = vault.project(vault.selection) else { return .ignored }
        let children = ProjectTree.children(of: project.id, in: vault.projects).filter { !$0.isArchived }
        guard let first = children.first else { return .handled }
        if !unfolded.contains(project.id) {
            withAnimation(.easeInOut(duration: 0.18)) { _ = unfolded.insert(project.id) }
        } else {
            vault.selection = first.id
        }
        return .handled
    }

    private func moveSelection(by step: Int) -> KeyPress.Result {
        let order = visibleOrder
        guard !order.isEmpty else { return .ignored }
        // A selection hidden in a folded group counts from the nearest group that shows.
        var anchor = vault.selection
        if let project = vault.project(anchor), !order.contains(project.id) {
            anchor = ProjectTree.ancestors(of: project, in: vault.projects).last { order.contains($0.id) }?.id
        }
        let current = order.firstIndex { $0 == anchor }
        let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? (step > 0 ? 0 : order.count - 1)
        vault.selection = order[next]
        return .handled
    }

    /// Folds or unfolds the sidebar with AppKit's own toggle, so it moves with the system's
    /// animation (the one the system button runs), not a SwiftUI animation layered over the split
    /// view's. It goes up the main window's own responder chain: `NSApp.sendAction(to: nil)` only
    /// reaches the window that is active, which isn't always this one.
    private func toggleSidebar() {
        let action = #selector(NSSplitViewController.toggleSidebar(_:))
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == mainWindowID }) else { return }
        let start: NSResponder? = window.firstResponder ?? window.contentView
        if start?.tryToPerform(action, with: nil) != true {
            NSApp.sendAction(action, to: nil, from: nil)
        }
    }

    /// The sidebar's place in the main window's split view.
    private static func sidebarItem() -> NSSplitViewItem? {
        let window = NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }
        return window?.contentView.flatMap(splitViewController(in:))?.splitViewItems.first { $0.behavior == .sidebar }
    }

    /// The controller of the window's split view, found from its views.
    private static func splitViewController(in view: NSView) -> NSSplitViewController? {
        if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
            return controller
        }
        for subview in view.subviews {
            if let controller = splitViewController(in: subview) { return controller }
        }
        return nil
    }

    /// Shows or hides the sidebar, with the app's own icon (the system's button can't take one).
    private var sidebarButton: some View {
        Button {
            toggleSidebar()
        } label: {
            SidebarButtonLabel()
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: [.control, .command])
        .help(localized("Mostrar ou ocultar a barra lateral (⌃⌘S)"))
        .accessibilityLabel(localized("Mostrar ou ocultar a barra lateral"))
    }

    /// Opens the search at the top of the sidebar, or closes it and clears what was typed.
    private var searchButton: some View {
        Button {
            if searchOpen { closeSearch() } else { openSearch() }
        } label: {
            TitlebarButtonLabel(active: searchOpen) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f")
        .help(searchOpen ? localized("Fechar a busca (⌘F)") : localized("Buscar em tudo (⌘F)"))
        .accessibilityLabel(searchOpen ? localized("Fechar a busca") : localized("Buscar em tudo"))
    }

    private static let searchAnimation = Animation.smooth(duration: 0.28)

    private func openSearch() {
        // With the sidebar folded away there is nowhere for the field: it comes back first. It is
        // brought back through `columns`: the update that opens the search would otherwise put
        // back the folded state SwiftUI still holds, undoing AppKit's own toggle.
        if Self.sidebarItem()?.isCollapsed ?? (columns == .detailOnly) {
            withAnimation(Self.searchAnimation) { columns = .all }
        }
        withAnimation(Self.searchAnimation) { searchOpen = true }
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(Self.searchAnimation) {
            searchOpen = false
            query = ""
        }
        listFocused = true
    }

    /// The search field, sliding down from under the title bar. Esc closes it, ↓ and ↑ move
    /// through what it found, and Return keeps the open project and goes back to the list.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            TextField(localized("Buscar em tudo"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onSubmit { listFocused = true }
                .onKeyPress(.downArrow) { moveSelection(by: 1) }
                .onKeyPress(.upArrow) { moveSelection(by: -1) }
                .onExitCommand { closeSearch() }
            if !query.isEmpty {
                IconButton(symbol: "xmark.circle.fill", help: localized("Limpar a busca")) { query = "" }
                    .frame(width: 18, height: 18)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Theme.paper.opacity(searchFocused ? 0.09 : 0.06), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: query.isEmpty)
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if searchOpen {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            projectList
        }
        // The field slides out from under the title bar, not over it.
        .clipped()
    }

    private var projectList: some View {
        // The list draws no selection of its own: the system's would be a strong accent color.
        // Each row shows its own quiet highlight (see ProjectRow), and the arrow keys and Delete
        // still work while the list has the keyboard.
        List {
            if Search.words(query).isEmpty {
                HomeRow()
                // The projects in use, as a tree. Archived ones aren't here at all: they live in
                // Settings › Archived, out of the way.
                ForEach(ProjectTree.roots(archived: false, in: vault.projects)) { project in
                    ProjectTreeRow(project: project, archived: false, unfolded: $unfolded, actions: rowActions)
                }
            } else {
                // A search shows what matched as a flat list, each with the path to it.
                ForEach(searchResults) { project in
                    SelectableProjectRow(project: project, path: ProjectTree.ancestors(of: project, in: vault.projects).map(\.name))
                        .contextMenu { rowActions(project) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        // The keyboard starts on the list, never in a text field: a project's name field with
        // the focus has its text selected, so the first keystroke would replace the name.
        .defaultFocus($listFocused, true)
        // Without a search field in the sidebar, AppKit makes the project's name the window's
        // first responder as it opens, and the list can't take the keyboard from a field that
        // holds it: the window lets go of it first.
        .onAppear {
            DispatchQueue.main.async {
                NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }?.makeFirstResponder(nil)
                listFocused = true
            }
        }
        // The app's own button takes the system's place (see `body`).
        .toolbar(removing: .sidebarToggle)
        .onChange(of: vault.selection, initial: true) { reveal(vault.selection) }
        // Archiving the open project takes it out of the sidebar: the project above it, if that one
        // is still in use, opens instead.
        .onChange(of: vault.project(vault.selection)?.archivedAt) {
            guard let project = vault.project(vault.selection), project.isArchived else { return }
            vault.selection = ProjectTree.ancestors(of: project, in: vault.projects).last { !$0.isArchived }?.id
        }
        .onKeyPress(.leftArrow) { foldOrGoUp() }
        .onKeyPress(.rightArrow) { unfoldOrGoIn() }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        // The Delete key asks before removing the selected project, as in Finder and Mail.
        .onDeleteCommand { deleting = vault.selection }
        .overlay {
            if vault.projects.isEmpty {
                ContentUnavailableView {
                    Label(localized("Nenhum projeto ainda"), systemImage: "shippingbox")
                } actions: {
                    Button(localized("Novo projeto")) { vault.addProject() }
                        .buttonStyle(PillButtonStyle())
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    @ViewBuilder
    private func rowActions(_ project: Project) -> some View {
        Button(localized("Novo subprojeto")) { vault.addProject(inside: project.id) }
        Button(localized("Arquivar")) { vault.setArchived(project.id, true) }
        Divider()
        Button(localized("Apagar projeto…"), role: .destructive) { deleting = project.id }
    }
}

/// A project in the sidebar and, under a disclosure triangle, the projects inside it.
struct ProjectTreeRow<Actions: View>: View {
    let project: Project
    /// Which of the sidebar's lists the row is in: its subprojects shown are those on that side.
    let archived: Bool
    /// The projects above it, for a row that heads its list without its parent (see `roots`).
    var path: [String] = []
    /// How deep in the tree the row is: each level indents it a little.
    var depth = 0
    @Binding var unfolded: Set<Project.ID>
    let actions: (Project) -> Actions
    @EnvironmentObject private var vault: Vault

    var body: some View {
        // Rows of their own rather than a DisclosureGroup: the system's disclosure triangle made
        // the list keep an empty column on the left of every row, groups or not.
        let children = ProjectTree.children(of: project.id, in: vault.projects).filter { $0.isArchived == archived }
        let expanded = unfolded.contains(project.id)
        SelectableProjectRow(project: project, path: path, expanded: children.isEmpty ? nil : expanded) {
            withAnimation(.easeInOut(duration: 0.18)) {
                if expanded { unfolded.remove(project.id) } else { unfolded.insert(project.id) }
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
        .contextMenu { actions(project) }
        if expanded {
            ForEach(children) { child in
                // Type-erased: the row contains rows of its own type.
                AnyView(ProjectTreeRow(project: child, archived: archived, depth: depth + 1, unfolded: $unfolded, actions: actions))
            }
        }
    }
}

/// A project row that opens the project when clicked and shows whether it's the open one.
struct SelectableProjectRow: View {
    let project: Project
    var path: [String] = []
    /// For a project with subprojects, whether they show; nil for one without.
    var expanded: Bool? = nil
    var toggle: () -> Void = {}
    @EnvironmentObject private var vault: Vault

    var body: some View {
        let selected = vault.selection == project.id
        // A button rather than a tap gesture, so VoiceOver and other assistive tools can open it too.
        Button {
            vault.selection = project.id
        } label: {
            ProjectRow(project: project, path: path, selected: selected, trailingRoom: expanded == nil ? 0 : 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if let expanded {
                // The group's own chevron, on the right, pointing down while its subprojects show.
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.paper.opacity(0.45))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .help(expanded ? localized("Ocultar os subprojetos") : localized("Mostrar os subprojetos"))
                .accessibilityLabel(expanded ? localized("Ocultar os subprojetos") : localized("Mostrar os subprojetos"))
            }
        }
    }
}

/// The start page's place at the top of the sidebar, highlighted while it shows.
struct HomeRow: View {
    @EnvironmentObject private var vault: Vault
    @State private var hovering = false

    var body: some View {
        let selected = vault.selection == nil
        Button {
            vault.selection = nil
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.paper.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Theme.paper.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(localized("Início"))
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.paper : Theme.paper.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .background(
                Theme.paper.opacity(selected ? 0.09 : hovering ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ProjectRow: View {
    let project: Project
    /// The names of the projects above it, shown when the tree isn't (in a search).
    var path: [String] = []
    /// The open project: a quiet surface behind it and its name in semibold, in the app's own
    /// colors rather than the system's accent.
    var selected = false
    /// Room kept free on the right for the group's chevron.
    var trailingRoom: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ProjectBadge(project: project, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name.isEmpty ? localized("Sem nome") : project.name)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.paper : Theme.paper.opacity(0.85))
                    .lineLimit(1)
                if !path.isEmpty {
                    Text(path.joined(separator: " › "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                } else if !project.summary.isEmpty {
                    Text(project.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, trailingRoom)
        // Archived projects read a little quieter, except the one that's open.
        .opacity(project.isArchived && !selected ? 0.6 : 1)
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(
            Theme.paper.opacity(selected ? 0.09 : hovering ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { hovering = $0 }
    }
}
