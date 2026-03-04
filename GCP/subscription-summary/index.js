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
      "Access-Control-Allow-Methods": "GET,OPTIONS",
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
          "Access-Control-Allow-Methods": "GET,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
        })
        .send("");
    }

    if (!isExpectedPath(req, "/subscription/summary")) return json(res, 404, { message: "Not Found" });
    if (req.method !== "GET") return json(res, 405, { message: "Method not allowed" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });
    if (!MP_ACCESS_TOKEN) return json(res, 500, { message: "MP_ACCESS_TOKEN missing" });

    const preapprovalUrl =
      "https://api.mercadopago.com/preapproval/search" +
      `?external_reference=${encodeURIComponent(userId)}` +
      "&sort=date_created:desc&limit=1";

    const preapprovalResponse = await fetch(preapprovalUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    });
    if (!preapprovalResponse.ok) {
      const body = await safeJson(preapprovalResponse);
      console.error("subscription-summary preapproval search failed", preapprovalResponse.status, body);
      return json(res, 502, { message: "Failed to get subscription summary" });
    }
    const preapprovalData = await preapprovalResponse.json();
    const preapproval = (preapprovalData?.results ?? [])[0] ?? null;

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
      console.error("subscription-summary payment search failed", paymentResponse.status, body);
      return json(res, 502, { message: "Failed to get subscription summary" });
    }
    const paymentData = await paymentResponse.json();
    const lastPayment = (paymentData?.results ?? [])[0] ?? null;

    const mpStatus = preapproval?.status ?? "unknown";
    const preapprovalId = preapproval?.id ?? null;
    const ar = preapproval?.auto_recurring ?? {};
    const amount = ar.transaction_amount ?? null;
    const currency = ar.currency_id ?? null;
    const frequency = ar.frequency ?? null;
    const frequencyType = ar.frequency_type ?? null;
    const lastPaymentDate = lastPayment?.date_created ?? null;
    const lastPaymentId = lastPayment?.id ?? null;

    let nextChargeDate = null;
    if (lastPaymentDate && frequency && frequencyType === "months") {
      const d = new Date(lastPaymentDate);
      const day = d.getDate();
      d.setMonth(d.getMonth() + Number(frequency));
      if (d.getDate() < day) d.setDate(0);
      nextChargeDate = d.toISOString();
    }

    const isSubscribed = mpStatus === "authorized";
    const subscriptionUpdatedAt = Date.now();

    await db.collection(USERS_COLLECTION).doc(userId).set(
      {
        isSubscribed,
        subscriptionUpdatedAt,
        mpStatus,
        mpSubscriptionStatus: mpStatus,
        mpPreapprovalId: preapprovalId,
      },
      { merge: true }
    );

    return json(res, 200, {
      isSubscribed,
      mp: {
        status: mpStatus,
        preapprovalId,
        amount,
        currency,
        frequency,
        frequencyType,
      },
      billing: {
        lastPaymentId,
        lastPaymentDate,
        nextChargeDate,
      },
      subscriptionUpdatedAt,
    });
  } catch (error) {
    console.error("subscription-summary error", error);
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
