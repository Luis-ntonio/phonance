/* Amplify Params - DO NOT EDIT
	ENV
	REGION
	STORAGE_PHONANCEDYNAMO_ARN
	STORAGE_PHONANCEDYNAMO_NAME
	STORAGE_PHONANCEDYNAMO_STREAMARN
Amplify Params - DO NOT EDIT *//* Amplify Params - DO NOT EDIT
  ENV
  REGION
  STORAGE_PHONANCEDYNAMO_ARN
  STORAGE_PHONANCEDYNAMO_NAME
  STORAGE_PHONANCEDYNAMO_STREAMARN
Amplify Params - DO NOT EDIT */

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const axios = require("axios");

/**
 * Config
 */
const TABLE_NAME = process.env.STORAGE_PHONANCEDYNAMO_NAME || process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION || "us-east-1";
const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN;

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

exports.handler = async (event) => {
  try {
    // Preflight
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers: corsHeaders, body: "" };
    }

    const path = (event.path || "/").toLowerCase();

    // Endpoint: POST /subscription/refresh
    if (event.httpMethod === "POST" && path.endsWith("/subscription/refresh")) {
      const userId = getUserId(event);
      if (!userId) return json(401, { message: "Unauthorized" });

      if (!MP_ACCESS_TOKEN) return json(500, { message: "MP_ACCESS_TOKEN missing" });
      if (!TABLE_NAME) return json(500, { message: "TABLE_NAME missing" });

      // 1) Buscar la suscripción más reciente por external_reference=userId
      const searchUrl =
        `https://api.mercadopago.com/preapproval/search` +
        `?external_reference=${encodeURIComponent(userId)}` +
        `&sort=date_created:desc&limit=1`;

      const mpRes = await axios.get(searchUrl, {
        headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
      });

      const results = mpRes.data?.results ?? [];
      const latest = results[0] ?? null;

      // 2) Determinar estado
      // status típicos: authorized (activa), pending, cancelled, paused
      const status = latest?.status ?? null;

      const lastPayment = await getLastApprovedPaymentByExternalRef(userId);
      const hasApprovedPayment = Boolean(lastPayment?.id);

      const isSubscribed = status === "authorized" && hasApprovedPayment;

      // 3) Persistir en Dynamo (cache/estado local)
      const now = Date.now();
      await ddb.send(
        new UpdateCommand({
          TableName: TABLE_NAME,
          Key: { username: userId },
          UpdateExpression:
            "SET isSubscribed = :s, subscriptionUpdatedAt = :t, mpSubscriptionStatus = :ms, mpPreapprovalId = :pid",
          ExpressionAttributeValues: {
            ":s": isSubscribed,
            ":t": now,
            ":ms": status ?? "unknown",
            ":pid": latest?.id ?? null,
          },
        })
      );

      return json(200, {
        isSubscribed,
        subscriptionUpdatedAt: now,
        mp: {
          status: status ?? "unknown",
          preapprovalId: latest?.id ?? null,
          lastPaymentId: lastPayment?.id ?? null,
          lastPaymentDate: lastPayment?.date_created ?? null,
        },
      });
    }

    return json(404, { message: "Not Found" });
  } catch (err) {
    // Log detallado para depurar (sin filtrar tokens)
    console.error("refresh endpoint error:", err?.response?.status, err?.response?.data || err);
    return json(500, { message: "Internal Server Error" });
  }
};

async function getLastApprovedPaymentByExternalRef(userId) {
  const url =
    "https://api.mercadopago.com/v1/payments/search" +
    `?external_reference=${encodeURIComponent(userId)}` +
    "&status=approved" +
    "&sort=date_created&criteria=desc&limit=1";

  const res = await axios.get(url, {
    headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
  });

  return (res.data?.results ?? [])[0] ?? null;
}

function getUserId(event) {
  // Cognito authorizer (Amplify suele poner claims aquí)
  const claims = event?.requestContext?.authorizer?.claims;
  const sub = claims?.sub;
  if (sub) return sub;

  // fallback (si usas identity pool)
  const identityId = event?.requestContext?.identity?.cognitoIdentityId;
  if (identityId) return identityId;

  return null;
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", ...corsHeaders },
    body: JSON.stringify(body ?? {}),
  };
}

