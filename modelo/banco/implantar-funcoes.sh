#!/usr/bin/env bash
# Publica as Edge Functions deste restaurante. Uso:  ./implantar-funcoes.sh <ref-do-projeto> <https://usuario.github.io/repositorio/>
# Precisa do Supabase CLI logado (supabase login).
set -e
REF="$1"; SITE="$2"
[ -z "$REF" ] || [ -z "$SITE" ] && { echo "Uso: $0 <ref-do-projeto> <url-do-site-com-barra-no-fim>"; exit 1; }
ORIGEM=$(echo "$SITE" | sed -E 's#^(https?://[^/]+).*#\1#')
supabase secrets set --project-ref "$REF" SITE_URL="$SITE" SITE_ORIGEM="$ORIGEM"
cd "$(dirname "$0")/funcoes"
for d in */; do n="${d%/}"; echo ">> $n"; supabase functions deploy "$n" --project-ref "$REF" --no-verify-jwt; done
