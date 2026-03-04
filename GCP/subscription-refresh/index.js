const { Firestore } = require("@google-cloud/firestore");

const db = new Firestore({ databaseId: process.env.FIRESTORE_DATABASE_ID || "users" });
const USERS_COLLECTION = "users";
const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN || "";

function isExpectedPath(req, expectedPath) {
  const raw = (req.path || req.url || "").split("?")[0].toLowerCase();
  const expected = expectedPath.toLowerCase();
  return raw === expected || raw.endsWith(expected) || raw === "/" || raw === "";
}

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

    if (!isExpectedPath(req, "/subscription/refresh")) return json(res, 404, { message: "Not Found" });
    if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });
    if (!MP_ACCESS_TOKEN) return json(res, 500, { message: "MP_ACCESS_TOKEN missing" });

    const searchUrl =
      "https://api.mercadopago.com/preapproval/search" +
      `?external_reference=${encodeURIComponent(userId)}` +
      "&sort=date_created:desc&limit=1";

    const preapprovalResponse = await fetch(searchUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    });

    if (!preapprovalResponse.ok) {
      const body = await safeJson(preapprovalResponse);
      console.error("subscription-refresh preapproval search failed", preapprovalResponse.status, body);
      return json(res, 502, { message: "Failed to refresh subscription" });
    }

    const preapprovalData = await preapprovalResponse.json();
    const latest = (preapprovalData?.results ?? [])[0] ?? null;
    const status = latest?.status ?? "unknown";

    const paymentUrl =
      "https://api.mercadopago.com/v1/payments/search" +
      `?external_reference=${encodeURIComponent(userId)}` +
      "&status=approved&sort=date_created&criteria=desc&limit=1";

    const paymentResponse = await fetch(paymentUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    });

    if (!paymentResponse.ok) {
      const body = await safeJson(paymentResponse);
      console.error("subscription-refresh payments search failed", paymentResponse.status, body);
      return json(res, 502, { message: "Failed to refresh subscription" });
    }

    const paymentData = await paymentResponse.json();
    const lastPayment = (paymentData?.results ?? [])[0] ?? null;
    const hasApprovedPayment = Boolean(lastPayment?.id);
    const isSubscribed = status === "authorized" && hasApprovedPayment;

    const subscriptionUpdatedAt = Date.now();
    const payload = {
      isSubscribed,
      subscriptionUpdatedAt,
      mpStatus: status,
      mpSubscriptionStatus: status,
      mpPreapprovalId: latest?.id ?? null,
      lastPaymentId: lastPayment?.id ?? null,
      lastPaymentDate: lastPayment?.date_created ?? null,
    };

    await db.collection(USERS_COLLECTION).doc(userId).set(payload, { merge: true });

    return json(res, 200, {
      isSubscribed,
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
    return json(res, 500, {
      message: "Internal Server Error",
      detail: String(error?.message || error),
      code: error?.code || null,
    });
  }
};

async function safeJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}
