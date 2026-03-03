function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
    "Content-Type": "application/json"
  }).send(JSON.stringify(body ?? {}));
}

function isExpectedPath(req, expectedPath) {
  const raw = (req.path || req.url || "").split("?")[0].toLowerCase();
  const expected = expectedPath.toLowerCase();
  return raw === expected || raw.endsWith(expected) || raw === "/" || raw === "";
}

function getUserId(req) {
  const byHeader = req.get("x-user-id");
  if (byHeader) return byHeader;

  const auth = req.get("authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  try {
    const parts = token.split(".");
    if (parts.length < 2) return null;
    const normalized = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const payload = JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
    return payload?.user_id || payload?.sub || payload?.uid || null;
  } catch {
    return null;
  }
}

exports.handler = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(204).set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (!isExpectedPath(req, "/getMPlink")) return json(res, 404, { message: "Not Found" });
  if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });

  const userId = getUserId(req);
  if (!userId) return json(res, 401, { message: "Unauthorized" });

  const orderId = String(req.body?.order_id || userId);
  const baseUrl = process.env.SUCCESS_URL || "https://example.com/success";
  const mockPreferenceId = `pre_${Date.now()}`;

  return json(res, 200, {
    preference_id: mockPreferenceId,
    checkout_url: `${baseUrl}?pref_id=${encodeURIComponent(mockPreferenceId)}&order_id=${encodeURIComponent(orderId)}`
  });
};
