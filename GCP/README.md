# GCP endpoint services (1:1 con Amplify)

Esta carpeta contiene una versión 1:1 de tus endpoints actuales de Amplify, separados por servicio para Cloud Run.

## Endpoints incluidos

- `/profile` -> `GCP/profile`
- `/expenses` -> `GCP/expenses`
- `/subscription` -> `GCP/subscription`
- `/webhook` -> `GCP/webhook`
- `/getMPlink` -> `GCP/getMPlink`
- `/subscription/refresh` -> `GCP/subscription-refresh`
- `/subscription/summary` -> `GCP/subscription-summary`
- `/subscription/cancel` -> `GCP/subscription-cancel`

## Despliegue desde GitHub (Cloud Run)

Para cada servicio:

1. Selecciona **Implementar continuamente desde repositorio**.
2. Define **Directorio de contexto de compilación** con la carpeta del servicio (por ejemplo `GCP/profile`).
3. En **Tipo de compilación**, usa Node.js vía Buildpacks.
4. En **Objetivo de la función**, usa: `handler`.
5. Configura variables de entorno (si aplica):
   - `MP_ACCESS_TOKEN`
   - `SUCCESS_URL`

## Base de datos (Firestore)

- Colección de usuarios: `users`
- Colección de gastos: `expenses`

## Notas

- Los endpoints privados toman el usuario desde el JWT (validado por API Gateway).
- `webhook` permanece público y actualiza suscripción en `users` cuando llega un evento `approved/authorized`.
