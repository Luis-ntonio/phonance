const { Firestore } = require("@google-cloud/firestore");

const db = new Firestore();
const USERS_COLLECTION = "users";

function json(res, status, body) {
  res
    .status(status)
    .set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST,OPTIONS",
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
          "Access-Control-Allow-Methods": "POST,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
        })
        .send("");
    }

    if (req.path !== "/subscription/refresh") return json(res, 404, { message: "Not Found" });
    if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });

    const subscriptionUpdatedAt = Date.now();
    const payload = {
      isSubscribed: true,
      subscriptionUpdatedAt,
      mpStatus: "authorized",
      mpPreapprovalId: `pre_${subscriptionUpdatedAt}`,
      lastPaymentId: `pay_${subscriptionUpdatedAt}`,
      lastPaymentDate: new Date(subscriptionUpdatedAt).toISOString(),
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(payload, { merge: true });

    return json(res, 200, {
      isSubscribed: true,
      subscriptionUpdatedAt,
      mp: {
        status: payload.mpStatus,
        preapprovalId: payload.mpPreapprovalId,
        lastPaymentId: payload.lastPaymentId,
        lastPaymentDate: payload.lastPaymentDate,
      },
    });
  } catch (error) {
    console.error("subscription-refresh error", error);
    return json(res, 500, { message: "Internal Server Error" });
  }
};
