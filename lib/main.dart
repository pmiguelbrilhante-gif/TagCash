import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const NfcShareApp());
}

class NfcShareApp extends StatelessWidget {
  const NfcShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TagCash',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color.fromARGB(255, 5, 6, 7),
      ),
      home: const LinkScreen(),
    );
  }
}

class LinkScreen extends StatefulWidget {
  const LinkScreen({super.key});

  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {

  static const MethodChannel _hce = MethodChannel('nfc_share/hce');

  final TextEditingController _urlController = TextEditingController();
  bool _compartilhando = false;
  bool _lendo = false;
  String? _ultimoLink;

  @override
  void dispose() {
    _urlController.dispose();
    _hce.invokeMethod('clear');
    NfcManager.instance.stopSession().catchError((_) {});
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // essa parte envia

  Future<void> _iniciarCompartilhamento() async {
    final texto = _urlController.text.trim();
    if (texto.isEmpty) {
      _aviso('Digite ou cole um link primeiro.');
      return;
    }
    final link = texto.contains('://') ? texto : 'https://$texto';

    try {
      final suportado = await _hce.invokeMethod<bool>('isHceSupported') ?? false;
      if (!suportado) {
        _aviso('Este aparelho não suporta emulação de cartão NFC (HCE).');
        return;
      }
      await _hce.invokeMethod('setUrl', {'url': link});
      if (!mounted) return;
      setState(() => _compartilhando = true);
      _aviso('Pronto! Encoste a traseira deste celular no outro.');
    } on PlatformException catch (e) {
      _aviso(e.message ?? 'Erro ao preparar o NFC.');
    }
  }

  Future<void> _pararCompartilhamento() async {
    await _hce.invokeMethod('clear');
    if (!mounted) return;
    setState(() => _compartilhando = false);
  }

  // essa parte recebe, ao menos é a ideia 

  Future<void> _iniciarLeitura() async {
    final disponibilidade = await NfcManager.instance.checkAvailability();
    if (disponibilidade != NfcAvailability.enabled) {
      _aviso('NFC não está disponível ou está desativado neste aparelho.');
      return;
    }

    setState(() => _lendo = true);
    _aviso('Encoste este celular no que está compartilhando...');

    NfcManager.instance.startSession(
      
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        final link = _extrairLink(tag);
        await NfcManager.instance.stopSession();
        if (!mounted) return;
        setState(() => _lendo = false);

        if (link == null) {
          _aviso('Nenhum link encontrado no outro aparelho.');
          return;
        }
        setState(() => _ultimoLink = link);
        await _abrirLink(link);
      },
    );
  }

  Future<void> _cancelarLeitura() async {
    await NfcManager.instance.stopSession();
    if (!mounted) return;
    setState(() => _lendo = false);
  }


  String? _extrairLink(NfcTag tag) {
    final ndef = Ndef.from(tag);
    final mensagem = ndef?.cachedMessage;
    if (mensagem == null) return null;

    const prefixos = ['', 'http://www.', 'https://www.', 'http://', 'https://'];

    for (final r in mensagem.records) {
      final ehUri = r.type.length == 1 && r.type[0] == 0x55;
      if (ehUri && r.payload.isNotEmpty) {
        final codigo = r.payload[0];
        final prefixo = codigo < prefixos.length ? prefixos[codigo] : '';
        return prefixo + utf8.decode(r.payload.sublist(1));
      }
    }
    return null;
  }

  Future<void> _abrirLink(String link) async {
    final uri = Uri.tryParse(link);
    // abre o link
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      _aviso('Link ignorado por segurança: $link');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _aviso('Não consegui abrir: $link');
  }

  // ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TagCash'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Compartilhar link',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    enabled: !_compartilhando,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Link',
                      hintText: 'https://exemplo.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_compartilhando)
                    FilledButton.icon(
                      onPressed: _iniciarCompartilhamento,
                      icon: const Icon(Icons.nfc),
                      label: const Text('Compartilhar por NFC'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _pararCompartilhamento,
                      icon: const Icon(Icons.stop),
                      label: const Text('Compartilhando... toque para parar'),
                    ),
                  if (_compartilhando)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Mantenha a tela ligada e encoste a traseira deste celular no outro.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Receber link',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (!_lendo)
                    OutlinedButton.icon(
                      onPressed: _iniciarLeitura,
                      icon: const Icon(Icons.download),
                      label: const Text('Aguardar link por NFC'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _cancelarLeitura,
                      icon: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: const Text('Escutando NFC... toque para cancelar'),
                    ),
                  if (_ultimoLink != null) ...[
                    const SizedBox(height: 12),
                    Text('Último link recebido:',
                        style: Theme.of(context).textTheme.labelMedium),
                    SelectableText(_ultimoLink!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
