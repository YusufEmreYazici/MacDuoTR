import Foundation
import os

/// Uygulama günlükleri. Terminalden şöyle okunur:
///
///     log show --last 5m --predicate 'subsystem == "com.emre.MacDuoTR"'
///
/// `info` yerine `notice` kullanılır: `info` yalnızca bellekte durur,
/// `log show` ise diskteki kaydı okur.
enum Gunluk {
    static let gorsel = Logger(subsystem: "com.emre.MacDuoTR", category: "gorsel")
    static let kapak = Logger(subsystem: "com.emre.MacDuoTR", category: "kapak")
    static let klavye = Logger(subsystem: "com.emre.MacDuoTR", category: "klavye")
}
