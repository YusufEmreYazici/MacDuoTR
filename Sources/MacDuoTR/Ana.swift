import AppKit

@main
@MainActor
enum Ana {
    /// `NSApplication.delegate` zayıf tutulur; temsilcinin başlatma kapsamından
    /// daha uzun yaşayan bir sahibi olmalı.
    private static var temsilci: UygulamaTemsilcisi?

    static func main() {
        let uygulama = NSApplication.shared
        let temsilci = UygulamaTemsilcisi()
        Self.temsilci = temsilci
        uygulama.delegate = temsilci
        uygulama.setActivationPolicy(.accessory)
        uygulama.run()
    }
}
