// SPDX-License-Identifier: MIT

import SwiftUI

/// Geometry from tools/logo/default.svg, without the icon background.
nonisolated enum AlohaBrandPaths {
    static func flower(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.30925990, y: 0.56197522))
        path.addCurve(
            to: CGPoint(x: 0.19566042, y: 0.40111408),
            control1: CGPoint(x: 0.22648073, y: 0.53414507),
            control2: CGPoint(x: 0.17571102, y: 0.46251205))
        path.addCurve(
            to: CGPoint(x: 0.38211614, y: 0.33774679),
            control1: CGPoint(x: 0.21560986, y: 0.33971609),
            control2: CGPoint(x: 0.29878824, y: 0.31160546))
        path.addCurve(
            to: CGPoint(x: 0.50000000, y: 0.17999844),
            control1: CGPoint(x: 0.38300400, y: 0.25041912),
            control2: CGPoint(x: 0.43544235, y: 0.17999844))
        path.addCurve(
            to: CGPoint(x: 0.61788387, y: 0.33774679),
            control1: CGPoint(x: 0.56455765, y: 0.17999844),
            control2: CGPoint(x: 0.61699600, y: 0.25041912))
        path.addCurve(
            to: CGPoint(x: 0.80433958, y: 0.40111408),
            control1: CGPoint(x: 0.70121176, y: 0.31160546),
            control2: CGPoint(x: 0.78439014, y: 0.33971609))
        path.addCurve(
            to: CGPoint(x: 0.69074010, y: 0.56197522),
            control1: CGPoint(x: 0.82428898, y: 0.46251205),
            control2: CGPoint(x: 0.77351927, y: 0.53414507))
        path.addCurve(
            to: CGPoint(x: 0.68809220, y: 0.75888670),
            control1: CGPoint(x: 0.74135171, y: 0.63314664),
            control2: CGPoint(x: 0.74032044, y: 0.72094067))
        path.addCurve(
            to: CGPoint(x: 0.50000000, y: 0.70055601),
            control1: CGPoint(x: 0.63586396, y: 0.79683273),
            control2: CGPoint(x: 0.55204820, y: 0.77068369))
        path.addCurve(
            to: CGPoint(x: 0.31190780, y: 0.75888670),
            control1: CGPoint(x: 0.44795180, y: 0.77068369),
            control2: CGPoint(x: 0.36413604, y: 0.79683273))
        path.addCurve(
            to: CGPoint(x: 0.30925990, y: 0.56197522),
            control1: CGPoint(x: 0.25967956, y: 0.72094067),
            control2: CGPoint(x: 0.25864829, y: 0.63314664))
        path.closeSubpath()
        return path.applying(
            CGAffineTransform(
                a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
    }

    static func glyph(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.49129259, y: 0.57368457))
        path.addQuadCurve(
            to: CGPoint(x: 0.45400820, y: 0.56467821),
            control: CGPoint(x: 0.46979354, y: 0.57368457))
        path.addQuadCurve(
            to: CGPoint(x: 0.42960387, y: 0.53901493),
            control: CGPoint(x: 0.43822286, y: 0.55567185))
        path.addQuadCurve(
            to: CGPoint(x: 0.42098488, y: 0.49989053),
            control: CGPoint(x: 0.42098488, y: 0.52235800))
        path.addQuadCurve(
            to: CGPoint(x: 0.42660175, y: 0.47035354),
            control: CGPoint(x: 0.42098488, y: 0.48381466))
        path.addQuadCurve(
            to: CGPoint(x: 0.44238709, y: 0.44701448),
            control: CGPoint(x: 0.43221862, y: 0.45689242))
        path.addQuadCurve(
            to: CGPoint(x: 0.46650089, y: 0.43171335),
            control: CGPoint(x: 0.45255556, y: 0.43713654))
        path.addQuadCurve(
            to: CGPoint(x: 0.49690946, y: 0.42629017),
            control: CGPoint(x: 0.48044622, y: 0.42629017))
        path.addQuadCurve(
            to: CGPoint(x: 0.53090120, y: 0.43151967),
            control: CGPoint(x: 0.51569692, y: 0.42629017))
        path.addQuadCurve(
            to: CGPoint(x: 0.55685501, y: 0.44643342),
            control: CGPoint(x: 0.54610549, y: 0.43674916))
        path.addQuadCurve(
            to: CGPoint(x: 0.57331825, y: 0.46986933),
            control: CGPoint(x: 0.56760454, y: 0.45611768))
        path.addQuadCurve(
            to: CGPoint(x: 0.57903196, y: 0.50085895),
            control: CGPoint(x: 0.57903196, y: 0.48362097))
        path.addQuadCurve(
            to: CGPoint(x: 0.57457721, y: 0.52603802),
            control: CGPoint(x: 0.57903196, y: 0.51538534))
        path.addQuadCurve(
            to: CGPoint(x: 0.56285925, y: 0.54366337),
            control: CGPoint(x: 0.57012245, y: 0.53669071))
        path.addQuadCurve(
            to: CGPoint(x: 0.54697707, y: 0.55412237),
            control: CGPoint(x: 0.55559606, y: 0.55063604))
        path.addQuadCurve(
            to: CGPoint(x: 0.53022331, y: 0.55760870),
            control: CGPoint(x: 0.53835808, y: 0.55760870))
        path.addQuadCurve(
            to: CGPoint(x: 0.50901478, y: 0.55005498),
            control: CGPoint(x: 0.51724640, y: 0.55760870))
        path.addQuadCurve(
            to: CGPoint(x: 0.50078316, y: 0.52991173),
            control: CGPoint(x: 0.50078316, y: 0.54250126))
        path.addQuadCurve(
            to: CGPoint(x: 0.50078316, y: 0.52933067),
            control: CGPoint(x: 0.50078316, y: 0.52971804))
        path.addQuadCurve(
            to: CGPoint(x: 0.50078316, y: 0.52894330),
            control: CGPoint(x: 0.50078316, y: 0.52894330))
        path.addQuadCurve(
            to: CGPoint(x: 0.49739367, y: 0.53088015),
            control: CGPoint(x: 0.49942737, y: 0.52991173))
        path.addQuadCurve(
            to: CGPoint(x: 0.49274523, y: 0.53242963),
            control: CGPoint(x: 0.49535998, y: 0.53184858))
        path.addQuadCurve(
            to: CGPoint(x: 0.48683783, y: 0.53301069),
            control: CGPoint(x: 0.49013048, y: 0.53301069))
        path.addQuadCurve(
            to: CGPoint(x: 0.47579778, y: 0.53039594),
            control: CGPoint(x: 0.48102728, y: 0.53301069))
        path.addQuadCurve(
            to: CGPoint(x: 0.46650089, y: 0.52332643),
            control: CGPoint(x: 0.47056828, y: 0.52778119))
        path.addQuadCurve(
            to: CGPoint(x: 0.46020612, y: 0.51306112),
            control: CGPoint(x: 0.46243350, y: 0.51887167))
        path.addQuadCurve(
            to: CGPoint(x: 0.45797874, y: 0.50085895),
            control: CGPoint(x: 0.45797874, y: 0.50725056))
        path.addQuadCurve(
            to: CGPoint(x: 0.45797874, y: 0.49863157),
            control: CGPoint(x: 0.45797874, y: 0.49969684))
        path.addQuadCurve(
            to: CGPoint(x: 0.45817243, y: 0.49640419),
            control: CGPoint(x: 0.45797874, y: 0.49756630))
        path.addQuadCurve(
            to: CGPoint(x: 0.46243350, y: 0.48303992),
            control: CGPoint(x: 0.45894717, y: 0.48943153))
        path.addQuadCurve(
            to: CGPoint(x: 0.47114933, y: 0.47161249),
            control: CGPoint(x: 0.46591983, y: 0.47664831))
        path.addQuadCurve(
            to: CGPoint(x: 0.48257676, y: 0.46367140),
            control: CGPoint(x: 0.47637883, y: 0.46657668))
        path.addQuadCurve(
            to: CGPoint(x: 0.49516629, y: 0.46076612),
            control: CGPoint(x: 0.48877468, y: 0.46076612))
        path.addQuadCurve(
            to: CGPoint(x: 0.50262317, y: 0.46192824),
            control: CGPoint(x: 0.49923368, y: 0.46076612))
        path.addQuadCurve(
            to: CGPoint(x: 0.50862741, y: 0.46531773),
            control: CGPoint(x: 0.50601266, y: 0.46309035))
        path.addQuadCurve(
            to: CGPoint(x: 0.51259796, y: 0.47064407),
            control: CGPoint(x: 0.51124216, y: 0.46754510))
        path.addLine(to: CGPoint(x: 0.50814320, y: 0.47180618))
        path.addQuadCurve(
            to: CGPoint(x: 0.51182322, y: 0.46318719),
            control: CGPoint(x: 0.50853057, y: 0.46580194))
        path.addQuadCurve(
            to: CGPoint(x: 0.52228221, y: 0.46057244),
            control: CGPoint(x: 0.51511586, y: 0.46057244))
        path.addQuadCurve(
            to: CGPoint(x: 0.53177279, y: 0.46270298),
            control: CGPoint(x: 0.52848014, y: 0.46057244))
        path.addQuadCurve(
            to: CGPoint(x: 0.53448438, y: 0.46967564),
            control: CGPoint(x: 0.53506543, y: 0.46483351))
        path.addLine(to: CGPoint(x: 0.52673697, y: 0.52952435))
        path.addQuadCurve(
            to: CGPoint(x: 0.52741487, y: 0.53126752),
            control: CGPoint(x: 0.52673697, y: 0.53088015))
        path.addQuadCurve(
            to: CGPoint(x: 0.53099805, y: 0.53165489),
            control: CGPoint(x: 0.52809277, y: 0.53165489))
        path.addQuadCurve(
            to: CGPoint(x: 0.53700229, y: 0.53039594),
            control: CGPoint(x: 0.53332227, y: 0.53165489))
        path.addQuadCurve(
            to: CGPoint(x: 0.54445916, y: 0.52574749),
            control: CGPoint(x: 0.54068230, y: 0.52913698))
        path.addQuadCurve(
            to: CGPoint(x: 0.55075393, y: 0.51586955),
            control: CGPoint(x: 0.54823603, y: 0.52235800))
        path.addQuadCurve(
            to: CGPoint(x: 0.55327184, y: 0.49872841),
            control: CGPoint(x: 0.55327184, y: 0.50938110))
        path.addQuadCurve(
            to: CGPoint(x: 0.54949498, y: 0.47926306),
            control: CGPoint(x: 0.55327184, y: 0.48788205))
        path.addQuadCurve(
            to: CGPoint(x: 0.53855177, y: 0.46463983),
            control: CGPoint(x: 0.54571812, y: 0.47064407))
        path.addQuadCurve(
            to: CGPoint(x: 0.52121695, y: 0.45543978),
            control: CGPoint(x: 0.53138542, y: 0.45863559))
        path.addQuadCurve(
            to: CGPoint(x: 0.49826525, y: 0.45224398),
            control: CGPoint(x: 0.51104847, y: 0.45224398))
        path.addQuadCurve(
            to: CGPoint(x: 0.47124618, y: 0.45805453),
            control: CGPoint(x: 0.48277044, y: 0.45224398))
        path.addQuadCurve(
            to: CGPoint(x: 0.45342714, y: 0.47422724),
            control: CGPoint(x: 0.45972191, y: 0.46386509))
        path.addQuadCurve(
            to: CGPoint(x: 0.44713237, y: 0.49872841),
            control: CGPoint(x: 0.44713237, y: 0.48458940))
        path.addQuadCurve(
            to: CGPoint(x: 0.45216819, y: 0.52565065),
            control: CGPoint(x: 0.44713237, y: 0.51480428))
        path.addQuadCurve(
            to: CGPoint(x: 0.46708194, y: 0.54201705),
            control: CGPoint(x: 0.45720400, y: 0.53649702))
        path.addQuadCurve(
            to: CGPoint(x: 0.49148627, y: 0.54753707),
            control: CGPoint(x: 0.47695989, y: 0.54753707))
        path.addQuadCurve(
            to: CGPoint(x: 0.49962105, y: 0.54840866),
            control: CGPoint(x: 0.49690946, y: 0.54753707))
        path.addQuadCurve(
            to: CGPoint(x: 0.50339791, y: 0.55208868),
            control: CGPoint(x: 0.50233264, y: 0.54928024))
        path.addQuadCurve(
            to: CGPoint(x: 0.50446318, y: 0.56070766),
            control: CGPoint(x: 0.50446318, y: 0.55489711))
        path.addQuadCurve(
            to: CGPoint(x: 0.50242949, y: 0.56981087),
            control: CGPoint(x: 0.50446318, y: 0.56709928))
        path.addQuadCurve(
            to: CGPoint(x: 0.49739367, y: 0.57310351),
            control: CGPoint(x: 0.50039579, y: 0.57252246))
        path.addQuadCurve(
            to: CGPoint(x: 0.49129259, y: 0.57368457),
            control: CGPoint(x: 0.49439155, y: 0.57368457))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.49303576, y: 0.50647582))
        path.addQuadCurve(
            to: CGPoint(x: 0.49681262, y: 0.50570108),
            control: CGPoint(x: 0.49497261, y: 0.50647582))
        path.addQuadCurve(
            to: CGPoint(x: 0.50020211, y: 0.50357054),
            control: CGPoint(x: 0.49865263, y: 0.50492634))
        path.addQuadCurve(
            to: CGPoint(x: 0.50281686, y: 0.50047158),
            control: CGPoint(x: 0.50175159, y: 0.50221475))
        path.addQuadCurve(
            to: CGPoint(x: 0.50407581, y: 0.49679156),
            control: CGPoint(x: 0.50388212, y: 0.49872841))
        path.addLine(to: CGPoint(x: 0.50407581, y: 0.49582314))
        path.addQuadCurve(
            to: CGPoint(x: 0.50349475, y: 0.49233680),
            control: CGPoint(x: 0.50407581, y: 0.49388629))
        path.addQuadCurve(
            to: CGPoint(x: 0.50175159, y: 0.48962521),
            control: CGPoint(x: 0.50291370, y: 0.49078732))
        path.addQuadCurve(
            to: CGPoint(x: 0.49904000, y: 0.48788205),
            control: CGPoint(x: 0.50058948, y: 0.48846310))
        path.addQuadCurve(
            to: CGPoint(x: 0.49574735, y: 0.48730099),
            control: CGPoint(x: 0.49749051, y: 0.48730099))
        path.addQuadCurve(
            to: CGPoint(x: 0.49187364, y: 0.48807573),
            control: CGPoint(x: 0.49381050, y: 0.48730099))
        path.addQuadCurve(
            to: CGPoint(x: 0.48838731, y: 0.49020627),
            control: CGPoint(x: 0.48993679, y: 0.48885047))
        path.addQuadCurve(
            to: CGPoint(x: 0.48586940, y: 0.49330523),
            control: CGPoint(x: 0.48683783, y: 0.49156206))
        path.addQuadCurve(
            to: CGPoint(x: 0.48451361, y: 0.49717893),
            control: CGPoint(x: 0.48490098, y: 0.49504840))
        path.addLine(to: CGPoint(x: 0.48451361, y: 0.49834104))
        path.addQuadCurve(
            to: CGPoint(x: 0.48567572, y: 0.50240843),
            control: CGPoint(x: 0.48451361, y: 0.50047158))
        path.addQuadCurve(
            to: CGPoint(x: 0.48877468, y: 0.50541055),
            control: CGPoint(x: 0.48683783, y: 0.50434528))
        path.addQuadCurve(
            to: CGPoint(x: 0.49303576, y: 0.50647582),
            control: CGPoint(x: 0.49071153, y: 0.50647582))
        path.closeSubpath()
        return path.applying(
            CGAffineTransform(
                a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
    }

}
