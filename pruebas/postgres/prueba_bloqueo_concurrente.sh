#!/usr/bin/env bash
# Comprueba en PostgreSQL 16 y 17 si un bloqueo de tarjeta concurrente puede quedar
# registrado sin aplicarse, la falla encontrada en MySQL con REPEATABLE READ. La
# sesión 1 pide BLOQUEADA y la sesión 2 desbloquea la tarjeta, en dos órdenes y en
# dos niveles de aislamiento. Un resultado es válido si el bloqueo se aplica y avisa
# a SEGURIDAD, o si falla sin dejar rastro. PERDIDO es que el historial lo registre y
# la tarjeta siga ACTIVA. El caso de control fabrica ese estado para comprobar que
# la verificación lo detecta.
#
# No escribe en resultados/ ni en la matriz: es una prueba aparte.
# Uso: pruebas/postgres/prueba_bloqueo_concurrente.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/lib/comun.sh"
TAG="bna-bloqueo-$$"
declare -A IMAGE=([16]="$PG16_IMAGE" [17]="$PG17_IMAGE")
fallas=0

cleanup() { docker rm -f "$TAG-16" "$TAG-17" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for v in 16 17; do
  C="$TAG-$v"
  docker run -d --rm --name "$C" -e POSTGRES_PASSWORD=x "${IMAGE[$v]}" >/dev/null
  for _ in $(seq 1 60); do docker exec "$C" pg_isready -h 127.0.0.1 -q && break; sleep 1; done
  sleep 2
  psql_() { docker exec -i "$C" psql -U postgres -X -q -d bna "$@"; }
  docker exec "$C" psql -U postgres -X -q -c "CREATE DATABASE bna"
  psql_ -v ON_ERROR_STOP=1 < "$ROOT/sql/bna_core.sql" >/dev/null
  psql_ -v ON_ERROR_STOP=1 < "$HERE/arnes.sql" >/dev/null
  psql_ -v ON_ERROR_STOP=1 < "$HERE/datos.sql" >/dev/null
  version="$(psql_ -tAc "SELECT split_part(version(), ' ', 2)")"
  echo "== PostgreSQL $version"

  nueva_tarjeta() { # imprime el identificador de una tarjeta BLOQUEADA nueva
    local id
    id="$(psql_ -tAc "SELECT gen_random_uuid()")"
    psql_ -v ON_ERROR_STOP=1 >/dev/null <<SQL
INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
VALUES ('$id', left(md5('$id'), 32), '455788', '1234', '2026-01-01', '2030-01-01', 'ACTIVA', 'C001');
INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta) VALUES ('BLOQUEADA', 'x', 'SEGURIDAD', '$id');
SQL
    echo "$id"
  }
  veredicto() { # NOMBRE TARJETA
    local estado registrado avisos
    estado="$(psql_ -tAc "SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = '$2'")"
    registrado="$(psql_ -tAc "SELECT count(*) FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = '$2' AND motivo = 'robo'")"
    avisos="$(psql_ -tAc "SELECT count(*) FROM tarjetas.evento_salida WHERE id_tarjeta = '$2' AND carga_json->>'motivo' = 'robo'")"
    if [ "$registrado" = 0 ]; then echo "RECHAZADO (estado $estado)"
    elif [ "$estado" = BLOQUEADA ] && [ "$avisos" = 1 ]; then echo "APLICADO"
    else echo "PERDIDO (estado $estado, historial $registrado, avisos $avisos)"
    fi
  }
  bloquear="INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta) VALUES ('BLOQUEADA', 'robo', 'CLIENTE', "
  desbloquear="INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta) VALUES ('ACTIVA', 'y', 'OPERADOR', "
  registrar() { echo "   $1: $2"; case "$2" in PERDIDO*) fallas=$((fallas + 1)) ;; esac; }

  for nivel in 'READ COMMITTED' 'REPEATABLE READ'; do
    # Lectura previa: la sesión 1 fija su instantánea y la sesión 2 confirma antes.
    t="$(nueva_tarjeta)"
    psql_ > /dev/null 2>&1 <<SQL &
BEGIN ISOLATION LEVEL $nivel;
SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = '$t';
SELECT pg_sleep(2);
$bloquear'$t');
COMMIT;
SQL
    sleep 1
    psql_ -c "$desbloquear'$t')" >/dev/null
    wait
    registrar "$nivel, lectura previa" "$(veredicto x "$t")"

    # Solape: la sesión 2 tiene la tarjeta bloqueada, sin confirmar, cuando la 1 escribe.
    t="$(nueva_tarjeta)"
    psql_ > /dev/null 2>&1 <<SQL &
BEGIN;
$desbloquear'$t');
SELECT pg_sleep(2);
COMMIT;
SQL
    sleep 1
    psql_ > /dev/null 2>&1 <<SQL || true
BEGIN ISOLATION LEVEL $nivel;
$bloquear'$t');
COMMIT;
SQL
    wait
    registrar "$nivel, solape" "$(veredicto x "$t")"
  done

  # Control: fabrica el estado perdido con los triggers apagados.
  t="$(nueva_tarjeta)"
  psql_ -v ON_ERROR_STOP=1 >/dev/null <<SQL
ALTER TABLE tarjetas.historial_estado_tarjeta DISABLE TRIGGER USER;
$bloquear'$t');
ALTER TABLE tarjetas.historial_estado_tarjeta ENABLE TRIGGER USER;
SQL
  control="$(veredicto x "$t")"
  case "$control" in
    PERDIDO*) echo "   control: la verificación detecta el estado perdido" ;;
    *) echo "   control: FALLA, no detectó el estado perdido ($control)"; fallas=$((fallas + 1)) ;;
  esac
done

if [ "$fallas" -ne 0 ]; then
  echo "Casos con falla: $fallas"
  exit 1
fi
echo 'Sin bloqueos perdidos.'
