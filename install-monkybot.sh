#!/usr/bin/env bash
# Monky Bot installer
# Instala o Monky Bot oficial como CLI global (monkybot).
#
# Usage:
#   curl -fsSL https://monkyorg.github.io/install-monkybot.sh | bash
set -euo pipefail

REPO="MonkyOrg/MonkyBot"
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
DIM="\033[2m"
RESET="\033[0m"

info()  { printf "${CYAN}%s${RESET}\n" "$*"; }
ok()    { printf "${GREEN}%s${RESET}\n" "$*"; }
err()   { printf "${RED}%s${RESET}\n" "$*" >&2; }
bold()  { printf "${BOLD}%s${RESET}\n" "$*"; }

bold "🤖 Monky Bot Installer"
echo ""

# --- Check dependencies ---

if ! command -v node &>/dev/null; then
  err "Node.js não encontrado. Instale o Node.js 18+ antes de continuar."
  err "https://nodejs.org/"
  exit 1
fi

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [ "$NODE_MAJOR" -lt 18 ]; then
  err "Node.js $NODE_MAJOR detectado, mas o Monky Bot requer Node.js 18+."
  exit 1
fi

if ! command -v npm &>/dev/null; then
  err "npm não encontrado. Instale o npm antes de continuar."
  exit 1
fi

info "Node.js $(node -v) • npm $(npm -v)"

# --- Fetch latest release ---

info "Buscando última versão..."

API_URL="https://api.github.com/repos/$REPO/releases/latest"

API_RESPONSE=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" "$API_URL" 2>/dev/null) || {
  err "Falha ao consultar a API do GitHub. Verifique sua conexão."
  exit 1
}

TGZ_URL=$(echo "$API_RESPONSE" | node -e "
  const release = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  const asset = (release.assets||[]).find(a => a.name && a.name.includes('monky-bot') && a.name.endsWith('.tgz'));
  if (!asset) { process.exit(1); }
  process.stdout.write(asset.browser_download_url);
") || {
  err "Nenhuma release com artefato monky-bot encontrada."
  err "Verifique: https://github.com/$REPO/releases"
  exit 1
}

if [ -z "$TGZ_URL" ]; then
  err "Não foi possível encontrar o artefato de instalação."
  exit 1
fi

VERSION=$(echo "$TGZ_URL" | grep -oP 'monky-bot-\K[^.]+\.[^.]+\.[^.]+[^/]*(?=\.tgz)')
info "Versão: $VERSION"
echo ""

# --- Install ---

bold "Instalando Monky Bot..."
info "$TGZ_URL"
echo ""

npm install -g "$TGZ_URL"

echo ""
ok "✅ Monky Bot instalado com sucesso!"
echo ""
printf "${DIM}Primeiros passos:${RESET}\n"
echo ""
echo "  monkybot setup     — Configura servidor e token interativamente"
echo "  monkybot start     — Inicia o bot em background via pm2"
echo "  monkybot status    — Verifica o estado"
echo "  monkybot logs      — Exibe os logs"
echo "  monkybot --help    — Ver todos os comandos"
echo ""
echo "  📖 Docs: https://monkyorg.github.io/Monky/bots"
echo ""
