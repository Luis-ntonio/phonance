package com.luis.phonance

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.os.Bundle

import com.luis.phonance.BuildConfig
import android.util.Log

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch


private const val TAG = "PHONANCE_NL"

private fun log(msg: String) {
    Log.d(TAG, msg)
}

private fun logWarn(msg: String) {
    Log.w(TAG, msg)
}

private fun logErr(msg: String, t: Throwable? = null) {
    if (t != null) Log.e(TAG, msg, t) else Log.e(TAG, msg)
}

private fun isAllowedGmailNotification(
    title: String?,
    text: String?,
    bigText: String?,
    subText: String?
): Boolean {
    // En Gmail normalmente:
    // - title: asunto (a veces remitente)
    // - text: preview (a veces asunto)
    // - subText: cuenta o "Gmail"
    // En algunos teléfonos cambia, por eso combinamos todo.
    val combined = listOfNotNull(title, text, bigText, subText)
        .joinToString("\n") { it.trim() }
        .lowercase()

    log("combined: $combined")

    // Caso 1: BCP
    val isBCP =
        combined.contains("bcp") &&
                (combined.contains("\n" + "operación realizada" + "\n" + "consumo") || combined.contains("\n" + "operación realizada transferencia")) &&
                combined.contains("servicio de notificaciones bcp")

    val isBBVA =
        combined.contains("bbva") &&
                (combined.contains("\n" + "has realizado un consumo") || combined.contains("\n" + "has realizado el siguiente consumo") || combined.contains("\n" + "constancia"))

    // Caso 2: Yape
    val isYape =
        combined.contains("yape notificaciones") &&
                combined.contains("por tu seguridad, te notificaremos por cada yapeo que realices")

    // Caso 3: scotiabank
    val isScotia =
        combined.contains("scotiabank") &&
                combined.contains("constancia de operacion")


    val isLimit = combined.contains("gasto excedido")

    log("isBCP=$isBCP isYape=$isYape isLimit=$isLimit")
    return isBCP || isYape || isBBVA || isScotia
}


class GPayNotificationListener : NotificationListenerService() {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Paquetes comunes. En algunos dispositivos/versions Wallet vs Pay varía.
    private val allowedPackages = setOf(
        "com.google.android.apps.walletnfcrel",  // Google Wallet
        "com.google.android.apps.nbu.paisa.user", // (ejemplos antiguos/regionales)
        "com.google.android.gms",                 // a veces hay intermediación
        "com.google.android.gm" // Gmail
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val pkg = sbn.packageName ?: return
            log("onNotificationPosted() pkg=$pkg id=${sbn.id} postTime=${sbn.postTime}")

            val allowThisPackage =
                allowedPackages.contains(pkg) || (BuildConfig.DEBUG && pkg == applicationContext.packageName)

            // Filtro inicial por paquete (si quieres hacerlo menos estricto, comenta esta parte)
            if (!allowThisPackage) {
                logWarn("Skip: package not allowed -> $pkg (allowed=$allowedPackages)")
                return
            }

            val n: Notification = sbn.notification ?: return
            val extras: Bundle = n.extras ?: return

            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
            val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.toString()

            // Evitar notificaciones agrupadas/summary (ej: "3 new messages")
            if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) {
                logWarn("Skip: notification is a group summary")
                return
            }

            val combined = listOfNotNull(title, text, bigText, subText, textLines)
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            log("combined: ${combined.joinToString("\n")}")
            if (combined.isEmpty()) {
                logWarn("Skip: combined text is empty")
                return
            }

            // Para Gmail, aplicar filtro estricto de transacciones
            if (pkg == "com.google.android.gm") {
                if (!isAllowedGmailNotification(title, text, bigText, subText)) {
                    logWarn("Skip: Gmail notification not recognized as transaction")
                    return
                }
            }

            // En DEBUG permitir notificaciones del propio paquete para testing
            if (BuildConfig.DEBUG && pkg == applicationContext.packageName) {
                log("DEBUG mode: allowing own package")
            }

            // Segundo filtro por contenido (palabras clave) para reducir ruido
            val allText = combined.joinToString("\n")
            if (!looksLikePayment(allText)) {
                logWarn("Skip: text doesn't look like a payment notification")
                return
            }

            val payload = hashMapOf<String, Any?>(
                "sourcePackage" to pkg,
                "title" to title,
                "text" to text,
                "bigText" to bigText,
                "subText" to subText,
                "postTime" to sbn.postTime
            )
            log("✅ Processing notification: ${payload.keys}")

            // NUEVO: Parsear y guardar directamente en SQLite desde Android
            // Esto funciona incluso cuando la app está cerrada
            ioScope.launch {
                try {
                    val combined = listOfNotNull(title, text, bigText, subText)
                        .joinToString("\n")
                    
                    val parsed = ExpenseParser.parseAmountCurrencyMerchant(combined)
                    
                    ExpensesDbWriter.insertExpense(
                        context = applicationContext,
                        timestampMs = sbn.postTime,
                        amount = parsed.amount,
                        currency = parsed.currency,
                        merchant = parsed.merchant,
                        category = null,
                        rawText = combined,
                        sourcePackage = pkg,
                        ownerUserId = null, // Se actualizará desde Flutter cuando esté disponible
                        synced = 0
                    )
                    
                    log("✅ Expense saved to database")
                } catch (e: Exception) {
                    logErr("Error saving expense", e)
                }
            }

            // También emitir a Flutter si está escuchando (para actualizar UI)
            NotificationEventBridge.emit(payload)

        } catch (_: Exception) {
            // evita crashear el listener
        }
    }

    private fun looksLikePayment(s: String): Boolean {
        val lower = s.lowercase()

        // Palabras clave de acción de pago
        val actionKeywords = listOf(
            "pagaste", "pago", "compra", "purchase", "spent", "transacción",
            "se realizó", "se ha realizado", "aprobada", "approved",
            "consumo", "cargo", "débito", "yapeo", "transferencia", "visa", "transf"
        )

        // Palabras clave de moneda/monto
        val moneyKeywords = listOf(
            "s/", "pen", "usd", "$", "soles", "dólares"
        )

        // Debe tener al menos una palabra de acción Y una de dinero
        val hasAction = actionKeywords.any { lower.contains(it) }
        val hasMoney = moneyKeywords.any { lower.contains(it) }



        return hasAction && hasMoney
    }
}
