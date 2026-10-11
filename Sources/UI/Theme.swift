import SwiftUI

/// 端口簿的纸面视觉体系：米白纸、墨字、蓝墨标注、朱砂批注。
/// 三种墨色各司其职：蓝墨 = 信息与链接（项目标注、页签），朱砂 = 破坏性/告警，赭金 = 收藏。
enum Paper {
    static let bg        = Color(red: 0.968, green: 0.952, blue: 0.913)  // 纸面 #F7F3E9
    static let bgDeep    = Color(red: 0.936, green: 0.920, blue: 0.872)  // 深一度：悬停、页脚、分组带
    static let ink       = Color(red: 0.122, green: 0.118, blue: 0.102)  // 墨 #1F1E1A
    static let inkSoft   = Color(red: 0.435, green: 0.416, blue: 0.365)  // 淡墨
    static let blue      = Color(red: 0.176, green: 0.294, blue: 0.435)  // 蓝墨 #2D4B6F
    static let vermilion = Color(red: 0.639, green: 0.196, blue: 0.110)  // 朱砂 #A3321C
    static let ochre     = Color(red: 0.588, green: 0.416, blue: 0.114)  // 赭金 #96 6A 1D
    static let hairline  = ink.opacity(0.14)

    static func songti(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Songti SC", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// 细分隔线，账簿的横格。
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(height: 1)
    }
}

/// 印章式小标注：「新」「占」。方框单字，像账簿上的批注。
struct SealMark: View {
    let character: String
    let color: Color

    var body: some View {
        Text(character)
            .font(Paper.body(9, .bold))
            .foregroundStyle(color)
            .frame(width: 15, height: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color.opacity(0.75), lineWidth: 1)
            )
    }
}
