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

const TABLE_NAME = process.env.STORAGE_PHONANCEDYNAMO_NAME || process.env.TABLE_NAME;
const REGION = process.env.AWS_REGION || "us-east-1";
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};
// index.js (Node 18+)
exports.handler = async (event) => {
  const body = JSON.parse(event.body || "{}");

  const accessToken = process.env.MP_ACCESS_TOKEN; // del VENDEDOR
  if (!accessToken) {
    return { statusCode: 500, body: "MP_ACCESS_TOKEN missing" };
  }

  const preference = {
        "reason": "Phonance",
        "external_reference": body.order_id,
        "payer_email": "test_user_2615456274316828665@testuser.com",
        "auto_recurring": {
          "frequency": 1,
          "frequency_type": "months",
          "transaction_amount": 3.99,
          "currency_id": "PEN"
      },
    "back_url": process.env.SUCCESS_URL,
    "status": "pending",
  };

  console.log("Enviando a MP:", JSON.stringify(preference));

  const mpRes = await fetch("https://api.mercadopago.com/preapproval", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(preference),
  });

  const data = await mpRes.json();
  console.log(mpRes)

  if (!mpRes.ok) {
    return {
      statusCode: mpRes.status,
      body: JSON.stringify({ error: data }),
    };
  }

  // Para sandbox, revisa si data.sandbox_init_point viene presente en tu cuenta/config.
  const checkoutUrl = data.init_point ?? data.sandbox_init_point;

  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      preference_id: data.id,
      checkout_url: checkoutUrl,
    }),
  };
};
