import 'package:flutter/material.dart';
import '../subscription/subscription_api.dart'; // ajusta el import a tu estructura

class MembershipSettingsPage extends StatefulWidget {
  const MembershipSettingsPage({super.key});

  @override
  State<MembershipSettingsPage> createState() => _MembershipSettingsPageState();
}

class _MembershipSettingsPageState extends State<MembershipSettingsPage> {
  bool _loading = true;
  SubscriptionSummary? _summary;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await SubscriptionApi.getSummary();
      if (!mounted) return;
      setState(() {
        _summary = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtIso(String? iso) {
    if (iso == null) return "—";
    final d = DateTime.tryParse(iso);
    if (d == null) return "—";
    // Lima -05:00: toLocal ya depende del device; ok para UI
    final local = d.toLocal();
    return "${local.year}-${local.month.toString().padLeft(2,'0')}-${local.day.toString().padLeft(2,'0')} "
        "${local.hour.toString().padLeft(2,'0')}:${local.minute.toString().padLeft(2,'0')}";
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cancelar suscripción"),
        content: const Text("Se detendrán los cobros automáticos. ¿Continuar?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Sí, cancelar")),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await SubscriptionApi.cancel();
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Suscripción cancelada.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se pudo cancelar: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes de membresía'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text("Error: $_error"))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Estado'),
            subtitle: Text(s?.isSubscribed == true
                ? "Activa (${s!.mpStatus})"
                : "Inactiva (${s?.mpStatus ?? "unknown"})"),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.payments),
            title: const Text('Precio'),
            subtitle: Text(
              (s?.amount != null && s?.currency != null)
                  ? "${s!.amount} ${s.currency}"
                  : "—",
            ),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Renovación'),
            subtitle: Text(
              (s?.frequency != null && s?.frequencyType != null)
                  ? "Cada ${s!.frequency} ${s.frequencyType}"
                  : "—",
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Último cobro'),
            subtitle: Text(_fmtIso(s?.lastPaymentDate)),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Próximo cobro (estimado)'),
            subtitle: Text(_fmtIso(s?.nextChargeDate)),
          ),
          const SizedBox(height: 12),
          if (s?.isSubscribed == true)
            ElevatedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel),
              label: const Text("Cancelar suscripción"),
            ),
        ],
      ),
    );
  }
}
