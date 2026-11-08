#!/usr/bin/env bash
# Backup auditavel do banco PostgreSQL de origem. Nao altera producao.
# Necessita pg_dump, pg_restore, node e sha256sum.
set -Eeuo pipefail
umask 077

: "${SOURCE_BACKUP_DATABASE_URL:?Defina SOURCE_BACKUP_DATABASE_URL privadamente no ambiente de execucao.}"
: "${BACKUP_DIR:?Defina BACKUP_DIR para uma pasta privada fora do repositorio.}"

for command in node pg_dump pg_restore sha256sum; do
  command -v "$command" >/dev/null 2>&1 || { echo "Dependencia indisponivel: $command" >&2; exit 2; }
done

# Nao confiar apenas no nome do banco: confirma o projeto Supabase pelo endpoint.
node -e '
  const u=new URL(process.env.SOURCE_BACKUP_DATABASE_URL);
  const project="dsglwwwwdtjynipauvrp";
  const user=decodeURIComponent(u.username);
  const direct=u.hostname===`db.${project}.supabase.co`;
  const pool=u.hostname.endsWith(".pooler.supabase.com") && user.endsWith(`.${project}`);
  if(!["postgres:","postgresql:"].includes(u.protocol)||(!direct&&!pool)){
    process.stderr.write("Origem nao corresponde ao Supabase autorizado.\n"); process.exit(2);
  }
'

[[ "$BACKUP_DIR" = /* ]] || { echo 'BACKUP_DIR precisa ser caminho absoluto.' >&2; exit 2; }
mkdir -p -- "$BACKUP_DIR"
DEST="$(cd "$BACKUP_DIR" && pwd -P)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
case "$DEST/" in "$REPO/"*) echo 'Nao salvar backups dentro do repositorio.' >&2; exit 2;; esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NAME="supabase-coroinhas-${STAMP}.dump"
FINAL="$DEST/$NAME"
TMP="$(mktemp "$DEST/.supabase-coroinhas-XXXXXX.partial")"
trap 'rm -f -- "$TMP"' EXIT

# PGDATABASE evita registrar a connection string na linha de comando do pg_dump.
PGDATABASE="$SOURCE_BACKUP_DATABASE_URL" pg_dump \
  --format=custom --no-owner --no-privileges --serializable-deferrable \
  --file="$TMP"

# Integridade basica do arquivo e presenca das tabelas Auth e public.
MANIFEST="$(pg_restore --list "$TMP")"
grep -Eq ' TABLE auth ' <<< "$MANIFEST" || { echo 'Backup sem tabelas de auth: ABORTADO.' >&2; exit 3; }
grep -Eq ' TABLE public ' <<< "$MANIFEST" || { echo 'Backup sem tabelas public: ABORTADO.' >&2; exit 3; }

[[ ! -e "$FINAL" ]] || { echo 'Nome de backup ja existe.' >&2; exit 3; }
mv -- "$TMP" "$FINAL"
trap - EXIT
(cd "$DEST" && sha256sum "$NAME" > "$NAME.sha256")
printf '%s\n' "BACKUP_DB_CRIADO=$FINAL" "CHECKSUM=$FINAL.sha256" \
  'RESTAURACAO_AINDA_NAO_COMPROVADA=true' \
  'BACKUP_DO_BANCO_NAO_INCLUI_CONFIGURACOES_EXTERNAS_DO_PROJETO=true'
