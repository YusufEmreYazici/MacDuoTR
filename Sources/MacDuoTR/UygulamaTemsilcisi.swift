import AppKit
import CoreGraphics

@MainActor
final class UygulamaTemsilcisi: NSObject, NSApplicationDelegate {

    private var denetleyici: KapakDenetleyici?
    private var menuCubugu: MenuCubugu?
    private let kilit = KlavyeKilidi()

    func applicationDidFinishLaunching(_ bildirim: Notification) {
        Gunluk.gorsel.notice(
            "başlatıldı, ekran kaydı izni: \(CGPreflightScreenCaptureAccess()), erişilebilirlik izni: \(KlavyeKilidi.erisimIzniVar)"
        )
        let ayarlar = Ayarlar.ortak
        let denetleyici = KapakDenetleyici(ayarlar: ayarlar)
        self.denetleyici = denetleyici
        menuCubugu = MenuCubugu(denetleyici: denetleyici, ayarlar: ayarlar, kilit: kilit)
        denetleyici.baslat()

        kilitKendiTestiniYap()

        // Uyku sırasında klavyenin kilitli kalmasının bir anlamı yok ve
        // uyanışta şaşırtıcı olur.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.kilit.kilidiAc() }
        }
    }

    /// Sorun giderme yolu. Uygulama `MACDUOTR_KILIT_TESTI=<saniye>` ile
    /// başlatılırsa klavyeyi o kadar süre kilitler ve sonucu günlüğe yazar.
    /// Erişilebilirlik izni her yeniden derlemede sıfırlanabildiği için
    /// kilidin gerçekten kurulup kurulmadığını tıklamadan doğrulamaya yarar.
    /// Yalnızca uygulamayı başlatan kişi ayarlayabilir; dışarıdan tetiklenemez.
    private func kilitKendiTestiniYap() {
        guard let ham = ProcessInfo.processInfo.environment["MACDUOTR_KILIT_TESTI"],
              let sure = Double(ham), sure > 0 else { return }
        Gunluk.klavye.notice("kendi testi: \(sure, format: .fixed(precision: 0)) saniyelik kilit deneniyor")
        let sonuc = kilit.kilitle()
        switch sonuc {
        case .tamam:
            Gunluk.klavye.notice("kendi testi: kilit kuruldu")
            // Yalnızca bu test yolunda süreli açılır; normal kullanımda kilit
            // her zaman elle açılır.
            DispatchQueue.main.asyncAfter(deadline: .now() + sure) { [weak self] in
                MainActor.assumeIsolated {
                    self?.kilit.kilidiAc()
                    Gunluk.klavye.notice("kendi testi: kilit açıldı")
                }
            }
        case .izinYok: Gunluk.klavye.error("kendi testi: erişilebilirlik izni yok")
        case .basarisiz: Gunluk.klavye.error("kendi testi: yakalayıcı kurulamadı")
        }
    }

    func applicationWillTerminate(_ bildirim: Notification) {
        // Kilit her hâlükârda süreçle birlikte ölür; yine de düzgünce açılır.
        kilit.kilidiAc()
        denetleyici?.durdur()
    }
}
