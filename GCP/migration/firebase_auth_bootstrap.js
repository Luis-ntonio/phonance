const admin = require("firebase-admin");
const { Firestore } = require("@google-cloud/firestore");

function getArg(name, fallback = null) {
  const prefix = `--${name}=`;
  const found = process.argv.find((value) => value.startsWith(prefix));
  if (!found) return fallback;
  return found.slice(prefix.length);
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function randomPassword() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
  let out = "";
  for (let i = 0; i < 16; i += 1) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

function toEmail(value) {
  const email = String(value || "").trim().toLowerCase();
  return email.includes("@") ? email : null;
}

async function main() {
  const projectId = getArg("gcp-project-id", process.env.GOOGLE_CLOUD_PROJECT || null);
  const keyFile = getArg("gcp-key-file", process.env.GOOGLE_APPLICATION_CREDENTIALS || null);
  const firestoreProjectId = getArg("firestore-project-id", projectId);
  const firestoreKeyFile = getArg("firestore-key-file", keyFile);
  const authProjectId = getArg("auth-project-id", projectId);
  const authKeyFile = getArg("auth-key-file", keyFile);
  const firestoreDb = getArg("firestore-db", process.env.FIRESTORE_DATABASE_ID || "(default)");
  const usersCollection = getArg("users-collection", "users");
  const dryRun = hasFlag("dry-run");
  const sendResetEmails = hasFlag("send-reset-emails");

  if (!projectId && (!authProjectId || !firestoreProjectId)) {
    console.error("Falta projectId. Usa --gcp-project-id=<PROJECT_ID> o define --firestore-project-id y --auth-project-id.");
    process.exit(1);
  }

  if (authKeyFile) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = authKeyFile;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: authProjectId,
  });

  const firestore = new Firestore({
    projectId: firestoreProjectId,
    ...(firestoreKeyFile ? { keyFilename: firestoreKeyFile } : {}),
    databaseId: firestoreDb,
    preferRest: true,
  });

  console.log("== Firebase Auth bootstrap start ==");
  console.log({
    authProjectId,
    firestoreProjectId,
    firestoreDb,
    usersCollection,
    dryRun,
    sendResetEmails,
  });

  const usersSnapshot = await firestore.collection(usersCollection).get();
  let created = 0;
  let updated = 0;
  let skipped = 0;
  let resetSent = 0;

  for (const doc of usersSnapshot.docs) {
    const data = doc.data() || {};
    const uid = String(doc.id || data.username || "").trim();
    const email = toEmail(data.email);

    if (!uid || !email) {
      skipped += 1;
      continue;
    }

    const payload = {
      uid,
      email,
      displayName: String(data.name || "").trim() || undefined,
      emailVerified: data.emailVerified === true,
      disabled: false,
    };

    if (dryRun) {
      continue;
    }

    try {
      await admin.auth().getUser(uid);
      await admin.auth().updateUser(uid, payload);
      updated += 1;
    } catch (error) {
      if (error?.code === "auth/user-not-found") {
        await admin.auth().createUser({
          ...payload,
          password: randomPassword(),
        });
        created += 1;
      } else {
        throw error;
      }
    }

    if (sendResetEmails) {
      try {
        await admin.auth().generatePasswordResetLink(email);
        resetSent += 1;
      } catch (error) {
        console.warn(`No se pudo generar reset link para ${email}:`, error?.message || error);
      }
    }
  }

  console.log("== Firebase Auth bootstrap done ==");
  console.log({
    totalFirestoreUsers: usersSnapshot.size,
    created,
    updated,
    skipped,
    resetSent,
    dryRun,
  });
}

main().catch((error) => {
  console.error("Bootstrap failed:", error);
  process.exit(1);
});
