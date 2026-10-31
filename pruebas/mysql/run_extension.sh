#!/usr/bin/env bash
# Prueba sql/bna_extension.sql: carga el DDL y la extensión, y ejecuta todas las
# pruebas SQL de la base (pruebas.sql y pruebas_admin.sql) más las de la
# extensión. Muestra que las reglas existentes siguen pasando con la extensión
# cargada. Las pruebas con dos sesiones y las brechas siguen en run_tests.sh.
# No escribe en resultados/: la extensión queda fuera de la matriz.
#
# Uso: pruebas/mysql/run_extension.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/lib/comun.sh"
C="bna-pruebas-extension-$$"
TMP="$(mktemp -d)"

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

docker run -d --rm --name "$C" -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
  -v "$ROOT/conf/mysql/bna.cnf:/etc/mysql/conf.d/bna.cnf:ro" "$MYSQL_IMAGE" >/dev/null
for _ in $(seq 1 90); do
  docker exec "$C" mysql -uroot -h127.0.0.1 --protocol=TCP -e 'SELECT 1' >/dev/null 2>&1 && break
  sleep 2
done

root_() { docker exec -i "$C" mysql -uroot --default-character-set=utf8mb4 "$@"; }
app_() { docker exec -i -e MYSQL_PWD=app "$C" mysql -ubna_app_user --default-character-set=utf8mb4 "$@"; }
admin_() { docker exec -i -e MYSQL_PWD=admin "$C" mysql -ubna_admin_user --default-character-set=utf8mb4 "$@"; }

root_ < "$ROOT/sql/bna_core.sql" > "$TMP/carga.log" 2>&1
root_ < "$HERE/arnes.sql"
root_ < "$HERE/datos.sql"
root_ < "$ROOT/sql/bna_extension.sql"
root_ -e "INSERT INTO core.periodo_contable VALUES (2001, 1, '2001-01-01', '2001-01-31', 'CERRADO'),
                                                   (2002, 1, '2002-01-01', '2002-01-31', 'ABIERTO')"

cat "$HERE/pruebas.sql" "$HERE/pruebas_extension.sql" | app_ > "$TMP/app.log" 2>&1 || { tail -5 "$TMP/app.log"; exit 1; }
cat "$HERE/pruebas_admin.sql" "$HERE/pruebas_extension_admin.sql" | admin_ > "$TMP/admin.log" 2>&1 || { tail -5 "$TMP/admin.log"; exit 1; }

root_ -N -e "SELECT IF(id LIKE 'X%', 'extension', 'base') grupo, IF(ok IS NULL, 'N/A', IF(ok, 'pasa', 'FALLA')) r, COUNT(*)
             FROM prueba.resultado GROUP BY 1, 2 ORDER BY 1, 2"
fallas="$(root_ -N -e "SELECT id, usuario, LEFT(esperado, 60), LEFT(obtenido, 120) FROM prueba.resultado WHERE ok = 0")"
if [ -n "$fallas" ]; then
  echo "$fallas"
  exit 1
fi
