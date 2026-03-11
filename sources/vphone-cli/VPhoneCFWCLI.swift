import ArgumentParser
import Foundation

struct CFWCryptexPathsCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cfw-cryptex-paths",
        abstract: "Print SystemOS and AppOS cryptex paths from a BuildManifest plist"
    )

    @Argument(help: "Path to BuildManifest.plist", transform: URL.init(fileURLWithPath:))
    var manifestURL: URL

    mutating func run() throws {
        let manifest = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: manifestURL),
            options: [],
            format: nil
        ) as? [String: Any]

        guard let identities = manifest?["BuildIdentities"] as? [[String: Any]] else {
            throw ValidationError("BuildIdentities not found in \(manifestURL.path)")
        }

        for identity in identities {
            guard let manifest = identity["Manifest"] as? [String: Any] else { continue }
            let sysos = ((manifest["Cryptex1,SystemOS"] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String
            let appos = ((manifest["Cryptex1,AppOS"] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String
            if let sysos, let appos, !sysos.isEmpty, !appos.isEmpty {
                print(sysos)
                print(appos)
                return
            }
        }

        throw ValidationError("Cryptex1,SystemOS/AppOS paths not found in any BuildIdentity")
    }
}

struct CFWPatchSeputilCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cfw-patch-seputil",
        abstract: "Patch seputil gigalocker UUID format string to AA"
    )

    @Argument(help: "Path to seputil binary", transform: URL.init(fileURLWithPath:))
    var binaryURL: URL

    mutating func run() throws {
        var data = try Data(contentsOf: binaryURL)
        let anchor = Data("/%s.gl\0".utf8)
        guard let range = data.range(of: anchor) else {
            throw ValidationError("Format string '/%s.gl' not found in seputil")
        }
        let patchOffset = range.lowerBound + 1
        data[patchOffset] = UInt8(ascii: "A")
        data[patchOffset + 1] = UInt8(ascii: "A")
        try data.write(to: binaryURL)
        print("  [+] Patched at 0x\(String(patchOffset, radix: 16).uppercased()): %s -> AA")
    }
}

struct CFWInjectDaemonsCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cfw-inject-daemons",
        abstract: "Inject daemon plist entries into launchd.plist"
    )

    @Argument(help: "Path to launchd.plist", transform: URL.init(fileURLWithPath:))
    var plistURL: URL

    @Argument(help: "Directory containing daemon plist files", transform: URL.init(fileURLWithPath:))
    var daemonDirectory: URL

    mutating func run() async throws {
        _ = try? await VPhoneHost.runCommand("/usr/bin/plutil", arguments: ["-convert", "xml1", plistURL.path])

        var target = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]

        var launchDaemons = target["LaunchDaemons"] as? [String: Any] ?? [:]
        for name in ["bash", "dropbear", "trollvnc", "vphoned", "rpcserver_ios"] {
            let sourceURL = daemonDirectory.appendingPathComponent("\(name).plist")
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                print("  [!] Missing \(sourceURL.path), skipping")
                continue
            }
            let daemon = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: sourceURL),
                options: [],
                format: nil
            )
            launchDaemons["/System/Library/LaunchDaemons/\(name).plist"] = daemon
            print("  [+] Injected \(name)")
        }

        target["LaunchDaemons"] = launchDaemons
        let output = try PropertyListSerialization.data(fromPropertyList: target, format: .xml, options: 0)
        try output.write(to: plistURL)
    }
}

struct CFWInjectDylibCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cfw-inject-dylib",
        abstract: "Inject an LC_LOAD_DYLIB into a Mach-O using insert_dylib"
    )

    @Argument(help: "Path to target Mach-O", transform: URL.init(fileURLWithPath:))
    var binaryURL: URL

    @Argument(help: "Dylib path to inject")
    var dylibPath: String

    mutating func run() async throws {
        let insertDylib = try resolveInsertDylib()
        _ = try await VPhoneHost.runCommand(
            insertDylib,
            arguments: ["--weak", "--inplace", "--all-yes", dylibPath, binaryURL.path],
            requireSuccess: true
        )
    }

    func resolveInsertDylib() throws -> String {
        if let path = which("insert_dylib") {
            return path
        }
        let candidate = VPhoneHost.currentDirectoryURL().appendingPathComponent(".tools/bin/insert_dylib").path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        throw ValidationError("insert_dylib not found. Run: make setup_tools")
    }

    func which(_ command: String) -> String? {
        ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(command).path }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
