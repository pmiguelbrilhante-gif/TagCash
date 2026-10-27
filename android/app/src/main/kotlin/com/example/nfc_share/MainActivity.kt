package com.example.nfc_share

import android.content.ComponentName
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Enquanto o app estiver na tela, o NdefHceService tem prioridade
    // e o Android não pergunta qual aplicativo usar.
    override fun onResume() {
        super.onResume()
        definirServicoPreferido(true)
    }

    override fun onPause() {
        definirServicoPreferido(false)
        super.onPause()
    }

    private fun definirServicoPreferido(ativar: Boolean) {
        try {
            val adapter = NfcAdapter.getDefaultAdapter(this) ?: return
            val emulation = CardEmulation.getInstance(adapter)
            if (ativar) {
                emulation.setPreferredService(
                    this,
                    ComponentName(this, NdefHceService::class.java)
                )
            } else {
                emulation.unsetPreferredService(this)
            }
        } catch (e: Exception) {
            // Se o aparelho não permitir, o comportamento antigo continua
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nfc_share/hce")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isHceSupported" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
                    )
                    "setUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("ARGS", "Parâmetro 'url' ausente", null)
                        } else {
                            try {
                                NdefHceService.setUrl(url)
                                result.success(true)
                            } catch (e: IllegalArgumentException) {
                                result.error("INVALID", e.message, null)
                            }
                        }
                    }
                    "clear" -> {
                        NdefHceService.clear()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}