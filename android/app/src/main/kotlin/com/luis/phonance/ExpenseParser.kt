package com.luis.phonance

import android.util.Log

data class ParsedExpense(
    val amount: Double?,
    val currency: String?,
    val merchant: String?
)

object ExpenseParser {
    private const val TAG = "PHONANCE_PARSER"

    fun parseAmountCurrencyMerchant(s: String): ParsedExpense {
        val normalized = s.replace("\u00A0", " ").trim()
        
        val lines = normalized
            .split("\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        var currency: String? = null
        var amount: Double? = null
        var merchant: String? = null

        // NUEVO: Formato de campos separados por líneas (BBVA nuevo formato)
        // Buscar patrones como "Monto:" en una línea y el valor en la siguiente
        for (i in lines.indices) {
            val line = lines[i]
            val nextLine = if (i + 1 < lines.size) lines[i + 1] else null

            // Buscar "Comercio:" y tomar la siguiente línea
            if (merchant == null && 
                Regex("^\\s*comercio\\s*:\\s*$", RegexOption.IGNORE_CASE).matches(line) && 
                nextLine != null) {
                merchant = nextLine.trim()
            }

            // Buscar "Monto:" y tomar la siguiente línea
            if (amount == null && 
                Regex("^\\s*monto\\s*:\\s*\$", RegexOption.IGNORE_CASE).matches(line) && 
                nextLine != null) {
                val rawNum = nextLine.trim()
                amount = toDoubleSmart(rawNum)
            }

            // Buscar "Moneda:" y tomar la siguiente línea
            if (currency == null && 
                Regex("^\\s*moneda\\s*:\\s*\$", RegexOption.IGNORE_CASE).matches(line) && 
                nextLine != null) {
                currency = nextLine.trim().uppercase()
            }
        }

        // FORMATO ANTIGUO: Monedas y montos en la misma línea
        if (amount == null || currency == null) {
            val patterns = listOf(
                Regex("(S/)\\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)", RegexOption.IGNORE_CASE),
                Regex("\\b(PEN)\\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)\\b", RegexOption.IGNORE_CASE),
                Regex("\\b(USD)\\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)\\b", RegexOption.IGNORE_CASE),
                Regex("(\\$)\\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)", RegexOption.IGNORE_CASE),
                Regex("(Monto:)\\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)", RegexOption.IGNORE_CASE),
            )

            for (pattern in patterns) {
                val match = pattern.find(normalized)
                if (match != null) {
                    if (currency == null) {
                        currency = match.groupValues.getOrNull(1)?.uppercase()
                    }
                    if (amount == null) {
                        val rawNum = match.groupValues.getOrNull(2) ?: ""
                        amount = toDoubleSmart(rawNum)
                    }
                    break
                }
            }
        }

        // FORMATO ANTIGUO: Merchant (solo si no se encontró en el nuevo formato)
        if (merchant == null) {
            merchant = extractMerchantFromHtml(normalized)

            val merchantPatterns = listOf(
                Regex("\\b(en)\\s+([A-Za-z0-9].+)\$", RegexOption.IGNORE_CASE),
                Regex("\\b(at)\\s+([A-Za-z0-9].+)\$", RegexOption.IGNORE_CASE),
                Regex("\\b(para)\\s+([A-Za-z0-9].+)\$", RegexOption.IGNORE_CASE),
                Regex("\\bempresa\\s*[:\\-]?\\s*([\\p{L}0-9 .,*-]{2,})", RegexOption.IGNORE_CASE),
                Regex("\\bcomercio\\s*[:\\-]?\\s*([\\p{L}0-9 .,*-]{2,})", RegexOption.IGNORE_CASE),
            )

            // Primero verificar si es YAPE o PLIN
            val isYape = normalized.uppercase().contains("YAPE")
            val isPlin = normalized.uppercase().contains("PLIN")
            
            when {
                isYape -> merchant = "YAPE"
                isPlin -> merchant = "PLIN"
                else -> {
                    if (merchant == null) {
                        // Buscar en todas las líneas limpias (evita capturar footer/legal HTML)
                        for (line in lines) {
                            val cleanLine = line
                                .replace(Regex("<[^>]+>"), " ")
                                .replace(Regex("\\s+"), " ")
                                .trim()

                            if (cleanLine.isEmpty() || cleanLine.length > 90) continue

                            val lower = cleanLine.lowercase()
                            if (
                                lower.contains("<!doctype") ||
                                lower.contains("<html") ||
                                lower.contains("http") ||
                                lower.contains("www.") ||
                                lower.contains("style=")
                            ) continue

                            for (pattern in merchantPatterns) {
                                val match = pattern.find(cleanLine)
                                if (match != null) {
                                    val captured = match.groupValues
                                        .drop(1)
                                        .lastOrNull { it.isNotBlank() }
                                        ?.trim()
                                        ?.trimEnd('.')

                                    if (!captured.isNullOrBlank() && isLikelyMerchant(captured)) {
                                        merchant = captured
                                        break
                                    }
                                }
                            }
                            if (merchant != null) break
                        }
                    }
                }
            }

            if ((merchant == null || merchant.isEmpty()) && normalized.length < 80) {
                merchant = normalized
            }
        }

        // Normaliza moneda
        when (currency) {
            "$", "USD" -> currency = "USD"
            "S/", "PEN" -> currency = "PEN"
        }

        Log.d(TAG, "merchant=$merchant amount=$amount currency=$currency")

        return ParsedExpense(amount = amount, currency = currency, merchant = merchant)
    }

    private fun extractMerchantFromHtml(text: String): String? {
        val htmlPatterns = listOf(
            Regex("(?is)\\ben\\s*<b>\\s*([^<]{2,80})\\s*</b>"),
            Regex("(?is)>\\s*Empresa\\s*</td>\\s*<td[^>]*>\\s*<b>\\s*([^<]{2,80})\\s*</b>")
        )

        for (pattern in htmlPatterns) {
            val match = pattern.find(text) ?: continue
            val candidate = match.groupValues
                .drop(1)
                .firstOrNull { it.isNotBlank() }
                ?.replace(Regex("\\s+"), " ")
                ?.trim()
                ?.trimEnd('.')

            if (!candidate.isNullOrBlank() && isLikelyMerchant(candidate)) {
                return candidate
            }
        }

        return null
    }

    private fun isLikelyMerchant(value: String): Boolean {
        val candidate = value.trim()
        if (candidate.length < 2 || candidate.length > 80) return false

        val lower = candidate.lowercase()
        val blockedFragments = listOf(
            "ayudarte a verificarla",
            "servicio de notificaciones",
            "comunícate inmediatamente",
            "datos de tu operación",
            "tarjeta de crédito bcp",
            "<!doctype",
            "<html",
            "http",
            "www."
        )

        if (blockedFragments.any { lower.contains(it) }) return false

        return candidate.any { it.isLetterOrDigit() }
    }

    private fun toDoubleSmart(raw: String): Double? {
        var s = raw.trim()
        
        val hasComma = s.contains(',')
        val hasDot = s.contains('.')

        s = when {
            hasComma && hasDot -> {
                val lastComma = s.lastIndexOf(',')
                val lastDot = s.lastIndexOf('.')
                if (lastComma > lastDot) {
                    // decimal = ','
                    s.replace(".", "").replace(",", ".")
                } else {
                    // decimal = '.'
                    s.replace(",", "")
                }
            }
            hasComma && !hasDot -> {
                // asumir decimal ','
                s.replace(".", "").replace(",", ".")
            }
            else -> {
                // asumir decimal '.'
                s.replace(",", "")
            }
        }

        return s.toDoubleOrNull()
    }
}
