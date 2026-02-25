package com.luis.phonance

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.security.MessageDigest

object ExpensesDbWriter {
    private const val TAG = "PHONANCE_DB"
    private const val DB_NAME = "gpay_expenses.db"

    // Mismo CREATE TABLE que en Flutter (idempotente)
    private const val CREATE_TABLE = """
        CREATE TABLE IF NOT EXISTS expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestampMs INTEGER NOT NULL,
            amount REAL,
            currency TEXT,
            merchant TEXT,
            category TEXT,
            rawText TEXT,
            sourcePackage TEXT,
            dedupeKey TEXT NOT NULL UNIQUE,
            ownerUserId TEXT,
            synced INTEGER NOT NULL DEFAULT 0
        )
    """

    private const val CREATE_IDX_TS = "CREATE INDEX IF NOT EXISTS idx_expenses_ts ON expenses(timestampMs DESC)"
    private const val CREATE_IDX_OWNER = "CREATE INDEX IF NOT EXISTS idx_expenses_owner ON expenses(ownerUserId)"

    private fun dbPath(context: Context): String {
        // Apunta a /data/data/<pkg>/databases/gpay_expenses.db (mismo lugar que sqflite)
        return context.getDatabasePath(DB_NAME).absolutePath
    }

    private fun openOrCreate(context: Context): SQLiteDatabase {
        val path = dbPath(context)
        // Asegura que la carpeta exista
        context.getDatabasePath(DB_NAME).parentFile?.mkdirs()

        val db = SQLiteDatabase.openDatabase(
            path,
            null,
            SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY
        )

        // Asegura schema mínimo
        db.execSQL(CREATE_TABLE)
        db.execSQL(CREATE_IDX_TS)
        db.execSQL(CREATE_IDX_OWNER)

        return db
    }

    fun insertExpense(
        context: Context,
        timestampMs: Long,
        amount: Double?,
        currency: String?,
        merchant: String?,
        category: String?,
        rawText: String,
        sourcePackage: String,
        ownerUserId: String? = null,
        synced: Int?
    ) {
        val db = openOrCreate(context)

        try {
            // Detectar si viene de Gmail
            val isFromGmail = sourcePackage == "com.google.android.gm"
            
            // Si es de Gmail, verificar si ya existe un gasto similar de Google Pay en los últimos 5 min
            if (isFromGmail && existsSimilarFromGPay(db, timestampMs, amount, currency, merchant)) {
                Log.d(TAG, "Duplicate ignored (Gmail skipped: similar GPay transaction within 5 min)")
                return
            }
            
            // Verificar duplicados generales (mismo dedupeKey)
            if (existsSimilar(db, timestampMs, amount, currency, merchant)) {
                Log.d(TAG, "Duplicate ignored (similar expense)")
                return
            }

            val dedupeKey = sha256("$sourcePackage|$timestampMs|${rawText.take(120)}")

            val cv = ContentValues().apply {
                put("timestampMs", timestampMs)
                if (amount != null) put("amount", amount) else putNull("amount")
                if (currency != null) put("currency", currency) else putNull("currency")
                if (merchant != null) put("merchant", merchant) else putNull("merchant")
                if (category != null) put("category", category) else putNull("category")
                put("rawText", rawText)
                put("sourcePackage", sourcePackage)
                put("dedupeKey", dedupeKey)
                if (ownerUserId != null) put("ownerUserId", ownerUserId) else putNull("ownerUserId")
                put("synced", synced)
            }

            // Si dedupeKey ya existe, no insertará (UNIQUE). Eso es ok.
            val rowId = db.insertWithOnConflict("expenses", null, cv, SQLiteDatabase.CONFLICT_IGNORE)

            if (rowId == -1L) {
                Log.d(TAG, "Duplicate ignored (dedupeKey)")
            } else {
                Log.d(TAG, "Inserted expense id=$rowId ts=$timestampMs pkg=$sourcePackage")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Insert failed", e)
        } finally {
            db.close()
        }
    }

    private fun existsSimilar(
        db: SQLiteDatabase,
        timestampMs: Long,
        amount: Double?,
        currency: String?,
        merchant: String?,
        windowMs: Long = 5 * 60 * 1000
    ): Boolean {
        if (amount == null) return false

        val from = timestampMs - windowMs
        val to = timestampMs + windowMs

        val where = StringBuilder("timestampMs BETWEEN ? AND ? AND ABS(amount - ?) < 0.01")
        val args = ArrayList<String>()
        args.add(from.toString())
        args.add(to.toString())
        args.add(amount.toString())

        if (currency == null) {
            where.append(" AND currency IS NULL")
        } else {
            where.append(" AND currency = ?")
            args.add(currency)
        }

        if (merchant == null || merchant.isBlank()) {
            where.append(" AND (merchant IS NULL OR merchant = '')")
        } else {
            where.append(" AND merchant = ?")
            args.add(merchant)
        }

        val cursor = db.query(
            "expenses",
            arrayOf("id"),
            where.toString(),
            args.toTypedArray(),
            null,
            null,
            null,
            "1"
        )

        cursor.use {
            return it.moveToFirst()
        }
    }

    private fun existsSimilarFromGPay(
        db: SQLiteDatabase,
        timestampMs: Long,
        amount: Double?,
        currency: String?,
        merchant: String?,
        windowMs: Long = 5 * 60 * 1000
    ): Boolean {
        if (amount == null) return false

        val from = timestampMs - windowMs
        val to = timestampMs + windowMs

        val where = StringBuilder(
            "timestampMs BETWEEN ? AND ? AND ABS(amount - ?) < 0.01 " +
            "AND sourcePackage = 'com.google.android.apps.walletnfcrel'"
        )
        val args = ArrayList<String>()
        args.add(from.toString())
        args.add(to.toString())
        args.add(amount.toString())

        if (currency == null) {
            where.append(" AND currency IS NULL")
        } else {
            where.append(" AND currency = ?")
            args.add(currency)
        }

        if (merchant == null || merchant.isBlank()) {
            where.append(" AND (merchant IS NULL OR merchant = '')")
        } else {
            where.append(" AND merchant = ?")
            args.add(merchant)
        }

        val cursor = db.query(
            "expenses",
            arrayOf("id"),
            where.toString(),
            args.toTypedArray(),
            null,
            null,
            null,
            "1"
        )

        cursor.use {
            return it.moveToFirst()
        }
    }

    private fun sha256(input: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        val bytes = md.digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
