const { Firestore } = require("@google-cloud/firestore");

const db = new Firestore();
const USERS_COLLECTION = "users";

function json(res, status, body) {
  res
    .status(status)
    .set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
      "Content-Type": "application/json",
    })
    .send(JSON.stringify(body ?? {}));
}

function decodeJwtPayload(token) {
  try {
    const parts = token.split(".");
    if (parts.length < 2) return null;
    const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    return null;
  }
}

function getUserId(req) {
  const byHeader = req.get("x-user-id");
  if (byHeader) return byHeader;
  const auth = req.get("authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  const payload = decodeJwtPayload(token);
  return payload?.user_id || payload?.sub || payload?.uid || null;
}

exports.handler = async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      return res
        .status(204)
        .set({
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
        })
        .send("");
    }

    if (req.path !== "/subscription/summary") return json(res, 404, { message: "Not Found" });
    if (req.method !== "GET") return json(res, 405, { message: "Method not allowed" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });

    const snapshot = await db.collection(USERS_COLLECTION).doc(userId).get();
    const user = snapshot.exists ? snapshot.data() : {};

    const subscriptionUpdatedAt = user?.subscriptionUpdatedAt ?? Date.now();
    const lastPaymentDate = user?.lastPaymentDate ?? null;
    const nextChargeDate = user?.nextChargeDate ?? null;

    return json(res, 200, {
      isSubscribed: user?.isSubscribed === true,
      mp: {
        status: user?.mpStatus ?? "unknown",
        preapprovalId: user?.mpPreapprovalId ?? null,
        amount: user?.mpAmount ?? 3.99,
        currency: user?.mpCurrency ?? "PEN",
        frequency: user?.mpFrequency ?? 1,
        frequencyType: user?.mpFrequencyType ?? "months",
      },
      billing: {
        lastPaymentId: user?.lastPaymentId ?? null,
        lastPaymentDate,
        nextChargeDate,
      },
      subscriptionUpdatedAt,
    });
  } catch (error) {
    console.error("subscription-summary error", error);
    return json(res, 500, { message: "Internal Server Error" });
  }
};
