import SwiftUI

/// The project's accesses in its list: logins, databases, servers and API keys, those matching
/// `query` while there's a search. Opening and deleting are the project's (see ProjectView).
struct CredentialsSection: View {
    let credentials: [Credential]
    /// The access open in the side panel, highlighted in the list.
    let selected: Credential.ID?
    let open: (Credential.ID) -> Void
    /// The projects an access here can move to.
    let destinations: () -> [CredentialDestination]
    let move: (Credential.ID, Project.ID) -> Void
    let delete: (Credential.ID) -> Void

    var body: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(credentials) { credential in
                    if credential.id != credentials.first?.id { RowDivider() }
                    CredentialRow(credential: credential, selected: credential.id == selected) { open(credential.id) }
                        .contextMenu {
                            Button(localized("Abrir")) { open(credential.id) }
                            Menu(localized("Mover para")) {
                                CredentialDestinations(destinations: destinations) { move(credential.id, $0) }
                            }
                            .disabled(credential.isEmpty)
                            Divider()
                            Button(localized("Apagar acesso…"), role: .destructive) { delete(credential.id) }
                        }
                }
            }
        }
    }
}

/// The items of a "Move to" menu: projects and subprojects by their path.
struct CredentialDestinations: View {
    let destinations: () -> [CredentialDestination]
    let move: (Project.ID) -> Void

    var body: some View {
        let available = destinations()
        if available.isEmpty {
            Text(localized("Nenhum outro projeto"))
        }
        ForEach(available) { destination in
            Button(destination.path.isEmpty ? localized("Sem nome") : destination.path) { move(destination.id) }
        }
    }
}

struct CredentialRow: View {
    let credential: Credential
    var selected = false
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CredentialIcon(symbol: credential.displaySymbol, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.displayTitle.isEmpty ? localized("Sem nome") : credential.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                Text(credential.username.isEmpty ? credential.kind.label : credential.username)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !credential.username.isEmpty {
                CopyButton(value: credential.username, symbol: "person", help: localized("Copiar o usuário"))
            }
            CopyButton(value: credential.password, secret: true, symbol: "key", help: localized("Copiar a senha"))
            if let url = URL(string: credential.url), let scheme = url.scheme, ["http", "https"].contains(scheme) {
                IconButton(symbol: "arrow.up.right", help: localized("Abrir \(url.host() ?? credential.url)")) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            Theme.paper.opacity(selected ? 0.08 : hovering ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        // Back out to the card's edge, so the highlight doesn't shift the row.
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        // A click anywhere but on the buttons opens the access: theirs come first.
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, open)
    }
}

/// An access's icon on its tinted tile.
struct CredentialIcon: View {
    let symbol: String
    var size: CGFloat = 28
    /// Follows the project the access is in (see ProjectView).
    @Environment(\.iconStyle) private var style

    var body: some View {
        Image(systemName: symbol)
            .iconStyle(style, size: size * 0.46)
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// One access in the panel floating on the project's right; the changes apply as they are typed.
/// What is done most, opening and copying, sits on top; the details to edit come below, and moving
/// and deleting wait in "More", away from a stray click.
struct CredentialEditor: View {
    @Binding var credential: Credential
    let close: () -> Void
    let destinations: () -> [CredentialDestination]
    let move: (Project.ID) -> Void
    let delete: () -> Void
    @State private var revealed = false
    @State private var generator = PasswordGenerator()
    @State private var showsGenerator = false
    @State private var choosingSymbol = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top], 18)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasSomethingToUse {
                        actions
                    }
                    section(localized("Detalhes")) {
                        VStack(spacing: 0) {
                            row(localized("Tipo")) {
                                Picker(localized("Tipo"), selection: $credential.kind) {
                                    ForEach(Credential.Kind.allCases) { kind in
                                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .buttonStyle(.plain)
                                .fixedSize()
                                Spacer(minLength: 0)
                            }
                            RowDivider()
                            row(localized("Nome")) {
                                TextField(localized("Painel da Vercel, banco de produção…"), text: $credential.title)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                            }
                            RowDivider()
                            row(localized("Endereço")) {
                                TextField("https://", text: $credential.url)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5, design: .monospaced))
                            }
                            RowDivider()
                            row(localized("Usuário")) {
                                TextField(localized("Usuário"), text: $credential.username)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5, design: .monospaced))
                            }
                            RowDivider()
                            row(localized("Senha")) {
                                Group {
                                    if revealed {
                                        TextField(localized("Senha"), text: $credential.password)
                                    } else {
                                        SecureField(localized("Senha"), text: $credential.password)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, design: .monospaced))
                                IconButton(symbol: revealed ? "eye.slash" : "eye", help: revealed ? localized("Ocultar") : localized("Mostrar")) {
                                    revealed.toggle()
                                }
                                IconButton(symbol: "wand.and.stars", help: localized("Gerar senha"), color: Theme.accent) {
                                    showsGenerator.toggle()
                                }
                                .popover(isPresented: $showsGenerator, arrowEdge: .bottom) {
                                    GeneratorPopover(generator: $generator) { password in
                                        credential.password = password
                                        revealed = true
                                        showsGenerator = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    RecoveryCodesSection(codes: $credential.recoveryCodes)
                    section(localized("Notas")) {
                        TextEditor(text: $credential.notes)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 96)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack {
                moreMenu
                Spacer()
                Button(localized("Pronto"), action: close)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
        .foregroundStyle(Theme.paper)
        .tint(Theme.accent)
        .onChange(of: credential.password) { credential.updatedAt = Date() }
        .onChange(of: credential.recoveryCodes) { credential.updatedAt = Date() }
    }

    /// The address, when it is a page the browser can open.
    private var webURL: URL? {
        guard let url = URL(string: credential.url), let scheme = url.scheme, ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    private var hasSomethingToUse: Bool {
        webURL != nil || !credential.username.isEmpty || !credential.password.isEmpty
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let url = webURL {
                ActionTile(symbol: "arrow.up.right", title: localized("Abrir"), help: localized("Abrir \(url.host() ?? credential.url)")) {
                    NSWorkspace.shared.open(url)
                }
            }
            if !credential.username.isEmpty {
                CopyTile(value: credential.username, symbol: "person", title: localized("Copiar usuário"))
            }
            if !credential.password.isEmpty {
                CopyTile(value: credential.password, secret: true, symbol: "key", title: localized("Copiar senha"))
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Menu(localized("Mover para")) {
                CredentialDestinations(destinations: destinations, move: move)
            }
            // An access with nothing in it isn't kept, so there's nothing to move.
            .disabled(credential.isEmpty)
            Divider()
            Button(localized("Apagar acesso…"), role: .destructive, action: delete)
        } label: {
            Label(localized("Mais"), systemImage: "ellipsis")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(PillButtonStyle(prominent: false))
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                choosingSymbol.toggle()
            } label: {
                CredentialIcon(symbol: credential.displaySymbol, size: 40)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 15, height: 15)
                            .background(Theme.accent, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localized("Trocar o ícone"))
            .accessibilityLabel(localized("Trocar o ícone"))
            .popover(isPresented: $choosingSymbol, arrowEdge: .bottom) {
                CredentialSymbolPicker(symbol: $credential.symbol, automatic: credential.kind.symbol)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.displayTitle.isEmpty ? localized("Novo acesso") : credential.displayTitle)
                    .font(Theme.display(19))
                    .lineLimit(1)
                Text(webURL?.host() ?? credential.kind.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            IconButton(symbol: "xmark", help: localized("Fechar"), action: close)
                .keyboardShortcut(.cancelAction)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 2)
            content()
        }
    }

    /// A line of the details: its name on the left, what to edit on the right.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .frame(width: 66, alignment: .leading)
            content()
        }
        .frame(minHeight: 36)
    }
}

/// A large button with its icon over its name, for what an access is used for most.
struct ActionTile: View {
    let symbol: String
    let title: String
    var help: String?
    var highlighted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.paper.opacity(highlighted || hovering ? 1 : 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(Theme.paper.opacity(highlighted ? 0.14 : hovering ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .help(help ?? title)
    }
}

/// An action tile that copies `value`, saying "Copied" for a moment.
struct CopyTile: View {
    let value: String
    var secret = false
    let symbol: String
    let title: String
    @State private var copied = false

    var body: some View {
        ActionTile(symbol: copied ? "checkmark" : symbol, title: copied ? localized("Copiado") : title, highlighted: copied) {
            Clipboard.copy(value, secret: secret)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        }
        .accessibilityLabel(title)
    }
}

/// The icon grid for an access. The first choice follows the access's kind.
struct CredentialSymbolPicker: View {
    @Binding var symbol: String?
    /// The kind's icon, shown while none is picked.
    let automatic: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iconStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Ícone"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button(localized("Usar o do tipo")) {
                    symbol = nil
                    dismiss()
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(symbol == nil ? Theme.muted : Theme.accent)
                    .disabled(symbol == nil)
            }
            SymbolGrid(categories: Credential.symbolCategories, selected: symbol ?? automatic, color: Theme.accent, style: style) { option in
                symbol = option == automatic ? nil : option
                dismiss()
            }
        }
        .padding(16)
        .frame(width: SymbolGrid.width + 32)
        .keysSurface()
    }
}

struct GeneratorPopover: View {
    @Binding var generator: PasswordGenerator
    let use: (String) -> Void
    @State private var preview = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(preview)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(width: 300, alignment: .leading)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 10) {
                Text(localized("\(generator.length) caracteres"))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .frame(width: 92, alignment: .leading)
                Slider(
                    value: Binding(get: { Double(generator.length) }, set: { generator.length = Int($0) }),
                    in: Double(PasswordGenerator.lengths.lowerBound)...Double(PasswordGenerator.lengths.upperBound),
                    step: 1
                )
            }
            HStack(spacing: 14) {
                Toggle("A–Z", isOn: $generator.uppercase)
                Toggle("a–z", isOn: $generator.lowercase)
                Toggle("0–9", isOn: $generator.digits)
                Toggle("!#%", isOn: $generator.symbols)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            HStack {
                Button(localized("Outra")) { preview = generator.generate() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Spacer()
                Button(localized("Usar esta senha")) { use(preview) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .keysSurface()
        .onAppear { preview = generator.generate() }
        .onChange(of: generator) { preview = generator.generate() }
    }
}

/// An access's recovery codes: masked until asked, each copied on its own and marked once used,
/// with how many are left. Added by pasting the list the service gave, numbering and all.
struct RecoveryCodesSection: View {
    @Binding var codes: [RecoveryCode]
    @State private var revealed = false
    @State private var adding = false
    @State private var draft = ""
    @State private var confirmingDelete = false

    /// The same mask for every code, so the screen doesn't tell how long they are.
    static let mask = "•••••-•••••"

    private var available: Int { codes.filter { !$0.isUsed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if adding {
                editor
            } else if codes.isEmpty {
                empty
            } else {
                list
            }
        }
        .confirmationDialog(localized("Apagar os códigos de recuperação?"), isPresented: $confirmingDelete) {
            Button(localized("Apagar códigos"), role: .destructive) { codes = [] }
        } message: {
            Text(localized("Eles saem do cofre. Guarde-os em outro lugar antes, se ainda precisar deles."))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(localized("Códigos de recuperação"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            if !codes.isEmpty {
                Text(localized("\(available) de \(codes.count) disponíveis"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(available == 0 ? Theme.color(.amber) : Theme.paper.opacity(0.45))
            }
            Spacer(minLength: 4)
            if !codes.isEmpty && !adding {
                IconButton(symbol: revealed ? "eye.slash" : "eye", help: revealed ? localized("Ocultar os códigos") : localized("Mostrar os códigos")) {
                    revealed.toggle()
                }
                Menu {
                    Button(localized("Adicionar códigos…")) { startAdding() }
                    Button(localized("Copiar os disponíveis")) {
                        Clipboard.copy(codes.filter { !$0.isUsed }.map(\.code).joined(separator: "\n"), secret: true)
                    }
                    .disabled(available == 0)
                    Divider()
                    Button(localized("Apagar todos…"), role: .destructive) { confirmingDelete = true }
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
                .help(localized("Adicionar, copiar ou apagar os códigos"))
            }
        }
        .padding(.leading, 2)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Os códigos de uso único que o serviço dá para entrar se você perder a senha ou o segundo fator."))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button(localized("Colar da área de transferência")) {
                    let pasted = RecoveryCode.parse(NSPasteboard.general.string(forType: .string) ?? "")
                    if pasted.isEmpty { startAdding() } else { add(pasted) }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                Button(localized("Digitar…"), action: startAdding)
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.paper.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var editor: some View {
        let found = RecoveryCode.parse(draft)
        return VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(6)
                .frame(height: 120)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                Text(localized("Um por linha. A numeração é ignorada."))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Button(localized("Cancelar")) { adding = false }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(found.count == 1 ? localized("Adicionar 1 código") : localized("Adicionar \(found.count) códigos")) {
                    add(found)
                }
                .buttonStyle(PillButtonStyle())
                .disabled(found.isEmpty)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(codes.enumerated()), id: \.element.id) { index, code in
                if index > 0 { RowDivider() }
                RecoveryCodeRow(
                    number: index + 1,
                    code: code,
                    revealed: revealed,
                    toggleUsed: { setUsed(code.id, !code.isUsed) }
                )
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func startAdding() {
        draft = ""
        adding = true
    }

    /// Adds the codes not already here, after the others.
    private func add(_ new: [String]) {
        let known = Set(codes.map(\.code))
        codes += new.filter { !known.contains($0) }.map { RecoveryCode(code: $0) }
        adding = false
    }

    private func setUsed(_ id: RecoveryCode.ID, _ used: Bool) {
        guard let index = codes.firstIndex(where: { $0.id == id }) else { return }
        codes[index].usedAt = used ? Date() : nil
    }
}

struct RecoveryCodeRow: View {
    let number: Int
    let code: RecoveryCode
    let revealed: Bool
    let toggleUsed: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.paper.opacity(0.3))
                .frame(width: 18, alignment: .trailing)
            Text(revealed ? code.code : RecoveryCodesSection.mask)
                .font(.system(size: 12.5, design: .monospaced))
                .strikethrough(code.isUsed)
                .foregroundStyle(Theme.paper.opacity(code.isUsed ? 0.35 : (revealed ? 0.95 : 0.5)))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !code.isUsed {
                CopyButton(value: code.code, secret: true, help: localized("Copiar o código"))
            }
            IconButton(
                symbol: code.isUsed ? "checkmark.circle.fill" : "circle",
                help: code.isUsed ? localized("Marcar como não usado") : localized("Marcar como usado"),
                color: code.isUsed ? Theme.paper.opacity(0.45) : Theme.paper.opacity(0.7),
                action: toggleUsed
            )
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(code.isUsed ? localized("Código \(number), usado") : localized("Código \(number)"))
    }
}
