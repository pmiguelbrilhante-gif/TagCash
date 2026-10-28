import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
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

  @override
  void dispose() {
    _urlController.dispose();
    _hce.invokeMethod('clear');
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

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
      final ligado = await _hce.invokeMethod<bool>('isNfcEnabled') ?? false;
      if (!ligado) {
        _aviso('O NFC está desligado. Ative nas configurações do celular.');
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
        ],
      ),
    );
  }
}