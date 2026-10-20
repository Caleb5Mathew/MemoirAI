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

    private let softCream = LinenTheme.paper
    private let terracotta = LinenTheme.accent
    private let darkText = LinenTheme.ink

    var body: some View {
        ZStack {
            softCream.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(terracotta)
                    .onAppear { Haptics.success() }

                VStack(spacing: 10) {
                    Text("Your payment is confirmed")
                        .font(LinenTheme.heading())
                        .foregroundColor(darkText)
                        .multilineTextAlignment(.center)

                    Text("We're preparing your order for printing. You'll get a receipt by email from Stripe.")
                        .font(LinenTheme.body(14))
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
                            .font(LinenTheme.body(16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    Button(action: onDone) {
                        Text("Done")
                            .font(LinenTheme.body(16, weight: .semibold))
                            .foregroundColor(terracotta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
