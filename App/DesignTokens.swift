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
        static let edgeTab = CGSize(width: 24, height: 72)
        static let tile = CGSize(width: 44, height: 44)
        static let handleGap: CGFloat = 8
    }

    enum Motion {
        static let quick = Animation.spring(response: 0.28, dampingFraction: 0.82)
    }

    enum TextRole {
        static let sectionTitle = Font.headline
        static let row = Font.body
        static let detail = Font.footnote
        static let meta = Font.callout
    }

    enum Tint {
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
