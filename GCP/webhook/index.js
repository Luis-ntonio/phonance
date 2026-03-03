const receivedEvents = [];

function json(res, status, body) {
  res.status(status).set({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id",
    "Content-Type": "application/json"
  }).send(JSON.stringify(body ?? {}));
}

exports.handler = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(204).set({
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-User-Id"
    }).send("");
  }

  if (req.path !== "/webhook") return json(res, 404, { message: "Not Found" });
  if (req.method !== "POST") return json(res, 405, { message: "Method not allowed" });

  const event = {
    id: req.body?.data?.id || req.body?.id || `evt_${Date.now()}`,
    type: req.body?.type || req.body?.topic || "unknown",
    payload: req.body || {},
    receivedAt: new Date().toISOString()
  };

  receivedEvents.push(event);

  return json(res, 200, {
    received: true,
    processed: true,
    eventId: event.id,
    type: event.type
  });
};
