import SwiftUI

/// The whole look, tunable from this one file.
enum Tokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let panel: CGFloat = 24
    }

    enum Size {
        static let panel = CGSize(width: 380, height: 600)
        static let panelMin = CGSize(width: 340, height: 460)
        static let panelMax = CGSize(width: 560, height: 900)
        static let edgeTab = CGSize(width: 24, height: 72)
        static let tile = CGSize(width: 44, height: 44)
        static let handleGap: CGFloat = 8
    }

    enum Surface {
        static let contentOpacity: Double = 0.94
    }

    /// One small vocabulary of motion, so everything moves the same way: selections glide, pages
    /// cross-fade, small things ease in. With Reduce Motion everything becomes a short fade.
    enum Motion {
        static let quick = Animation.spring(response: 0.28, dampingFraction: 0.82)
        /// A highlight sliding to what you picked.
        static let select = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// One page or list giving way to another.
        static let page = Animation.spring(response: 0.36, dampingFraction: 0.92)
        static let reduced = Animation.easeInOut(duration: 0.15)

        static func adaptive(_ animation: Animation, reduce: Bool) -> Animation { reduce ? reduced : animation }

        /// Pages fade with a slight lift; with Reduce Motion they only fade.
        static func pageTransition(reduce: Bool) -> AnyTransition {
            reduce ? .opacity : .opacity.combined(with: .offset(y: 6))
        }
        static let tuck = Animation.spring(response: 0.35, dampingFraction: 0.86)
        static let panel = Animation.spring(response: 0.3, dampingFraction: 0.84)
        static let panelCloseSeconds = 0.22
    }

    enum TextRole {
        static let sectionTitle = Font.headline
        static let row = Font.body
        static let detail = Font.footnote
        static let meta = Font.callout
    }

    enum Tint {
        static func named(_ name: String) -> Color {
            switch name {
            case "clients": clients
            case "personal": personal
            case "learning": learning
            case "homeReno": homeReno
            default: work
            }
        }

        static let clients = Color(red: 0.36, green: 0.58, blue: 0.42)
        static let work = Color(red: 0.36, green: 0.50, blue: 0.70)
        static let personal = Color(red: 0.72, green: 0.52, blue: 0.38)
        static let learning = Color(red: 0.56, green: 0.46, blue: 0.70)
        static let homeReno = Color(red: 0.44, green: 0.60, blue: 0.64)
    }
}

enum Density: String {
    case comfortable, compact

    var rowPadding: CGFloat { self == .comfortable ? Tokens.Spacing.s : Tokens.Spacing.xs }
    var sectionGap: CGFloat { self == .comfortable ? Tokens.Spacing.m : Tokens.Spacing.s }
}
