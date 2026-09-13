import Foundation

/// Efektin tamamı tek bir parça (fragment) gölgelendiricisinde.
///
/// Her ekran pikseli, ters perspektif dönüşümüyle görüntünün içine geri
/// eşlenir ve orada istenen bulanıklığa göre seçilen bir Gauss piramidi
/// düzeyinden tek örnek alınır. Doku görüntüyü siyah bir kenarlık üzerinde
/// tuttuğu için ikisi birlikte bulanıklaşır ve kenarlar ayrıca ele alınmaz.
enum DerinlikGolgelendirici {
    static let kaynak = """
    #include <metal_stdlib>
    using namespace metal;

    // Hepsi float4: Swift tarafındaki yerleşimden sapma olmasın.
    struct Degiskenler {
        float4 sutun0;          // ekran -> görüntü matrisi, 0. sütun xyz'de
        float4 sutun1;
        float4 sutun2;
        float4 ekranVeBaslangic; // ekran boyutu, dolgulu başlangıç (punto)
        float4 dolguVeBulaniklik; // dolgulu boyut, en büyük yarıçap (piksel), bulanıklık gücü
        float4 bicim;            // bulanıklık tabanı, en fazla karartma, piksel ölçeği, en üst düzey
        float4 isik;             // karartma tabanı, karartma gücü, karartma erimi, boş
    };

    vertex float4 derinlikKose(uint kimlik [[vertex_id]]) {
        const float2 koseler[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(koseler[kimlik], 0.0, 1.0);
    }

    fragment float4 derinlikParca(float4 konum [[position]],
                                  constant Degiskenler &d [[buffer(0)]],
                                  texture2d<float> goruntu [[texture(0)]]) {
        constexpr sampler dogrusal(filter::linear, mip_filter::linear, address::clamp_to_edge);

        float2 ekranBoyutu = d.ekranVeBaslangic.xy;
        float2 dolguBaslangici = d.ekranVeBaslangic.zw;
        float2 dolguBoyutu = d.dolguVeBulaniklik.xy;
        float enFazlaYaricap = d.dolguVeBulaniklik.z;
        float guc = d.dolguVeBulaniklik.w;
        float bulaniklikTabani = d.bicim.x;
        float enFazlaKarartma = d.bicim.y;
        float pikselOlcegi = d.bicim.z;
        float enUstDuzey = d.bicim.w;
        float karartmaTabani = d.isik.x;
        float karartmaGucu = d.isik.y;
        float karartmaErimi = d.isik.z;

        // Parça koordinatları piksel ve y aşağı; geometri punto ve y yukarı.
        float2 ekranNoktasi = float2(konum.x / pikselOlcegi,
                                     ekranBoyutu.y - konum.y / pikselOlcegi);

        float3x3 ekrandanGoruntuye = float3x3(d.sutun0.xyz, d.sutun1.xyz, d.sutun2.xyz);
        float3 eslenen = ekrandanGoruntuye * float3(ekranNoktasi, 1.0);
        if (abs(eslenen.z) < 1e-6) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 goruntuNoktasi = eslenen.xy / eslenen.z;

        float2 birim = (goruntuNoktasi - dolguBaslangici) / dolguBoyutu;
        if (birim.x < 0.0 || birim.x > 1.0 || birim.y < 0.0 || birim.y > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
        float2 dokuKoordinati = float2(birim.x, 1.0 - birim.y);

        float yukseklik = clamp(goruntuNoktasi.y / ekranBoyutu.y, 0.0, 1.0);
        float bulaniklik = guc * (bulaniklikTabani + (1.0 - bulaniklikTabani) * yukseklik);
        // Metal'in level() seçicisini gölgelememek için "duzey" adı kullanılıyor.
        float duzey = clamp(log2(max(bulaniklik * enFazlaYaricap, 1.0)), 0.0, enUstDuzey);

        float4 renk = goruntu.sample(dogrusal, dokuKoordinati, level(duzey));
        // Sınırlanmış bir oran yerine smoothstep: karartmanın tam güce ulaştığı
        // yükseklikte görünür bir kenar bırakmaz.
        float yayilim = smoothstep(0.0, max(karartmaErimi, 0.02), yukseklik);
        float sonme = karartmaGucu * (karartmaTabani + (1.0 - karartmaTabani) * yayilim);
        // Örnek doğrusal ışıkta. Çarpanı 2.2 kuvvetine yükseltmek, karartma
        // ayarının kodlanmış parlaklığın oranı olarak kalmasını sağlar.
        renk.rgb *= pow(1.0 - enFazlaKarartma * sonme, 2.2);
        return float4(renk.rgb, 1.0);
    }
    """
}
