const { Firestore, FieldValue } = require("@google-cloud/firestore");

const db = process.env.FIRESTORE_DATABASE_ID
  ? new Firestore({ databaseId: process.env.FIRESTORE_DATABASE_ID })
  : new Firestore();
const USERS_COLLECTION = "users";
const EVENTS_COLLECTION = "webhook_events";

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

function resolveUserId(payload) {
  return (
    payload?.external_reference ||
    payload?.metadata?.external_reference ||
    payload?.data?.external_reference ||
    payload?.userId ||
    null
  );
}

function resolveStatus(payload) {
  return payload?.status || payload?.data?.status || payload?.type || payload?.topic || "unknown";
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

    const payload = req.body || {};
    const eventId = payload?.data?.id || payload?.id || `evt_${Date.now()}`;
    const type = payload?.type || payload?.topic || "unknown";
    const status = resolveStatus(payload);

    await db.collection(EVENTS_COLLECTION).doc(String(eventId)).set(
      {
        eventId: String(eventId),
        type,
        status,
        payload,
        receivedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const userId = resolveUserId(payload);
    const isActive = status === "approved" || status === "authorized";

    if (userId && isActive) {
      await db.collection(USERS_COLLECTION).doc(String(userId)).set(
        {
          isSubscribed: true,
          subscriptionUpdatedAt: Date.now(),
          mpStatus: status,
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
    return json(res, 500, { message: "Internal Server Error" });
  }
};
