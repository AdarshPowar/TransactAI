package com.transactai.models

import com.google.gson.annotations.SerializedName

/**
 * Request model for categorization API
 *
 * NOTE: the backend /classify endpoint expects the JSON field `message`
 * (see backend/api/main.py — it reads payload.get("sms_text") or payload.get("message")).
 */
data class CategorizationRequest(
    @SerializedName("message")
    val message: String
)

/**
 * Response model from categorization API
 */
data class CategorizationResponse(
    @SerializedName("category")
    val category: String,
    
    @SerializedName("confidence")
    val confidence: Double
)

/**
 * Transaction model for local storage
 */
data class Transaction(
    val id: Long = 0,
    val text: String,
    val category: String,
    val confidence: Double,
    val timestamp: Long = System.currentTimeMillis(),
    val appPackage: String
)
