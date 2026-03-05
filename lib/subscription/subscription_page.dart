import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subscription_api.dart';

class SubscriptionPage extends StatefulWidget {
  // Alterado para coincidir com o nome usado no Gate
  final Future<void> Function() onSubscribeSuccess;

  const SubscriptionPage({super.key, required this.onSubscribeSuccess});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool _isVerifying = false;

  Future<void> _payWithMercadoPago() async {
    try {
      // 1. Obtener el ID del usuario logueado en Firebase
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid;
      if (userId == null) {
        throw 'No hay sesión activa en Firebase';
      }

      // 2. Tu link real de suscripción con el external_reference
      //test f99140fb1090406f9ab119279dab8a67
      //prod 8ab560a6aee9482a8d4b9a528d293909
      final checkoutUri = await SubscriptionApi.createCheckoutUrl(userId);

      //final baseUrl = 'https://www.mercadopago.com.pe/subscriptions/checkout?preapproval_plan_id=6bed08b78dda433bb3773f929a28da47';
      //final fullUrl = Uri.parse('$baseUrl&external_reference=$userId');

      // 3. Abrir el navegador
      if (await canLaunchUrl(checkoutUri)) {
        await launchUrl(checkoutUri, mode: LaunchMode.inAppBrowserView);
      } else {
        throw 'No se pudo abrir el enlace de pago $checkoutUri';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar pago: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Bloqueia o botão voltar para forçar a assinatura
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Membresia'),
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.stars, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Acesso Restringido',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Para utilizar o Phonance, Necesita activar la suscripcion mediante mercado pago',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const Spacer(),

              // Botão Principal de Pagamento
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                // ANTES: onPressed: _launchMercadoPago,
                onPressed: _payWithMercadoPago, // AHORA: Usa el método que incluye el userId
                child: const Text(
                  'PAGAR CON MERCADO PAGO',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 16),

              // Botão de Verificação
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: Colors.blue),
                ),
                onPressed: _isVerifying ? null : () async {
                  setState(() => _isVerifying = true);

                  // Chama a função de verificação no Gate
                  await widget.onSubscribeSuccess();

                  // Pequeno delay visual
                  await Future.delayed(const Duration(seconds: 2));
                  if (mounted) setState(() => _isVerifying = false);
                },
                child: _isVerifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('YA PAGUE, LIBERAR ACCESO'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}