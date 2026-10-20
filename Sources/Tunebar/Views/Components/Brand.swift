import SwiftUI

/// The YouTube Music logo and wordmark for the top bar.
struct Brand: View {
    var body: some View {
        HStack(spacing: 5) {
            YouTubeMusicMark().frame(width: 22, height: 22)
            Text("Music")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("YouTube Music")
    }
}

/// The YouTube Music mark: a red disc with a white ring and a white play triangle. (The same mark is
/// drawn for the menu bar in MenuBarIcon.swift and for the app icon by Scripts/make-icon.swift.)
struct YouTubeMusicMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(Color(red: 1, green: 0, blue: 0))
                Circle()
                    .strokeBorder(.white, lineWidth: size * 0.065)
                    .padding(size * 0.2)
                PlayTriangle()
                    .fill(.white)
                    .frame(width: size * 0.24, height: size * 0.27)
                    .offset(x: size * 0.025)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
