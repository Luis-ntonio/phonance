# Migración de gastos AWS -> GCP

Este script migra datos desde DynamoDB (AWS Amplify) a Firestore (GCP) para las colecciones usadas por tus servicios Cloud Run.

## Qué migra

- Tabla de perfiles (`username`) -> Firestore DB `<databaseId>` / collection `users`
- Tabla de gastos (`userId`, `sk`) -> Firestore DB `<databaseId>` / collection `expenses`

`users-db`, `expenses-db` y `firestore-db` son **database IDs de Firestore**, no nombres de colección.

## Requisitos

- Credenciales AWS válidas en tu shell (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, opcional `AWS_SESSION_TOKEN`)
- Credenciales GCP con acceso a Firestore (ADC: `GOOGLE_APPLICATION_CREDENTIALS` o cuenta con sesión activa)
- Permisos de escritura en Firestore y lectura de DynamoDB

### Variables GCP requeridas

`$env:GOOGLE_CLOUD_PROJECT='tu-project-id'`

`$env:GOOGLE_APPLICATION_CREDENTIALS='C:\ruta\service-account.json'`

También puedes pasar argumentos al script:

- `--gcp-project-id=tu-project-id`
- `--gcp-key-file=C:\ruta\service-account.json`
- `--gcp-credentials-json='{...service_account_json...}'`

Nota: por defecto el script usa transporte REST en Firestore para evitar errores de gRPC en entornos Windows. Si quieres forzar gRPC usa `--use-grpc`.

### Opciones de credenciales AWS (PowerShell)

Opción A (perfil):

`$env:AWS_PROFILE='default'`

`$env:AWS_SDK_LOAD_CONFIG='1'`

Opción B (claves directas):

`$env:AWS_ACCESS_KEY_ID='TU_KEY'`

`$env:AWS_SECRET_ACCESS_KEY='TU_SECRET'`

`$env:AWS_REGION='us-east-1'`

También puedes pasar al script:

- `--aws-profile=default`
- `--aws-access-key-id=... --aws-secret-access-key=... [--aws-session-token=...]`

## Instalar dependencias

Desde `GCP/migration`:

`npm install`

## Ejecución recomendada

1) Primero simulación (sin escribir):

`npm run migrate -- --aws-region=us-east-1 --users-table=<TABLA_USERS_AWS> --expenses-table=<TABLA_EXPENSES_AWS> --firestore-db=<DATABASE_ID> --dry-run`

2) Migración real:

`npm run migrate -- --aws-region=us-east-1 --users-table=<TABLA_USERS_AWS> --expenses-table=<TABLA_EXPENSES_AWS> --firestore-db=<DATABASE_ID>`

Ejemplo completo con args de AWS/GCP:

`npm run migrate -- --aws-profile=default --aws-region=us-east-1 --users-table=<TABLA_USERS_AWS> --expenses-table=<TABLA_EXPENSES_AWS> --gcp-project-id=<GCP_PROJECT_ID> --gcp-key-file=C:\ruta\service-account.json --firestore-db=<DATABASE_ID>`

Ejemplo para tu caso (database ID `phonance`):

`npm run migrate -- --aws-region=us-east-1 --users-table=phonanceDynamo-dev --expenses-table=phonanceExpenses-dev --gcp-project-id=phonance-486106 --gcp-key-file=C:\Users\lagg1\Downloads\phonance-486106-b8cfe0edfd25.json --firestore-db=phonance --dry-run`

## Estrategia segura (recomendada)

1. Congela escritura en app antigua (o ventana de baja actividad)
2. Ejecuta migración real
3. Valida conteos y muestras en Firestore
4. Cambia tráfico de app al backend GCP

## Validaciones mínimas post-migración

- Conteo de documentos `users` en Firestore ~= cantidad de usuarios en DynamoDB
- Conteo de documentos `expenses` en Firestore ~= cantidad de gastos en DynamoDB
- Probar en app:
  - login
  - carga de historial de gastos
  - registrar gasto nuevo y verificar local + cloud

## Bootstrap de usuarios en Firebase Auth

La migración de DynamoDB no mueve contraseñas de Cognito a Firebase Auth. Para habilitar login en la app Firebase, crea/provisiona usuarios desde Firestore `users`.

### Comando (simulación)

`npm run bootstrap-auth -- --gcp-project-id=<GCP_PROJECT_ID> --gcp-key-file=C:\ruta\service-account.json --firestore-db=<DATABASE_ID> --dry-run`

### Comando real

`npm run bootstrap-auth -- --gcp-project-id=<GCP_PROJECT_ID> --gcp-key-file=C:\ruta\service-account.json --firestore-db=<DATABASE_ID>`

Si Firestore y Firebase Auth están en proyectos distintos:

`npm run bootstrap-auth -- --firestore-project-id=<FIRESTORE_PROJECT_ID> --firestore-key-file=C:\ruta\firestore-sa.json --auth-project-id=<AUTH_PROJECT_ID> --auth-key-file=C:\ruta\auth-sa.json --firestore-db=<DATABASE_ID>`

Notas:

- El script usa `doc.id` de Firestore como `uid` de Firebase Auth (evita romper referencias).
- Si el usuario ya existe, lo actualiza.
- Si no existe, lo crea con contraseña temporal aleatoria.
- Luego el usuario usa “Olvidé mi contraseña” en la app para definir su contraseña final.
