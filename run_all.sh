#!/usr/bin/env bash
# Vuelve a ejecutar todo y regenera las salidas y los fragmentos del informe.
#   1. Modelo: sql/bna_core.sql y los fragmentos del modelo en informe/.
#   2. Experimentos E1 a E7 (MySQL 8.4, PostgreSQL 16 y 17): resultados/experimentos/.
#   3. Reproducción de las fallas de la línea base MySQL: resultados/repro_mysql/.
#   4. Pruebas en PostgreSQL 16 y 17: resultados/postgres/ e informe/pruebas-*.tex.
#   5. Control: las mismas pruebas sobre el DDL sin triggers del commit
#      CONTROL_COMMIT: resultados/control/.
#   6. Matriz de trazabilidad y cuadro de objetos programados:
#      resultados/trazabilidad.{md,csv} e informe/{trazabilidad,programacion}*.tex.
# Cada carpeta de resultados/ incluye metadatos.txt (fecha, commit, versiones
# e imágenes). Para que el commit registrado describa lo ejecutado, conviene
# correrlo con el árbol limpio (fuera de resultados/ e informe/).
#
# Uso: ./run_all.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/lib/comun.sh"
CONTROL_COMMIT=8aec444

case "$(commit_actual)" in
  *sucio*) echo "Aviso: hay cambios sin confirmar; los metadatos registrarán el commit como «sucio»." >&2 ;;
esac

echo "== 1. Modelo"
(cd "$ROOT/modelo" && python3 modelo_bna.py ../informe > /dev/null)

echo "== 2. Experimentos"
"$ROOT/experimentos/sgbd/experimentos.sh" > /dev/null

echo "== 3. Reproducción MySQL"
"$ROOT/repro_mysql/run.sh" > /dev/null

echo "== 4. Pruebas"
"$ROOT/pruebas/postgres/run_tests.sh"

echo "== 5. Control ($CONTROL_COMMIT)"
ddl="$(mktemp)"
trap 'rm -f "$ddl"' EXIT
git -C "$ROOT" show "$CONTROL_COMMIT:sql/bna_core.sql" > "$ddl"
DDL="$ddl" DDL_ORIGEN="sql/bna_core.sql en $(git -C "$ROOT" rev-parse --short=12 "$CONTROL_COMMIT") (sin triggers)" \
  "$ROOT/pruebas/postgres/run_tests.sh"

echo "== 6. Trazabilidad"
python3 "$ROOT/trazabilidad/matriz.py"
