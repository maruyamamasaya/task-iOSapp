import SwiftUI

extension ProjectColor {
    var color: Color {
        switch self { case .blue: .blue; case .green: .green; case .orange: .orange; case .purple: .purple; case .pink: .pink; case .red: .red; case .teal: .teal; case .gray: .gray }
    }
}
