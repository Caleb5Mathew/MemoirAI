function normalizedAllowedEmails(raw) {
  return String(raw || "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);
}

function isMemoirAdminToken(token, allowedEmailsRaw) {
  if (token?.admin === true) return true;
  const allowedEmails = normalizedAllowedEmails(allowedEmailsRaw);
  const email = String(token?.email || "").trim().toLowerCase();
  return token?.email_verified === true
    && Boolean(email)
    && allowedEmails.includes(email);
}

module.exports = { isMemoirAdminToken, normalizedAllowedEmails };
