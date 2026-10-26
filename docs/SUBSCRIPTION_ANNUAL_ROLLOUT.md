# Memoir annual subscription rollout

Verified October 25, 2026. This records the source and live configuration for the requested $59.99 yearly plan. It does not claim an unperformed purchase.

## Implemented in the app

- The paywall presents the yearly and monthly StoreKit products as selectable cards.
- Yearly is selected by default whenever it is available. Monthly remains selectable before Apple's confirmation sheet appears.
- The selected StoreKit package, not a hardcoded product, is passed to RevenueCat for purchase.
- Price and currency come from StoreKit. The annual charge is displayed as the annual charge, not only as a monthly equivalent.
- `Start Free Trial` appears only when the selected product has a free-trial introductory offer and RevenueCat verifies that the Apple account is eligible. Otherwise the button says `Continue`.
- Trial duration and the renewal price are disclosed below the purchase button.
- Mixpanel app events include only the bounded `subscription_plan` value (`yearly` or `monthly`). RevenueCat remains the source of truth for trial, charge, renewal, refund, and revenue events.

## Verified live configuration

- RevenueCat project: `25cadd3a` (`MemoirAI: Life Storytelling`).
- Current offering: `default` (`ofrng93347aa839`).
- Monthly package: `$rc_monthly` → `com.Buildr.MemoirAI.ProMonthly`.
- Annual package: `$rc_annual` → `com.Buildr.MemoirAI.ProYearly`.
- Both products grant the existing `Basic` entitlement; no new entitlement or backend product identifier is needed.
- App Store Connect subscription group: `21688646`, currently named `Monthly`.
- The approved yearly product has a one-week free introductory offer in the United States and most configured territories.
- The United States yearly price is currently `$34.99`. A `$59.99` new-subscriber price is scheduled for October 27, 2026 across all 175 storefronts using Apple's equivalents.
- Existing yearly subscribers keep their current storefront price.
- Approved monthly and yearly products are both at subscription level 2, correctly making them equal-service crossgrades.

## External configuration completed

App Store Connect now schedules `com.Buildr.MemoirAI.ProYearly` at **$59.99 USD per year** for new subscribers effective October 27, 2026, with Apple's territory-equivalent prices across 175 storefronts. Current prices are preserved for existing subscribers. The approved monthly and yearly products remain together at level 2.

After App Store Connect finishes propagating the change:

1. Confirm RevenueCat still returns both standard packages in the current offering.
2. Test annual-default and monthly-selection paths with separate sandbox accounts.
3. Confirm eligible accounts see the one-week trial disclosure and previously used subscription-group accounts do not.
4. Confirm Apple's sheet names the selected product and shows its localized price and trial terms.
5. Confirm both purchases activate `Basic`, restore correctly, survive relaunch, and keep historical content available after expiry.
6. Confirm Mixpanel app events contain `subscription_plan` and RevenueCat lifecycle events retain their provider-defined product identifier and environment fields.

The current App Store version 3.44 is already Waiting for Review. The custom selector requires a later binary; changing only the App Store price does not add this UI to 3.44.
