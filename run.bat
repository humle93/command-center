@echo off
REM Command Center - Windows startscript. Opretter din bruger ved foerste besoeg (ingen token).
cd /d "%~dp0"
if exist .env for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do set "%%a=%%b"
set "HOST=127.0.0.1"
set "PORT=8000"
set "FORWARDED=127.0.0.1"
if defined CC_HOST set "HOST=%CC_HOST%"
if defined CC_PORT set "PORT=%CC_PORT%"
if defined CC_FORWARDED_ALLOW_IPS set "FORWARDED=%CC_FORWARDED_ALLOW_IPS%"
if not exist venv python -m venv venv
call venv\Scripts\activate.bat
python -m pip install --upgrade pip > nul 2>&1
python -m pip install -r requirements.txt
set "LAN="
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4"') do if not defined LAN set "LAN=%%i"
if defined LAN set "LAN=%LAN: =%"
echo Starter Command Center v7.11 (Windows)...
echo    Lokalt:   http://127.0.0.1:%PORT%
if defined CC_PUBLIC_URL echo    Offentlig: %CC_PUBLIC_URL%   (via nginx -^> http://%HOST%:%PORT%)
if defined LAN echo    Netvaerk: http://%LAN%:%PORT%   (naas kun med CC_HOST=0.0.0.0)
echo    Login:    opret din bruger ved foerste besoeg (ingen token).
python -m uvicorn app.main:app --host %HOST% --port %PORT% --proxy-headers --forwarded-allow-ips %FORWARDED%
