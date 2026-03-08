import SwiftUI

struct SplashView: View {
    @State private var opacity = 0.0

    private let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }()

    var body: some View {
        ZStack {
            Color(red: 0.980, green: 0.400, blue: 0.133)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 72, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)

                Text("Maestro")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(version)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1.0 }
        }
    }
}
