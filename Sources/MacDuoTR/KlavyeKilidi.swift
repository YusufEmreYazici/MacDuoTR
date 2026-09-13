import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Klavyeyi devre dışı bırakır — temizlik modu. Yalnızca elle açılır.
///
/// Yöntem bir `CGEventTap`: klavye olayları pencere sunucusuna ulaşmadan önce
/// yakalanır ve geri çağırma `nil` döndürerek onları düşürür. Trackpad, fare ve
/// dokunma olaylarına hiç dokunulmaz, bu yüzden kilidi her zaman fareyle
/// açabilirsiniz.
///
/// Yakalayıcı **kendi iş parçacığında** çalışır. `.defaultTap` her tuş
/// vuruşunu bu uygulamadan geçirdiği için bu zorunlu: yakalayıcı ana iş
/// parçacığında dururken arayüz işi araya girerse macOS geri çağırmayı yavaş
/// sayıp yakalayıcıyı kapatır, tuşlar sızar ve kilit güvenilmez olur.
///
/// Kapsam dışı kalanlar: Caps Lock ve güç düğmesi sürücü seviyesinde işlenir;
/// parola alanları açıkken macOS "güvenli giriş" moduna geçer ve tuş vuruşlarını
/// hiçbir uygulamaya, bu yakalayıcıya da, göstermez.
///
/// Güvenlik ağı: kilit yalnızca fareyle açılır — ekrandaki panelin düğmesinden
/// ya da menü çubuğundan. Ayrıca uykuya geçişte ve uygulamadan çıkışta açılır,
/// süreç ölürse de macOS klavyeyi kendiliğinden geri verir.
@MainActor
final class KlavyeKilidi: ObservableObject {

    enum Sonuc {
        case tamam
        /// Erişilebilirlik izni verilmemiş.
        case izinYok
        /// İzin var ama yakalayıcı kurulamadı.
        case basarisiz
    }

    /// Klavye şu anda kilitli mi.
    @Published private(set) var kilitli = false

    /// Ses, parlaklık ve oynatma tuşları da engellensin mi. Kilit kurulurken
    /// okunur; çalışan bir kilidi etkilemez.
    var medyaTuslariniDaEngelle = false

    /// macOS'un medya/parlaklık tuşları için kullandığı olay türü (NX_SYSDEFINED).
    /// `CGEventType` içinde adlandırılmış bir karşılığı yok.
    private static let sistemOlayTuru: UInt32 = 14

    private var motor: YakalayiciMotoru?
    /// App Nap bu uygulamayı yavaşlatmasın: kilitliyken panelin düğmesi ilk
    /// tıklamada yanıt vermeli.
    private var etkinlikJetonu: NSObjectProtocol?

    // MARK: - İzin

    /// Erişilebilirlik izni verilmiş mi. Sormadan yalnızca bakar.
    static var erisimIzniVar: Bool { AXIsProcessTrusted() }

    /// macOS'un izin penceresini açar. İzin verildikten sonra uygulamanın
    /// yeniden başlatılması gerekir.
    static func erisimIzniIste() {
        let secenekler = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(secenekler as CFDictionary)
    }

    /// Sistem Ayarları'ndaki Erişilebilirlik bölümünü açar.
    static func erisimAyarlariniAc() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Kilit

    /// Klavyeyi kilitler. Kilit yalnızca `kilidiAc()` ile açılır.
    @discardableResult
    func kilitle() -> Sonuc {
        guard !kilitli else { return .tamam }
        guard Self.erisimIzniVar else {
            Gunluk.klavye.notice("kilit reddedildi: erişilebilirlik izni yok")
            return .izinYok
        }

        var maske: CGEventMask =
            (1 as CGEventMask) << CGEventType.keyDown.rawValue
            | (1 as CGEventMask) << CGEventType.keyUp.rawValue
            | (1 as CGEventMask) << CGEventType.flagsChanged.rawValue
        if medyaTuslariniDaEngelle {
            maske |= (1 as CGEventMask) << Self.sistemOlayTuru
        }

        guard let motor = YakalayiciMotoru(maske: maske) else {
            Gunluk.klavye.error("yakalayıcı kurulamadı")
            return .basarisiz
        }
        motor.baslat()

        self.motor = motor
        etkinlikJetonu = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Klavye kilidi etkin"
        )
        kilitli = true
        Gunluk.klavye.notice("klavye kilitlendi, medya tuşları \(self.medyaTuslariniDaEngelle)")
        return .tamam
    }

    /// Kilidi açar. Zaten açıksa hiçbir şey yapmaz.
    func kilidiAc() {
        guard kilitli else { return }
        kilitli = false
        motor?.durdur()
        motor = nil
        if let etkinlikJetonu {
            ProcessInfo.processInfo.endActivity(etkinlikJetonu)
            self.etkinlikJetonu = nil
        }
        Gunluk.klavye.notice("klavye kilidi açıldı")
    }

    /// Kilitliyse açar, değilse kilitler.
    @discardableResult
    func degistir() -> Sonuc {
        if kilitli {
            kilidiAc()
            return .tamam
        }
        return kilitle()
    }
}

// MARK: - Yakalayıcı

/// Yakalayıcının iş parçacıklar arası durumu.
///
/// Olay geri çağırması yakalayıcı iş parçacığında, kapatma ana iş parçacığında
/// çalışır; ikisi de kanala buradan, kilit altında erişir.
private final class YakalayiciKutusu: @unchecked Sendable {
    private let kilit = NSLock()
    private var kanal: CFMachPort?
    private var dongu: CFRunLoop?

    /// Kanal `tapCreate` döndükten sonra bağlanır: geri çağırmaya bağlam
    /// olarak geçilecek işaretçi, yakalayıcı kurulmadan önce gerekli.
    func kanaliBagla(_ yeniKanal: CFMachPort) {
        kilit.lock()
        defer { kilit.unlock() }
        kanal = yeniKanal
    }

    var gecerliKanal: CFMachPort? {
        kilit.lock()
        defer { kilit.unlock() }
        return kanal
    }

    func donguyuBagla(_ yeniDongu: CFRunLoop) {
        kilit.lock()
        defer { kilit.unlock() }
        dongu = yeniDongu
    }

    /// macOS yakalayıcıyı kapattığında geri açar. Yakalayıcı iş parçacığından
    /// çağrılır, bu yüzden anında etki eder.
    func yenidenAc() {
        kilit.lock()
        defer { kilit.unlock() }
        guard let kanal else { return }
        CGEvent.tapEnable(tap: kanal, enable: true)
    }

    /// Yakalayıcıyı kapatır ve çalışma döngüsünü durdurur. Kanal döngü
    /// durmadan önce geçersiz kılınır, böylece bu çağrı döndüğünde tuşlar
    /// artık düşürülmez.
    func kapat() {
        kilit.lock()
        let kapanan = kanal
        let duracak = dongu
        kanal = nil
        dongu = nil
        kilit.unlock()

        if let kapanan {
            CGEvent.tapEnable(tap: kapanan, enable: false)
            CFMachPortInvalidate(kapanan)
        }
        if let duracak {
            CFRunLoopStop(duracak)
        }
    }
}

/// Olay yakalayıcısını kendi iş parçacığındaki çalışma döngüsünde yürütür.
private final class YakalayiciMotoru: @unchecked Sendable {

    private let kutu: YakalayiciKutusu

    init?(maske: CGEventMask) {
        // Kutu yakalayıcıdan önce kurulur: bağlam işaretçisi `tapCreate`
        // çağrısında gerekiyor, kanal ise ancak çağrı dönünce elde ediliyor.
        let kutu = YakalayiciKutusu()
        guard let kanal = CGEvent.tapCreate(
            // Pencere sunucusundan önce, HID akışının başında.
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            // Olayları düşürebilmek için dinleyici değil, tam yakalayıcı.
            options: .defaultTap,
            eventsOfInterest: maske,
            callback: { _, tur, olay, baglam in
                // macOS, geri çağırma yavaş kalırsa ya da kullanıcı girişi
                // nedeniyle yakalayıcıyı kapatabilir. Kendi iş parçacığımızda
                // çalıştığımız için bu neredeyse hiç olmamalı; yine de anında
                // geri açıyoruz, yoksa tuşlar sızar.
                if tur == .tapDisabledByTimeout || tur == .tapDisabledByUserInput {
                    if let baglam {
                        Gunluk.klavye.error("yakalayıcı macOS tarafından kapatıldı, geri açılıyor")
                        Unmanaged<YakalayiciKutusu>.fromOpaque(baglam)
                            .takeUnretainedValue()
                            .yenidenAc()
                    }
                    return Unmanaged.passUnretained(olay)
                }
                // Klavye olayını düşür: hiçbir uygulamaya ulaşmaz.
                return nil
            },
            // Kutuyu motor tutar ve yakalayıcı geçersiz kılındıktan sonra bırakır.
            userInfo: Unmanaged.passUnretained(kutu).toOpaque()
        ) else { return nil }

        kutu.kanaliBagla(kanal)
        self.kutu = kutu
    }

    /// Yakalayıcı iş parçacığını başlatır ve yakalayıcı gerçekten etkin olana
    /// kadar bekler; böylece çağıran, kilidin kurulduğundan emin döner.
    func baslat() {
        let kutu = self.kutu
        let hazir = DispatchSemaphore(value: 0)
        let isParcacigi = Thread {
            guard let dongu = CFRunLoopGetCurrent() else {
                hazir.signal()
                return
            }
            kutu.donguyuBagla(dongu)
            guard let kanal = kutu.gecerliKanal,
                  let kaynak = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, kanal, 0) else {
                hazir.signal()
                return
            }
            CFRunLoopAddSource(dongu, kaynak, .commonModes)
            CGEvent.tapEnable(tap: kanal, enable: true)
            hazir.signal()
            // `kapat()` kanalı geçersiz kılıp döngüyü durdurana kadar döner.
            CFRunLoopRun()
            CFRunLoopRemoveSource(dongu, kaynak, .commonModes)
        }
        isParcacigi.name = "MacDuoTR.klavyeKilidi"
        // Tuş vuruşları bu iş parçacığından geçiyor; geride kalmamalı.
        isParcacigi.qualityOfService = QualityOfService.userInteractive
        isParcacigi.start()
        hazir.wait()
    }

    /// Yakalayıcıyı kapatır ve iş parçacığını sonlandırır.
    func durdur() {
        kutu.kapat()
    }
}
