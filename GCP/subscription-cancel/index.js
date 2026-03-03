const { Firestore } = require("@google-cloud/firestore");

const db = process.env.FIRESTORE_DATABASE_ID
  ? new Firestore({ databaseId: process.env.FIRESTORE_DATABASE_ID })
  : new Firestore();
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

function decodeBase64Json(value) {
  try {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    return null;
  }
}

function decodeJwtPayload(token) {
  try {
    const parts = token.split(".");
    if (parts.length < 2) return null;
    return decodeBase64Json(parts[1]);
  } catch {
    return null;
  }
}

function getUserId(req) {
  const byHeader = req.get("x-user-id");
  if (byHeader) return byHeader;

  const apiUserInfo = req.get("x-apigateway-api-userinfo") || req.get("x-endpoint-api-userinfo");
  if (apiUserInfo) {
    const payload = decodeBase64Json(apiUserInfo);
    const uid = payload?.user_id || payload?.sub || payload?.uid;
    if (uid) return uid;
  }

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

    if (req.path !== "/subscription/cancel") return json(res, 404, { message: "Not Found" });
    if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });

    const subscriptionUpdatedAt = Date.now();
    const payload = {
      isSubscribed: false,
      subscriptionUpdatedAt,
      mpStatus: "cancelled",
      mpPreapprovalId: `pre_${userId}`,
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(payload, { merge: true });

    return json(res, 200, {
      cancelled: true,
      mp: {
        status: payload.mpStatus,
        preapprovalId: payload.mpPreapprovalId,
      },
      subscriptionUpdatedAt,
    });
  } catch (error) {
    console.error("subscription-cancel error", error);
    return json(res, 500, { message: "Internal Server Error" });
  }
};
