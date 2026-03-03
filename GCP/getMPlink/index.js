function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
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

exports.handler = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(204).set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (req.path !== "/getMPlink") return json(res, 404, { message: "Not Found" });
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
