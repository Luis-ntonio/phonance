const expensesDb = new Map();

function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
    "Content-Type": "application/json"
  }).send(JSON.stringify(body ?? {}));
}

function getUserId(req) {
  const byHeader = req.get("x-user-id");
  if (byHeader) return byHeader;
  const auth = req.get("authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  return token ? `user_${token.slice(0, 12)}` : null;
}

function getBucket(userId) {
  if (!expensesDb.has(userId)) expensesDb.set(userId, []);
  return expensesDb.get(userId);
}

exports.handler = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(204).set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (req.path !== "/expenses") return json(res, 404, { message: "Not Found" });

  const userId = getUserId(req);
  if (!userId) return json(res, 401, { message: "Unauthorized" });

  const bucket = getBucket(userId);

  if (req.method === "GET") {
    const fromMs = req.query.fromMs ? Number(req.query.fromMs) : 0;
    const toMs = req.query.toMs ? Number(req.query.toMs) : Number.MAX_SAFE_INTEGER;
    const limit = req.query.limit ? Math.min(Number(req.query.limit), 2000) : 500;

    const items = bucket
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

    const exists = bucket.find((item) => item.dedupeKey === dedupeKey && item.timestampMs === timestampMs);
    if (exists) return json(res, 409, { message: "Expense already exists (duplicate)." });

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
      createdAt: Date.now()
    };

    bucket.push(item);
    return json(res, 201, item);
  }

  if (req.method === "PATCH") {
    const payload = req.body || {};
    const timestampMs = Number(payload.timestampMs);
    const dedupeKey = String(payload.dedupeKey || "");
    if (!Number.isFinite(timestampMs) || !dedupeKey) {
      return json(res, 400, { message: "Missing dedupeKey or timestampMs" });
    }

    const item = bucket.find((entry) => entry.timestampMs === timestampMs && entry.dedupeKey === dedupeKey);
    if (!item) return json(res, 404, { message: "Expense not found" });

    item.category = payload.category ?? item.category;
    item.updatedAt = Date.now();
    return json(res, 200, item);
  }

  return json(res, 405, { message: "Method not allowed" });
};
