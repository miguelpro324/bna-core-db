#!/usr/bin/env bash
# Comprueba el despliegue con los mismos montajes que usa
# docker-compose.coredb.yml: arranca el contenedor con bna.cnf, el DDL y
# crear_usuarios.sh, y revisa la configuración y los usuarios. bna.cnf se monta
# con permisos 666, como puede verse un montaje desde Windows: MySQL ignora un
# archivo de configuración escribible por todos, y el arranque debe evitarlo.
#
# Uso: pruebas/mysql/prueba_despliegue.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/lib/comun.sh"
C="bna-prueba-despliegue-$$"
TMP="$(mktemp -d)"
PW_ROOT="raiz-$RANDOM"
# Comillas y barra invertida: crear_usuarios.sh debe escaparlas.
PW_APP="app'con\\raros-$RANDOM"
PW_ADMIN="admin-$RANDOM"

cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

cp "$ROOT/conf/mysql/bna.cnf" "$TMP/bna.cnf"
chmod 666 "$TMP/bna.cnf"

docker run -d --name "$C" \
  -e MYSQL_ROOT_PASSWORD="$PW_ROOT" \
  -e CORE_DB_APP_PASSWORD="$PW_APP" \
  -e CORE_DB_ADMIN_PASSWORD="$PW_ADMIN" \
  -v "$TMP/bna.cnf:/bna/bna.cnf:ro" \
  -v "$ROOT/sql/bna_core.sql:/docker-entrypoint-initdb.d/01_bna_core.sql:ro" \
  -v "$ROOT/conf/mysql/crear_usuarios.sh:/docker-entrypoint-initdb.d/02_crear_usuarios.sh:ro" \
  --entrypoint sh "$MYSQL_IMAGE" \
  -c 'install -m 644 /bna/bna.cnf /etc/mysql/conf.d/bna.cnf && exec docker-entrypoint.sh mysqld' >/dev/null

app() { docker exec -i -e MYSQL_PWD="$PW_APP" "$C" mysql -ubna_app_user -h127.0.0.1 --protocol=TCP -N "$@"; }

for _ in $(seq 1 90); do
  app -e 'SELECT 1' >/dev/null 2>&1 && break
  sleep 2
done

fallas=0
comprobar() { # DESCRIPCION ESPERADO OBTENIDO
  if printf '%s' "$3" | grep -q -- "$2"; then
    echo "ok    $1"
  else
    echo "FALLA $1: $3"
    fallas=$((fallas + 1))
  fi
}

comprobar 'configuración del servidor' 'BNA-CONFIGURACION: correcta' \
  "$(app -e 'CALL core.verificar_configuracion()' 2>&1 || true)"
comprobar 'rol de bna_app_user' 'bna_app' "$(app -e 'SELECT CURRENT_ROLE()' 2>&1 || true)"
comprobar 'bna_app_user no borra' 'denied' \
  "$(app -e 'DELETE FROM core.agencia' 2>&1 || true)"
comprobar 'bna_admin_user con su rol' 'bna_admin' \
  "$(docker exec -e MYSQL_PWD="$PW_ADMIN" "$C" mysql -ubna_admin_user -h127.0.0.1 --protocol=TCP -N \
     -e 'SELECT CURRENT_ROLE()' 2>&1 || true)"

if [ "$fallas" -ne 0 ]; then
  docker logs "$C" 2>&1 | tail -20
  exit 1
fi
echo 'Despliegue correcto.'
