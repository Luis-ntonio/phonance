/* Amplify Params - DO NOT EDIT
	ENV
	REGION
	STORAGE_PHONANCEDYNAMO_ARN
	STORAGE_PHONANCEDYNAMO_NAME
	STORAGE_PHONANCEDYNAMO_STREAMARN
	STORAGE_PHONANCEEXPENSES_ARN
	STORAGE_PHONANCEEXPENSES_NAME
	STORAGE_PHONANCEEXPENSES_STREAMARN
Amplify Params - DO NOT EDIT */

/**
 * @type {import('@types/aws-lambda').APIGatewayProxyHandler}
 */
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, UpdateCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");

const EXPENSES_TABLE =
  process.env.STORAGE_PHONANCEEXPENSES_NAME || process.env.EXPENSES_TABLE;

const TABLE_NAME = process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION || "us-east-1";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,PATCH,OPTIONS",
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
        if (path.endsWith("/profile")) return getProfile(userId);
        if (path.endsWith("/expenses")) {
            console.log("get expenses")
            const qs = event.queryStringParameters || {};
            const fromMs = qs.fromMs ? Number(qs.fromMs) : null;
            const toMs = qs.toMs ? Number(qs.toMs) : null;
            const limit = qs.limit ? Math.min(Number(qs.limit), 2000) : 500;

            const fromSk = fromMs ? `${pad13(fromMs)}#` : "0000000000000#";
            const toSk = toMs ? `${pad13(toMs)}#\uffff` : "9999999999999#\uffff";


            const params = {
                TableName: EXPENSES_TABLE,
                KeyConditionExpression: "userId = :u AND sk BETWEEN :a AND :b",
                ExpressionAttributeValues: {
                  ":u": userId,
                  ":a": fromSk,
                  ":b": toSk,
                },
                ScanIndexForward: false, // descendente (del más nuevo al más antiguo)
                Limit: limit,
              };

            const res = await ddb.send(new QueryCommand(params));


            return json(200, { items: res.Items || [] });
          }
            break;

      case "POST":
        if (path.endsWith("/profile")) {
          const payload = parseJson(event.body);
          if (!payload) return json(400, { message: "Invalid JSON body." });
          return postProfile(userId, payload);
        }
        if (path.endsWith("/expenses")) {
        console.log("pago recibido")
        try {
          const payload = event.body ? JSON.parse(event.body) : null;
          if (!payload) return json(400, { message: "Invalid JSON body" });

          const timestampMs = Number(payload.timestampMs);
          const dedupeKey = String(payload.dedupeKey || "");
          if (!Number.isFinite(timestampMs) || !dedupeKey) {
            return json(400, { message: "Missing timestampMs or dedupeKey" });
          }

          const sk = `${pad13(timestampMs)}#${dedupeKey}`;

          const item = {
            userId,
            sk,
            timestampMs,
            amount: payload.amount ?? null,
            currency: payload.currency ?? null,
            merchant: payload.merchant ?? null,
            category: payload.category ?? null,
            rawText: payload.rawText ?? null,
            sourcePackage: payload.sourcePackage ?? null,
            dedupeKey,
            createdAt: Date.now(),
          };

          await ddb.send(new PutCommand({
            TableName: EXPENSES_TABLE,
            Item: item,
            ConditionExpression: "attribute_not_exists(sk)", // Solo verifica que no exista este sk específico (dedupeKey)
          }));

          return json(201, item);
        } catch (err) {
          // Si el error es ConditionalCheckFailedException, significa que el gasto ya existe (duplicado)
          if (err?.name === "ConditionalCheckFailedException") {
            console.log("Duplicate expense detected:", err.message);
            return json(409, { message: "Expense already exists (duplicate)." });
          }
          console.error("DynamoDB Post error:", err);
          return json(500, { message: "Error creating expense." });
        }
        }
        break;

      case "PUT":
        if (path.endsWith("/profile")) {
          const payload = parseJson(event.body);
          if (!payload) return json(400, { message: "Invalid JSON body." });
          return putProfile(userId, payload);
        }
        break;

      case "PATCH":
        if (path.endsWith("/expenses")) {
          const payload = parseJson(event.body);
          if (!payload) return json(400, { message: "Invalid JSON body." });
          return patchExpense(userId, payload);
        }
        break;
    }

    return json(404, { message: "Not Found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return json(500, { message: "Internal Server Error", error: String(err) });
  }
};

async function getProfile(userId) {
  try {
    const res = await ddb.send(new GetCommand({ TableName: TABLE_NAME, Key: { username: userId } }));
    if (!res.Item) return json(404, { message: "Profile not found." });
    return json(200, res.Item);
  } catch (err) {
    console.error("DynamoDB Get error:", err);
    return json(500, { message: "Error reading profile." });
  }
}

async function postProfile(userId, payload) {
  const email = stringOrEmpty(payload.email);
  const name = stringOrEmpty(payload.name);
  if (!email || !name) return json(400, { message: "Missing required fields: email and name." });

  const now = Date.now();
  const item = {
    username: userId,
    phoneNumber: payload.phoneNumber,
    email,
    name,
    preferredCurrency: stringOrEmpty(payload.preferredCurrency ?? "PEN"),
    savingsGoal: numberOrZero(payload.savingsGoal),
    monthlyIncome: numberOrZero(payload.monthlyIncome),
    spendingLimit: numberOrZero(payload.spendingLimit),
    isSubscribed: payload.isSubscribed ?? false,
    subscriptionUpdatedAt: payload.subscriptionUpdatedAt ?? 0,
    createdAt: now,
    updatedAt: now,
  };

  try {
    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: item,
        ConditionExpression: "attribute_not_exists(userId)",
      })
    );
    return json(201, item);
  } catch (err) {
    if (err?.name === "ConditionalCheckFailedException") {
      return json(409, { message: "Profile already exists." });
    }
    console.error("DynamoDB Post error:", err);
    return json(500, { message: "Error creating profile." });
  }
}

async function putProfile(userId, payload) {
  const now = Date.now();
  const item = {
    username: userId,
    phoneNumber: payload.phoneNumber,
    email: stringOrEmpty(payload.email),
    name: stringOrEmpty(payload.name),
    preferredCurrency: stringOrEmpty(payload.preferredCurrency ?? "PEN"),
    savingsGoal: numberOrZero(payload.savingsGoal),
    monthlyIncome: numberOrZero(payload.monthlyIncome),
    spendingLimit: numberOrZero(payload.spendingLimit),
    isSubscribed: payload.isSubscribed ?? false,
    subscriptionUpdatedAt: payload.subscriptionUpdatedAt ?? 0,
    updatedAt: now,
    createdAt: payload.createdAt ?? now,
  };

  try {
    await ddb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
    return json(200, item);
  } catch (err) {
    console.error("DynamoDB Put error:", err);
    return json(500, { message: "Error writing profile." });
  }
}

function parseJson(body) {
  try {
    return body ? JSON.parse(body) : null;
  } catch {
    return null;
  }
}

function json(statusCode, obj) {
  return { statusCode, headers: corsHeaders, body: JSON.stringify(obj ?? {}) };
}

function stringOrEmpty(v) {
  return typeof v === "string" && v.trim().length > 0 ? v.trim() : "";
}
function numberOrZero(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

async function patchExpense(userId, payload) {
  try {
    const dedupeKey = String(payload.dedupeKey || "");
    const timestampMs = Number(payload.timestampMs);
    const category = payload.category ?? null;

    if (!dedupeKey || !Number.isFinite(timestampMs)) {
      return json(400, { message: "Missing dedupeKey or timestampMs" });
    }

    // Construir la sk directamente usando timestampMs + dedupeKey
    const sk = `${pad13(timestampMs)}#${dedupeKey}`;

    console.log(`Attempting to update item with userId=${userId}, sk=${sk}`);

    // Usar UpdateCommand directamente con la sk construida
    const updateParams = {
      TableName: EXPENSES_TABLE,
      Key: {
        userId,
        sk,
      },
      UpdateExpression: "SET category = :cat, updatedAt = :now",
      ExpressionAttributeValues: {
        ":cat": category,
        ":now": Date.now(),
      },
      ReturnValues: "ALL_NEW",
    };

    const updateRes = await ddb.send(new UpdateCommand(updateParams));
    
    console.log("Update successful:", JSON.stringify(updateRes.Attributes));
    return json(200, updateRes.Attributes || {});
  } catch (err) {
    console.error("DynamoDB Patch error:", err);
    return json(500, { message: "Error updating expense", error: String(err) });
  }
}
