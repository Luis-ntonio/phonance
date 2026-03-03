const dummyDb = new Map();

function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
    "Content-Type": "application/json"
  }).send(JSON.stringify(body ?? {}));
}

function getUserId(req) {
  const raw = req.get("x-user-id");
  if (raw) return raw;

  const auth = req.get("authorization") || "";
  if (!auth) return null;

  const token = auth.replace(/^Bearer\s+/i, "").trim();
  return token ? `user_${token.slice(0, 12)}` : null;
}

function normalizeProfile(userId, payload) {
  return {
    username: userId,
    name: String(payload?.name || ""),
    email: String(payload?.email || ""),
    phoneNumber: String(payload?.phoneNumber || ""),
    preferredCurrency: String(payload?.preferredCurrency || "PEN"),
    savingsGoal: Number(payload?.savingsGoal || 0),
    monthlyIncome: Number(payload?.monthlyIncome || 0),
    spendingLimit: Number(payload?.spendingLimit || 0),
    isSubscribed: payload?.isSubscribed === true,
    subscriptionUpdatedAt: Number(payload?.subscriptionUpdatedAt || 0),
    updatedAt: Date.now()
  };
}

exports.handler = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(204).set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (req.path !== "/profile") {
    return json(res, 404, { message: "Not Found" });
  }

  const userId = getUserId(req);
  if (!userId) return json(res, 401, { message: "Unauthorized" });

  if (req.method === "GET") {
    const item = dummyDb.get(userId);
    if (!item) return json(res, 404, { message: "Profile not found" });
    return json(res, 200, item);
  }

  if (req.method === "POST" || req.method === "PUT") {
    const profile = normalizeProfile(userId, req.body || {});
    const prev = dummyDb.get(userId);
    if (!prev) profile.createdAt = Date.now();
    else profile.createdAt = prev.createdAt;

    dummyDb.set(userId, profile);
    return json(res, req.method === "POST" ? 201 : 200, profile);
  }

  return json(res, 405, { message: "Method not allowed" });
};
