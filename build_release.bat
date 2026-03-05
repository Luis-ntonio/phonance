@echo off
echo Building Phonance release AAB...

flutter build appbundle --release ^
  --dart-define=PHONANCE_API_BASE_URL=https://phonance-gate-89lez58f.ue.gateway.dev ^
  --dart-define=PHONANCE_PRIVACY_URL=https://phonance-43490.web.app/privacy-policy

echo.
echo Done! AAB located at:
echo build\app\outputs\bundle\release\app-release.aab
