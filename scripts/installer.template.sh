#!/bin/bash
set -e
PROJECT_DIR="$HOME/command-center"

echo "⚡ Command Center v7.10 - installerer i $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR/app/templates" "$PROJECT_DIR/app/data" "$PROJECT_DIR/app/static" "$PROJECT_DIR/deploy" "$PROJECT_DIR/scripts"
echo "📄 requirements.txt..."
cat << 'EOF_REQ' > "$PROJECT_DIR/requirements.txt"
#@@embed:requirements.txt@@
EOF_REQ

echo "📄 .env.example..."
cat << 'EOF_ENVDOT' > "$PROJECT_DIR/.env.example"
#@@embed:.env.example@@
EOF_ENVDOT

echo "📄 app/main.py..."
cat << 'EOF_MAIN' > "$PROJECT_DIR/app/main.py"
#@@embed:app/main.py@@
EOF_MAIN

echo "📄 app/templates/dashboard.html..."
cat << 'EOF_HTML' > "$PROJECT_DIR/app/templates/dashboard.html"
#@@embed:app/templates/dashboard.html@@
EOF_HTML

echo "📄 app/templates/login.html..."
cat << 'EOF_LOGIN' > "$PROJECT_DIR/app/templates/login.html"
#@@embed:app/templates/login.html@@
EOF_LOGIN

echo "📄 run.sh..."
cat << 'EOF_RUNSH' > "$PROJECT_DIR/run.sh"
#@@embed:run.sh@@
EOF_RUNSH

echo "📄 Dockerfile..."
cat << 'EOF_DOCKER' > "$PROJECT_DIR/Dockerfile"
#@@embed:Dockerfile@@
EOF_DOCKER

echo "📄 docker-compose.yml..."
cat << 'EOF_COMPOSE' > "$PROJECT_DIR/docker-compose.yml"
#@@embed:docker-compose.yml@@
EOF_COMPOSE

echo "📄 deploy/command-center.service..."
cat << 'EOF_SERVICE' > "$PROJECT_DIR/deploy/command-center.service"
#@@embed:deploy/command-center.service@@
EOF_SERVICE

echo "📄 README.md..."
cat << 'EOF_README' > "$PROJECT_DIR/README.md"
#@@embed:README.md@@
EOF_README

echo "📄 scripts/smoke_test.sh..."
cat << 'EOF_SMOKE' > "$PROJECT_DIR/scripts/smoke_test.sh"
#@@embed:scripts/smoke_test.sh@@
EOF_SMOKE

echo "📄 run.bat..."
cat << 'EOF_WINBAT' > "$PROJECT_DIR/run.bat"
#@@embed:run.bat@@
EOF_WINBAT

if [ -f "$PROJECT_DIR/.env" ]; then echo "✅ .env findes allerede - bruger den"; else cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"; echo "⚠ Opret .env (se .env.example) inden foerste start"; fi
cat << 'EOF_RUN' > "$PROJECT_DIR/run.sh"
#@@embed:run.sh@@
EOF_RUN
chmod +x "$PROJECT_DIR/run.sh"
if curl -s -o /dev/null --max-time 3 http://127.0.0.1:8000/health 2>/dev/null; then echo "🔎 App koerer allerede - koerer smoke-test:"; bash "$PROJECT_DIR/scripts/smoke_test.sh" || true; fi
echo "✨ Installation klar! Sæt noegler i $PROJECT_DIR/.env og kør: cd ~/command-center && ./run.sh (smoke-test bagefter: bash scripts/smoke_test.sh)"

