import SwiftUI

/// The ledger's paper visual system: warm paper, ink text, blue annotations,
/// vermilion corrections. Each ink has one job: blue = information and links
/// (project labels, tabs), vermilion = destructive/alert, ochre = favorites.
enum Paper {
    static let bg        = Color(red: 0.968, green: 0.952, blue: 0.913)  // paper #F7F3E9
    static let bgDeep    = Color(red: 0.936, green: 0.920, blue: 0.872)  // one shade deeper: hover, footer, group band
    static let ink       = Color(red: 0.122, green: 0.118, blue: 0.102)  // ink #1F1E1A
    static let inkSoft   = Color(red: 0.435, green: 0.416, blue: 0.365)  // faded ink
    static let blue      = Color(red: 0.176, green: 0.294, blue: 0.435)  // blue ink #2D4B6F
    static let vermilion = Color(red: 0.639, green: 0.196, blue: 0.110)  // vermilion #A3321C
    static let ochre     = Color(red: 0.588, green: 0.416, blue: 0.114)  // ochre #966A1D
    static let hairline  = ink.opacity(0.14)

    /// Titles use the system serif (New York) so the ledger look carries no
    /// font-name dependency and stays Latin-native.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Hairline divider: the ledger's ruled line.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(height: 1)
    }
}

/// Small seal-style tag ("new", "taken"). A boxed word, like a margin note.
/// Sizes to its label so single characters and words both sit tight.
struct SealMark: View {
    let character: String
    let color: Color

    var body: some View {
        Text(character)
            .font(Paper.body(9, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(color.opacity(0.75), lineWidth: 1)
            )
            .fixedSize()
    }
}

/// Hand-drawn switch: the system SwitchToggleStyle ignores a custom tint on
/// recent macOS, so the blue-ink track from the design has to be drawn here.
/// On = blue track with white knob, off = faded track.
struct PaperToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Paper.blue : Paper.inkSoft.opacity(0.28))
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: Paper.ink.opacity(0.15), radius: 1, x: 0, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
