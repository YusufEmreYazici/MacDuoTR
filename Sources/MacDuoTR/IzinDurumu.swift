import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// İzinlerin o anki hâli.
///
/// Ayarlar paneli bunları `@State` içinde tutamaz: balon kapanıp yeniden
/// açıldığında barındıran denetleyici aynı kaldığı için `onAppear` tekrar
/// tetiklenmez ve kullanıcı izni verdikten sonra bile eski değer ekranda
/// kalır. Bu nesne balon her gösterildiğinde tazelenir.
@MainActor
final class IzinDurumu: ObservableObject {
    @Published private(set) var ekranKaydi: Bool
    @Published private(set) var erisilebilirlik: Bool

    /// Ekran kaydı izni süreç başladıktan sonra verildiyse doğru. macOS bir
    /// süreci ekran kaydı için bir kez reddettiyse o süreç ömrü boyunca
    /// reddedilmiş kalır; kullanıcıya yeniden başlatması söylenmeli.
    @Published private(set) var yenidenBaslatmakGerekiyor = false

    /// Sürecin açılışta gördüğü ekran kaydı izni.
    private let acilistakiEkranKaydi: Bool

    init() {
        let ekran = CGPreflightScreenCaptureAccess()
        ekranKaydi = ekran
        acilistakiEkranKaydi = ekran
        erisilebilirlik = AXIsProcessTrusted()
    }

    func tazele() {
        let ekran = CGPreflightScreenCaptureAccess()
        if ekranKaydi != ekran { ekranKaydi = ekran }
        let erisim = AXIsProcessTrusted()
        if erisilebilirlik != erisim { erisilebilirlik = erisim }
        let gerekli = ekran && !acilistakiEkranKaydi
        if yenidenBaslatmakGerekiyor != gerekli { yenidenBaslatmakGerekiyor = gerekli }
    }

    /// Uygulamayı kapatıp yeniden açar.
    func yenidenBaslat() {
        guard let paketYolu = Bundle.main.bundleURL as URL? else { return }
        let yapilandirma = NSWorkspace.OpenConfiguration()
        yapilandirma.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: paketYolu, configuration: yapilandirma) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
