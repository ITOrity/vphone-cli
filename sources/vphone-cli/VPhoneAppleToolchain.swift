import ArgumentParser
import Foundation

enum VPhoneAppleToolchain {
    static func defaultDeveloperDirectory() throws -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["DEVELOPER_DIR"],
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer",
        ].compactMap { $0 }.map { URL(fileURLWithPath: $0, isDirectory: true) }

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }

        throw ValidationError("Unable to locate an Xcode Developer directory. Set DEVELOPER_DIR or install Xcode in /Applications.")
    }

    static func clangURL() throws -> URL {
        let clangURL = try defaultDeveloperDirectory()
            .appendingPathComponent("Toolchains/XcodeDefault.xctoolchain/usr/bin/clang")
        guard FileManager.default.isExecutableFile(atPath: clangURL.path) else {
            throw ValidationError("Unable to locate clang in Xcode toolchain: \(clangURL.path)")
        }
        return clangURL
    }

    static func sdkURL(platformName: String) throws -> URL {
        let sdkDirectory = try defaultDeveloperDirectory()
            .appendingPathComponent("Platforms/\(platformName).platform/Developer/SDKs", isDirectory: true)
        let candidates = try FileManager.default.contentsOfDirectory(
            at: sdkDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasPrefix(platformName) && $0.pathExtension == "sdk"
        }.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedDescending
        }

        guard let sdkURL = candidates.first else {
            throw ValidationError("Unable to locate \(platformName) SDK in \(sdkDirectory.path)")
        }
        return sdkURL
    }
}
