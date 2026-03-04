function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
    "Content-Type": "application/json"
  }).send(JSON.stringify(body ?? {}));
}

const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN || "";

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
  try {
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
    if (!MP_ACCESS_TOKEN) return json(res, 500, { message: "MP_ACCESS_TOKEN missing" });

    const orderId = String(req.body?.order_id || userId);
    const successUrl = process.env.SUCCESS_URL || "https://example.com/success";

    const preference = {
      reason: "Phonance",
      external_reference: orderId,
      payer_email: "test_user_2615456274316828665@testuser.com",
      auto_recurring: {
        frequency: 1,
        frequency_type: "months",
        transaction_amount: 3.99,
        currency_id: "PEN",
      },
      back_url: successUrl,
      status: "pending",
    };

    const mpRes = await fetch("https://api.mercadopago.com/preapproval", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${MP_ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(preference),
    });

    const data = await safeJson(mpRes);
    if (!mpRes.ok) {
      console.error("getMPlink mp error", mpRes.status, data);
      return json(res, mpRes.status, { error: data });
    }

    return json(res, 200, {
      preference_id: data?.id ?? null,
      checkout_url: data?.init_point ?? data?.sandbox_init_point ?? null,
    });
  } catch (error) {
    console.error("getMPlink error", error);
    return json(res, 500, { message: "Internal Server Error" });
  }
};

async function safeJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}
