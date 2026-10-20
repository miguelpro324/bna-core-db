#!/usr/bin/env bash
# Reproduce los hallazgos de la revision del backend MySQL del BNA.
# Levanta un contenedor MySQL 8.4 temporal, carga 99_bna_unificado.sql,
# ejecuta las pruebas de sql/ y compara la documentacion con la base cargada.
# No modifica el repositorio. El contenedor se elimina al terminar.
#
# Uso: ./run.sh [--detalle] [ruta/a/backend/Trabajo_hecho]
#   --detalle  muestra tambien las tablas tecnicas de cada prueba (siempre quedan en out/)
#   Sin ruta, extrae backend/Trabajo_hecho de la linea base MySQL (BASE, por
#   defecto el commit ab6a6ec de este repositorio).
set -euo pipefail

DETALLE=0
if [ "${1:-}" = "--detalle" ]; then DETALLE=1; shift; fi

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${BASE:-ab6a6ec}"
NAME="bna-repro-mysql-$$"
TMP="$(mktemp -d)"
if [ -n "${1:-}" ]; then
  TH="$(cd "$1" && pwd)"
else
  git -C "$HERE" archive "$BASE" backend/Trabajo_hecho | tar -x -C "$TMP"
  TH="$TMP/backend/Trabajo_hecho"
fi
IMAGE="mysql:8.4"
OUT="$HERE/out"
mkdir -p "$OUT"

[ -f "$TH/BD/99_bna_unificado.sql" ] || { echo "No se encontro $TH/BD/99_bna_unificado.sql" >&2; exit 1; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

paso() { echo "-> $*"; }
mysql_run() { docker exec -i "$NAME" mysql -uroot "$@"; }
sql_str() { printf "'%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")"; }
# reg BUG TITULO QUE_SE_HIZO ESPERADO OBTENIDO OK(0|1) SIGNIFICA
reg() {
  mysql_run -e "CALL repro.reg($(sql_str "$1"), $(sql_str "$2"), $(sql_str "$3"), $(sql_str "$4"), $(sql_str "$5"), $6, $(sql_str "$7"))"
}

# --- Informe en lenguaje simple -------------------------------------------------
informe() {
  echo
  echo "======================================================================"
  echo " RESULTADO DE LAS COMPROBACIONES"
  echo " [ OK  ] el script se comporta como deberia"
  echo " [FALLA] el script hace algo distinto de lo correcto (se explica abajo)"
  echo " Bug N  = numero del hallazgo en la revision; '-' = comprobacion adicional"
  echo "======================================================================"
  mysql_run -N -B -e "SELECT n, ok, bug, titulo, que_se_hizo, esperado, obtenido, significa
                      FROM repro.resultado ORDER BY n" \
  | awk -F'\t' '
      function wrap(label, text,   width, pad, line, n, i, words) {
        width = 62; pad = sprintf("%16s", "")
        n = split(text, words, " "); line = ""
        for (i = 1; i <= n; i++) {
          if (length(line) + length(words[i]) + 1 > width && line != "") {
            print (label != "" ? label : pad) line; label = ""; line = words[i]
          } else line = (line == "" ? words[i] : line " " words[i])
        }
        print (label != "" ? label : pad) line
      }
      {
        total++; if ($2 == 1) ok++
        printf "\n%s %2d. %s%s\n", ($2 == 1 ? "[ OK  ]" : "[FALLA]"), $1, $4, ($3 != "-" ? "  (bug " $3 ")" : "")
        gsub(/\\\\/, "\\", $5); gsub(/\\\\/, "\\", $6); gsub(/\\\\/, "\\", $7); gsub(/\\\\/, "\\", $8)
        wrap("   Que se hizo: ", $5)
        wrap("   Correcto:    ", $6)
        wrap("   Obtenido:    ", $7)
        if ($2 != 1) wrap("   Significa:   ", $8)
      }
      END {
        print ""
        print "----------------------------------------------------------------------"
        printf " %d comprobaciones: %d OK, %d FALLA\n", total, ok, total - ok
        print "----------------------------------------------------------------------"
      }'
}

# --- Servidor temporal ----------------------------------------------------------
paso "Arrancando $IMAGE temporal ($NAME)"
docker run -d --rm --name "$NAME" -e MYSQL_ALLOW_EMPTY_PASSWORD=yes "$IMAGE" >/dev/null
# El entrypoint arranca primero un servidor temporal sin red y luego el definitivo;
# solo el definitivo acepta conexiones TCP, asi que se espera por TCP.
listo=0
for _ in $(seq 1 90); do
  if docker exec "$NAME" mysql -uroot -h127.0.0.1 -e "SELECT 1" >/dev/null 2>&1; then listo=1; break; fi
  sleep 2
done
[ "$listo" = 1 ] || { echo "MySQL no arranco a tiempo" >&2; exit 1; }
paso "$(mysql_run -N -e "SELECT CONCAT('MySQL ', VERSION())")"
mysql_run < "$HERE/sql/_setup_repro.sql"

# --- Bug 1: ruta del script en cargar_bna.ps1 -----------------------------------
paso "Revisando cargar_bna.ps1"
default_script="$(grep -oE '\$Script *= *"[^"]+"' "$TH/cargar_bna.ps1" | sed -E 's/.*"(.*)"/\1/')"
if [ -f "$TH/$default_script" ]; then b1_ok=1; b1_obt="Busca Trabajo_hecho\\$default_script y el archivo existe";
else b1_ok=0; b1_obt="Busca Trabajo_hecho\\$default_script, que no existe (el archivo esta en BD\\)"; fi
reg 1 "El script de carga encuentra el archivo SQL" \
  "Se leyo la ruta que usa cargar_bna.ps1 por defecto (carpeta del .ps1 + \$Script)." \
  "Que apunte a Trabajo_hecho\\BD\\99_bna_unificado.sql" "$b1_obt" "$b1_ok" \
  "Quien siga la guia y ejecute .\\cargar_bna.ps1 recibe 'No se encontro el script' y no se carga nada. Lo mismo pasa con los comandos manuales del README y la guia."

# --- Carga ----------------------------------------------------------------------
paso "Cargando BD/99_bna_unificado.sql (log en out/carga.log)"
if mysql_run --show-warnings < "$TH/BD/99_bna_unificado.sql" > "$OUT/carga.log" 2>&1; then
  avisos="$(grep -c '^Warning' "$OUT/carga.log" || true)"
  reg - "El script unificado carga sin errores en MySQL 8.4" \
    "Se ejecuto BD/99_bna_unificado.sql completo con el cliente mysql." \
    "Termina sin ningun ERROR" \
    "Termino sin errores ($avisos avisos de obsolescencia, inofensivos: TINYINT(1) y sql_mode)" 1 ""
else
  reg - "El script unificado carga sin errores en MySQL 8.4" \
    "Se ejecuto BD/99_bna_unificado.sql completo con el cliente mysql." \
    "Termina sin ningun ERROR" "$(grep -m1 '^ERROR' "$OUT/carga.log")" 0 \
    "La base no se pudo crear; el resto de pruebas no se ejecuta."
  informe; exit 1
fi

# --- Pruebas SQL ----------------------------------------------------------------
for f in 00_conteos 01_estado_demo 02_integridad 03_topes_y_bloqueo; do
  paso "Ejecutando sql/$f.sql (detalle en out/$f.log)"
  mysql_run -t --force bna < "$HERE/sql/$f.sql" > "$OUT/$f.log" 2>&1
  if [ "$DETALLE" = 1 ]; then cat "$OUT/$f.log"; fi
done

# --- Documentacion vs. base cargada ---------------------------------------------
paso "Comparando la documentacion con la base cargada"
mysql_run -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='bna' AND table_type='BASE TABLE'" \
  | LC_ALL=C sort > "$OUT/db_tablas.txt"
mysql_run -N -e "SELECT CONCAT(c.table_name,'.',c.column_name) FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name
  WHERE c.table_schema='bna' AND t.table_type='BASE TABLE'" | LC_ALL=C sort > "$OUT/db_columnas.txt"
tr -d '\r' < "$TH/diccionario_datos.md" \
  | awk '/^## /{t=$2} /^\| [a-z_0-9]+ \|/{print t"."$2}' | LC_ALL=C sort > "$OUT/dic_columnas.txt"
ncols="$(wc -l < "$OUT/db_columnas.txt")"
if diff "$OUT/dic_columnas.txt" "$OUT/db_columnas.txt" > "$OUT/dic_diff.txt"; then
  reg - "El diccionario de datos describe la base real" \
    "Se compararon las columnas de diccionario_datos.md con las de la base cargada." \
    "Las mismas columnas en las mismas tablas" "Coinciden las $ncols columnas" 1 ""
else
  reg - "El diccionario de datos describe la base real" \
    "Se compararon las columnas de diccionario_datos.md con las de la base cargada." \
    "Las mismas columnas en las mismas tablas" "Hay $(grep -c '^[<>]' "$OUT/dic_diff.txt") diferencias (ver out/dic_diff.txt)" 0 \
    "El diccionario no refleja lo que realmente crea el script."
fi

grep -oE '^\s+[A-Z_]+ [|}][|o]--[o|][{|] [A-Z_]+' "$TH/mer_bna.mermaid" \
  | awk '{print tolower($1); print tolower($3)}' | LC_ALL=C sort -u > "$OUT/mer_tablas.txt"
nrel="$(grep -cE '[|}][|o]--[o|][{|]' "$TH/mer_bna.mermaid")"
nfk="$(mysql_run -N -e "SELECT COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='bna'")"
faltan="$(LC_ALL=C comm -23 "$OUT/db_tablas.txt" "$OUT/mer_tablas.txt" | paste -sd, - | sed 's/,/, /g')"
reg - "El diagrama Mermaid muestra todas las relaciones" \
  "Se contaron las relaciones de mer_bna.mermaid y las claves foraneas de la base." \
  "Una relacion por clave foranea ($nfk) y todas las tablas presentes" \
  "$nrel relaciones de $nfk; faltan las tablas: ${faltan:-ninguna}" \
  "$([ "$nrel" -ge "$nfk" ] && [ -z "$faltan" ] && echo 1 || echo 0)" \
  "El diagrama es parcial: no sirve para ver todo el modelo aunque su leyenda diga que las flechas son las FKs."

informe | tee "$OUT/informe.txt"
echo
echo "Informe guardado en out/informe.txt; tablas tecnicas en out/*.log (o ./run.sh --detalle)."
