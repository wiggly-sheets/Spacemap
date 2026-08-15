import Foundation

enum CLISymlinkInstallationResult: Equatable {
    case installed
    case targetUnavailable
    case conflictingItem
    case authorizationRequired
    case failed
}

enum CLISymlinkInstaller {
    static func install(
        symlinkPath: String,
        targetPath: String,
        targetMustBeExecutable: Bool = true,
        fileManager: FileManager = .default
    ) -> CLISymlinkInstallationResult {
        var targetIsDirectory = ObjCBool(false)
        let targetExists = fileManager.fileExists(atPath: targetPath, isDirectory: &targetIsDirectory)
        guard targetExists,
              !targetIsDirectory.boolValue,
              (!targetMustBeExecutable || fileManager.isExecutableFile(atPath: targetPath)) else {
            return .targetUnavailable
        }

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath) {
            return destination == targetPath ? .installed : .conflictingItem
        }

        // `fileExists` catches non-symlink items after the link check above.
        if fileManager.fileExists(atPath: symlinkPath) {
            return .conflictingItem
        }

        let directoryURL = URL(fileURLWithPath: symlinkPath).deletingLastPathComponent()
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return .conflictingItem }
            guard fileManager.isWritableFile(atPath: directoryURL.path) else {
                return .authorizationRequired
            }
        } else {
            let existingParent = nearestExistingParent(of: directoryURL, fileManager: fileManager)
            guard fileManager.isWritableFile(atPath: existingParent.path) else {
                return .authorizationRequired
            }

            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                return .failed
            }
        }

        do {
            try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
            return .installed
        } catch {
            return .failed
        }
    }

    private static func nearestExistingParent(of url: URL, fileManager: FileManager) -> URL {
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
