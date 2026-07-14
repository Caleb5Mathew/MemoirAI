"use strict";

/**
 * Server-side email alerts to memoirstorybook@gmail.com (Caleb) so paid orders, fulfillment
 * failures, and refunds/disputes don't require someone to remember to open /ops.
 *
 * Env-gated the same way as `isAppCheckEnforced()` in index.js: when OPS_ALERT_SMTP_URL is unset,
 * `sendOpsAlert` is a no-op that logs and returns false. Set the secret to enable real emails —
 * see the "Ops alert emails" section in STRIPE_GO_LIVE_CHECKLIST.md for the Gmail app-password setup.
 */

const { defineSecret } = require("firebase-functions/params");
const nodemailer = require("nodemailer");

/** SMTP connection URL, e.g. smtps://user%40gmail.com:app-password@smtp.gmail.com:465 */
const opsAlertSmtpUrl = defineSecret("OPS_ALERT_SMTP_URL");

const OPS_ALERT_TO = "memoirstorybook@gmail.com";

function extractSmtpUser(smtpUrl) {
  try {
    const parsed = new URL(smtpUrl);
    return parsed.username ? decodeURIComponent(parsed.username) : OPS_ALERT_TO;
  } catch {
    return OPS_ALERT_TO;
  }
}

/**
 * Sends a plaintext ops alert email. Never throws — a failed alert must not break the caller
 * (Stripe webhook, Lulu fulfillment, refund handling). Returns whether the email was sent.
 * @param {string} subject
 * @param {string} textBody
 * @returns {Promise<boolean>}
 */
async function sendOpsAlert(subject, textBody) {
  try {
    const smtpUrl = String(opsAlertSmtpUrl.value() || "").trim();
    if (!smtpUrl) {
      console.warn(`ops alert skipped (OPS_ALERT_SMTP_URL not configured): ${subject}`);
      return false;
    }

    const transporter = nodemailer.createTransport(smtpUrl);
    await transporter.sendMail({
      from: extractSmtpUser(smtpUrl),
      to: OPS_ALERT_TO,
      subject,
      text: textBody
    });
    console.log(`ops alert sent: ${subject}`);
    return true;
  } catch (err) {
    console.error(`ops alert failed: ${subject}`, err?.message || err);
    return false;
  }
}

module.exports = {
  opsAlertSmtpUrl,
  sendOpsAlert
};
