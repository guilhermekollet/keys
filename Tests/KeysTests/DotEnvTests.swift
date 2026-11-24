import Testing
@testable import Keys

@Suite("Dotenv")
struct DotEnvTests {
    private func pairs(_ text: String) -> [String] {
        DotEnv.parse(text).map { "\($0.key)=\($0.value)" }
    }

    @Test func readsPlainLinesAndSkipsTheRest() {
        let text = """
        # Database
        DATABASE_URL=postgres://localhost:5432/app

        export PORT=3000
        not a variable
        1BAD=x
        EMPTY=
        """
        #expect(pairs(text) == ["DATABASE_URL=postgres://localhost:5432/app", "PORT=3000", "EMPTY="])
    }

    @Test func dropsCommentsAfterUnquotedValues() {
        #expect(pairs("MODE=fast # or slow\nCOLOR=#fff") == ["MODE=fast", "COLOR=#fff"])
    }

    @Test func trimsSpacesAroundTheEqualsSign() {
        #expect(pairs("  NAME =  Keys  ") == ["NAME=Keys"])
    }

    @Test func understandsQuotes() {
        let text = #"""
        SINGLE='a $literal # kept'
        DOUBLE="line one\nline two \"quoted\""
        BACKTICK=`it's fine`
        TRAILING="value" # comment
        """#
        let entries = DotEnv.parse(text)
        #expect(entries.map(\.key) == ["SINGLE", "DOUBLE", "BACKTICK", "TRAILING"])
        #expect(entries[0].value == "a $literal # kept")
        #expect(entries[1].value == "line one\nline two \"quoted\"")
        #expect(entries[2].value == "it's fine")
        #expect(entries[3].value == "value")
    }

    @Test func quotedValuesMaySpanLines() {
        let text = "KEY=\"-----BEGIN KEY-----\nabc\n-----END KEY-----\"\nNEXT=1"
        #expect(pairs(text) == ["KEY=-----BEGIN KEY-----\nabc\n-----END KEY-----", "NEXT=1"])
    }

    @Test func anUnclosedQuoteIsPartOfThePlainValue() {
        #expect(pairs("A=\"oops\nB=2") == ["A=\"oops", "B=2"])
    }

    @Test func windowsLineEndings() {
        #expect(pairs("A=1\r\nB=2\r\n") == ["A=1", "B=2"])
    }

    @Test func formatsWhatParseReadsBack() {
        let entries = [
            DotEnv.Entry(key: "PLAIN", value: "postgres://user@host:5432/db"),
            DotEnv.Entry(key: "SPACES", value: "two words"),
            DotEnv.Entry(key: "DOLLAR", value: "pa$$word"),
            DotEnv.Entry(key: "QUOTE", value: "it's \"both\""),
            DotEnv.Entry(key: "MULTILINE", value: "one\ntwo"),
            DotEnv.Entry(key: "BACKSLASH", value: #"C:\path\n"#),
            DotEnv.Entry(key: "HASH", value: "#hashtag"),
            DotEnv.Entry(key: "EMPTY", value: ""),
        ]
        #expect(DotEnv.parse(DotEnv.format(entries)) == entries)
    }

    @Test func quotesOnlyWhenNeeded() {
        #expect(DotEnv.quoted("abc-123") == "abc-123")
        #expect(DotEnv.quoted("a b") == "'a b'")
        #expect(DotEnv.quoted("it's") == #""it's""#)
    }

    @Test func mergingUpdatesAndAdds() {
        let result = merge("API_TOKEN=new\nPORT=3000\nPORT=4000\nHOST=localhost", into: [("PORT", "80"), ("HOST", "localhost")])
        #expect(result.added == 1)
        #expect(result.updated == 2)
        #expect(result.lines == ["PORT=4000", "HOST=localhost", "API_TOKEN=new (secret)"])
    }

    @Test(arguments: ["STRIPE_SECRET_KEY", "GITHUB_TOKEN", "DB_PASSWORD", "DATABASE_URL", "jwt_private"])
    func secretLookingNames(_ key: String) {
        #expect(Variable.looksSecret(key))
    }

    @Test(arguments: ["PORT", "NODE_ENV", "NEXT_PUBLIC_SITE_NAME", "LOG_LEVEL"])
    func plainNames(_ key: String) {
        #expect(!Variable.looksSecret(key))
    }

    @Test func anExportIsPrivateFromTheStart() {
        let new = exportedDotEnv("API_KEY=secret\n", overExisting: false)
        #expect(new.permissions == "600")
        #expect(new.contents == "API_KEY=secret\n")
        // Over a file anyone could read: it becomes private, and nothing of the old one is left.
        let replaced = exportedDotEnv("API_KEY=secret\n", overExisting: true)
        #expect(replaced.permissions == "600")
        #expect(replaced.contents == "API_KEY=secret\n")
    }

    @Test func anExportDoesNotFollowASymbolicLink() {
        let result = exportRefusesSymlink()
        #expect(result.refused)
        #expect(result.targetUntouched)
    }

    // MARK: Shown as a file

    @Test func showsEachVariableAsTheFileWritesIt() {
        let lines = DotEnv.displayLines([
            Variable(key: "PORT", value: "3000"),
            Variable(key: "GREETING", value: "hello world"),
        ], revealing: false)
        #expect(lines == [
            DotEnv.DisplayLine(key: "PORT", value: "3000", masked: false),
            DotEnv.DisplayLine(key: "GREETING", value: "'hello world'", masked: false),
        ])
    }

    @Test func masksSecretsWithTheSameMaskWhateverTheirLength() {
        let lines = DotEnv.displayLines([
            Variable(key: "A_TOKEN", value: "x", isSecret: true),
            Variable(key: "B_TOKEN", value: String(repeating: "y", count: 64), isSecret: true),
        ], revealing: false)
        let mask = DotEnv.DisplayLine(key: "", value: DotEnv.mask, masked: true)
        #expect(lines == [
            DotEnv.DisplayLine(key: "A_TOKEN", value: mask.value, masked: true),
            DotEnv.DisplayLine(key: "B_TOKEN", value: mask.value, masked: true),
        ])
    }

    @Test func revealingShowsSecretsAsTheFileWritesThem() {
        let lines = DotEnv.displayLines([Variable(key: "API_KEY", value: "a b", isSecret: true)], revealing: true)
        #expect(lines == [DotEnv.DisplayLine(key: "API_KEY", value: "'a b'", masked: false)])
    }

    @Test func leavesOutUnnamedVariablesAndDoesNotMaskEmptySecrets() {
        let lines = DotEnv.displayLines([
            Variable(key: "", value: "orphan"),
            Variable(key: "EMPTY_SECRET", value: "", isSecret: true),
        ], revealing: false)
        #expect(lines == [DotEnv.DisplayLine(key: "EMPTY_SECRET", value: "", masked: false)])
    }

    // MARK: Edited as a file

    @Test func findsLinesThatAreNotVariables() {
        let text = """
        # Database
        DATABASE_URL=postgres://localhost/app

        MY KEY=1
        just words
        1BAD=x
        export PORT=3000
        """
        #expect(DotEnv.invalidLines(text) == [4, 5, 6])
    }

    @Test func linesInsideAQuotedValueAreNotMistakes() {
        let text = """
        PRIVATE_KEY="-----BEGIN KEY-----
        abc def
        -----END KEY-----"
        NAME='a "quoted" word'
        ESCAPED="say \\"hi\\" there"
        after the quote
        """
        #expect(DotEnv.invalidLines(text) == [6])
    }

    @Test func editingKeepsEachVariableAndWhetherItIsSecret() {
        var environment = EnvironmentSet(name: "production")
        environment.variables = [
            Variable(key: "PORT", value: "3000"),
            Variable(key: "API_KEY", value: "old", isSecret: true),
            Variable(key: "GONE", value: "x"),
        ]
        let before = environment.variables
        let result = environment.replaceVariables(with: DotEnv.parse("API_KEY=new\nPORT=3000\nSESSION_SECRET=s\n"))
        #expect(result.added == 1 && result.updated == 1 && result.removed == 1)
        #expect(environment.variables.map(\.key) == ["API_KEY", "PORT", "SESSION_SECRET"])
        #expect(environment.variables[0].id == before[1].id)
        #expect(environment.variables[0].isSecret)
        #expect(environment.variables[0].value == "new")
        #expect(environment.variables[1].id == before[0].id)
        #expect(environment.variables[2].isSecret)
    }

    @Test func editingKeepsTheLastOfARepeatedKeyAndUnnamedRows() {
        var environment = EnvironmentSet(name: "development")
        environment.variables = [Variable(key: "", value: "draft"), Variable(key: "MODE", value: "a")]
        environment.replaceVariables(with: DotEnv.parse("MODE=b\nMODE=c\n"))
        #expect(environment.variables.map(\.key) == ["MODE", ""])
        #expect(environment.variables.map(\.value) == ["c", "draft"])
    }

    @Test func anEditedFileReadsBackTheSame() {
        var environment = EnvironmentSet(name: "development")
        environment.variables = [Variable(key: "A", value: "it's \"x\""), Variable(key: "B", value: "line\nbreak")]
        let text = environment.dotEnv
        #expect(DotEnv.invalidLines(text).isEmpty)
        let result = environment.replaceVariables(with: DotEnv.parse(text))
        #expect(result.added == 0 && result.updated == 0 && result.removed == 0)
    }
}
