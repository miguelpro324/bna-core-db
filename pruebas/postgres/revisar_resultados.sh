#!/usr/bin/env bash
# Decide el código de salida de run_tests.sh: 1 si alguna prueba está como «falla» en
# PostgreSQL 16 o 17, o si falta alguno de los dos archivos de resultados.
#
# Uso: pruebas/postgres/revisar_resultados.sh CARPETA_DE_RESULTADOS
set -uo pipefail

OUT="$1"
fallas=0
for f in resultado-pg16.csv resultado-pg17.csv; do
  if [ ! -s "$OUT/$f" ]; then
    echo "   falta $OUT/$f"
    fallas=1
  elif grep -q ',falla$' "$OUT/$f"; then
    echo "   hay pruebas que fallan en $f:"
    grep ',falla$' "$OUT/$f" | cut -d, -f1 | sed 's/^/     /'
    fallas=1
  fi
done
exit "$fallas"
