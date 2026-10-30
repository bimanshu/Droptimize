import Foundation

/// Names for new files (CORE.md §6.6). The original is never touched (Rule 2).
enum OutputNaming {
    /// `photo.png` → `photo.webp` (no suffix) or `photo-min.png` (suffix `-min`), in the same
    /// folder unless `directory` is given. On a clash: `photo-min-2.png`, `photo-min-3.png`…
    static func url(for input: URL, fileExtension: String, suffix: String?, in directory: URL? = nil,
                    exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let folder = directory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent + (suffix ?? "")
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension(fileExtension)
        var number = 2
        while exists(candidate) || candidate.standardizedFileURL == input.standardizedFileURL {
            candidate = folder.appendingPathComponent("\(stem)-\(number)").appendingPathExtension(fileExtension)
            number += 1
        }
        return candidate
    }
}

/// Rule 3: never hand back a bigger file.
enum SizeGuard {
    /// An output must be at least this much smaller, or the original is kept.     (tune)
    static let minimumSaving = 0.01

    static func accepts(inputBytes: Int, outputBytes: Int) -> Bool {
        inputBytes > 0 && Double(outputBytes) <= Double(inputBytes) * (1 - minimumSaving)
    }
}

/// Saves results as new files: next to the original, or in Downloads when that folder can't
/// be written to (a read-only volume or disk image, say).
enum OutputWriter {
    static func write(_ data: Data, for input: URL, fileExtension: String, suffix: String?,
                      fallbackDirectory: URL? = defaultFallback) throws -> URL {
        do {
            return try write(data, for: input, fileExtension: fileExtension, suffix: suffix, in: nil)
        } catch let error as CocoaError where error.isPermissionProblem {
            guard let fallbackDirectory else { throw JobError.cantSave }
            return try write(data, for: input, fileExtension: fileExtension, suffix: suffix, in: fallbackDirectory)
        }
    }

    static var defaultFallback: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private static func write(_ data: Data, for input: URL, fileExtension: String, suffix: String?,
                              in directory: URL?) throws -> URL {
        // Writing without overwriting is the real guarantee; the name check just avoids most clashes.
        for _ in 0..<100 {
            let url = OutputNaming.url(for: input, fileExtension: fileExtension, suffix: suffix, in: directory)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw JobError.cantSave
    }
}

extension OutputWriter {
    /// Moves a finished file (a video written to a temporary folder) next to `input` under a fresh
    /// name; never overwrites. Falls back to Downloads like `write`.
    static func move(_ file: URL, for input: URL, fileExtension: String, suffix: String?,
                     fallbackDirectory: URL? = defaultFallback) throws -> URL {
        do {
            return try move(file, for: input, fileExtension: fileExtension, suffix: suffix, in: nil)
        } catch let error as CocoaError where error.isPermissionProblem {
            guard let fallbackDirectory else { throw JobError.cantSave }
            return try move(file, for: input, fileExtension: fileExtension, suffix: suffix, in: fallbackDirectory)
        }
    }

    private static func move(_ file: URL, for input: URL, fileExtension: String, suffix: String?,
                             in directory: URL?) throws -> URL {
        for _ in 0..<100 {
            let url = OutputNaming.url(for: input, fileExtension: fileExtension, suffix: suffix, in: directory)
            do {
                try FileManager.default.moveItem(at: file, to: url)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw JobError.cantSave
    }
}

private extension CocoaError {
    var isPermissionProblem: Bool {
        [.fileWriteNoPermission, .fileWriteVolumeReadOnly].contains(code)
    }
}
