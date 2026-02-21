# Copilot Instructions - Phonance

## Descripción del Proyecto

**Phonance** es una aplicación multiplataforma de gestión financiera personal desarrollada en Flutter que automatiza el seguimiento de gastos mediante el análisis de notificaciones bancarias. La app integra servicios de AWS Amplify para autenticación, almacenamiento y API backend.

### Propósito Principal
- Capturar y analizar notificaciones de bancos/wallets digitales automáticamente
- Registrar gastos en base a información extraída de las notificaciones
- Proporcionar visualizaciones y reportes de gastos por categoría y periodo
- Alertas de presupuesto y metas de ahorro
- Sistema de suscripción para funcionalidades premium

## Arquitectura y Stack Tecnológico

### Frontend
- **Framework**: Flutter (SDK 3.10.4+)
- **Lenguaje**: Dart
- **UI**: Material Design 3
- **Plataformas soportadas**: Android, iOS, Web, Linux, macOS, Windows

### Backend y Servicios
- **AWS Amplify**: Autenticación (Cognito), API REST, almacenamiento
- **Base de datos local**: SQLite (sqflite)
- **Notificaciones**: Flutter Local Notifications
- **Gráficos**: fl_chart
- **Pagos**: In-App Purchase (Google Play, App Store)
- **Comunicación nativa**: Platform Channels (MethodChannel/EventChannel)

### Estructura del Proyecto

```
lib/
├── main.dart                      # Entry point, HomePage, modelo Expense, ExpensesDb
├── amplify_initializer.dart       # Configuración de Amplify
├── amplifyconfiguration.dart      # Config generada por Amplify CLI
├── charts_utils.dart              # Utilidades para gráficos
├── test_notification.dart         # Herramientas de prueba de notificaciones
├── auth/                          # Autenticación y autorización
│   ├── auth_gate.dart            # Guard de autenticación
│   ├── auth_service.dart         # Servicios de auth
│   ├── login_page.dart           # Pantalla de login
│   ├── signup_page.dart          # Pantalla de registro
│   ├── confirm_sign_up_page.dart # Confirmación de email
│   └── profile_api.dart          # API de perfil de usuario
├── subscription/                  # Sistema de suscripción
│   ├── subscription_gate.dart    # Guard de suscripción
│   ├── subscription_page.dart    # Pantalla de suscripción
│   └── subscription_api.dart     # API de verificación de suscripción
├── apiExpenses/                   # Integración con backend de gastos
│   └── expenses_api.dart         # API REST para gastos
├── notifications/                 # Sistema de notificaciones
│   ├── notification_service.dart # Servicio de notificaciones locales
│   └── budget_alert_manager.dart # Gestor de alertas de presupuesto
├── settings/                      # Configuración de usuario
│   ├── settings_tab.dart         # Tab principal de settings
│   ├── account_settings_page.dart
│   ├── goals_settings_page.dart
│   └── membership_settings_page.dart
└── summary/                       # Visualizaciones y reportes
    ├── summary_tab.dart
    ├── monthly_summary_card.dart
    ├── monthly_category_pie.dart
    ├── expenses_history_chart.dart
    ├── savings_history_chart.dart
    └── category_palette.dart
```

## Flujo de Autenticación y Autorización

1. **AuthGate**: Verifica si el usuario está autenticado
2. **SubscriptionGate**: Verifica estado de suscripción (premium/free)
3. **HomePage**: Página principal con acceso a funcionalidades

### Gestión de Estado de Usuario
- Usuario autenticado: `Amplify.Auth.getCurrentUser()` → `user.userId`
- Perfil de usuario: `ProfileApi.getProfile()` → incluye `monthlyIncome`, `spendingLimit`, `preferredCurrency`
- Cada gasto se asocia a `ownerUserId` en la base de datos local

### Prevención de Duplicados
- **dedupeKey**: Hash estable basado en contenido normalizado + source + día (no hora exacta)
- Normalización: elimina espacios múltiples, limita a 150 caracteres
- Solo Flutter escribe en SQLite (el listener nativo solo emite eventos)
- Redondeo a nivel de día evita duplicados por actualizaciones de notificación

## Sistema de Gastos (Expenses)

### Modelo de Datos: Expense
```dart
class Expense {
  final int timestampMs;
  final double? amount;
  final String? currency;
  final String? merchant;
  final String? category;
  final String? rawText;
  final String? sourcePackage;
  final String dedupeKey;
}
```

### Flujo de Captura de Gastos

1. **Notificación recibida**: Listener de `EventChannel` en código nativo (Android)
2. **Parseo**: `Expense.fromNotification()` extrae datos estructurados
3. **Almacenamiento local**: `ExpensesDb.insertIfNotExists()` con `synced=0`
4. **Sincronización cloud**: `ExpensesApi.postExpense()` → marca `synced=1` si éxito
5. **Actualización UI**: `_loadItems()` refresca lista

### Base de Datos Local (SQLite)

- **Tabla**: `expenses`
- **Campos clave**: `dedupeKey` (unique), `ownerUserId`, `synced` (0/1)
- **Métodos principales**:
  - `insertIfNotExists()`: Insert OR IGNORE basado en dedupeKey
  - `listLatest(limit)`: Consulta últimos N gastos del usuario
  - `attachLegacyToOwner()`: Migra gastos sin ownerUserId
  - `markSynced()`: Actualiza flag de sincronización

### API Backend (ExpensesApi)

- **Endpoint**: `/expenses` (REST API en AWS API Gateway)
- **Autenticación**: JWT (ID Token de Cognito) en header `Authorization`
- **Métodos**:
  - `POST /expenses`: Crear nuevo gasto
  - `GET /expenses?fromMs=X&limit=Y`: Obtener gastos desde timestamp

## Notificaciones y Permisos

### Notification Access (Android)
- Requiere permiso `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`
- Verificación: `_platform.invokeMethod('hasNotificationAccess')`
- Apertura de settings: `_platform.invokeMethod('openNotificationAccessSettings')`

### Filtrado de Notificaciones
**Paquetes permitidos**:
- `com.google.android.apps.walletnfcrel` (Google Wallet)
- `com.google.android.gm` (Gmail - solo transacciones BCP/Yape)
- `com.google.android.gms` (intermediación)

**Filtros aplicados**:
1. **Filtro de paquete**: Solo paquetes en whitelist
2. **Filtro de Gmail específico**: Solo notificaciones de BCP/Yape con contenido de transacción
3. **Filtro de grupo**: Rechaza notificaciones agrupadas (`FLAG_GROUP_SUMMARY`)
4. **Filtro de contenido**: Requiere palabras clave de acción (pago, compra) + moneda
5. **Filtro de exclusión**: Rechaza promociones, recordatorios, mensajes genéricos

**Prevención de falsos positivos**:
- Requiere múltiples indicadores (acción + dinero)
- Lista de exclusión para palabras como "promoción", "recordatorio", "bienvenido"

### Notificaciones Locales
- Alertas de presupuesto: `BudgetAlertManager.evaluateAndNotify()`
- Notificaciones de prueba: `TestNotifications.showWalletLikeNotification()`

## Visualizaciones y Reportes

### Componentes de Gráficos
- **MonthlyCategory Pie**: Distribución de gastos por categoría (mes actual)
- **ExpensesHistoryChart**: Historial de gastos en el tiempo
- **SavingsHistoryChart**: Evolución de ahorros
- **MonthlySummaryCard**: Resumen de gastos del mes

### Utilidades
- `filterCurrentMonth()`: Filtra gastos del mes actual
- `category_palette.dart`: Colores consistentes por categoría

## Configuración de Amplify

### Plugins Configurados
1. **AmplifyAuthCognito**: Autenticación de usuarios
2. **AmplifyAPI**: REST API con API Gateway

### Inicialización
```dart
await AmplifyInit.ensureConfigured();
```

### Estructura Backend (amplify/)
- `auth/`: Configuración de Cognito User Pools
- `api/`: Definición de API Gateway
- `function/`: Funciones Lambda
- `storage/`: S3 buckets (si aplica)

## Convenciones de Código

### Idioma
- **Código**: Variables, funciones y clases en inglés
- **UI/UX**: Textos en español
- **Comentarios**: Español
- **Logs**: Español con `debugPrint()`

### Formato de Fechas/Moneda
- Timestamps: Milisegundos desde epoch (`timestampMs`)
- Moneda: String de código ISO (e.g., "PEN", "USD")
- Formato de fecha: `DateFormat('yyyy-MM-dd HH:mm:ss')`

### Manejo de Errores
- **Cloud sync failures**: No romper la app, log con `debugPrint()`, mantener `synced=0`
- **Offline-first**: Priorizar funcionamiento local, sincronizar cuando sea posible
- **Try-catch**: Siempre en operaciones de red y DB

### Estado y Lifecycle
- `initState()`: Inicialización de listeners, carga inicial de datos
- `dispose()`: Cancelar StreamSubscriptions
- `mounted check`: Antes de `setState()` en callbacks asíncronos

## Platform Channels

### MethodChannel: `com.luis.phonance/methods`
- `hasNotificationAccess()`: bool
- `openNotificationAccessSettings()`: void

### EventChannel: `com.luis.phonance/events`
- Stream de eventos de notificaciones bancarias
- Payload: `Map<String, dynamic>` con datos del gasto

## Testing

### Notificaciones de Prueba
Botón en AppBar para disparar notificación simulada:
```dart
TestNotifications.showWalletLikeNotification(
  currency: 'PEN',
  merchant: 'OXXO ALIAGA',
  amount: 11.89,
  cardSuffix: '8487',
)
```

## Buenas Prácticas para Desarrollo

### 1. Sincronización de Datos
- Siempre intentar POST a cloud después de insertar en local
- Marcar `synced=1` solo si POST exitoso
- Implementar retry logic para gastos con `synced=0`

### 2. Performance
- Limitar consultas DB: `listLatest(limit: 200)`
- Cargar datos cloud solo una vez: `_loadFromCloudOnce()`
- Usar `WHERE ownerUserId = ?` para multi-tenancy

### 3. Seguridad
- Nunca loguear tokens completos
- Verificar `ownerUserId` en todas las operaciones DB
- Validar datos de notificaciones antes de parsear

### 4. UI/UX
- Loading states durante operaciones asíncronas
- Mensajes de error claros en español
- Confirmaciones para acciones destructivas (borrar todo)

### 5. Offline Support
- Guardar primero en SQLite, sincronizar después
- Manejar fallos de red sin interrumpir UX
- Mostrar estado de sincronización si es relevante

## Comandos Útiles

### Flutter
```bash
flutter pub get              # Instalar dependencias
flutter run                  # Ejecutar en dispositivo/emulador
flutter build apk           # Build para Android
flutter clean               # Limpiar build cache
```

### Amplify CLI
```bash
amplify pull                # Sincronizar config desde cloud
amplify push                # Aplicar cambios de backend
amplify status              # Ver estado de recursos
```

## Dependencias Principales

| Paquete | Versión | Propósito |
|---------|---------|-----------|
| `amplify_flutter` | ^2.8.0 | Framework Amplify |
| `amplify_auth_cognito` | ^2.8.0 | Autenticación |
| `amplify_api` | ^2.8.0 | REST/GraphQL API |
| `sqflite` | ^2.3.3 | Base de datos SQLite |
| `fl_chart` | ^1.1.1 | Gráficos y visualizaciones |
| `intl` | ^0.20.2 | Internacionalización y formato |
| `flutter_local_notifications` | ^17.2.2 | Notificaciones locales |
| `in_app_purchase` | ^3.0.0 | Compras in-app |

## Notas Importantes

### Multi-tenancy
- Todos los datos están aislados por `ownerUserId`
- La migración de datos legacy se hace con `attachLegacyToOwner()`

### Categorización Automática
- Se extrae `category` de las notificaciones
- Categoría por defecto: "Otros"

### Presupuesto y Alertas
- `BudgetAlertManager` evalúa gastos vs límite mensual
- Se ejecuta después de cada nuevo gasto y en inicio de app
- Configuración desde `ProfileApi.getProfile()`

### Suscripción Premium
- Gate implementado con `SubscriptionGate`
- Verificación con `SubscriptionApi.refreshStatus()`
- Fallback a cache en Dynamo si servicio de pagos falla

---

## Al Trabajar en Este Proyecto

1. **Mantén la consistencia**: Sigue las convenciones de idioma (español en UI, inglés en código)
2. **Offline-first**: Toda funcionalidad debe funcionar sin conexión cuando sea posible
3. **Testing**: Usa las herramientas de notificaciones de prueba para validar flujos
4. **Security**: Valida permisos y autenticación en cada feature
5. **Performance**: Considera el impacto de queries DB y llamadas API
6. **Documentation**: Comenta código complejo, especialmente lógica de parseo y sincronización

---

**Última actualización**: Enero 2026
**Versión de la app**: 1.0.0+1
**SDK de Flutter**: ^3.10.4
