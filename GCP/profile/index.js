const { Firestore, FieldValue } = require("@google-cloud/firestore");

const USERS_COLLECTION = "users";
const configuredDatabaseId = (process.env.FIRESTORE_DATABASE_ID || "users").trim();
let dbClient = null;
let defaultDbClient = null;

function getDb() {
  if (dbClient) return dbClient;
  dbClient = new Firestore({ databaseId: configuredDatabaseId });
  return dbClient;
}

function getDefaultDb() {
  if (defaultDbClient) return defaultDbClient;
  defaultDbClient = new Firestore();
  return defaultDbClient;
}

async function withFirestoreFallback(run) {
  try {
    return await run(getDb());
  } catch (error) {
    if (error?.code !== 3) throw error;
    console.warn("profile firestore invalid databaseId, retrying with default", {
      configuredDatabaseId,
      detail: String(error?.message || error),
    });
    return run(getDefaultDb());
  }
}

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
      "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
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
  if (!auth) return null;

  const token = auth.replace(/^Bearer\s+/i, "").trim();
  const payload = decodeJwtPayload(token);
  return payload?.user_id || payload?.sub || payload?.uid || null;
}

function normalizeProfile(userId, payload, previous = {}) {
  const hasIncomingSubscribed = typeof payload?.isSubscribed === "boolean";
  const resolvedSubscribed = hasIncomingSubscribed
    ? payload.isSubscribed === true
    : previous?.isSubscribed === true;

  return {
    username: userId,
    name: String(payload?.name ?? previous?.name ?? ""),
    email: String(payload?.email ?? previous?.email ?? ""),
    phoneNumber: String(payload?.phoneNumber ?? previous?.phoneNumber ?? ""),
    preferredCurrency: String(payload?.preferredCurrency ?? previous?.preferredCurrency ?? "PEN"),
    savingsGoal: Number(payload?.savingsGoal ?? previous?.savingsGoal ?? 0),
    monthlyIncome: Number(payload?.monthlyIncome ?? previous?.monthlyIncome ?? 0),
    spendingLimit: Number(payload?.spendingLimit ?? previous?.spendingLimit ?? 0),
    isSubscribed: resolvedSubscribed,
    subscriptionUpdatedAt: Number(payload?.subscriptionUpdatedAt ?? previous?.subscriptionUpdatedAt ?? 0),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.handler = async (req, res) => {
  try {
    if (req.method === "OPTIONS") {
      return res
        .status(204)
        .set({
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
        })
        .send("");
    }

    if (!isExpectedPath(req, "/profile")) return json(res, 404, { message: "Not Found" });

    const userId = getUserId(req);
    if (!userId) return json(res, 401, { message: "Unauthorized" });

    if (req.method === "GET") {
      const snapshot = await withFirestoreFallback(async (db) =>
        db.collection(USERS_COLLECTION).doc(userId).get()
      );
      if (!snapshot.exists) return json(res, 404, { message: "Profile not found" });
      return json(res, 200, snapshot.data());
    }

    if (req.method === "POST" || req.method === "PUT") {
      const body = req.body || {};
      const existing = await withFirestoreFallback(async (db) =>
        db.collection(USERS_COLLECTION).doc(userId).get()
      );
      const previous = existing.exists ? (existing.data() || {}) : {};

      if (req.method === "POST") {
        const hasName = typeof body?.name === "string" && body.name.trim().length > 0;
        const hasEmail = typeof body?.email === "string" && body.email.trim().length > 0;
        if (!hasName || !hasEmail) {
          return json(res, 400, { message: "Missing required fields: email and name." });
        }
      }

      const profile = normalizeProfile(userId, body, previous);

      if (!existing.exists) {
        profile.createdAt = FieldValue.serverTimestamp();
      }

      await withFirestoreFallback(async (db) => {
        const userRef = db.collection(USERS_COLLECTION).doc(userId);
        await userRef.set(profile, { merge: true });
      });
      const saved = await withFirestoreFallback(async (db) =>
        db.collection(USERS_COLLECTION).doc(userId).get()
      );
      return json(res, req.method === "POST" ? 201 : 200, saved.data());
    }

    return json(res, 405, { message: "Method not allowed" });
  } catch (error) {
    console.error("profile error", error);
    return json(res, 500, {
      message: "Internal Server Error",
      detail: String(error?.message || error),
      code: error?.code || null,
      databaseId: configuredDatabaseId,
    });
  }
};
