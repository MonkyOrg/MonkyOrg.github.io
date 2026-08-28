#!/usr/bin/env bash
# Monky CLI installer
# Usage:
#   curl -fsSL https://monkyorg.github.io/install.sh | bash
#   curl -fsSL https://monkyorg.github.io/install.sh | bash -s -- --beta
set -euo pipefail

REPO="MonkyOrg/Monky"
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

INCLUDE_BETA=false
for arg in "$@"; do
  case "$arg" in
    --beta|-b) INCLUDE_BETA=true ;;
    --help|-h)
      echo "Monky CLI installer"
      echo ""
      echo "Usage:"
      echo "  curl -fsSL https://monkyorg.github.io/install.sh | bash"
      echo "  curl -fsSL https://monkyorg.github.io/install.sh | bash -s -- --beta"
      echo ""
      echo "Options:"
      echo "  --beta, -b   Install the latest version including betas"
      echo "  --help, -h   Show this help"
      exit 0
      ;;
    *)
      err "Unknown option: $arg"
      exit 1
      ;;
  esac
done

bold "🐵 Monky CLI Installer"
echo ""

# --- Check dependencies ---

if ! command -v node &>/dev/null; then
  err "Node.js não encontrado. Instale o Node.js 20+ antes de continuar."
  err "https://nodejs.org/"
  exit 1
fi

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [ "$NODE_MAJOR" -lt 20 ]; then
  err "Node.js $NODE_MAJOR detectado, mas o Monky CLI requer Node.js 20+."
  exit 1
fi

if ! command -v npm &>/dev/null; then
  err "npm não encontrado. Instale o npm antes de continuar."
  exit 1
fi

info "Node.js $(node -v) • npm $(npm -v)"

# --- Fetch latest release ---

if [ "$INCLUDE_BETA" = true ]; then
  info "Canal: beta (inclui prereleases)"
  API_URL="https://api.github.com/repos/$REPO/releases?per_page=100"
else
  info "Canal: estável"
  API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi

info "Buscando última versão..."

API_RESPONSE=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" "$API_URL" 2>/dev/null) || {
  err "Falha ao consultar a API do GitHub. Verifique sua conexão."
  exit 1
}

if [ "$INCLUDE_BETA" = true ]; then
  # Pick the newest non-draft release by sorting semver tags
  TGZ_URL=$(echo "$API_RESPONSE" | node -e "
    const releases = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const parse = v => {
      const c = String(v||'').replace(/^v/,'');
      const [main, pre] = c.split('-');
      const [M=0,m=0,p=0] = main.split('.').map(Number);
      const b = pre ? ((/beta\.?(\d+)/i.exec(pre))||[])[1]|0 : 0;
      return {M,m,p,beta:!!pre,b};
    };
    const cmp = (a,b) => {
      const x=parse(a), y=parse(b);
      if(x.M!==y.M) return y.M-x.M;
      if(x.m!==y.m) return y.m-x.m;
      if(x.p!==y.p) return y.p-x.p;
      if(x.beta&&!y.beta) return 1;
      if(!x.beta&&y.beta) return -1;
      return y.b-x.b;
    };
    const valid = releases.filter(r => !r.draft && r.tag_name);
    valid.sort((a,b) => cmp(a.tag_name, b.tag_name));
    const best = valid[0];
    if (!best) { process.exit(1); }
    const asset = (best.assets||[]).find(a => a.name && a.name.includes('monky-cli') && a.name.endsWith('.tgz'));
    if (!asset) { process.exit(1); }
    process.stdout.write(asset.browser_download_url);
  ") || {
    err "Nenhuma release com artefato monky-cli encontrada."
    exit 1
  }
else
  TGZ_URL=$(echo "$API_RESPONSE" | node -e "
    const release = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const asset = (release.assets||[]).find(a => a.name && a.name.includes('monky-cli') && a.name.endsWith('.tgz'));
    if (!asset) { process.exit(1); }
    process.stdout.write(asset.browser_download_url);
  ") || {
    err "Nenhuma release com artefato monky-cli encontrada."
    exit 1
  }
fi

if [ -z "$TGZ_URL" ]; then
  err "Não foi possível encontrar o artefato de instalação."
  exit 1
fi

VERSION=$(echo "$TGZ_URL" | grep -oP 'monky-cli-\K[^.]+\.[^.]+\.[^.]+[^/]*(?=\.tgz)')
info "Versão: $VERSION"
echo ""

# --- Install ---

bold "Instalando Monky CLI..."
info "$TGZ_URL"
echo ""

npm install -g "$TGZ_URL"

echo ""
ok "✅ Monky CLI instalado com sucesso!"
echo ""
printf "${DIM}Comece com:${RESET}\n"
echo "  monky create    — criar um novo servidor"
echo "  monky --help    — ver todos os comandos"
echo ""
