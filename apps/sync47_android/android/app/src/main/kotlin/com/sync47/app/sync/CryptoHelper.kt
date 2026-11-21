package com.sync47.app.sync

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object CryptoHelper {
    private const val AES_GCM_NO_PADDING = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH_BITS = 128
    private const val IV_LENGTH_BYTES = 12

    fun sha256Hex(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(text.toByteArray(Charsets.UTF_8))
        return hashBytes.joinToString("") { "%02x".format(it) }
    }

    fun generateKeyBase64(): String {
        val random = SecureRandom()
        val keyBytes = ByteArray(32)
        random.nextBytes(keyBytes)
        return Base64Helper.encode(keyBytes)
    }

    /**
     * Wire format matches Dart AesGcmCrypto:
     * Base64( 12-byte random IV || ciphertext || 16-byte GCM authentication tag )
     */
    fun encrypt(plaintext: String, keyBase64: String): String {
        val keyBytes = Base64Helper.decode(keyBase64)
        require(keyBytes.size == 32) { "Key must be 32 bytes for AES-256" }

        val iv = ByteArray(IV_LENGTH_BYTES)
        SecureRandom().nextBytes(iv)

        val secretKey = SecretKeySpec(keyBytes, "AES")
        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, spec)

        val cipherTextAndTag = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        val combined = ByteArray(iv.size + cipherTextAndTag.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(cipherTextAndTag, 0, combined, iv.size, cipherTextAndTag.size)

        return Base64Helper.encode(combined)
    }

    /**
     * Decrypts Base64( 12-byte IV || ciphertext || 16-byte GCM tag )
     */
    fun decrypt(base64Payload: String, keyBase64: String): String {
        val keyBytes = Base64Helper.decode(keyBase64)
        require(keyBytes.size == 32) { "Key must be 32 bytes for AES-256" }

        val combined = Base64Helper.decode(base64Payload)
        require(combined.size >= 28) { "Payload too short for IV and GCM tag" }

        val iv = combined.copyOfRange(0, IV_LENGTH_BYTES)
        val cipherTextAndTag = combined.copyOfRange(IV_LENGTH_BYTES, combined.size)

        val secretKey = SecretKeySpec(keyBytes, "AES")
        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)

        val decrypted = cipher.doFinal(cipherTextAndTag)
        return String(decrypted, Charsets.UTF_8)
    }

    /**
     * Dual-environment Base64 adapter compatible with both Android runtime and JVM JUnit tests.
     */
    internal object Base64Helper {
        fun encode(bytes: ByteArray): String {
            return try {
                android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
            } catch (_: Throwable) {
                java.util.Base64.getEncoder().encodeToString(bytes)
            }
        }

        fun decode(str: String): ByteArray {
            return try {
                android.util.Base64.decode(str, android.util.Base64.DEFAULT)
            } catch (_: Throwable) {
                java.util.Base64.getDecoder().decode(str.trim())
            }
        }
    }
}
