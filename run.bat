@echo off
REM Command Center - Windows startscript (v7.9). Ligger .env ved siden af og koer filen.
cd /d "%~dp0"
if exist .env for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do set "%%a=%%b"
if not exist venv python -m venv venv
call venv\Scripts\activate.bat
python -m pip install --upgrade pip > nul 2>&1
python -m pip install -r requirements.txt
echo Starter Command Center v7.9 (Windows - lokal brug, self-update er Linux-only)...
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
