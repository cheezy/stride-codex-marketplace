// Vulnerable fixture: hardcoded API key in source.
// DO NOT USE — the value below is an obvious placeholder.

const axios = require("axios");

// Vulnerability: production-shaped API key committed to source.
// Anyone who reads the repo (including via git history after a later
// "removal") gets the key. Even though this value is a placeholder, the
// pattern of a key literal next to a client constructor is what makes
// real keys leak.
const STRIPE_API_KEY = "sk_live_DO_NOT_USE_PLACEHOLDER_FOR_REVIEW_AGENT";

const stripe = axios.create({
  baseURL: "https://api.stripe.com/v1",
  headers: { Authorization: `Bearer ${STRIPE_API_KEY}` },
});

async function chargeCustomer(customerId, amountCents) {
  return stripe.post("/charges", {
    customer: customerId,
    amount: amountCents,
    currency: "usd",
  });
}

module.exports = { chargeCustomer };
