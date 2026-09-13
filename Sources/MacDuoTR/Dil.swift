import Foundation

/// Arayüz dili. Efekt ayarlarından bağımsızdır ve "Sıfırla" ile silinmez.
enum Dil: String, CaseIterable {
    case turkce = "tr"
    case ingilizce = "en"

    /// Sistemin dil sıralamasına göre seçilen dil.
    static var tercihEdilen: Self {
        Bundle.preferredLocalizations(from: ["tr", "en"]).first == "en" ? .ingilizce : .turkce
    }

    var gorunenAd: String {
        switch self {
        case .turkce: return "Türkçe"
        case .ingilizce: return "English"
        }
    }

    // Paketlenmiş uygulamalar kaynakları Contents/Resources altında tutar;
    // SwiftPM'in ürettiği erişimci yalnızca uygulama kökünü ve özgün derleme
    // dizinini arar.
    private static var kaynaklar: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("MacDuoTR_MacDuoTR.bundle"),
           let paket = Bundle(url: url) { return paket }
        return Bundle.module
    }

    private var paket: Bundle {
        guard let yol = Self.kaynaklar.path(forResource: rawValue, ofType: "lproj"),
              let paket = Bundle(path: yol) else { return Self.kaynaklar }
        return paket
    }

    /// Anahtarın bu dildeki karşılığı. Karşılığı yoksa anahtarın kendisi döner.
    func yazi(_ anahtar: String) -> String {
        paket.localizedString(forKey: anahtar, value: anahtar, table: nil)
    }
}
