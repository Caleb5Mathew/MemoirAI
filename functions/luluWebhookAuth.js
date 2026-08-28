const crypto = require("crypto");

function verifyLuluWebhookSignature(rawBody, signature, webhookSecret) {
  if (!rawBody || !signature || !webhookSecret) return false;
  try {
    const payload = typeof rawBody === "string" ? Buffer.from(rawBody, "utf8") : rawBody;
    const expected = crypto.createHmac("sha256", webhookSecret).update(payload).digest("hex");
    const signatureBuffer = Buffer.from(String(signature).trim(), "hex");
    const expectedBuffer = Buffer.from(expected, "hex");
    return signatureBuffer.length === expectedBuffer.length &&
      crypto.timingSafeEqual(signatureBuffer, expectedBuffer);
  } catch {
    return false;
  }
}

module.exports = { verifyLuluWebhookSignature };
