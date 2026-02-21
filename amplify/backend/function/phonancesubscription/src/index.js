/* Amplify Params - DO NOT EDIT
	ENV
	REGION
	STORAGE_PHONANCEDYNAMO_ARN
	STORAGE_PHONANCEDYNAMO_NAME
	STORAGE_PHONANCEDYNAMO_STREAMARN
Amplify Params - DO NOT EDIT */

/**
 * @type {import('@types/aws-lambda').APIGatewayProxyHandler}
 */
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");

const axios = require('axios');
const crypto = require('crypto'); // Necesario para la validación criptográfica


const EXPENSES_TABLE =
  process.env.STORAGE_PHONANCEEXPENSES_NAME || process.env.EXPENSES_TABLE;
const STORAGE_PHONANCEDYNAMO_NAME = process.env.STORAGE_PHONANCEDYNAMO_NAME;
const TABLE_NAME = process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION || "us-east-1";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

function json(statusCode, body) {
  return { statusCode, headers: corsHeaders, body: JSON.stringify(body ?? {}) };
}

function getUserId(event) {
  // Si usas Cognito User Pools authorizer:
  const claims = event?.requestContext?.authorizer?.claims;
  const sub = claims?.sub;
  if (sub) return sub;

  // Si usas AWS_IAM + Identity Pool:
  const identityId = event?.requestContext?.identity?.cognitoIdentityId;
  if (identityId) return identityId;

  return null;
}

function pad13(ms) {
  const s = String(ms ?? "");
  return s.padStart(13, "0");
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers: corsHeaders, body: "" };
    }

    const claims = event?.requestContext?.authorizer?.claims;
    const userId = getUserId(event);
    if (!userId) return json(401, { message: "Unauthorized" });

    const path = (event.path || "/").toLowerCase();

    switch (event.httpMethod) {
      case "GET":
        if (path.endsWith("/subscription")) return getSubscription(userId);
        if (path.endsWith("/subscription/summary")) return getSubscriptionSummary(userId);
        break;

      case "POST":
        if (path.endsWith("/subscription/cancel")) return cancelSubscription(userId);
        break;

      case "PUT":
        if (path.endsWith("/subscription")) {
            const payload = parseJson(event.body);
            if (!payload) return json(400, { message: "Invalid JSON body." });
            return putSubscription(userId, payload);
        }
        break;
    }

    return json(404, { message: "Not Found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return json(500, { message: "Internal Server Error", error: String(err) });
  }
};

// GET /subscription
async function getSubscription(userId) {
  try {
    const res = await ddb.send(new GetCommand({
      TableName: STORAGE_PHONANCEDYNAMO_NAME,
      Key: { username: userId }
    }));

    const item = res.Item ?? {};
    return json(200, {
      isSubscribed: Boolean(item.isSubscribed),
      subscriptionUpdatedAt: item.subscriptionUpdatedAt ?? null,
    });
  } catch (err) {
    console.error("DynamoDB getSubscription error:", err);
    return json(500, { message: "Error reading subscription." });
  }
}

// PUT /subscription
// body: { isSubscribed: true/false }
async function putSubscription(userId, payload) {
  const isSubscribed = payload.isSubscribed === true;
  const now = Date.now();

  try {
    await ddb.send(new UpdateCommand({
      TableName: STORAGE_PHONANCEDYNAMO_NAME,
      Key: { username: userId },
      UpdateExpression: "SET isSubscribed = :s, subscriptionUpdatedAt = :t",
      ExpressionAttributeValues: {
        ":s": isSubscribed,
        ":t": now,
      }
    }));

    return json(200, { isSubscribed, subscriptionUpdatedAt: now });
  } catch (err) {
    console.error("DynamoDB putSubscription error:", err);
    return json(500, { message: "Error writing subscription." });
  }
}


const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN;

function addMonthsISO(dateIso, months) {
  const d = new Date(dateIso);
  const day = d.getDate();
  d.setMonth(d.getMonth() + months);

  // Manejo simple de meses con menos días (ej 31 -> 30/28)
  if (d.getDate() < day) d.setDate(0);
  return d.toISOString();
}

async function getLatestPreapprovalByExternalRef(userId) {
  const url =
    "https://api.mercadopago.com/preapproval/search" +
    `?external_reference=${encodeURIComponent(userId)}` +
    "&sort=date_created:desc&limit=1";

  const res = await axios.get(url, {
    headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
  });

  return (res.data?.results ?? [])[0] ?? null;
}

async function getLastApprovedPaymentByExternalRef(userId) {
  // payments search: últimos 12 meses, filtrable
  // usamos sort desc para quedarnos con el más reciente
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

// GET /subscription/summary
async function getSubscriptionSummary(userId) {
  if (!MP_ACCESS_TOKEN) return json(500, { message: "MP_ACCESS_TOKEN missing" });

  try {
    const preapproval = await getLatestPreapprovalByExternalRef(userId);

    const mpStatus = preapproval?.status ?? "unknown";
    const preapprovalId = preapproval?.id ?? null;

    const ar = preapproval?.auto_recurring ?? {};
    const amount = ar.transaction_amount ?? null;
    const currency = ar.currency_id ?? null;
    const frequency = ar.frequency ?? null;
    const frequencyType = ar.frequency_type ?? null;

    // último pago real (si existe)
    const lastPayment = await getLastApprovedPaymentByExternalRef(userId);
    const lastPaymentDate = lastPayment?.date_created ?? null;
    const lastPaymentId = lastPayment?.id ?? null;

    // próximo cobro estimado: último pago + frecuencia (si sabemos)
    let nextChargeDate = null;
    if (lastPaymentDate && frequency && frequencyType === "months") {
      nextChargeDate = addMonthsISO(lastPaymentDate, Number(frequency));
    }

    // activa si MP dice authorized
    const isSubscribed = mpStatus === "authorized";

    // cache en Dynamo (opcional pero útil)
    const now = Date.now();
    await ddb.send(new UpdateCommand({
      TableName: STORAGE_PHONANCEDYNAMO_NAME,
      Key: { username: userId },
      UpdateExpression:
        "SET isSubscribed = :s, subscriptionUpdatedAt = :t, mpSubscriptionStatus = :ms, mpPreapprovalId = :pid",
      ExpressionAttributeValues: {
        ":s": isSubscribed,
        ":t": now,
        ":ms": mpStatus,
        ":pid": preapprovalId,
      }
    }));

    return json(200, {
      isSubscribed,
      mp: {
        status: mpStatus,
        preapprovalId,
        amount,
        currency,
        frequency,
        frequencyType,
      },
      billing: {
        lastPaymentId,
        lastPaymentDate,
        nextChargeDate,
      },
      subscriptionUpdatedAt: now,
    });
  } catch (err) {
    console.error("getSubscriptionSummary error:", err?.response?.status, err?.response?.data || err);
    return json(502, { message: "Failed to get subscription summary" });
  }
}

// POST /subscription/cancel
async function cancelSubscription(userId) {
  if (!MP_ACCESS_TOKEN) return json(500, { message: "MP_ACCESS_TOKEN missing" });

  try {
    const preapproval = await getLatestPreapprovalByExternalRef(userId);
    const preapprovalId = preapproval?.id;
    if (!preapprovalId) {
      return json(404, { message: "No subscription found to cancel" });
    }

    // Cancelación: PUT /preapproval/{id} status=cancelled :contentReference[oaicite:2]{index=2}
    const url = `https://api.mercadopago.com/preapproval/${preapprovalId}`;
    const mpRes = await axios.put(url, { status: "cancelled" }, {
      headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` },
    });

    const mpStatus = mpRes.data?.status ?? "cancelled";

    // Refleja en Dynamo
    const now = Date.now();
    await ddb.send(new UpdateCommand({
      TableName: STORAGE_PHONANCEDYNAMO_NAME,
      Key: { username: userId },
      UpdateExpression:
        "SET isSubscribed = :s, subscriptionUpdatedAt = :t, mpSubscriptionStatus = :ms, mpPreapprovalId = :pid",
      ExpressionAttributeValues: {
        ":s": false,
        ":t": now,
        ":ms": mpStatus,
        ":pid": preapprovalId,
      }
    }));

    return json(200, {
      cancelled: true,
      mp: { status: mpStatus, preapprovalId },
      subscriptionUpdatedAt: now,
    });
  } catch (err) {
    console.error("cancelSubscription error:", err?.response?.status, err?.response?.data || err);
    return json(502, { message: "Failed to cancel subscription" });
  }
}
