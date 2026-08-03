import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var config: Config
    @State private var showScanner = false
    @State private var badCode = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 64))
                .foregroundColor(Color(red: 0.18, green: 0.83, blue: 0.75))
            Text("Bienvenue").font(.title).bold().foregroundColor(.white)
            Text("Scanne ton code SafeDesk pour retrouver ton espace.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            Button {
                showScanner = true
            } label: {
                Text("Scanner mon code")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color(red: 0.18, green: 0.83, blue: 0.75))
                    .foregroundColor(.black)
                    .cornerRadius(16)
            }
            .padding(.top, 20)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.06, green: 0.07, blue: 0.08).ignoresSafeArea())
        .sheet(isPresented: $showScanner) {
            ScannerView { code in
                showScanner = false
                if !config.apply(code: code) { badCode = true }
            }
        }
        .alert("Ce code n est pas un code SafeDesk valide.", isPresented: $badCode) {
            Button("OK", role: .cancel) {}
        }
    }
}