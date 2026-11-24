import SwiftUI

/// One environment in the project's list: its name and menu (import, export, rename, duplicate,
/// delete), then its variables, those matching `query` while there's a search.
struct EnvironmentSection: View {
    @Binding var project: Project
    let environmentID: EnvironmentSet.ID
    var query = ""
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var notice: String?
    /// Shown as a `.env` file instead of as rows to edit; the choice is kept for every environment.
    @AppStorage("variablesAsDotEnv") private var asDotEnv = false

    var body: some View {
        if let environment {
            let searching = !Search.words(query).isEmpty
            let visible = environment.variables.filter { $0.matches(query) }
            VStack(alignment: .leading, spacing: 8) {
                header(environment)
                if asDotEnv && (!visible.isEmpty || !searching) {
                    DotEnvView(variables: visible, dotEnv: environment.dotEnv, canEdit: !searching) { text in
                        var result = (added: 0, updated: 0, removed: 0)
                        update { result = $0.replaceVariables(with: DotEnv.parse(text)) }
                        if result != (0, 0, 0) {
                            show(localized("\(result.added) novas, \(result.updated) atualizadas, \(result.removed) removidas"))
                        }
                    }
                } else if !visible.isEmpty {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(visible) { variable in
                                if variable.id != visible.first?.id { RowDivider() }
                                if let binding = binding(for: variable.id) {
                                    VariableRow(variable: binding) {
                                        update { $0.variables.removeAll { $0.id == variable.id } }
                                    }
                                }
                            }
                        }
                    }
                } else if !searching {
                    Text(localized("Nenhuma variável. Adicione uma a uma ou importe um arquivo .env."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 4)
                }
                if !searching && !asDotEnv {
                    Button {
                        update { $0.variables.append(Variable()) }
                    } label: {
                        Label(localized("Adicionar variável"), systemImage: "plus")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .alert(localized("Nome do ambiente"), isPresented: $renaming) {
                TextField("production", text: $newName)
                Button(localized("Salvar")) {
                    if !newName.isEmpty { update { $0.name = newName } }
                }
                Button(localized("Cancelar"), role: .cancel) {}
            }
            .confirmationDialog(localized("Apagar o ambiente \(environment.name)?"), isPresented: $confirmingDelete) {
                Button(localized("Apagar ambiente"), role: .destructive) {
                    project.environments.removeAll { $0.id == environmentID }
                }
            } message: {
                Text(localized("As variáveis dele saem do cofre."))
            }
        }
    }

    private var environment: EnvironmentSet? {
        project.environments.first { $0.id == environmentID }
    }

    private func header(_ environment: EnvironmentSet) -> some View {
        HStack(spacing: 8) {
            Text(environment.name.isEmpty ? localized("Sem nome") : environment.name)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
            Text("\(environment.variables.count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.muted)
            Spacer()
            if let notice {
                Text(notice)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
            ViewModePicker(asDotEnv: $asDotEnv)
            Menu {
                Button(localized("Importar de um arquivo .env…"), action: importFile)
                Button(localized("Colar da área de transferência"), action: importClipboard)
                Divider()
                Button(localized("Copiar como .env")) {
                    Clipboard.copy(environment.dotEnv, secret: true)
                    show(localized("Copiado como .env"))
                }
                .disabled(environment.variables.isEmpty)
                Button(localized("Salvar arquivo .env…"), action: exportFile)
                    .disabled(environment.variables.isEmpty)
                Divider()
                Button(localized("Renomear…")) {
                    newName = environment.name
                    renaming = true
                }
                Button(localized("Duplicar")) { duplicate(environment) }
                Button(localized("Apagar…"), role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(localized("Importar, exportar e organizar o ambiente"))
        }
    }

    /// Changes this environment in place, found by id rather than by position.
    private func update(_ change: (inout EnvironmentSet) -> Void) {
        guard let index = project.environments.firstIndex(where: { $0.id == environmentID }) else { return }
        change(&project.environments[index])
    }

    /// The variable with `id`, looked up on every read and write, so removing one while it's on
    /// screen can't reach past the end of the list.
    private func binding(for id: Variable.ID) -> Binding<Variable>? {
        guard let current = environment?.variables.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { environment?.variables.first { $0.id == id } ?? current },
            set: { new in
                update { environment in
                    if let index = environment.variables.firstIndex(where: { $0.id == id }) { environment.variables[index] = new }
                }
            }
        )
    }

    private func duplicate(_ environment: EnvironmentSet) {
        var copy = environment
        copy.id = UUID()
        copy.name = localized("\(environment.name) (cópia)")
        copy.variables = environment.variables.map { variable in
            var variable = variable
            variable.id = UUID()
            return variable
        }
        project.environments.append(copy)
    }

    private func merge(_ text: String) {
        let entries = DotEnv.parse(text)
        guard !entries.isEmpty else {
            show(localized("Nenhuma variável encontrada"))
            return
        }
        var result = (added: 0, updated: 0)
        update { result = $0.merge(entries) }
        show(localized("\(result.added) novas, \(result.updated) atualizadas"))
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.message = localized("Escolha um arquivo .env")
        if let folder = projectFolder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            merge(try String(contentsOf: url, encoding: .utf8))
        } catch {
            show(error.localizedDescription)
        }
    }

    private func importClipboard() {
        merge(NSPasteboard.general.string(forType: .string) ?? "")
    }

    /// Writes the set to a file the person picks. The file is plain text, as tools expect it to be.
    private func exportFile() {
        guard let environment else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = environment.name == "development" ? ".env" : ".env.\(environment.name)"
        panel.showsHiddenFiles = true
        panel.message = localized("O arquivo fica sem criptografia, como as ferramentas esperam. Não o coloque no Git.")
        if let folder = projectFolder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DotEnv.write(environment.dotEnv, to: url)
            show(localized("Salvo em \(url.lastPathComponent)"))
        } catch {
            show(error.localizedDescription)
        }
    }

    private var projectFolder: URL? {
        let path = (project.localPath as NSString).expandingTildeInPath
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

/// Rows or `.env`: two small icon buttons side by side, the chosen one lit.
struct ViewModePicker: View {
    @Binding var asDotEnv: Bool

    var body: some View {
        HStack(spacing: 2) {
            option(symbol: "list.bullet", title: localized("Ver como lista"), selected: !asDotEnv) { asDotEnv = false }
            option(symbol: "doc.plaintext", title: localized("Ver como .env"), selected: asDotEnv) { asDotEnv = true }
        }
        .padding(2)
        .background(Theme.paper.opacity(0.06), in: Capsule())
    }

    private func option(symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.paper.opacity(selected ? 0.95 : 0.55))
                .frame(width: 26, height: 20)
                .background(Theme.paper.opacity(selected ? 0.14 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An environment as its `.env` file reads: numbered lines, keys, values and the "=" between
/// them in their own colors, as a code editor shows it. Secret values stay masked until asked;
/// copying takes the real file. The pencil turns it into the file's text to edit, real values and
/// all; saving makes the environment what the text says.
struct DotEnvView: View {
    let variables: [Variable]
    /// The whole environment as a file, for copying and as the text to edit.
    let dotEnv: String
    /// Off while searching: the lines shown are then only some of the environment.
    var canEdit = true
    /// Opens on the text, for the screenshots `--snapshot` takes.
    var startsEditing = false
    let save: (String) -> Void
    @State private var revealed = false
    @State private var copied = false
    @State private var editing = false
    @State private var draft = ""
    @State private var problem: String?
    @FocusState private var editorFocused: Bool

    private var hasSecrets: Bool {
        variables.contains { $0.isSecret && !$0.value.isEmpty }
    }

    var body: some View {
        Group {
            if editing {
                editor
            } else {
                reader
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(editing ? Theme.paper.opacity(0.22) : Theme.hairline))
        .onAppear {
            if startsEditing {
                draft = dotEnv
                editing = true
            }
        }
    }

    private var reader: some View {
        let lines = DotEnv.displayLines(variables, revealing: revealed)
        return HStack(alignment: .top, spacing: 0) {
            if lines.isEmpty {
                Text(localized("# Vazio. Use o lápis para escrever as variáveis."))
                    .foregroundStyle(Theme.paper.opacity(0.35))
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text("\(index + 1)")
                            .foregroundStyle(Theme.paper.opacity(0.28))
                    }
                }
                .padding(.trailing, 14)
                .accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(Self.highlighted(lines[index]))
                                .fixedSize()
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .lineSpacing(2)
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 100)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if hasSecrets {
                    IconButton(symbol: revealed ? "eye.slash" : "eye", help: revealed ? localized("Ocultar os valores secretos") : localized("Mostrar os valores secretos")) {
                        revealed.toggle()
                    }
                }
                if !lines.isEmpty {
                    IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: localized("Copiar como .env"), color: copied ? Theme.accent : Theme.paper.opacity(0.7)) {
                        Clipboard.copy(dotEnv, secret: true)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            copied = false
                        }
                    }
                }
                if canEdit {
                    IconButton(symbol: "pencil", help: localized("Editar como texto (mostra os valores secretos)")) {
                        draft = dotEnv
                        problem = nil
                        editing = true
                        editorFocused = true
                    }
                }
            }
            .padding(8)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $draft)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .focused($editorFocused)
                // About as tall as the lines, with room to add a few, up to a screenful.
                .frame(height: min(max(CGFloat(draft.split(separator: "\n", omittingEmptySubsequences: false).count + 2) * 19, 120), 420))
                .onChange(of: draft) { problem = nil }
            HStack(spacing: 8) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.color(.amber))
                } else {
                    Text(localized("Uma variável por linha, como CHAVE=valor. Linhas com # são ignoradas."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Button(localized("Cancelar")) { editing = false }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(localized("Salvar"), action: commit)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(10)
    }

    /// Saves the text unless a line isn't a variable: that would be dropped, so it's pointed out instead.
    private func commit() {
        let invalid = DotEnv.invalidLines(draft)
        if invalid.count == 1, let line = invalid.first {
            problem = localized("A linha \(line) não é CHAVE=valor.")
            return
        }
        if !invalid.isEmpty {
            problem = localized("As linhas \(invalid.map(String.init).joined(separator: ", ")) não são CHAVE=valor.")
            return
        }
        save(draft)
        editing = false
    }

    /// A line in an editor's colors: the key, a quiet "=", and the value, quoted ones in the
    /// string color, masked ones dimmed.
    static func highlighted(_ line: DotEnv.DisplayLine) -> AttributedString {
        var key = AttributedString(line.key)
        key.foregroundColor = Theme.color(.sky)
        var equals = AttributedString("=")
        equals.foregroundColor = Theme.paper.opacity(0.4)
        var value = AttributedString(line.value)
        if line.masked {
            value.foregroundColor = Theme.paper.opacity(0.35)
        } else if let first = line.value.first, first == "'" || first == "\"" {
            value.foregroundColor = Theme.color(.mint)
        } else {
            value.foregroundColor = Theme.color(.amber)
        }
        return key + equals + value
    }
}

struct VariableRow: View {
    @Binding var variable: Variable
    let remove: () -> Void
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("NAME", text: $variable.key)
                .textFieldStyle(.code)
                .frame(width: 230)
            Group {
                if variable.isSecret && !revealed {
                    SecureField(localized("valor"), text: $variable.value)
                } else {
                    TextField(localized("valor"), text: $variable.value)
                }
            }
            .textFieldStyle(.code)
            IconButton(symbol: revealed ? "eye.slash" : "eye", help: revealed ? localized("Ocultar") : localized("Mostrar")) {
                revealed.toggle()
            }
            .opacity(variable.isSecret ? 1 : 0)
            .disabled(!variable.isSecret)
            CopyButton(value: variable.value, secret: variable.isSecret, help: localized("Copiar o valor"))
            IconButton(
                symbol: variable.isSecret ? "lock.fill" : "lock.open",
                help: variable.isSecret ? localized("Secreta: oculta na tela") : localized("Marcar como secreta"),
                color: variable.isSecret ? Theme.accent : Theme.paper.opacity(0.7)
            ) {
                variable.isSecret.toggle()
            }
            IconButton(symbol: "trash", help: localized("Remover"), action: remove)
        }
        .padding(.vertical, 6)
    }
}
