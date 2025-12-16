# Script para sincronizar el Taller (Windows) con la Bóveda (WSL)
Write-Host "Sincronizando Frontend con el Repositorio en WSL..." -ForegroundColor Cyan

# Rutas (Ajustadas a tu entorno)
$source = "C:\src\paws_app\*"
$dest = "\\wsl.localhost\Ubuntu\home\alonso\dev\PAWS-2.0\app"

# Copiar todo (excluyendo carpetas basura de compilación para que sea rápido)
# Usamos Robocopy que es más rápido e inteligente para ignorar archivos
robocopy "C:\src\paws_app" $dest /MIR /XD .dart_tool .idea build .git

Write-Host "Sincronización completada. Ahora puedes hacer 'git commit' en Ubuntu." -ForegroundColor Green
Pause