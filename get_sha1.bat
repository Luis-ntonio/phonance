@echo off
echo Getting SHA-1 fingerprint for debug keystore...
echo.
cd android
gradlew signingReport
echo.
echo Check the output above for SHA-1 certificate fingerprints
pause
