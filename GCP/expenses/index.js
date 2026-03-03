const { Firestore, FieldValue } = require("@google-cloud/firestore");

const db = process.env.FIRESTORE_DATABASE_ID
  ? new Firestore({ databaseId: process.env.FIRESTORE_DATABASE_ID })
  : new Firestore();
const EXPENSES_COLLECTION = "expenses";

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
      "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
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

function expenseDocId(userId, timestampMs, dedupeKey) {
  return `${userId}_${timestampMs}_${dedupeKey}`;
}

exports.handler = async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      return res
        .status(204)
        .set({
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
        })
        .send("");
    }

    if (!isExpectedPath(req, "/expenses")) return json(res, 404, { message: "Not Found" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });

    if (req.method === "GET") {
      const fromMs = req.query.fromMs ? Number(req.query.fromMs) : 0;
      const toMs = req.query.toMs ? Number(req.query.toMs) : Number.MAX_SAFE_INTEGER;
      const limit = req.query.limit ? Math.min(Number(req.query.limit), 2000) : 500;

      const snapshot = await db.collection(EXPENSES_COLLECTION).where("userId", "==", userId).get();

      const items = snapshot.docs
        .map((doc) => doc.data())
        .filter((item) => item.timestampMs >= fromMs && item.timestampMs <= toMs)
        .sort((a, b) => b.timestampMs - a.timestampMs)
        .slice(0, limit);

      return json(res, 200, { items });
    }

    if (req.method === "POST") {
      const payload = req.body || {};
      const timestampMs = Number(payload.timestampMs);
      const dedupeKey = String(payload.dedupeKey || "");
      if (!Number.isFinite(timestampMs) || !dedupeKey) {
        return json(res, 400, { message: "Missing timestampMs or dedupeKey" });
      }

      const docId = expenseDocId(userId, timestampMs, dedupeKey);
      const ref = db.collection(EXPENSES_COLLECTION).doc(docId);
      const existing = await ref.get();
      if (existing.exists) return json(res, 409, { message: "Expense already exists (duplicate)." });

      const item = {
        userId,
        sk: `${String(timestampMs).padStart(13, "0")}#${dedupeKey}`,
        timestampMs,
        dedupeKey,
        amount: payload.amount ?? null,
        currency: payload.currency ?? null,
        merchant: payload.merchant ?? null,
        category: payload.category ?? null,
        rawText: payload.rawText ?? null,
        sourcePackage: payload.sourcePackage ?? null,
        createdAt: FieldValue.serverTimestamp(),
      };

      await ref.set(item);
      const saved = await ref.get();
      return json(res, 201, saved.data());
    }

    if (req.method === "PATCH") {
      const payload = req.body || {};
      const timestampMs = Number(payload.timestampMs);
      const dedupeKey = String(payload.dedupeKey || "");
      if (!Number.isFinite(timestampMs) || !dedupeKey) {
        return json(res, 400, { message: "Missing dedupeKey or timestampMs" });
      }

      const docId = expenseDocId(userId, timestampMs, dedupeKey);
      const ref = db.collection(EXPENSES_COLLECTION).doc(docId);
      const existing = await ref.get();
      if (!existing.exists) return json(res, 404, { message: "Expense not found" });

      await ref.set(
        {
          category: payload.category ?? existing.data()?.category ?? null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const saved = await ref.get();
      return json(res, 200, saved.data());
    }

    return json(res, 405, { message: "Method not allowed" });
  } catch (error) {
    console.error("expenses error", error);
    return json(res, 500, { message: "Internal Server Error" });
  }
};
