import SwiftUI

/// A scalable, original mark for the iPhone dashboard. The open arc echoes the score rings while
/// staying legible at small sizes; no image asset or raster scaling is needed.
public struct PremiumNoopMark: View {
    public var size: CGFloat

    public init(size: CGFloat = NoopMetrics.premiumBrandSize) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(NoopVisualStyle.borderHighlight.opacity(0.65), lineWidth: max(0.5, size * 0.012))
            Circle()
                .trim(from: 0.07, to: 0.82)
                .stroke(LinearGradient(colors: [NoopVisualStyle.brandBlue, NoopVisualStyle.brandMint],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size * 0.20)
            Circle().fill(NoopVisualStyle.primaryText).frame(width: size * 0.095, height: size * 0.095)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("NOOP"))
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - BrandMark — the NOOP logo mark (Titanium & Gold)
//
// The app's identity glyph, rendered natively for use as a hero on onboarding,
// "about", and empty states. Per the design handoff ("Engraved" app-icon
// direction + the brand glyph spec):
//
//   • a circular DEEP-NAVY tile (Circle filled with the navy ramp, a faint top
//     sheen, and a 1px hairline rim), over which sits
//   • an OPEN GOLD recovery ring — an ~80% arc starting at 12 o'clock (-90°) and
//     sweeping clockwise, stroked with the gold ramp and round-capped (a THICK
//     stroke to match the app icon), and
//   • a solid GOLD CORE DOT centred ("on-device core").
//
// Gold-on-navy, matching the app icon (the maintainer's brand direction, 2026-06-15).
//
// It reads as the "O" in NOOP and as a small echo of the hero recovery ring.
// CLEAN and flat by design: no bloom, no shadow, no glow — the titanium does the
// depth via its gradient + sheen, the gold ring does the accent. Everything is
// driven off a single `size`, so the mark stays crisp from a 28pt list avatar up
// to a 120pt onboarding hero.

public struct BrandMark: View {

    /// Edge length of the square mark; everything scales from this.
    public var size: CGFloat

    public init(size: CGFloat = 120) {
        self.size = size
    }

    // The open ring sweeps ~80% of a full turn (≈291° of 364, per the logo spec),
    // starting at 12 o'clock and going clockwise — the same orientation as the
    // hero recovery ring, so the two read as one family.
    private let openFraction: Double = 0.80
    private var startAngle: Angle { .degrees(-90) }

    // Proportions derived from `size` so the mark is resolution-independent.
    private var ringInset: CGFloat { size * 0.20 }          // tile edge → ring band
    private var ringWidth: CGFloat { size * 0.13 }          // THICK gold stroke (matches the icon)
    private var ringDiameter: CGFloat { size - ringInset * 2 }
    private var coreDiameter: CGFloat { size * 0.18 }       // centre core dot
    private var rimWidth: CGFloat { max(1, size * 0.008) }  // ~1px hairline rim

    public var body: some View {
        ZStack {
            navyTile
            goldRing
            coreDot
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("NOOP"))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Deep-navy tile

    /// The navy disc the gold mark sits on — a deep-navy vertical ramp (lifted at
    /// the top, deeper at the bottom) with a faint cool top sheen and a soft
    /// hairline rim, matching the app icon. No shadow — flat and clean.
    private var navyTile: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#1A1E24"), Color(hex: "#0E1116")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Faint cool top sheen — a soft light catch across the upper third (flat, no bloom).
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#2A2F37").opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .opacity(0.6)
            )
            // 1px hairline rim so the disc reads cleanly on the navy canvas.
            .overlay(
                Circle().strokeBorder(StrandPalette.hairline, lineWidth: rimWidth)
            )
    }

    // MARK: Open gold recovery ring

    /// The open ~80% gold arc — round-capped, stroked with the gold ramp via an
    /// AngularGradient so the metal shifts along the sweep (light → gold → deep),
    /// matching how the hero recovery ring fills.
    private var goldRing: some View {
        RecoveryArc(
            startAngle: startAngle,
            spanDegrees: 360 * openFraction,
            fraction: 1,
            lineWidth: ringWidth
        )
        .stroke(
            StrandPalette.chargeColor,
            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
        )
        .frame(width: ringDiameter, height: ringDiameter)
    }

    // MARK: Solid gold core

    /// The "on-device core" — a solid gold dot at the exact centre, completing the
    /// open-ring + core-dot lock-up.
    private var coreDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: coreDiameter, height: coreDiameter)
    }
}

#if DEBUG
#Preview("BrandMark — sizes") {
    VStack(spacing: 40) {
        BrandMark(size: 120)
        HStack(spacing: 28) {
            BrandMark(size: 72)
            BrandMark(size: 44)
            BrandMark(size: 28)
        }
    }
    .padding(48)
    .frame(width: 420, height: 460)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
