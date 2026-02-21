# Configuración de Google Sign In para Gmail

## Problema actual
El error que ves indica que Google Sign In no está configurado correctamente para tu app.

## Pasos para solucionar:

### 1. Obtener el SHA-1 de tu keystore de debug

Ejecuta el archivo `get_sha1.bat` o ejecuta manualmente:

```bash
cd android
gradlew signingReport
```

Busca en la salida el **SHA-1** del keystore de **debug**. Se verá algo como:
```
SHA1: AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD
```

### 2. Configurar OAuth 2.0 en Google Cloud Console

1. Ve a [Google Cloud Console](https://console.cloud.google.com/)
2. Crea un proyecto nuevo o selecciona uno existente
3. Ve a **APIs & Services > Credentials**
4. Click en **+ CREATE CREDENTIALS > OAuth client ID**
5. Selecciona **Android** como tipo de aplicación
6. Configura:
   - **Name**: Phonance Android
   - **Package name**: `com.luis.phonance`
   - **SHA-1 certificate fingerprint**: Pega el SHA-1 que obtuviste en el paso 1
7. Click en **CREATE**

### 3. Habilitar Gmail API

1. En Google Cloud Console, ve a **APIs & Services > Library**
2. Busca "Gmail API"
3. Click en **ENABLE**

### 4. Reintentar la conexión

Una vez configurado todo, vuelve a intentar conectar Gmail en la app.

### Notas importantes:

- El SHA-1 del keystore de **release** será diferente. Cuando publiques la app, necesitarás agregar ese SHA-1 también.
- Si usas Google Play App Signing, necesitarás el SHA-1 que Google Play genera automáticamente.

### Verificar package name

Asegúrate de que el package name en `android/app/build.gradle.kts` sea `com.luis.phonance`
