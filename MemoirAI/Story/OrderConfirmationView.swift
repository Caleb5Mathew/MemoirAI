//
//  OrderConfirmationView.swift
//  MemoirAI
//
//  Shown after a successful Stripe checkout (`memoirai://order-complete`) instead of silently
//  dismissing the order flow. The order total isn't available client-side at this point, so we
//  don't fake one — the receipt comes from Stripe by email.
//

import SwiftUI

struct OrderConfirmationView: View {
    /// Called when the user taps "Done"; the presenting view is responsible for dismissing itself.
    var onDone: () -> Void

    @State private var showOrderHistory = false

    private let softCream = Color(red: 0.98, green: 0.96, blue: 0.89)
    private let terracotta = Color(red: 0.82, green: 0.45, blue: 0.32)
    private let darkText = Color.black.opacity(0.85)

    private func serifFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .bold || weight == .semibold ? "Georgia-Bold" : "Georgia"
        return .custom(name, size: size)
    }

    var body: some View {
        ZStack {
            softCream.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(terracotta)

                VStack(spacing: 10) {
                    Text("Your book is on its way to the printer!")
                        .font(serifFont(size: 24, weight: .bold))
                        .foregroundColor(darkText)
                        .multilineTextAlignment(.center)

                    Text("You'll get a receipt by email from our payment processor.")
                        .font(serifFont(size: 15))
                        .foregroundColor(darkText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showOrderHistory = true
                    } label: {
                        Text("View My Orders")
                            .font(serifFont(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button(action: onDone) {
                        Text("Done")
                            .font(serifFont(size: 16, weight: .semibold))
                            .foregroundColor(terracotta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(isPresented: $showOrderHistory) {
            OrderHistoryView()
        }
    }
}

#Preview {
    OrderConfirmationView(onDone: {})
}
