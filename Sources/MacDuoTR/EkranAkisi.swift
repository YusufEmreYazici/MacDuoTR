import AppKit
import CoreVideo
import Metal
import ScreenCaptureKit

/// Kareler `IOSurface` tabanlı olduğu için dokuya sarmak hiçbir kopyalama
/// yapmaz. `startCapture` yeterince uzun sürdüğünden akış, eşik açısında değil,
/// kapak hâlâ kapanırken başlatılmalı.
@MainActor
final class EkranAkisi {

    /// Display P3, sRGB ile aynı aktarım eğrisini taşır; gölgelendiricinin
    /// sRGB piksel biçimi onu doğru çözer.
    static let renkUzayiAdi = CGColorSpace.displayP3

    /// Kareler akışın kendi kuyruğunda gelir. En yenisi bir kilit altında
    /// tutulur ve ana iş parçacığında alınır; doku önbelleğine yalnızca akış
    /// kuyruğundan dokunulur.
    private final class Alici: NSObject, SCStreamOutput {
        private let onbellek: CVMetalTextureCache
        private let kilit = NSLock()
        private var enYeni: YakalananKare?
        private var enYeniKimlik: UInt64 = 0

        init?(aygit: MTLDevice) {
            var uretilen: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, aygit, nil, &uretilen) == kCVReturnSuccess,
                  let uretilen else { return nil }
            onbellek = uretilen
            super.init()
        }

        /// En yeni kare ve numarası; ilk kareden önce `nil`.
        func sonuncu() -> (kare: YakalananKare, kimlik: UInt64)? {
            kilit.lock()
            defer { kilit.unlock() }
            guard let enYeni else { return nil }
            return (enYeni, enYeniKimlik)
        }

        func stream(
            _ akis: SCStream,
            didOutputSampleBuffer ornek: CMSampleBuffer,
            of tur: SCStreamOutputType
        ) {
            guard tur == .screen,
                  CMSampleBufferIsValid(ornek),
                  let pikseller = CMSampleBufferGetImageBuffer(ornek) else { return }

            // Kimsenin tutmadığı yüzeyleri bırakır, böylece havuz dönmeyi sürdürür.
            CVMetalTextureCacheFlush(onbellek, 0)

            var sarilmis: CVMetalTexture?
            let sonuc = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                onbellek,
                pikseller,
                nil,
                .bgra8Unorm_srgb,
                CVPixelBufferGetWidth(pikseller),
                CVPixelBufferGetHeight(pikseller),
                0,
                &sarilmis
            )
            guard sonuc == kCVReturnSuccess, let sarilmis,
                  let kare = YakalananKare(sarilmis) else { return }

            kilit.lock()
            enYeni = kare
            enYeniKimlik &+= 1
            kilit.unlock()
        }
    }

    private let aygit: MTLDevice?
    private var akis: SCStream?
    private var alici: Alici?
    private var baslatmaGorevi: Task<Void, Never>?
    /// Ekrandaki her pencereyi saymak yaklaşık 70 ms sürdüğü için süzgeç
    /// çalışmalar arasında saklanır ve yalnızca ekran değişince yenilenir.
    private var suzgec: SCContentFilter?
    private var suzgecEkranKimligi: CGDirectDisplayID?
    private var tuketilenKimlik: UInt64 = 0
    private var sonDevir: CFTimeInterval = 0

    /// Kareler bundan daha sık devredilmez. Yeni başlayan bir akış, istenen
    /// hızın epey üstünde bir patlama gönderir.
    private static let enKisaDevirAraligi: TimeInterval = 1.0 / 32

    private(set) var basladi = false
    private(set) var ekran: NSScreen?

    init(aygit: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.aygit = aygit
    }

    /// Yakalamayı başlatır; zaten çalışıyorsa hiçbir şey yapmaz.
    func baslat() {
        guard !basladi, baslatmaGorevi == nil, aygit != nil else { return }
        guard let hedef = NSScreen.dahili, let ekranKimligi = hedef.ekranKimligi else { return }
        ekran = hedef
        basladi = true
        baslatmaGorevi = Task { [weak self] in
            await self?.basla(ekranKimligi: ekranKimligi, hedef: hedef)
            guard !Task.isCancelled else { return }
            self?.baslatmaGorevi = nil
        }
    }

    func durdur() {
        guard basladi || akis != nil else { return }
        basladi = false
        baslatmaGorevi?.cancel()
        baslatmaGorevi = nil
        let kapanan = akis
        akis = nil
        alici = nil
        tuketilenKimlik = 0
        sonDevir = 0
        Gunluk.gorsel.notice("akış durduruldu")
        guard let kapanan else { return }
        Task { try? await kapanan.stopCapture() }
    }

    /// Hiçbir şey başlatmadan yakalama süzgecini kurar.
    func suzgeciIsit() async {
        guard let ekranKimligi = NSScreen.dahili?.ekranKimligi else { return }
        guard suzgec == nil || suzgecEkranKimligi != ekranKimligi else { return }
        await suzgeciYenidenKur(ekranKimligi: ekranKimligi)
    }

    /// Saklanan süzgeci atar; bir sonraki başlangıç pencereleri yeniden sayar.
    func suzgeciGecersizKil() {
        suzgec = nil
        suzgecEkranKimligi = nil
    }

    /// En yeni kare, ama yalnızca bir kez. Son çağrıdan beri yeni bir şey
    /// gelmediyse `nil`.
    func yeniKare() -> YakalananKare? {
        let simdi = CACurrentMediaTime()
        guard simdi - sonDevir >= Self.enKisaDevirAraligi else { return nil }
        guard let sonuncu = alici?.sonuncu(), sonuncu.kimlik != tuketilenKimlik else { return nil }
        tuketilenKimlik = sonuncu.kimlik
        sonDevir = simdi
        return sonuncu.kare
    }

    private func basla(ekranKimligi: CGDirectDisplayID, hedef: NSScreen) async {
        guard !Task.isCancelled else { return }
        guard let aygit, let alici = Alici(aygit: aygit) else {
            basladi = false
            return
        }
        do {
            if suzgec == nil || suzgecEkranKimligi != ekranKimligi {
                await suzgeciYenidenKur(ekranKimligi: ekranKimligi)
            }
            guard !Task.isCancelled, basladi, let etkinSuzgec = suzgec else { return }

            let yapilandirma = SCStreamConfiguration()
            yapilandirma.width = Int(etkinSuzgec.contentRect.width * CGFloat(etkinSuzgec.pointPixelScale))
            yapilandirma.height = Int(etkinSuzgec.contentRect.height * CGFloat(etkinSuzgec.pointPixelScale))
            yapilandirma.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            yapilandirma.pixelFormat = kCVPixelFormatType_32BGRA
            yapilandirma.colorSpaceName = Self.renkUzayiAdi
            yapilandirma.showsCursor = false
            yapilandirma.queueDepth = 5
            yapilandirma.scalesToFit = false

            let taze = SCStream(filter: etkinSuzgec, configuration: yapilandirma, delegate: nil)
            try taze.addStreamOutput(
                alici,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "MacDuoTR.kareler", qos: .userInteractive)
            )
            try await taze.startCapture()
            guard !Task.isCancelled, basladi else {
                try? await taze.stopCapture()
                return
            }
            self.alici = alici
            self.akis = taze
            self.ekran = hedef
            Gunluk.gorsel.notice("akış başladı \(yapilandirma.width)x\(yapilandirma.height) px")
        } catch {
            guard !Task.isCancelled else { return }
            Gunluk.gorsel.error("akış başlatılamadı: \(String(describing: error), privacy: .public)")
            suzgeciGecersizKil()
            basladi = false
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
                suzgeciGecersizKil()
                return
            }
            // Kendimizi dışarıda bırakırız, yoksa örtü kendi görüntüsüne
            // geri beslenir.
            let paketKimligi = Bundle.main.bundleIdentifier
            let kendiUygulamalarimiz = icerik.applications.filter { $0.bundleIdentifier == paketKimligi }
            if kendiUygulamalarimiz.isEmpty {
                Gunluk.gorsel.error("akış bu uygulamayı dışarıda bırakamıyor: henüz penceresi yok")
            }
            suzgec = SCContentFilter(
                display: ekran,
                excludingApplications: kendiUygulamalarimiz,
                exceptingWindows: []
            )
            suzgecEkranKimligi = ekranKimligi
        } catch {
            guard !Task.isCancelled else { return }
            Gunluk.gorsel.error("akış süzgeci kurulamadı: \(String(describing: error), privacy: .public)")
            suzgeciGecersizKil()
        }
    }
}
