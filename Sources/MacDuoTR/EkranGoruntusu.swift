import AppKit
import CoreGraphics
import ScreenCaptureKit

extension NSScreen {
    var ekranKimligi: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Dahili ekran; yalnızca harici ekranlar bağlıysa `nil`.
    static var dahili: NSScreen? {
        screens.first { ekran in
            guard let kimlik = ekran.ekranKimligi else { return false }
            return CGDisplayIsBuiltin(kimlik) != 0
        }
    }
}

/// Dahili ekranın güncel bir görüntüsünü hazır tutar.
///
/// `SCContentFilter` kurmak ekrandaki bütün pencereleri taradığı için süzgeç
/// saklanır ve yalnızca ekran değiştiğinde yeniden kurulur.
@MainActor
final class EkranGoruntusu {

    private(set) var sonResim: CGImage?
    private(set) var sonEkran: NSScreen?

    private var suzgec: SCContentFilter?
    private var suzgecEkranKimligi: CGDirectDisplayID?
    private var sayac: Timer?
    private var yoldaki: Task<Void, Never>?

    var onIsitiyor: Bool { sayac != nil }

    var izinVar: Bool { CGPreflightScreenCaptureAccess() }

    func onIsitmayiBaslat(aralik: TimeInterval = 0.2) {
        guard sayac == nil else { return }
        yakala()
        let sayac = Timer(timeInterval: aralik, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.yakala() }
        }
        RunLoop.main.add(sayac, forMode: .common)
        self.sayac = sayac
    }

    func onIsitmayiBitir() {
        sayac?.invalidate()
        sayac = nil
    }

    func durdur() {
        onIsitmayiBitir()
        yoldaki?.cancel()
        yoldaki = nil
        birak()
    }

    /// Elde tutulan görüntüyü atar.
    func birak() {
        sonResim = nil
        sonEkran = nil
    }

    /// Bir ekran görüntüsü bekler. Süren bir ön ısıtma yakalaması bu bekleme
    /// yerine geçer.
    func birKezYakala() async {
        await yakalamayiBaslat().value
    }

    /// Ekran görüntüsü almadan yalnızca süzgeci kurar.
    func suzgeciIsit() async {
        guard let ekran = NSScreen.dahili, let ekranKimligi = ekran.ekranKimligi else { return }
        if suzgec == nil || suzgecEkranKimligi != ekranKimligi {
            await suzgeciYenidenKur(ekranKimligi: ekranKimligi)
        }
    }

    private func yakala() {
        yakalamayiBaslat()
    }

    @discardableResult
    private func yakalamayiBaslat() -> Task<Void, Never> {
        if let yoldaki { return yoldaki }
        let gorev = Task { [weak self] in
            await self?.yakalamayiYurut()
            guard !Task.isCancelled else { return }
            self?.yoldaki = nil
        }
        yoldaki = gorev
        return gorev
    }

    private func yakalamayiYurut() async {
        guard !Task.isCancelled else { return }
        guard let ekran = NSScreen.dahili, let ekranKimligi = ekran.ekranKimligi else { return }
        if suzgec == nil || suzgecEkranKimligi != ekranKimligi {
            await suzgeciYenidenKur(ekranKimligi: ekranKimligi)
        }
        guard !Task.isCancelled, let etkinSuzgec = suzgec else { return }

        let yapilandirma = SCStreamConfiguration()
        yapilandirma.width = Int(etkinSuzgec.contentRect.width * CGFloat(etkinSuzgec.pointPixelScale))
        yapilandirma.height = Int(etkinSuzgec.contentRect.height * CGFloat(etkinSuzgec.pointPixelScale))
        yapilandirma.showsCursor = false
        yapilandirma.captureResolution = .best
        yapilandirma.scalesToFit = false

        do {
            let resim = try await SCScreenshotManager.captureImage(
                contentFilter: etkinSuzgec,
                configuration: yapilandirma
            )
            guard !Task.isCancelled else { return }
            sonResim = resim
            sonEkran = ekran
        } catch {
            guard !Task.isCancelled else { return }
            Gunluk.gorsel.error("ekran görüntüsü alınamadı: \(String(describing: error), privacy: .public)")
            suzgec = nil
            suzgecEkranKimligi = nil
        }
    }

    private func suzgeciYenidenKur(ekranKimligi: CGDirectDisplayID) async {
        do {
            let icerik = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard !Task.isCancelled else { return }
            guard let ekran = icerik.displays.first(where: { $0.displayID == ekranKimligi }) else {
                suzgec = nil
                return
            }
            // Kendimizi dışarıda bırakırız, yoksa kalan bir örtü sonraki
            // görüntüye karışır.
            let paketKimligi = Bundle.main.bundleIdentifier
            let kendiUygulamalarimiz = icerik.applications.filter { $0.bundleIdentifier == paketKimligi }
            suzgec = SCContentFilter(
                display: ekran,
                excludingApplications: kendiUygulamalarimiz,
                exceptingWindows: []
            )
            suzgecEkranKimligi = ekranKimligi
        } catch {
            guard !Task.isCancelled else { return }
            suzgec = nil
            suzgecEkranKimligi = nil
        }
    }
}
