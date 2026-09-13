import Foundation

/// Sensörün saniyede ~10 kez gelen basamaklı değerini, ekran tazeleme hızında
/// yumuşak değişen bir değere çevirir.
///
/// Yarı örtük Euler, `frekans * dt` değeri 2'nin altında kaldığı sürece
/// kararlıdır; `dt` çağıran tarafından sınırlanır.
struct SonumluYay {
    var deger: Double
    var hiz: Double = 0

    /// Saniyedeki radyan. Yükseldikçe hedefi daha hızlı yakalar, daha az yumuşatır.
    var frekans: Double = 16

    init(deger: Double = 0) {
        self.deger = deger
    }

    mutating func ilerlet(hedef: Double, dt: Double) {
        let ivme = frekans * frekans * (hedef - deger) - 2 * frekans * hiz
        hiz += ivme * dt
        deger += hiz * dt
    }

    mutating func sifirla(_ yeniDeger: Double) {
        deger = yeniDeger
        hiz = 0
    }
}
