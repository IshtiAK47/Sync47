package com.sync47.app.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class CryptoHelperTest {

    @Test
    fun testSha256Hex() {
        val hash = CryptoHelper.sha256Hex("Hello Sync47")
        assertEquals(64, hash.length)
        assertEquals(hash, CryptoHelper.sha256Hex("Hello Sync47"))
        assertNotEquals(hash, CryptoHelper.sha256Hex("Different Text"))
    }

    @Test
    fun testGenerateKeyBase64() {
        val key = CryptoHelper.generateKeyBase64()
        assertNotNull(key)
        val decoded = Base64.getDecoder().decode(key)
        assertEquals(32, decoded.size)
    }

    @Test
    fun testEncryptDecryptRoundTrip() {
        val key = CryptoHelper.generateKeyBase64()
        val originalText = "Test sync message: 12345! https://example.com"

        val encrypted = CryptoHelper.encrypt(originalText, key)
        assertNotNull(encrypted)
        assertNotEquals(originalText, encrypted)

        val decrypted = CryptoHelper.decrypt(encrypted, key)
        assertEquals(originalText, decrypted)
    }

    @Test
    fun testWireFormatLayout() {
        val key = CryptoHelper.generateKeyBase64()
        val plaintext = "12345678" // 8 bytes
        val encrypted = CryptoHelper.encrypt(plaintext, key)
        val rawBytes = Base64.getDecoder().decode(encrypted)

        // 12 (IV) + 8 (ciphertext) + 16 (GCM tag) = 36 bytes
        assertEquals(12 + 8 + 16, rawBytes.size)
    }

    @Test(expected = Exception::class)
    fun testTamperedCiphertextThrows() {
        val key = CryptoHelper.generateKeyBase64()
        val originalText = "Tamper proof check"
        val encrypted = CryptoHelper.encrypt(originalText, key)

        val bytes = Base64.getDecoder().decode(encrypted)
        bytes[15] = (bytes[15].toInt() xor 0xFF).toByte()

        val tamperedBase64 = Base64.getEncoder().encodeToString(bytes)
        CryptoHelper.decrypt(tamperedBase64, key)
    }
}
