import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:phonance/charts_utils.dart';
import 'package:phonance/notifications/budget_alert_manager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_notification.dart';
import './summary/summary_tab.dart';
import './settings/settings_tab.dart';


import './auth/auth_gate.dart';
import 'amplify_initializer.dart';
import './apiExpenses/expenses_api.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../auth/profile_api.dart';

import 'notifications/notification_service.dart';
import 'gmail_service.dart';


void main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService().init();

  // Inicializa notificaciones locales
  await TestNotifications.init();

  // Pide permiso para mostrar notificaciones (Android 13+)
  final androidPlugin = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  await AmplifyInit.ensureConfigured();

  final db = await ExpensesDb.open();

  runApp(MyApp(db: db));
}

class MyApp extends StatelessWidget {
  final ExpensesDb db;
  const MyApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phonance',
      theme: ThemeData(useMaterial3: true),
      home: AuthGate(db: db),
    );
  }
}


class HomePage extends StatefulWidget {
  final ExpensesDb db;
  const HomePage({super.key, required this.db});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _platform = MethodChannel('com.luis.phonance/methods');
  static const _events = EventChannel('com.luis.phonance/events');

  String? _ownerUserId;
  bool _didInitialCloudLoad = false;

  StreamSubscription? _sub;
  bool _hasAccess = false;
  bool _gmailConnected = false;
  List<Expense> _items = [];
  int _selectedIndex = 0;  // Controlador de pestañas

  @override
  void initState() {
    super.initState();

    _init();
  }

  Future<void> _loadFromCloudOnce() async {
    if (_didInitialCloudLoad) return;
    if (_ownerUserId == null) return;

    _didInitialCloudLoad = true;

    // ejemplo: trae últimos 12 meses
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 12, 1).millisecondsSinceEpoch;

    try {
      final remote = await ExpensesApi.getExpenses(fromMs: from, limit: 2000);

      for (final m in remote) {
        final e = Expense(
          timestampMs: (m['timestampMs'] as num).toInt(),
          amount: (m['amount'] as num?)?.toDouble(),
          currency: m['currency'] as String?,
          merchant: m['merchant'] as String?,
          category: m['category'] as String?,
          rawText: m['rawText'] as String?,
          sourcePackage: m['sourcePackage'] as String?,
          dedupeKey: m['dedupeKey'] as String,
        );

        // Inserta si no existe y marca como synced=1
        await widget.db.insertIfNotExists(
          e,
          ownerUserId: _ownerUserId!,
          synced: 1,
        );
      }
    } catch (e, st) {
      // no rompas la app si falla cloud; igual tienes local
      debugPrint('fallo al cargar desde cloud:: $e\n$st');
    }
  }


  Future<void> _init() async {
    final user = await Amplify.Auth.getCurrentUser();
    _ownerUserId = user.userId;

    final p = await ProfileApi.getProfile();
    final monthlyIncome = p?.monthlyIncome ?? 0.0;

    BudgetAlertManager().setUserSettings(
      spendingLimit: p?.spendingLimit.toDouble() ?? 0.0,
      currency: p?.preferredCurrency ?? 'PEN',
    );

    await widget.db.attachLegacyToOwner(_ownerUserId!);
    
    // Inicializar Gmail si está disponible (intenta restaurar sesión anterior)
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final gmailService = GmailService();
      await gmailService.initializeFromStorage();
      // Actualizar el estado local
      await _refreshGmailStatus();
    }
    
    await _loadFromCloudOnce();
    await _refreshAccess();
    await _loadItems();

    final currentMonth = filterCurrentMonth(_items);
    await BudgetAlertManager().evaluateAndNotify(currentMonth, monthlyIncome);

    // En iOS: leer emails de Gmail
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // Si está conectado a Gmail, cargar emails desde última apertura
      if (_gmailConnected) {
        await _loadEmailsFromGmail();
      }
    } else {
      // En Android: solo escuchar eventos para actualizar UI
      // El guardado en DB ya se hace nativamente en GPayNotificationListener.kt
      _sub ??= _events.receiveBroadcastStream().listen((event) async {
        if (event is Map) {
          debugPrint('Notificación recibida (ya guardada nativamente)');
          
          // Solo recargar items y evaluar presupuesto
          await _loadItems();
          final expenses = filterCurrentMonth(_items);
          await BudgetAlertManager().evaluateAndNotify(expenses, monthlyIncome);
          
          // Si hay ownerUserId, actualizar los registros que no tienen ownerUserId
          if (_ownerUserId != null) {
            await _updateOwnerUserIdForUnassignedExpenses();
          }
        }
      }, onError: (e) {});
    }
  }

  Future<void> _updateOwnerUserIdForUnassignedExpenses() async {
    try {
      // Actualizar registros sin ownerUserId
      await widget.db.db.rawUpdate(
        'UPDATE expenses SET ownerUserId = ? WHERE ownerUserId IS NULL',
        [_ownerUserId]
      );
      
      // Sincronizar con cloud los registros no sincronizados
      final unsyncedExpenses = await widget.db.db.query(
        'expenses',
        where: 'synced = 0 AND ownerUserId = ?',
        whereArgs: [_ownerUserId],
      );
      
      for (final row in unsyncedExpenses) {
        try {
          final expense = Expense(
            id: row['id'] as int?,
            timestampMs: row['timestampMs'] as int,
            amount: row['amount'] as double?,
            currency: row['currency'] as String?,
            merchant: row['merchant'] as String?,
            category: row['category'] as String?,
            rawText: row['rawText'] as String,
            sourcePackage: row['sourcePackage'] as String,
            dedupeKey: row['dedupeKey'] as String,
          );
          
          await ExpensesApi.postExpense(expense);
          await widget.db.markSynced(expense.dedupeKey);
        } catch (e) {
          debugPrint('Error syncing expense: $e');
        }
      }
    } catch (e) {
      debugPrint('Error updating ownerUserId: $e');
    }
  }

  Future<void> _loadEmailsFromGmail() async {
    try {
      final gmailService = GmailService();
      
      // Verificar si ya está signed in
      if (!gmailService.isSignedIn) {
        await gmailService.signIn();
      }
      if (mounted) {
        setState(() => _gmailConnected = gmailService.isSignedIn);
      }
      
      // Obtener la última vez que cargamos emails
      final lastLoadTime = await _getLastEmailLoadTimeFromStorage();
      
      // Obtener emails desde la última carga
      final emails = await gmailService.getEmailsSince(lastLoadTime);
      
      // Procesar cada email (aplicando filtro de transacciones válidas)
      int validEmailsCount = 0;
      for (final email in emails) {
        // Aplicar el mismo filtro que en el NotificationListener
        if (!email.isValidTransaction()) {
          debugPrint('Skipped email (not a valid transaction): ${email.subject}');
          continue;
        }
        
        final expense = Expense.fromNotification({
          'sourcePackage': 'com.google.android.gm',
          'title': email.subject,
          'text': email.body,
          'bigText': email.body,
          'postTime': email.timestampMs,
        });
        
        if (expense != null) {
          await widget.db.insertIfNotExists(
            expense,
            ownerUserId: _ownerUserId!,
            synced: 1,
          );
          
          // Enviar a cloud
          try {
            await ExpensesApi.postExpense(expense);
            await widget.db.markSynced(expense.dedupeKey);
          } catch (e) {
            debugPrint('Error posting expense: $e');
          }
          validEmailsCount++;
        }
      }
      
      // Actualizar el tiempo de última carga
      await _saveLastEmailLoadTime(DateTime.now().millisecondsSinceEpoch);
      
      // Recargar items y notificaciones
      await _loadItems();
      final items = await _loadItems();
      final expenses = filterCurrentMonth(items);
      
      final monthlyIncome = (await ProfileApi.getProfile())?.monthlyIncome ?? 0.0;
      await BudgetAlertManager().evaluateAndNotify(expenses, monthlyIncome);
      
      debugPrint('✅ Loaded ${emails.length} emails, processed $validEmailsCount valid transactions');
    } catch (e) {
      debugPrint('❌ Error loading emails from Gmail: $e');
    }
  }

  Future<void> _connectGmail() async {
    try {
      final gmailService = GmailService();
      await gmailService.signIn();
      if (mounted) {
        setState(() => _gmailConnected = gmailService.isSignedIn);
      }
      if (gmailService.isSignedIn) {
        // Cargar emails inmediatamente después de conectar
        await _loadEmailsFromGmail();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Gmail conectado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error connecting Gmail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al conectar Gmail: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _refreshGmailStatus() async {
    final gmailService = GmailService();
    if (mounted) {
      setState(() => _gmailConnected = gmailService.isSignedIn);
    }
  }

  int _getLastEmailLoadTime() {
    // Por ahora retornar hace 7 días
    // Idealmente guardarías esto en SharedPreferences o en la BD
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    return sevenDaysAgo.millisecondsSinceEpoch;
  }

  Future<void> _saveLastEmailLoadTime(int timestampMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastEmailLoadTime', timestampMs);
    debugPrint('Saved last email load time: $timestampMs');
  }
  
  Future<int> _getLastEmailLoadTimeFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('lastEmailLoadTime');
    
    if (stored != null) {
      return stored;
    }
    
    // Por defecto, cargar emails desde hace 7 días
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    return sevenDaysAgo.millisecondsSinceEpoch;
  }

  Future<void> _refreshAccess() async {
    final has = await _platform.invokeMethod<bool>('hasNotificationAccess') ?? false;
    if (mounted) {
      setState(() => _hasAccess = has);
    }
  }

  Future<void> _openSettings() async {
    await _platform.invokeMethod('openNotificationAccessSettings');
    // al volver, refresca
    await Future.delayed(const Duration(milliseconds: 300));
    await _refreshAccess();
  }

  Future<List<Expense>> _loadItems() async {
    if (_ownerUserId == null) return [];
    final items = await widget.db.listLatest(limit: 200);
    if (mounted) setState(() => _items = items);
    return items;
  }

  Future<void> _clearAll() async {
    await widget.db.clearAll();
    await _loadItems();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phonance'),
        actions: [
          IconButton(
            tooltip: 'Refrescar estado',
            onPressed: _refreshAccess,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Borrar todo',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete),
          ),
          IconButton(
            tooltip: 'Notificación de prueba',
            onPressed: () async {
              await TestNotifications.showWalletLikeNotification(
                currency: 'PEN',
                // opcional: merchant: 'OXXO ALIAGA',
                // opcional: amount: 11.89,
                cardSuffix: '8487',
              );
            },
            icon: const Icon(Icons.science),
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? _buildExpenseList(df)
          : _selectedIndex == 1
            ? _buildCategoryChart()
            : SettingsTab(db: widget.db),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Gastos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Gráficos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Cuenta',
          ),

        ],
      ),
    );
  }

  // Vista de lista de gastos
  Widget _buildExpenseList(DateFormat df) {
    return Column(
      children: [
        if (Theme.of(context).platform == TargetPlatform.android && !_hasAccess)
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: Text('Acceso a notificaciones: ${_hasAccess ? "HABILITADO" : "DESHABILITADO"}'),
              subtitle: const Text(
                'Debes habilitar "Notification access" para que la app pueda leer notificaciones y registrar gastos.',
              ),
              trailing: ElevatedButton(
                onPressed: _openSettings,
                child: const Text('Abrir ajustes'),
              ),
            ),
          ),
        if (Theme.of(context).platform == TargetPlatform.iOS && !_gmailConnected)
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              title: const Text('Conectar Gmail'),
              subtitle: const Text(
                'Vincula tu cuenta de Gmail para leer correos y registrar gastos automáticamente.',
              ),
              trailing: ElevatedButton(
                onPressed: _connectGmail,
                child: const Text('Vincular'),
              ),
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: Text('Aún no hay gastos registrados.'))
              : ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = _items[i];
              return ListTile(
                title: Text(it.amount != null
                    ? '${it.currency ?? ""} ${it.amount!.toStringAsFixed(2)}'
                    : '(monto no detectado)'),
                subtitle: Text([
                  it.category ?? 'Otros',
                  if (it.merchant != null && it.merchant!.isNotEmpty) it.merchant!,
                  df.format(DateTime.fromMillisecondsSinceEpoch(it.timestampMs)),
                ].join(' • ')),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Ver texto crudo',
                  icon: const Icon(Icons.description),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Notificación (raw)'),
                        content: SingleChildScrollView(child: Text(it.rawText ?? '')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Vista de gráficos por categorías
  Widget _buildCategoryChart() {
    return SummaryTab(expenses: _items);
  }
}

/// =====================
/// Modelo + Parseo
/// =====================

class Expense {
  final int? id;
  final int timestampMs;
  final double? amount;
  final String? currency;
  final String? merchant;
  final String? category;
  final String? rawText;
  final String? sourcePackage;
  final String dedupeKey;

  Expense({
    this.id,
    required this.timestampMs,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.category,
    required this.rawText,
    required this.sourcePackage,
    required this.dedupeKey,
  });

  static Expense? fromNotification(Map<String, dynamic> payload) {
    final source = (payload['sourcePackage'] as String?)?.trim();
    final title = (payload['title'] as String?) ?? '';
    final text = (payload['text'] as String?) ?? '';
    final bigText = (payload['bigText'] as String?) ?? '';
    final postTime = (payload['postTime'] as int?) ?? DateTime.now().millisecondsSinceEpoch;

    final combined = [title, text, bigText].where((s) => s.trim().isNotEmpty).join('\n').trim();
    if (combined.isEmpty) return null;

    // Intento de parseo
    final parsed = _parseAmountCurrencyMerchant(combined);

    // Dedup key: suficientemente estable (ajústalo si hace falta)
    final dedupeKey = '${source ?? ""}|$postTime|${combined.hashCode}';

    final category = categorizeMerchant(parsed.merchant);

    return Expense(
      timestampMs: postTime,
      amount: parsed.amount,
      currency: parsed.currency,
      merchant: parsed.merchant,
      category: category,
      rawText: combined,
      sourcePackage: source,
      dedupeKey: dedupeKey,
    );
  }
}

class ParsedExpense {
  final double? amount;
  final String? currency;
  final String? merchant;
  ParsedExpense({this.amount, this.currency, this.merchant});
}

/// Parser heurístico (mejora con tus ejemplos reales)
ParsedExpense _parseAmountCurrencyMerchant(String s) {
  final normalized = s.replaceAll('\u00A0', ' ').trim();

  final lines = normalized
      .split('\n')
      .map((it) => it.trim())
      .where((it) => it.isNotEmpty)
      .toList();

  String? currency;
  double? amount;
  String? merchant;

  // NUEVO: Formato de campos separados por líneas (BBVA nuevo formato)
  // Buscar patrones como "Monto:" en una línea y el valor en la siguiente
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final nextLine = i + 1 < lines.length ? lines[i + 1] : null;

    // Buscar "Comercio:" y tomar la siguiente línea
    if (merchant == null && 
        RegExp(r'^\s*comercio\s*:\s*$', caseSensitive: false).hasMatch(line) && 
        nextLine != null) {
      merchant = nextLine.trim();
    }

    // Buscar "Monto:" y tomar la siguiente línea
    if (amount == null && 
        RegExp(r'^\s*monto\s*:\s*$', caseSensitive: false).hasMatch(line) && 
        nextLine != null) {
      final rawNum = nextLine.trim();
      amount = _toDoubleSmart(rawNum);
    }

    // Buscar "Moneda:" y tomar la siguiente línea
    if (currency == null && 
        RegExp(r'^\s*moneda\s*:\s*$', caseSensitive: false).hasMatch(line) && 
        nextLine != null) {
      currency = nextLine.trim().toUpperCase();
    }
  }

  // FORMATO ANTIGUO: Monedas y montos en la misma línea
  if (amount == null || currency == null) {
    final patterns = <RegExp>[
      RegExp(r'(S\/)\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)', caseSensitive: false),
      RegExp(r'\b(PEN)\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)\b', caseSensitive: false),
      RegExp(r'\b(USD)\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)\b', caseSensitive: false),
      RegExp(r'(\$)\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)', caseSensitive: false),
      RegExp(r'(\Monto:)\s*([0-9]{1,3}([.,][0-9]{3})*([.,][0-9]{2})?)', caseSensitive: false),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(normalized);
      if (m != null) {
        if (currency == null) {
          currency = m.group(1)?.toUpperCase();
        }
        if (amount == null) {
          final rawNum = m.group(2) ?? '';
          amount = _toDoubleSmart(rawNum);
        }
        break;
      }
    }
  }

  // Merchant (heurística): si hay “en X” o “at X” o “para X”
  final merchantPatterns = <RegExp>[
    RegExp(r'\b(en)\s+([A-Za-z0-9].+)$', caseSensitive: false),
    RegExp(r'\b(at)\s+([A-Za-z0-9].+)$', caseSensitive: false),
    RegExp(r'\b(para)\s+([A-Za-z0-9].+)$', caseSensitive: false),
    RegExp(r"""\bempresa\s*[:\-]?\s*([\p{L}0-9 .,*-]{2,})""", caseSensitive: false),
    RegExp(r"""\bcomercio\s*[:\-]?\s*([\p{L}0-9 .,*-]{2,})""", caseSensitive: false),
  ];


  // Primero verificar si es YAPE o PLIN
  final isYape = normalized.toUpperCase().contains('YAPE');
  final isPlin = normalized.toUpperCase().contains('PLIN');
  
  if (isYape) {
    merchant = 'YAPE';
  } else if (isPlin) {
    merchant = 'PLIN';
  } else {
    // Buscar en todas las líneas
    for (final line in lines) {
      for (final pattern in merchantPatterns) {
        final m = pattern.firstMatch(line);
        if (m != null) {
          merchant = m.group(2)?.trim();
          break;
        }
      }
      if (merchant != null) break;
    }
  }

  if ((merchant == null || merchant.isEmpty) && normalized.length < 80) {
    merchant = normalized;
  }

  // Normaliza moneda
  if (currency == r'$' || currency == 'USD') currency = 'USD';
  if (currency == 'S/' || currency == 'PEN') currency = 'PEN';

  debugPrint('merchant=$merchant amount=$amount currency=$currency');

  return ParsedExpense(amount: amount, currency: currency, merchant: merchant);
}

double? _toDoubleSmart(String raw) {
  var s = raw.trim();
  // Caso 1: 1.234,56 -> remover miles "." y usar "," como decimal
  // Caso 2: 1,234.56 -> remover miles "," y usar "." como decimal
  // Heurística: si contiene "," y ".", el último separador suele ser decimal.
  final hasComma = s.contains(',');
  final hasDot = s.contains('.');

  if (hasComma && hasDot) {
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma > lastDot) {
      // decimal = ','
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // decimal = '.'
      s = s.replaceAll(',', '');
    }
  } else if (hasComma && !hasDot) {
    // asumir decimal ','
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else {
    // asumir decimal '.'
    s = s.replaceAll(',', '');
  }

  return double.tryParse(s);
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

/// =====================
/// SQLite
/// =====================

class ExpensesDb {
  final Database db;
  ExpensesDb._(this.db);

  static Future<ExpensesDb> open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, 'gpay_expenses.db');
    final db = await openDatabase(
      path,
      version: 5,
      onCreate: (d, _) async {
        await d.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestampMs INTEGER NOT NULL,
        amount REAL,
        currency TEXT,
        merchant TEXT,
        category TEXT,
        rawText TEXT,
        sourcePackage TEXT,
        dedupeKey TEXT NOT NULL UNIQUE,
        ownerUserId TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
        await d.execute('CREATE INDEX idx_expenses_ts ON expenses(timestampMs DESC)');
        await d.execute('CREATE INDEX idx_expenses_owner ON expenses(ownerUserId)');
      },

      onUpgrade: (d, oldV, newV) async {
        // Mantén tus if antiguos por compatibilidad
        if (oldV < 2) {
          await d.execute('ALTER TABLE expenses ADD COLUMN category TEXT');
        }
        if (oldV < 3) {
          await d.execute('ALTER TABLE expenses ADD COLUMN ownerUserId TEXT');
          await d.execute('CREATE INDEX IF NOT EXISTS idx_expenses_owner ON expenses(ownerUserId)');
        }
        if (oldV < 4) {
          await d.execute('ALTER TABLE expenses ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
        }

        // ---- Migración defensiva (idempotente) ----
        await _ensureColumns(d);
      },
      onOpen: (d) async {
        // Asegura columnas también al abrir (por si quedaron casos raros)
        await _ensureColumns(d);
      },
    );


    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
    );
    debugPrint('Tables: $tables');

    final rows = await db.rawQuery('SELECT * FROM expenses LIMIT 20');
    for (final r in rows) {
      debugPrint(r.toString());
    }
    return ExpensesDb._(db);
  }

  static Future<void> _ensureColumns(DatabaseExecutor d) async {
    final info = await d.rawQuery('PRAGMA table_info(expenses)');
    bool has(String name) => info.any((c) => (c['name'] as String).toLowerCase() == name.toLowerCase());

    if (!has('category')) {
      await d.execute('ALTER TABLE expenses ADD COLUMN category TEXT');
    }
    if (!has('ownerUserId')) {
      await d.execute('ALTER TABLE expenses ADD COLUMN ownerUserId TEXT');
      await d.execute('CREATE INDEX IF NOT EXISTS idx_expenses_owner ON expenses(ownerUserId)');
    }
    if (!has('synced')) {
      await d.execute('ALTER TABLE expenses ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
    }
  }


  Future<void> insertIfNotExists(Expense e, {required String ownerUserId, int synced = 0}) async {
    try {
      await db.insert(
        'expenses',
        {
          'timestampMs': e.timestampMs,
          'amount': e.amount,
          'currency': e.currency,
          'merchant': e.merchant,
          'category': e.category,
          'rawText': e.rawText,
          'sourcePackage': e.sourcePackage,
          'dedupeKey': e.dedupeKey,
          'ownerUserId': ownerUserId,
          'synced': synced,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      // ignore
    }
  }

  Future<List<Expense>> listLatest({int limit = 200}) async {
    final rows = await db.query(
      'expenses',
      orderBy: 'timestampMs DESC',
      limit: limit,
    );
    return rows.map((r) {
      return Expense(
        id: r['id'] as int?,
        timestampMs: r['timestampMs'] as int,
        amount: (r['amount'] as num?)?.toDouble(),
        currency: r['currency'] as String?,
        merchant: r['merchant'] as String?,
        category: r['category'] as String?,
        rawText: r['rawText'] as String?,
        sourcePackage: r['sourcePackage'] as String?,
        dedupeKey: r['dedupeKey'] as String,
      );
    }).toList();
  }

  Future<void> clearAll() async {
    await db.delete('expenses');
  }

  //version 4
  Future<void> markSynced(String dedupeKey) async {
    await db.update('expenses', {'synced': 1}, where: 'dedupeKey = ?', whereArgs: [dedupeKey]);
  }

  Future<void> attachLegacyToOwner(String ownerUserId) async {
    await db.update(
      'expenses',
      {'ownerUserId': ownerUserId},
      where: 'ownerUserId IS NULL OR ownerUserId = ?',
      whereArgs: [''],
    );
  }

  Future<List<Expense>> listLatestForOwner(String ownerUserId, {int limit = 200}) async {
    final rows = await db.query(
      'expenses',
      where: 'ownerUserId = ?',
      whereArgs: [ownerUserId],
      orderBy: 'timestampMs DESC',
      limit: limit,
    );
    return rows.map(_rowToExpense).toList();
  }

  Expense _rowToExpense(Map<String, Object?> r) {
    return Expense(
      id: r['id'] as int?,
      timestampMs: r['timestampMs'] as int,
      amount: (r['amount'] as num?)?.toDouble(),
      currency: r['currency'] as String?,
      merchant: r['merchant'] as String?,
      category: r['category'] as String?,
      rawText: r['rawText'] as String?,
      sourcePackage: r['sourcePackage'] as String?,
      dedupeKey: r['dedupeKey'] as String,
    );
  }
}

String categorizeMerchant(String? merchant) {
  final m = merchant?.toUpperCase();

  bool hasAny(List<String> kws) => kws.any((k) => m == null ? false : m.contains(k));

  if (hasAny(['YAPE', 'PLIN'])) {
    return 'Transferencias';
  }
  if (hasAny(['SUSHI', 'RESTAUR', 'PIZZA', 'BURGER', 'CAF', 'STARBUCKS', 'KFC', 'MCD'])) {
    return 'Comida';
  }
  if (hasAny(['OXXO', 'TOTTUS', 'PLAZA VEA', 'WONG', 'METRO', 'MAKRO'])) {
    return 'Supermercado';
  }
  if (hasAny(['UBER', 'DIDI', 'CABIFY', 'TAXI', 'METRO'])) {
    return 'Transporte';
  }
  if (hasAny(['CINE', 'NETFLIX', 'SPOTIFY', 'DISNEY', 'PRIME'])) {
    return 'Entretenimiento';
  }
  if (hasAny(['FARM', 'BOTICA', 'INKAFARMA', 'MIFARMA'])) {
    return 'Salud';
  }
  if (hasAny(['ELECTRO', 'AGUA', 'GAS', 'INTERNET', 'TELECOM', 'MOVISTAR', 'CLARO', 'ENTEL'])) {
    return 'Servicios';
  }

  return 'Otros';
}
