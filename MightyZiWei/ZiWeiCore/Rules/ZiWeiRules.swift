import Foundation

public enum ZiWeiRules {
    public static func lifeBranch(chartMonth: Int, hourBranch: EarthlyBranch) -> EarthlyBranch {
        branch(2 + chartMonth - 1 - hourBranch.rawValue)
    }

    public static func bodyBranch(chartMonth: Int, hourBranch: EarthlyBranch) -> EarthlyBranch {
        branch(2 + chartMonth - 1 + hourBranch.rawValue)
    }

    public static func palaces(
        chartMonth: Int,
        hourBranch: EarthlyBranch,
        yearStem: HeavenlyStem
    ) -> [ChartPalace] {
        let life = lifeBranch(chartMonth: chartMonth, hourBranch: hourBranch)
        let body = bodyBranch(chartMonth: chartMonth, hourBranch: hourBranch)
        return PalaceKind.allCases.enumerated().map { offset, kind in
            let palaceBranch = branch(life.rawValue - offset)
            return ChartPalace(
                kind: kind,
                stemBranch: StemBranch(
                    stem: palaceStem(for: palaceBranch, yearStem: yearStem),
                    branch: palaceBranch
                ),
                isBodyPalace: palaceBranch == body
            )
        }
    }

    public static func palaceStem(for branch: EarthlyBranch, yearStem: HeavenlyStem) -> HeavenlyStem {
        let yinStem: Int
        switch yearStem {
        case .jia, .ji: yinStem = HeavenlyStem.bing.rawValue
        case .yi, .geng: yinStem = HeavenlyStem.wu.rawValue
        case .bing, .xin: yinStem = HeavenlyStem.geng.rawValue
        case .ding, .ren: yinStem = HeavenlyStem.ren.rawValue
        case .wu, .gui: yinStem = HeavenlyStem.jia.rawValue
        }
        return HeavenlyStem(rawValue: modulo(yinStem + branch.rawValue - EarthlyBranch.yin.rawValue, 10))!
    }

    public static func fiveElementBureau(lifeStemBranch: StemBranch) -> FiveElementBureau {
        let stemNumber = lifeStemBranch.stem.rawValue / 2 + 1
        let branchNumber: Int
        switch lifeStemBranch.branch {
        case .zi, .chou, .wu, .wei: branchNumber = 1
        case .yin, .mao, .shen, .you: branchNumber = 2
        case .chen, .si, .xu, .hai: branchNumber = 3
        }
        let result = (stemNumber + branchNumber - 1) % 5 + 1
        switch result {
        case 1: return .woodThree
        case 2: return .metalFour
        case 3: return .waterTwo
        case 4: return .fireSix
        default: return .earthFive
        }
    }

    public static func mainStars(lunarDay: Int, bureau: FiveElementBureau) -> [Star: EarthlyBranch] {
        let bureauNumber = bureau.number
        let multiplier = (lunarDay + bureauNumber - 1) / bureauNumber
        let deficit = multiplier * bureauNumber - lunarDay
        let base = EarthlyBranch.yin.rawValue + multiplier - 1
        let ziWei = branch(base + (deficit.isMultiple(of: 2) ? deficit : -deficit))
        let tianFu = branch(4 - ziWei.rawValue)

        return [
            .ziWei: ziWei,
            .tianJi: branch(ziWei.rawValue - 1),
            .taiYang: branch(ziWei.rawValue - 3),
            .wuQu: branch(ziWei.rawValue - 4),
            .tianTong: branch(ziWei.rawValue - 5),
            .lianZhen: branch(ziWei.rawValue - 8),
            .tianFu: tianFu,
            .taiYin: branch(tianFu.rawValue + 1),
            .tanLang: branch(tianFu.rawValue + 2),
            .juMen: branch(tianFu.rawValue + 3),
            .tianXiang: branch(tianFu.rawValue + 4),
            .tianLiang: branch(tianFu.rawValue + 5),
            .qiSha: branch(tianFu.rawValue + 6),
            .poJun: branch(tianFu.rawValue + 10)
        ]
    }

    public static func auxiliaryStars(
        chartMonth: Int,
        hourBranch: EarthlyBranch,
        yearStem: HeavenlyStem,
        yearBranch: EarthlyBranch
    ) -> [Star: EarthlyBranch] {
        let monthOffset = chartMonth - 1
        let hour = hourBranch.rawValue
        let luCun = luCunBranch(yearStem: yearStem)
        let (kui, yue) = kuiYueBranches(yearStem: yearStem)
        let (fireStart, bellStart) = fireBellStarts(yearBranch: yearBranch)

        return [
            .zuoFu: branch(EarthlyBranch.chen.rawValue + monthOffset),
            .youBi: branch(EarthlyBranch.xu.rawValue - monthOffset),
            .wenQu: branch(EarthlyBranch.chen.rawValue + hour),
            .wenChang: branch(EarthlyBranch.xu.rawValue - hour),
            .tianKui: kui,
            .tianYue: yue,
            .diJie: branch(EarthlyBranch.hai.rawValue + hour),
            .diKong: branch(EarthlyBranch.hai.rawValue - hour),
            .luCun: luCun,
            .qingYang: branch(luCun.rawValue + 1),
            .tuoLuo: branch(luCun.rawValue - 1),
            .tianMa: tianMaBranch(yearBranch: yearBranch),
            .huoXing: branch(fireStart.rawValue + hour),
            .lingXing: branch(bellStart.rawValue + hour)
        ]
    }

    public static func transformationStars(yearStem: HeavenlyStem) -> [TransformationKind: Star] {
        let stars: [Star]
        switch yearStem {
        case .jia: stars = [.lianZhen, .poJun, .wuQu, .taiYang]
        case .yi: stars = [.tianJi, .tianLiang, .ziWei, .taiYin]
        case .bing: stars = [.tianTong, .tianJi, .wenChang, .lianZhen]
        case .ding: stars = [.taiYin, .tianTong, .tianJi, .juMen]
        case .wu: stars = [.tanLang, .taiYin, .youBi, .tianJi]
        case .ji: stars = [.wuQu, .tanLang, .tianLiang, .wenQu]
        case .geng: stars = [.taiYang, .wuQu, .taiYin, .tianTong]
        case .xin: stars = [.juMen, .taiYang, .wenQu, .wenChang]
        case .ren: stars = [.tianLiang, .ziWei, .zuoFu, .wuQu]
        case .gui: stars = [.poJun, .juMen, .taiYin, .tanLang]
        }
        return Dictionary(uniqueKeysWithValues: zip(TransformationKind.allCases, stars))
    }

    public static func relations(palaces: [ChartPalace]) -> [PalaceRelation] {
        let palaceByBranch = Dictionary(uniqueKeysWithValues: palaces.map { ($0.stemBranch.branch, $0.kind) })
        return palaces.map { palace in
            let index = palace.stemBranch.branch.rawValue
            return PalaceRelation(
                palace: palace.kind,
                trines: [palaceByBranch[branch(index + 4)]!, palaceByBranch[branch(index + 8)]!],
                opposite: palaceByBranch[branch(index + 6)]!
            )
        }
    }

    public static func luCunBranch(yearStem: HeavenlyStem) -> EarthlyBranch {
        switch yearStem {
        case .jia: .yin
        case .yi: .mao
        case .bing, .wu: .si
        case .ding, .ji: .wu
        case .geng: .shen
        case .xin: .you
        case .ren: .hai
        case .gui: .zi
        }
    }

    public static func tianMaBranch(yearBranch: EarthlyBranch) -> EarthlyBranch {
        switch yearBranch {
        case .yin, .wu, .xu: .shen
        case .shen, .zi, .chen: .yin
        case .si, .you, .chou: .hai
        case .hai, .mao, .wei: .si
        }
    }

    private static func kuiYueBranches(yearStem: HeavenlyStem) -> (EarthlyBranch, EarthlyBranch) {
        switch yearStem {
        case .jia, .wu, .geng: (.chou, .wei)
        case .yi, .ji: (.zi, .shen)
        case .bing, .ding: (.hai, .you)
        case .xin: (.wu, .yin)
        case .ren, .gui: (.mao, .si)
        }
    }

    private static func fireBellStarts(yearBranch: EarthlyBranch) -> (EarthlyBranch, EarthlyBranch) {
        switch yearBranch {
        case .shen, .zi, .chen: (.yin, .xu)
        case .yin, .wu, .xu: (.chou, .mao)
        case .si, .you, .chou: (.mao, .xu)
        case .hai, .mao, .wei: (.you, .xu)
        }
    }

    private static func branch(_ rawValue: Int) -> EarthlyBranch {
        EarthlyBranch(rawValue: modulo(rawValue, 12))!
    }

    private static func modulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
