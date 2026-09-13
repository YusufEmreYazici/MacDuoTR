import Foundation

/// Görüntünün belirli bir yükseklikte ne kadar odak dışı kaldığını ve ne kadar
/// ışık yitirdiğini anlatır. Yükseklik menteşe kenarında 0, karşı kenarda 1'dir.
struct BulaniklikEgrisi {

    /// Kapanma yolunun üssü. 1'in üstündeki değerler yavaş başlatır.
    var bulaniklikUssu: Double = 1.6

    /// Karartma için kapanma yolunun üssü.
    var karartmaUssu: Double = 0.7

    /// Menteşe kenarındaki karartmanın, karşı kenardaki karartmaya oranı.
    var karartmaTabani: Double = 0.2

    func bulaniklikGucu(ilerleme: Double) -> Double {
        pow(min(max(ilerleme, 0), 1), bulaniklikUssu)
    }

    func karartmaGucu(ilerleme: Double) -> Double {
        pow(min(max(ilerleme, 0), 1), karartmaUssu)
    }
}
