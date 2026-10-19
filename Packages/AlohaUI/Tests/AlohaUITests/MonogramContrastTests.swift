// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaUI

@Suite("Monogram contrast")
struct MonogramContrastTests {
    @Test("White initials keep 4.5:1 on every hue, at both ends of the gradient")
    func everyHueIsLegible() {
        for degrees in 0..<360 {
            let hue = Double(degrees) / 360
            for lightness in [0.52, 0.38] {
                let brightness = Monogram.legibleBrightness(hue: hue, from: lightness + 0.28)
                #expect(
                    Monogram.contrastWithWhite(hue: hue, brightness: brightness)
                        >= Monogram.minimumContrast,
                    "hue \(degrees)° at lightness \(lightness)")
            }
        }
    }

    @Test("Yellow reads lighter than blue, as WCAG weights them")
    func luminance() {
        let yellow = Monogram.relativeLuminance(hue: 60.0 / 360, brightness: 0.8)
        let blue = Monogram.relativeLuminance(hue: 240.0 / 360, brightness: 0.8)
        #expect(yellow > blue)
    }
}
