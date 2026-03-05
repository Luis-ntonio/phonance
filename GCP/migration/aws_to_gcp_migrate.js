/*
  Migración AWS DynamoDB -> Firestore (GCP)

  Tablas esperadas:
  - users table (perfil): pk=username
  - expenses table: pk=userId, sk=timestamp#dedupeKey

  Firestore destino:
  - DB users: collection users, docId=<userId>
  - DB expenses: collection expenses, docId=<userId>_<timestampMs>_<dedupeKey>
*/

const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, ScanCommand } = require("@aws-sdk/lib-dynamodb");
const { Firestore } = require("@google-cloud/firestore");
const fs = require("fs");

function getArg(name, fallback = null) {
  const prefix = `--${name}=`;
  const found = process.argv.find((value) => value.startsWith(prefix));
  if (!found) return fallback;
  return found.slice(prefix.length);
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function loadJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

function normalizeServiceAccountCredentials(credentials) {
  if (!credentials || credentials.type !== "service_account") return null;

  const privateKey = credentials.private_key;
  if (typeof privateKey !== "string" || privateKey.length === 0) {
    throw new Error("Invalid service account JSON: private_key missing or invalid");
  }

  return {
    client_email: credentials.client_email,
    private_key: privateKey.includes("\\n") ? privateKey.replace(/\\n/g, "\n") : privateKey,
  };
}

function chunk(array, size) {
  const result = [];
  for (let index = 0; index < array.length; index += size) {
    result.push(array.slice(index, index + size));
  }
  return result;
}

function toNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizeUserItem(item) {
  const userId = String(item?.username || "").trim();
  if (!userId) return null;

  return {
    userId,
    doc: {
      username: userId,
      name: String(item?.name ?? ""),
      email: String(item?.email ?? ""),
      phoneNumber: String(item?.phoneNumber ?? ""),
      preferredCurrency: String(item?.preferredCurrency ?? "PEN"),
      savingsGoal: toNumber(item?.savingsGoal, 0),
      monthlyIncome: toNumber(item?.monthlyIncome, 0),
      spendingLimit: toNumber(item?.spendingLimit, 0),
      isSubscribed: item?.isSubscribed === true,
      subscriptionUpdatedAt: toNumber(item?.subscriptionUpdatedAt, 0),
      mpStatus: item?.mpStatus ?? item?.mpSubscriptionStatus ?? null,
      mpSubscriptionStatus: item?.mpSubscriptionStatus ?? item?.mpStatus ?? null,
      mpPreapprovalId: item?.mpPreapprovalId ?? null,
      lastPaymentId: item?.lastPaymentId ?? null,
      lastPaymentDate: item?.lastPaymentDate ?? null,
      createdAt: item?.createdAt ?? null,
      updatedAt: item?.updatedAt ?? null,
      migratedFrom: "aws-dynamodb",
      migratedAt: Date.now(),
    },
  };
}

function normalizeExpenseItem(item) {
  const userId = String(item?.userId || "").trim();
  const dedupeKey = String(item?.dedupeKey || "").trim();
  const timestampMs = toNumber(item?.timestampMs, NaN);

  if (!userId || !dedupeKey || !Number.isFinite(timestampMs)) return null;

  const docId = `${userId}_${timestampMs}_${dedupeKey}`;
  return {
    docId,
    doc: {
      userId,
      sk: item?.sk ?? `${String(timestampMs).padStart(13, "0")}#${dedupeKey}`,
      timestampMs,
      dedupeKey,
      amount: item?.amount ?? null,
      currency: item?.currency ?? null,
      merchant: item?.merchant ?? null,
      category: item?.category ?? null,
      rawText: item?.rawText ?? null,
      sourcePackage: item?.sourcePackage ?? null,
      createdAt: item?.createdAt ?? null,
      updatedAt: item?.updatedAt ?? null,
      migratedFrom: "aws-dynamodb",
      migratedAt: Date.now(),
    },
  };
}

async function scanAll(ddb, tableName) {
  const all = [];
  let exclusiveStartKey;

  do {
    const response = await ddb.send(
      new ScanCommand({
        TableName: tableName,
        ExclusiveStartKey: exclusiveStartKey,
      })
    );

    const items = response.Items || [];
    all.push(...items);
    exclusiveStartKey = response.LastEvaluatedKey;
  } while (exclusiveStartKey);

  return all;
}

async function writeBatched(firestore, collectionName, rows, dryRun) {
  if (rows.length === 0) return;
  if (dryRun) return;

  const batches = chunk(rows, 400);
  for (const group of batches) {
    const batch = firestore.batch();
    for (const row of group) {
      const ref = firestore.collection(collectionName).doc(row.docId);
      batch.set(ref, row.doc, { merge: true });
    }
    await batch.commit();
  }
}

async function main() {
  const awsRegion = getArg("aws-region", process.env.AWS_REGION || "us-east-1");
  const awsProfile = getArg("aws-profile", process.env.AWS_PROFILE || null);
  const awsAccessKeyId = getArg("aws-access-key-id", process.env.AWS_ACCESS_KEY_ID || null);
  const awsSecretAccessKey = getArg("aws-secret-access-key", process.env.AWS_SECRET_ACCESS_KEY || null);
  const awsSessionToken = getArg("aws-session-token", process.env.AWS_SESSION_TOKEN || null);
  const usersTable = getArg("users-table", process.env.AWS_USERS_TABLE || process.env.STORAGE_PHONANCEDYNAMO_NAME);
  const expensesTable = getArg("expenses-table", process.env.AWS_EXPENSES_TABLE || process.env.STORAGE_PHONANCEEXPENSES_NAME);
  const firestoreDb = getArg("firestore-db", process.env.FIRESTORE_DATABASE_ID || null);
  const usersDbId = getArg("users-db", process.env.USERS_FIRESTORE_DB || firestoreDb || "(default)");
  const expensesDbId = getArg("expenses-db", process.env.EXPENSES_FIRESTORE_DB || firestoreDb || "(default)");
  const gcpProjectId =
    getArg("gcp-project-id", process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || null);
  const gcpKeyFile = getArg("gcp-key-file", process.env.GOOGLE_APPLICATION_CREDENTIALS || null);
  const gcpCredentialsJson = getArg("gcp-credentials-json", process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON || null);
  const useGrpc = hasFlag("use-grpc");
  const dryRun = hasFlag("dry-run");

  if (awsProfile) {
    process.env.AWS_PROFILE = awsProfile;
    process.env.AWS_SDK_LOAD_CONFIG = process.env.AWS_SDK_LOAD_CONFIG || "1";
  }

  const explicitCredentials =
    awsAccessKeyId && awsSecretAccessKey
      ? {
          accessKeyId: awsAccessKeyId,
          secretAccessKey: awsSecretAccessKey,
          ...(awsSessionToken ? { sessionToken: awsSessionToken } : {}),
        }
      : undefined;

  if (!usersTable || !expensesTable) {
    console.error("Faltan tablas DynamoDB. Usa --users-table=... y --expenses-table=...");
    process.exit(1);
  }

  if (gcpProjectId) {
    process.env.GOOGLE_CLOUD_PROJECT = gcpProjectId;
  }
  if (gcpKeyFile) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = gcpKeyFile;
  }

  let loadedCredentials = null;
  if (gcpCredentialsJson) {
    loadedCredentials = JSON.parse(gcpCredentialsJson);
  } else if (gcpKeyFile && fs.existsSync(gcpKeyFile)) {
    loadedCredentials = loadJsonFile(gcpKeyFile);
  }

  const serviceAccountCredentials = normalizeServiceAccountCredentials(loadedCredentials);

  console.log("== AWS -> GCP migration start ==");
  console.log({ awsRegion, usersTable, expensesTable, usersDbId, expensesDbId, dryRun });

  const awsClient = new DynamoDBClient({
    region: awsRegion,
    ...(explicitCredentials ? { credentials: explicitCredentials } : {}),
  });
  const ddb = DynamoDBDocumentClient.from(awsClient);

  const firestoreBaseConfig = {
    ...(gcpProjectId ? { projectId: gcpProjectId } : {}),
    ...(gcpKeyFile ? { keyFilename: gcpKeyFile } : {}),
    ...(serviceAccountCredentials ? { credentials: serviceAccountCredentials } : {}),
    preferRest: !useGrpc,
  };

  const usersFs = new Firestore({ ...firestoreBaseConfig, databaseId: usersDbId });
  const expensesFs = new Firestore({ ...firestoreBaseConfig, databaseId: expensesDbId });

  console.log("Scanning users table...");
  const rawUsers = await scanAll(ddb, usersTable);
  const users = rawUsers.map(normalizeUserItem).filter(Boolean);
  console.log(`Users scanned=${rawUsers.length} normalized=${users.length}`);

  const usersRows = users.map((u) => ({ docId: u.userId, doc: u.doc }));
  await writeBatched(usersFs, "users", usersRows, dryRun);
  console.log(`Users ${dryRun ? "to write" : "written"}: ${usersRows.length}`);

  console.log("Scanning expenses table...");
  const rawExpenses = await scanAll(ddb, expensesTable);
  const expenses = rawExpenses.map(normalizeExpenseItem).filter(Boolean);
  console.log(`Expenses scanned=${rawExpenses.length} normalized=${expenses.length}`);

  await writeBatched(expensesFs, "expenses", expenses, dryRun);
  console.log(`Expenses ${dryRun ? "to write" : "written"}: ${expenses.length}`);

  console.log("== AWS -> GCP migration done ==");
}

main().catch((error) => {
  const message = String(error?.message || "");
  if (error?.name === "CredentialsProviderError" || message.includes("Could not load credentials")) {
    console.error("Migration failed: No se encontraron credenciales AWS válidas.");
    console.error("Opciones rápidas (PowerShell):");
    console.error("1) Usar perfil: $env:AWS_PROFILE='default' ; $env:AWS_SDK_LOAD_CONFIG='1'");
    console.error("2) Usar claves: $env:AWS_ACCESS_KEY_ID='...'; $env:AWS_SECRET_ACCESS_KEY='...'; $env:AWS_REGION='us-east-1'");
    console.error("3) O pasar argumentos: --aws-profile=default  (o --aws-access-key-id / --aws-secret-access-key)");
    process.exit(1);
  }

  if (message.includes("Unable to detect a Project Id")) {
    console.error("Migration failed: No se detectó projectId de GCP para Firestore.");
    console.error("Solución rápida (PowerShell):");
    console.error("1) $env:GOOGLE_CLOUD_PROJECT='tu-project-id'");
    console.error("2) $env:GOOGLE_APPLICATION_CREDENTIALS='C:\\ruta\\service-account.json'");
    console.error("3) o pasar args: --gcp-project-id=tu-project-id --gcp-key-file=C:\\ruta\\service-account.json");
    process.exit(1);
  }

  if (message.includes("key must be a string, a buffer or an object")) {
    console.error("Migration failed: credencial GCP inválida para firmar tokens (private_key).\n");
    console.error("Recomendado:");
    console.error("1) Usa un service account JSON real (type=service_account)");
    console.error("2) Pasa args explícitos: --gcp-project-id=<project> --gcp-key-file=C:\\ruta\\sa.json");
    console.error("3) Si usas JSON por env, usa --gcp-credentials-json y valida private_key");
    console.error("4) Reintenta sin gRPC (default ya usa REST). Solo usa --use-grpc si lo necesitas.");
    process.exit(1);
  }

  console.error("Migration failed:", error);
  process.exit(1);
});
