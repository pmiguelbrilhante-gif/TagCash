package com.example.nfc_share

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * Faz o celular se comportar como uma tag NFC Forum Type 4 (somente leitura)
 * contendo um único record NDEF do tipo URI. Quem encostar para ler recebe o link.
 */
class NdefHceService : HostApduService() {

    private enum class Selected { NONE, CC, NDEF }

    private var selected = Selected.NONE

    override fun processCommandApdu(apdu: ByteArray?, extras: Bundle?): ByteArray {
        if (apdu == null || apdu.size < 4) return SW_UNKNOWN
        val ins = apdu[1].toInt() and 0xFF
        val p1 = apdu[2].toInt() and 0xFF
        val p2 = apdu[3].toInt() and 0xFF
        return when (ins) {
            0xA4 -> handleSelect(apdu, p1)
            0xB0 -> handleRead(apdu, p1, p2)
            else -> SW_INS_NOT_SUPPORTED
        }
    }

    override fun onDeactivated(reason: Int) {
        selected = Selected.NONE
    }

    private fun handleSelect(apdu: ByteArray, p1: Int): ByteArray {
        if (apdu.size < 5) return SW_WRONG_LENGTH
        val lc = apdu[4].toInt() and 0xFF
        if (apdu.size < 5 + lc) return SW_WRONG_LENGTH
        val data = apdu.copyOfRange(5, 5 + lc)

        return when (p1) {
            // SELECT por nome (AID da aplicação NDEF)
            0x04 -> if (data.contentEquals(NDEF_AID)) {
                selected = Selected.NONE
                SW_OK
            } else {
                SW_NOT_FOUND
            }
            // SELECT por ID de arquivo
            0x00 -> {
                if (data.size != 2) return SW_NOT_FOUND
                val id = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
                when (id) {
                    0xE103 -> { selected = Selected.CC; SW_OK }
                    0xE104 -> { selected = Selected.NDEF; SW_OK }
                    else -> SW_NOT_FOUND
                }
            }
            else -> SW_NOT_FOUND
        }
    }

    private fun handleRead(apdu: ByteArray, p1: Int, p2: Int): ByteArray {
        val file = when (selected) {
            Selected.CC -> CC_FILE
            Selected.NDEF -> ndefFile
            Selected.NONE -> return SW_NOT_FOUND
        }
        val offset = (p1 shl 8) or p2
        if (offset > file.size) return SW_WRONG_PARAMS
        var le = if (apdu.size > 4) apdu[4].toInt() and 0xFF else 0
        if (le == 0) le = 256
        val end = minOf(offset + le, file.size)
        return file.copyOfRange(offset, end) + SW_OK
    }

    companion object {
        // AID da aplicação NDEF Type 4 Tag: D2760000850101
        private val NDEF_AID = byteArrayOf(
            0xD2.toByte(), 0x76, 0x00, 0x00, 0x85.toByte(), 0x01, 0x01
        )

        // Capability Container (15 bytes): versão 2.0, leitura livre, sem escrita
        private val CC_FILE = byteArrayOf(
            0x00, 0x0F,             // CCLEN
            0x20,                   // versão do mapeamento
            0x00, 0xFF.toByte(),    // MLe
            0x00, 0xFF.toByte(),    // MLc
            0x04, 0x06,             // TLV do arquivo NDEF
            0xE1.toByte(), 0x04,    // ID do arquivo NDEF (E104)
            0x08, 0x00,             // tamanho máximo do arquivo NDEF
            0x00,                   // leitura permitida
            0xFF.toByte()           // escrita proibida
        )

        private val SW_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_NOT_FOUND = byteArrayOf(0x6A, 0x82.toByte())
        private val SW_WRONG_PARAMS = byteArrayOf(0x6B, 0x00)
        private val SW_WRONG_LENGTH = byteArrayOf(0x67, 0x00)
        private val SW_INS_NOT_SUPPORTED = byteArrayOf(0x6D, 0x00)
        private val SW_UNKNOWN = byteArrayOf(0x6F, 0x00)

        // Arquivo NDEF = NLEN (2 bytes) + mensagem. Vazio por padrão.
        @Volatile
        private var ndefFile: ByteArray = byteArrayOf(0x00, 0x00)

        fun setUrl(rawUrl: String) {
            val url = rawUrl.trim()
            require(url.isNotEmpty()) { "Link vazio" }

            // Código de abreviação de prefixo do record URI (NFC Forum)
            val (code, rest) = when {
                url.startsWith("https://www.") -> 0x02 to url.removePrefix("https://www.")
                url.startsWith("http://www.") -> 0x01 to url.removePrefix("http://www.")
                url.startsWith("https://") -> 0x04 to url.removePrefix("https://")
                url.startsWith("http://") -> 0x03 to url.removePrefix("http://")
                else -> 0x00 to url
            }

            val payload = byteArrayOf(code.toByte()) + rest.toByteArray(Charsets.UTF_8)
            require(payload.size <= 255) { "Link muito longo (máximo ~250 caracteres)." }

            // Header 0xD1 = MB|ME|SR|TNF=well-known; tipo 'U' (0x55)
            val record = byteArrayOf(0xD1.toByte(), 0x01, payload.size.toByte(), 0x55) + payload
            val nlen = record.size
            ndefFile = byteArrayOf((nlen shr 8).toByte(), (nlen and 0xFF).toByte()) + record
        }

        fun clear() {
            ndefFile = byteArrayOf(0x00, 0x00)
        }
    }
}
