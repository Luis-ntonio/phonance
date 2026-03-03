function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
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
      "Access-Control-Allow-Methods": "GET,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (req.path !== "/subscription/summary") return json(res, 404, { message: "Not Found" });
  if (req.method !== "GET") return json(res, 405, { message: "Method not allowed" });

  const userId = getUserId(req);
  if (!userId) return json(res, 401, { message: "Unauthorized" });

  const now = Date.now();
  const lastPaymentDate = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();
  const nextChargeDate = new Date(now + 24 * 60 * 60 * 1000).toISOString();

  return json(res, 200, {
    isSubscribed: true,
    mp: {
      status: "authorized",
      preapprovalId: `pre_${userId}`,
      amount: 3.99,
      currency: "PEN",
      frequency: 1,
      frequencyType: "months"
    },
    billing: {
      lastPaymentId: `pay_${userId}`,
      lastPaymentDate,
      nextChargeDate
    },
    subscriptionUpdatedAt: now
  });
};
