import AppKit
import Metal
import MetalPerformanceShaders
import QuartzCore
import simd

/// Görüntüyü Metal ile çizer.
///
/// Görüntü, tek bir dokuda siyah bir kenarlığın üzerinde durur ve üstünde bir
/// Gauss piramidi bulunur. Her kare tek bir tam ekran geçişidir.
@MainActor
final class DerinlikCizici {

    /// Görüntünün çevresindeki siyah kenarlık, punto. En büyük bulanıklık
    /// yarıçapının üstünde tutulur ki bulanıklık her kenarda gerçek siyaha
    /// ulaşsın.
    nonisolated private static let dolguPunto: CGFloat = 120

    private struct Degiskenler {
        var sutun0: SIMD4<Float>
        var sutun1: SIMD4<Float>
        var sutun2: SIMD4<Float>
        var ekranVeBaslangic: SIMD4<Float>
        var dolguVeBulaniklik: SIMD4<Float>
        var bicim: SIMD4<Float>
        var isik: SIMD4<Float>
    }

    /// Ana iş parçacığı dışında hazırlanıp ana iş parçacığında devralınan
    /// dondurulmuş görüntü.
    struct HazirGoruntu {
        let doku: MTLTexture
        let renkUzayi: CGColorSpace
        let dolguBaslangici: CGPoint
        let dolguBoyutu: CGSize
        let enUstDuzey: Float
        let pikselOlcegi: CGFloat
        let ekranBoyutu: CGSize
    }

    /// Bir sonraki karenin gideceği katman.
    ///
    /// Bir katman aynı anda tek bir görünüme ait olabildiği için her örtü
    /// penceresinin kendi katmanı olmalı.
    private(set) var katman = CAMetalLayer()

    nonisolated private let aygit: MTLDevice
    nonisolated private let kuyruk: MTLCommandQueue
    private let hat: MTLRenderPipelineState
    private var doku: MTLTexture?
    private var ekranBoyutu: CGSize = .zero
    private var pikselOlcegi: CGFloat = 2
    private var dolguBaslangici: CGPoint = .zero
    private var dolguBoyutu: CGSize = .zero
    private var enUstDuzey: Float = 0

    /// Canlı akışın içine yazdığı görüntü. `goruntuHazirla` kendi dokusunu
    /// ürettiği için ikisinden yalnızca biri aynı anda kullanılır.
    private var canliDoku: MTLTexture?
    private var canliBoyut: CGSize = .zero
    private var canliOlcek: CGFloat = 0
    private var canliKaynak = false
    /// Sıradaki çizime kadar bekleyen en yeni canlı kare.
    private var bekleyenKare: YakalananKare?
    /// Aynı anı bekleyen, başlangıç için dondurulmuş kare. Önce gelen canlı
    /// kare kazanır, çünkü ikisinden yenisi odur.
    private var bekleyenTohum: (arabellek: MTLBuffer, genislik: Int, yukseklik: Int)?
    private static var piramitHatasiBildirildi = false
    /// Bir kez kurulur, her karede yeniden kodlanır.
    private lazy var canliPiramit = MPSImageGaussianPyramid(device: aygit, centerWeight: 0.375)

    var hazir: Bool { doku != nil }

    init?() {
        guard let aygit = MTLCreateSystemDefaultDevice(),
              let kuyruk = aygit.makeCommandQueue() else { return nil }
        self.aygit = aygit
        self.kuyruk = kuyruk

        do {
            let kitaplik = try aygit.makeLibrary(source: DerinlikGolgelendirici.kaynak, options: nil)
            let tanim = MTLRenderPipelineDescriptor()
            tanim.vertexFunction = kitaplik.makeFunction(name: "derinlikKose")
            tanim.fragmentFunction = kitaplik.makeFunction(name: "derinlikParca")
            tanim.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            hat = try aygit.makeRenderPipelineState(descriptor: tanim)
        } catch {
            Gunluk.gorsel.error("metal hattı kurulamadı: \(String(describing: error), privacy: .public)")
            return nil
        }

        ayarla(katman)
    }

    /// Yeni bir örtü penceresi için taze katman. Sonraki kareler buraya gider.
    func katmanUret() -> CAMetalLayer {
        let taze = CAMetalLayer()
        ayarla(taze)
        katman = taze
        return taze
    }

    private func ayarla(_ hedef: CAMetalLayer) {
        hedef.device = aygit
        hedef.pixelFormat = .bgra8Unorm_srgb
        hedef.framebufferOnly = true
        // Ekranı kaplayan mat bir katman, pencere sunucusunun arkadaki tüm
        // pencereleri gizli saymasına ve uygulamaların çizimi bırakmasına yol
        // açar. Gölgelendirici her yerde alfa 1 yazdığı için harmanlama aynı
        // görüntüyü verir.
        hedef.isOpaque = false
        // Tazelemeyi burada beklemek ana iş parçacığını kilitler. Yakalama
        // akışı bu uygulamayı kendi görüntüsünden çıkardığı için pencere
        // sunucusu ekranı iki kez çizer, çizilebilir geç döner ve bekleme bir
        // tazeleme sonrasına düşer: saniyede 60 kare 32'ye iner. Zamanlamayı
        // zaten ekran bağlantısı yapıyor.
        hedef.displaySyncEnabled = false
        hedef.needsDisplayOnBoundsChange = true
    }

    /// Görüntüyü siyah kenarlığın üzerine koyar, yükler ve piramidi kurar.
    /// Ana iş parçacığı dışında çağrılmalı.
    nonisolated func goruntuHazirla(
        resim: CGImage,
        ekranBoyutu: CGSize,
        pikselOlcegi: CGFloat
    ) -> HazirGoruntu? {
        let dolgu = Self.dolguPunto
        let dolguBoyutu = CGSize(
            width: ekranBoyutu.width + 2 * dolgu,
            height: ekranBoyutu.height + 2 * dolgu
        )
        let genislik = Int((dolguBoyutu.width * pikselOlcegi).rounded())
        let yukseklik = Int((dolguBoyutu.height * pikselOlcegi).rounded())
        guard genislik > 0, yukseklik > 0 else { return nil }
        let baytSayisi = genislik * yukseklik * 4

        guard let aktarim = aygit.makeBuffer(length: baytSayisi, options: .storageModeShared) else { return nil }

        let renkUzayi: CGColorSpace
        if let uzay = resim.colorSpace, uzay.model == .rgb {
            renkUzayi = uzay
        } else {
            renkUzayi = CGColorSpaceCreateDeviceRGB()
        }
        guard let baglam = CGContext(
            data: aktarim.contents(),
            width: genislik,
            height: yukseklik,
            bitsPerComponent: 8,
            bytesPerRow: genislik * 4,
            space: renkUzayi,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        baglam.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        baglam.fill(CGRect(x: 0, y: 0, width: genislik, height: yukseklik))
        let ickenar = dolgu * pikselOlcegi
        baglam.draw(resim, in: CGRect(
            x: ickenar,
            y: ickenar,
            width: CGFloat(genislik) - 2 * ickenar,
            height: CGFloat(yukseklik) - 2 * ickenar
        ))

        let duzeySayisi = Int(floor(log2(Double(max(genislik, yukseklik))))) + 1
        let tanim = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: genislik,
            height: yukseklik,
            mipmapped: true
        )
        tanim.usage = [.shaderRead, .shaderWrite]
        tanim.storageMode = .private
        guard var doku = aygit.makeTexture(descriptor: tanim),
              let komutlar = kuyruk.makeCommandBuffer(),
              let kopyalayici = komutlar.makeBlitCommandEncoder() else { return nil }
        kopyalayici.copy(
            from: aktarim,
            sourceOffset: 0,
            sourceBytesPerRow: genislik * 4,
            sourceBytesPerImage: baytSayisi,
            sourceSize: MTLSize(width: genislik, height: yukseklik, depth: 1),
            to: doku,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        kopyalayici.endEncoding()

        MPSImageGaussianPyramid(device: aygit, centerWeight: 0.375)
            .encode(commandBuffer: komutlar, inPlaceTexture: &doku, fallbackCopyAllocator: nil)
        komutlar.commit()
        komutlar.waitUntilCompleted()

        Gunluk.gorsel.notice("metal dokusu \(genislik)x\(yukseklik) px, \(duzeySayisi) düzey")
        return HazirGoruntu(
            doku: doku,
            renkUzayi: renkUzayi,
            dolguBaslangici: CGPoint(x: -dolgu, y: -dolgu),
            dolguBoyutu: dolguBoyutu,
            enUstDuzey: Float(duzeySayisi - 1),
            pikselOlcegi: pikselOlcegi,
            ekranBoyutu: ekranBoyutu
        )
    }

    // MARK: - Canlı kaynak

    /// Canlı akış için görüntüyü hazırlar. Kenarlık bir kez siyaha boyanır;
    /// sonraki her kare yalnızca iç bölgeyi değiştirir. İlk kare gelene kadar
    /// hiçbir şey çizilmez.
    @discardableResult
    func canliBaslat(ekranBoyutu: CGSize, pikselOlcegi: CGFloat) -> Bool {
        let dolgu = Self.dolguPunto
        let dolgulu = CGSize(
            width: ekranBoyutu.width + 2 * dolgu,
            height: ekranBoyutu.height + 2 * dolgu
        )
        let genislik = Int((dolgulu.width * pikselOlcegi).rounded())
        let yukseklik = Int((dolgulu.height * pikselOlcegi).rounded())
        guard genislik > 0, yukseklik > 0 else { return false }

        if canliDoku == nil || canliBoyut != dolgulu || canliOlcek != pikselOlcegi {
            let tanim = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb,
                width: genislik,
                height: yukseklik,
                mipmapped: true
            )
            // `renderTarget` yalnızca kenarlığı siyaha boyayan tek temizleme
            // için gerekli.
            tanim.usage = [.shaderRead, .shaderWrite, .renderTarget]
            tanim.storageMode = .private
            guard let taze = aygit.makeTexture(descriptor: tanim) else { return false }
            siyahaBoya(taze)
            canliDoku = taze
            canliBoyut = dolgulu
            canliOlcek = pikselOlcegi
        }

        doku = nil
        canliKaynak = true
        self.ekranBoyutu = ekranBoyutu
        self.pikselOlcegi = pikselOlcegi
        dolguBaslangici = CGPoint(x: -dolgu, y: -dolgu)
        dolguBoyutu = dolgulu
        enUstDuzey = Float(Int(floor(log2(Double(max(genislik, yukseklik))))))
        katman.colorspace = CGColorSpace(name: EkranAkisi.renkUzayiAdi)
        katman.drawableSize = CGSize(
            width: ekranBoyutu.width * pikselOlcegi,
            height: ekranBoyutu.height * pikselOlcegi
        )
        return true
    }

    /// Henüz gösterecek bir şeyi olmayan canlı örtüyü tek bir dondurulmuş
    /// kareyle başlatır. Akışın ilk karesi bunun üstüne yazar.
    @discardableResult
    func tohumla(resim: CGImage) -> Bool {
        guard canliKaynak, canliDoku != nil else { return false }
        let ickenar = Int((Self.dolguPunto * pikselOlcegi).rounded())
        let genislik = Int((ekranBoyutu.width * pikselOlcegi).rounded())
        let yukseklik = Int((ekranBoyutu.height * pikselOlcegi).rounded())
        guard genislik > 0, yukseklik > 0, ickenar >= 0 else { return false }
        let satirBayti = genislik * 4
        guard let aktarim = aygit.makeBuffer(length: satirBayti * yukseklik, options: .storageModeShared),
              // Akışın kendi renk uzayı, böylece devir teslimde renk kaymaz.
              let uzay = CGColorSpace(name: EkranAkisi.renkUzayiAdi),
              let baglam = CGContext(
                data: aktarim.contents(),
                width: genislik,
                height: yukseklik,
                bitsPerComponent: 8,
                bytesPerRow: satirBayti,
                space: uzay,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return false }
        baglam.draw(resim, in: CGRect(x: 0, y: 0, width: genislik, height: yukseklik))
        bekleyenTohum = (aktarim, genislik, yukseklik)
        doku = canliDoku
        return true
    }

    func kareyiAl(_ kare: YakalananKare) {
        guard canliKaynak, canliDoku != nil else { return }
        bekleyenKare = kare
        bekleyenTohum = nil
        // Sonraki geçişin okuyacağı doku nesnesi bu; içine kopyalama o geçişin
        // önünde kodlanır.
        doku = canliDoku
    }

    /// En yeni kareyi görüntüye kopyalar ve piramidi yeniden kurar.
    private func bekleyeniAl(_ komutlar: MTLCommandBuffer) {
        guard var hedef = canliDoku, bekleyenKare != nil || bekleyenTohum != nil else { return }
        let ickenar = Int((Self.dolguPunto * pikselOlcegi).rounded())
        guard let kopyalayici = komutlar.makeBlitCommandEncoder() else { return }
        if let kare = bekleyenKare {
            let genislik = min(kare.doku.width, hedef.width - 2 * ickenar)
            let yukseklik = min(kare.doku.height, hedef.height - 2 * ickenar)
            guard genislik > 0, yukseklik > 0 else { kopyalayici.endEncoding(); return }
            kopyalayici.copy(
                from: kare.doku,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: genislik, height: yukseklik, depth: 1),
                to: hedef,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: ickenar, y: ickenar, z: 0)
            )
            komutlar.addCompletedHandler { [kare] _ in
                withExtendedLifetime(kare) {}
            }
        } else if let tohum = bekleyenTohum {
            let genislik = min(tohum.genislik, hedef.width - 2 * ickenar)
            let yukseklik = min(tohum.yukseklik, hedef.height - 2 * ickenar)
            guard genislik > 0, yukseklik > 0 else { kopyalayici.endEncoding(); return }
            kopyalayici.copy(
                from: tohum.arabellek,
                sourceOffset: 0,
                sourceBytesPerRow: tohum.genislik * 4,
                sourceBytesPerImage: tohum.genislik * 4 * tohum.yukseklik,
                sourceSize: MTLSize(width: genislik, height: yukseklik, depth: 1),
                to: hedef,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: ickenar, y: ickenar, z: 0)
            )
        }
        bekleyenKare = nil
        bekleyenTohum = nil
        kopyalayici.endEncoding()
        let kuruldu = canliPiramit.encode(
            commandBuffer: komutlar,
            inPlaceTexture: &hedef,
            fallbackCopyAllocator: nil
        )
        if !kuruldu, !Self.piramitHatasiBildirildi {
            Self.piramitHatasiBildirildi = true
            Gunluk.gorsel.error("canlı piramit yerinde kodlama false döndü")
        }
        canliDoku = hedef
        doku = hedef
    }

    /// Canlı görüntüyü serbest bırakır.
    func canliBirak() {
        bekleyenKare = nil
        bekleyenTohum = nil
        if canliKaynak { doku = nil }
        canliKaynak = false
        canliDoku = nil
        canliBoyut = .zero
        canliOlcek = 0
    }

    private func siyahaBoya(_ hedef: MTLTexture) {
        let gecis = MTLRenderPassDescriptor()
        gecis.colorAttachments[0].texture = hedef
        gecis.colorAttachments[0].loadAction = .clear
        gecis.colorAttachments[0].storeAction = .store
        gecis.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let komutlar = kuyruk.makeCommandBuffer(),
              let kodlayici = komutlar.makeRenderCommandEncoder(descriptor: gecis) else { return }
        kodlayici.endEncoding()
        komutlar.commit()
        komutlar.waitUntilCompleted()
    }

    // MARK: - Dondurulmuş kaynak

    func devral(_ goruntu: HazirGoruntu) {
        canliKaynak = false
        doku = goruntu.doku
        // Etiket olmadan pencere sunucusu çizilebiliri sRGB sayar ve ekran
        // uzayına çevirir.
        katman.colorspace = goruntu.renkUzayi
        dolguBaslangici = goruntu.dolguBaslangici
        dolguBoyutu = goruntu.dolguBoyutu
        enUstDuzey = goruntu.enUstDuzey
        pikselOlcegi = goruntu.pikselOlcegi
        ekranBoyutu = goruntu.ekranBoyutu
        katman.drawableSize = CGSize(
            width: goruntu.ekranBoyutu.width * goruntu.pikselOlcegi,
            height: goruntu.ekranBoyutu.height * goruntu.pikselOlcegi
        )
    }

    func birak() {
        doku = nil
    }

    /// - Parameter koseler: görüntünün ekrana yansıtılmış köşeleri, punto
    ///   cinsinden; sırasıyla sol alt, sağ alt, sağ üst, sol üst.
    func ciz(
        koseler: [CGPoint],
        bulaniklikGucu: Double,
        karartmaGucu: Double,
        bulaniklikTabani: Double,
        karartmaTabani: Double,
        karartmaErimi: Double,
        enFazlaBulaniklik: Double,
        enFazlaKarartma: Double
    ) {
        guard let komutlar = kuyruk.makeCommandBuffer() else { return }
        bekleyeniAl(komutlar)
        guard let doku, ekranBoyutu.width > 0, ekranBoyutu.height > 0,
              let cizilebilir = katman.nextDrawable() else {
            komutlar.commit()
            return
        }

        let ileri = Homografi.matris(
            genislik: Double(ekranBoyutu.width),
            yukseklik: Double(ekranBoyutu.height),
            koseler: koseler.map { SIMD2(Double($0.x), Double($0.y)) }
        )
        let ters = ileri.inverse

        func sutun(_ indeks: Int) -> SIMD4<Float> {
            let c = ters[indeks]
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), 0)
        }
        var degiskenler = Degiskenler(
            sutun0: sutun(0),
            sutun1: sutun(1),
            sutun2: sutun(2),
            ekranVeBaslangic: SIMD4(
                Float(ekranBoyutu.width), Float(ekranBoyutu.height),
                Float(dolguBaslangici.x), Float(dolguBaslangici.y)
            ),
            dolguVeBulaniklik: SIMD4(
                Float(dolguBoyutu.width), Float(dolguBoyutu.height),
                Float(enFazlaBulaniklik * Double(pikselOlcegi)), Float(bulaniklikGucu)
            ),
            bicim: SIMD4(Float(bulaniklikTabani), Float(enFazlaKarartma), Float(pikselOlcegi), enUstDuzey),
            isik: SIMD4(Float(karartmaTabani), Float(karartmaGucu), Float(karartmaErimi), 0)
        )

        let gecis = MTLRenderPassDescriptor()
        gecis.colorAttachments[0].texture = cizilebilir.texture
        gecis.colorAttachments[0].loadAction = .clear
        gecis.colorAttachments[0].storeAction = .store
        gecis.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let kodlayici = komutlar.makeRenderCommandEncoder(descriptor: gecis) else {
            komutlar.commit()
            return
        }
        kodlayici.setRenderPipelineState(hat)
        kodlayici.setFragmentBytes(&degiskenler, length: MemoryLayout<Degiskenler>.stride, index: 0)
        kodlayici.setFragmentTexture(doku, index: 0)
        kodlayici.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        kodlayici.endEncoding()
        komutlar.present(cizilebilir)
        komutlar.commit()
    }
}
