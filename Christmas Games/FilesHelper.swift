import Foundation
import UIKit

enum FilesHelper {

    static func openAppFolder() {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        UIApplication.shared.open(url)
    }

    static func ensureGamesFolderExists() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let folder = docs.appendingPathComponent("Christmas Games", isDirectory: true)

        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}
