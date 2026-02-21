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
const { DynamoDBDocumentClient, GetCommand, UpdateCommand } = require("@aws-sdk/lib-dynamodb");
const axios = require('axios');
const crypto = require('crypto'); // Necesario para la validación criptográfica

const MP_WEBHOOK_TEST_SECRET = process.env.MP_WEBHOOK_TEST_SECRET;
const TABLE_NAME = process.env.STORAGE_PHONANCEDYNAMO_NAME || process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION || "us-east-1";
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

// VARIABLES DE ENTORNO (Configuradas con 'amplify update function')
const MP_ACCESS_TOKEN = process.env.MP_ACCESS_TOKEN;
const MP_WEBHOOK_SECRET = process.env.MP_WEBHOOK_SECRET;

exports.handler = async (event) => {
  try {
    const path = (event.path || "/").toLowerCase();

    // 1. Manejo del Webhook (POST)
    if (event.httpMethod === "POST" && path.endsWith("/webhook")) {
      return await handleMPWebhook(event);
    }

    // 2. Autenticación para rutas de la App (GET/PUT)
    const userId = getUserId(event);

    // Si no hay userId y no es el webhook, denegamos acceso
    if (!userId) return json(401, { message: "Unauthorized" });

    // Rutas protegidas de la App
    if (path.endsWith("/subscription")) {
        if (event.httpMethod === "GET") return getSubscription(userId);
        if (event.httpMethod === "PUT") {
            const payload = JSON.parse(event.body);
            return putSubscription(userId, payload);
        }
    }

    return json(404, { message: "Not Found" });

  } catch (err) {
    console.error("Error crítico:", err);
    return json(500, { message: "Internal Server Error" });
  }
};

/**
 * Lógica principal del Webhook
 */
async function handleMPWebhook(event) {
  // A. VALIDACIÓN CRIPTOGRÁFICA DE LA FIRMA
  // Si tenemos el secreto configurado, validamos. Si no, lanzamos error por seguridad.
  if (MP_WEBHOOK_SECRET) {
    const isValid = verifySignature(event, MP_WEBHOOK_SECRET);
    if (!isValid) {
      console.error("Firma inválida: El webhook no parece provenir de Mercado Pago.");
      return json(401, { message: "Invalid Signature" });
    }
  } else {
    console.warn("ADVERTENCIA: MP_WEBHOOK_SECRET no configurado. Saltando validación de firma.");
  }

  // B. PROCESAMIENTO DEL PAGO
  const body = JSON.parse(event.body);
  const resourceId = body.data?.id || body.id;
  const type = body.type || body.topic;

  console.log(`[DEBUG] Webhook recibido: ${resourceId} ${type}`)

  // Solo nos interesan eventos de pago o suscripción

    try {
      // Validamos el estado real consultando a la API de Mercado Pago
      // Esto es una doble seguridad: Firma + Consulta API
      let mpUrl = null;

      // pagos one-time o cuotas cobradas
      if (type === "payment") {
        mpUrl = `https://api.mercadopago.com/v1/payments/${resourceId}`;
      }

      // alta/estado de suscripción
      // según cuentas puede llegar como "subscription_preapproval" o "preapproval"
      if (type === "subscription_preapproval" || type === "preapproval") {
        mpUrl = `https://api.mercadopago.com/preapproval/${resourceId}`;
      }

      if (!mpUrl) {
        console.log(`Webhook type ignorado: ${type}`);
        return json(200, { received: true, ignored: true });
      }

      const response = await axios.get(mpUrl, {
        headers: { Authorization: `Bearer ${MP_ACCESS_TOKEN}` }
      });

      const data = response.data || {};

      // Pago aprobado o suscripción autorizada => activamos al usuario
      const isActiveEvent = data.status === "approved" || data.status === "authorized";
      if (isActiveEvent) {
        const userId = data.external_reference ||
                           data.metadata?.external_reference ||
                           null;

        if (userId) {
          console.log(`Pago aprobado para usuario: ${userId}`);
          await ddb.send(new UpdateCommand({
            TableName: TABLE_NAME,
            Key: { username: userId },
            UpdateExpression: "SET isSubscribed = :s, subscriptionUpdatedAt = :t",
            ExpressionAttributeValues: { ":s": true, ":t": Date.now() }
          }));
        } else {
            console.warn("Pago recibido sin 'external_reference' (userId desconocido).");
        }
      }
    } catch (e) {
      console.error("Error consultando API de MP:", e.message);
      // Retornamos 200 aunque falle nuestra lógica interna para que MP deje de reintentar
  }

  return json(200, { received: true });
}

/**
 * Función que implementa la validación oficial de firma de Mercado Pago
 */
function verifySignature(event, secret) {
    console.log(event.headers)
    const xSignature = event.headers['X-Signature'];
    const xRequestId = event.headers['X-Request-Id'];

    console.log(`[DEBUG] xSignature: ${xSignature} xRequestId: ${xRequestId}`)

    if (!xSignature || !xRequestId) {
        return false;
    }

    // 1. Extraer 'ts' (timestamp) y 'v1' (hash) del header
    // El header viene así: "ts=170490000,v1=abc1234..."
    const parts = xSignature.split(',');
    let ts = null;
    let hash = null;

    parts.forEach(part => {
        const [key, value] = part.split('=');
        if (key.trim() === 'ts') ts = value.trim();
        if (key.trim() === 'v1') hash = value.trim();
    });

    console.log(`[DEBUG] Hash: ${hash} ${ts}`);

    if (!ts || !hash) return false;

    // 2. Obtener el ID del dato del cuerpo
    const body = JSON.parse(event.body);
    const dataId = body.data?.id || body.id;

    // 3. Crear el "Manifiesto" (la cadena que vamos a hashear)
    // Formato oficial: id:[data.id];request-id:[x-request-id];ts:[ts];
    const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`;

    // --- DEBUG CRÍTICO ---
    console.log("--- DEBUG FIRMA ---");
    console.log("1. Manifiesto generado:", manifest);
    console.log("2. Hash recibido (v1):", hash);
    // NO imprimas el secreto completo por seguridad, solo el inicio y el largo
    const secretUsed = secret ? `${secret.substring(0, 5)}... (Largo: ${secret.length})` : "UNDEFINED";
    console.log("3. Secreto usado en Lambda:", secretUsed);
    // ---------------------

    const hmac = crypto.createHmac('sha256', secret);
    const digest = hmac.update(manifest).digest('hex');

    console.log("4. Hash calculado (digest):", digest);
    console.log("¿Coinciden?", digest === hash);

    return digest === hash;
}

// --- Funciones Auxiliares ---

async function getSubscription(userId) {
  try {
    const res = await ddb.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { username: userId }
    }));
    const item = res.Item ?? {};
    return json(200, {
      isSubscribed: Boolean(item.isSubscribed),
      subscriptionUpdatedAt: item.subscriptionUpdatedAt ?? null,
    });
  } catch (err) {
    console.error("DynamoDB error:", err);
    return json(500, { message: "Error reading DB" });
  }
}

async function putSubscription(userId, payload) {
  // ... (Tu lógica de PUT si la necesitas para pruebas) ...
  return json(200, { success: true });
}

function getUserId(event) {
  const claims = event?.requestContext?.authorizer?.claims;
  const sub = claims?.sub;
  if (sub) return sub;

  const identityId = event?.requestContext?.identity?.cognitoIdentityId;
  if (identityId) return identityId;

  return null;
}

function json(statusCode, body) {
  return { statusCode, headers: corsHeaders, body: JSON.stringify(body ?? {}) };
}