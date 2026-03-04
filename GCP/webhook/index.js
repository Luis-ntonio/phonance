const { Firestore, FieldValue } = require("@google-cloud/firestore");
const crypto = require("crypto");

const db = new Firestore({ databaseId: process.env.FIRESTORE_DATABASE_ID || "users" });
const USERS_COLLECTION = "users";
const EVENTS_COLLECTION = "webhook_events";
const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN || "";
const MP_WEBHOOK_SECRET = process.env.MP_WEBHOOK_SECRET || "";

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

    if (!isExpectedPath(req, "/webhook")) return json(res, 404, { message: "Not Found" });
    if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });
    if (!MP_ACCESS_TOKEN) return json(res, 500, { message: "MP_ACCESS_TOKEN missing" });

    if (MP_WEBHOOK_SECRET && !verifySignature(req, MP_WEBHOOK_SECRET)) {
      return json(res, 401, { message: "Invalid Signature" });
    }

    const payload = req.body || {};
    const eventId = payload?.data?.id || payload?.id || `evt_${Date.now()}`;
    const type = payload?.type || payload?.topic || "unknown";

    const mpUrl = resolveMercadoPagoUrl(type, eventId);
    if (!mpUrl) {
      return json(res, 200, { received: true, ignored: true });
    }

    const mpResponse = await fetch(mpUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    });
    if (!mpResponse.ok) {
      const body = await safeJson(mpResponse);
      console.error("webhook mp fetch failed", mpResponse.status, body);
      return json(res, 200, { received: true, processed: false });
    }

    const mpData = await mpResponse.json();
    const status = mpData?.status || "unknown";
    const userId =
      mpData?.external_reference ||
      mpData?.metadata?.external_reference ||
      null;

    await db.collection(EVENTS_COLLECTION).doc(String(eventId)).set(
      {
        eventId: String(eventId),
        type,
        status,
        payload: mpData,
        receivedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const isActive = status === "approved" || status === "authorized";

    if (userId && isActive) {
      await db.collection(USERS_COLLECTION).doc(String(userId)).set(
        {
          isSubscribed: true,
          subscriptionUpdatedAt: Date.now(),
          mpStatus: status,
          mpSubscriptionStatus: status,
          lastWebhookEventId: String(eventId),
        },
        { merge: true }
      );
    }

    return json(res, 200, {
      received: true,
      processed: true,
      eventId: String(eventId),
      type,
    });
  } catch (error) {
    console.error("webhook error", error);
    return json(res, 500, {
      message: "Internal Server Error",
      detail: String(error?.message || error),
      code: error?.code || null,
    });
  }
};

function resolveMercadoPagoUrl(type, resourceId) {
  if (!resourceId) return null;
  if (type === "payment") {
    return `https://api.mercadopago.com/v1/payments/${resourceId}`;
  }
  if (type === "subscription_preapproval" || type === "preapproval") {
    return `https://api.mercadopago.com/preapproval/${resourceId}`;
  }
  return null;
}

function verifySignature(req, secret) {
  const xSignature = req.get("x-signature") || req.get("X-Signature");
  const xRequestId = req.get("x-request-id") || req.get("X-Request-Id");
  if (!xSignature || !xRequestId) return false;

  const ts = xSignature
    .split(",")
    .map((part) => part.trim())
    .find((part) => part.startsWith("ts="))
    ?.replace("ts=", "");
  const hash = xSignature
    .split(",")
    .map((part) => part.trim())
    .find((part) => part.startsWith("v1="))
    ?.replace("v1=", "");

  if (!ts || !hash) return false;

  const body = req.body || {};
  const dataId = body?.data?.id || body?.id;
  if (!dataId) return false;

  const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`;
  const digest = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
  return digest === hash;
}

async function safeJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}
