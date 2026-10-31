#!/usr/bin/env bash
# Prueba revisar_resultados.sh sin base de datos: una falla en cualquiera de las dos
# versiones debe dar un código de salida distinto de 0.
#
# Uso: pruebas/postgres/prueba_revisar_resultados.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fallas=0

# esperar SALIDA DESCRIPCION PG16 PG17
esperar() {
  printf '%s' "$3" > "$TMP/resultado-pg16.csv"
  printf '%s' "$4" > "$TMP/resultado-pg17.csv"
  "$HERE/revisar_resultados.sh" "$TMP" >/dev/null
  local obtenido=$?
  if [ "$obtenido" = "$1" ]; then
    echo "ok    $2"
  else
    echo "FALLA $2: salió con $obtenido, se esperaba $1"
    fallas=1
  fi
}

esperar 0 'todo pasa' $'F01,x,pasa\nF02,x,N/A\n' $'F01,x,pasa\n'
esperar 1 'falla una prueba en PostgreSQL 16' $'F01,x,falla\n' $'F01,x,pasa\n'
esperar 1 'falla una prueba en PostgreSQL 17' $'F01,x,pasa\n' $'F01,x,falla\n'
esperar 1 'no hay resultados de PostgreSQL 16' '' $'F01,x,pasa\n'
esperar 1 'no hay resultados de PostgreSQL 17' $'F01,x,pasa\n' ''
exit "$fallas"
