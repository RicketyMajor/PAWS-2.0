# 1. Obtiene la IP actual de WSL automáticamente
$wsl_ip = (wsl hostname -I).Trim().Split(" ")[0]

Write-Host "Detectada IP de WSL: $wsl_ip" -ForegroundColor Green

# 2. Borra la regla vieja (para evitar conflictos)
netsh interface portproxy delete v4tov4 listenport=8080 listenaddress=0.0.0.0

# 3. Crea la regla nueva
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=$wsl_ip

# 4. Abre el firewall (por si acaso se cerró)
netsh advfirewall firewall add rule name="WSL Bridge 8080" dir=in action=allow protocol=TCP localport=8080

Write-Host "Puente listo. Tu backend en WSL ahora es visible desde Windows/Emulador." -ForegroundColor Cyan
Pause