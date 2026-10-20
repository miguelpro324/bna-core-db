#!/usr/bin/env bash
# Experimentos que respaldan la comparación de SGBD del informe
# (sección «Selección del sistema gestor de base de datos»).
# Ejecuta el mismo caso en MySQL 8.4 y en PostgreSQL 16 y 17, cada uno en un
# contenedor temporal que se elimina al terminar, e imprime lo observado.
# Salidas en resultados/experimentos/: salida.txt (lo impreso),
# experimentos.csv (experimento, caso, gestor, lo observado) y metadatos.txt.
#
# Uso: experimentos/sgbd/experimentos.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/lib/comun.sh"
OUT="$ROOT/resultados/experimentos"
rm -rf "$OUT"
mkdir -p "$OUT"
CSV="$OUT/experimentos.csv"
echo "experimento,caso,gestor,obtenido" > "$CSV"
exec > >(tee "$OUT/salida.txt")

TAG="sgbd-$$"
MY="$TAG-my84"
# contenedor:etiqueta
PGS=("$TAG-pg16:PG 16" "$TAG-pg17:PG 17")
declare -A PG_IMAGE=(["$TAG-pg16"]="$PG16_IMAGE" ["$TAG-pg17"]="$PG17_IMAGE")
TMP="$(mktemp -d)"
cleanup() {
  docker rm -f "$MY" "${PGS[@]%%:*}" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

docker run -d --rm --name "$MY" -e MYSQL_ALLOW_EMPTY_PASSWORD=yes "$MYSQL_IMAGE" >/dev/null
for p in "${PGS[@]}"; do
  docker run -d --rm --name "${p%%:*}" -e POSTGRES_PASSWORD=x "${PG_IMAGE[${p%%:*}]}" >/dev/null
done
# El contenedor de MySQL arranca un servidor temporal sin red antes del
# definitivo; solo el definitivo acepta TCP.
for _ in $(seq 1 90); do
  ok=1
  docker exec "$MY" mysql -uroot -h127.0.0.1 -e "SELECT 1" >/dev/null 2>&1 || ok=0
  for p in "${PGS[@]}"; do docker exec "${p%%:*}" pg_isready -h 127.0.0.1 -q || ok=0; done
  [ "$ok" = 1 ] && break
  sleep 2
done
docker exec "$MY" mysql -uroot -h127.0.0.1 -e "CREATE DATABASE e"

my() { docker exec -i "$MY" mysql -uroot -h127.0.0.1 -NB e 2>&1 || true; }
pg() { docker exec -i "$1" psql -U postgres -X -q -tA 2>&1 || true; }

V_MY="$(echo 'SELECT VERSION()' | my)"
V_PG16="$(echo "SELECT current_setting('server_version')" | pg "$TAG-pg16")"
V_PG17="$(echo "SELECT current_setting('server_version')" | pg "$TAG-pg17")"
echo "Versiones:"
echo "  MySQL $V_MY"
echo "  PostgreSQL $V_PG16"
echo "  PostgreSQL $V_PG17"

# linea ID TÍTULO: empieza un experimento; CASO distingue sus variantes.
EXP=""; CASO=""
linea() { EXP="$1"; CASO=""; printf '\n%s\n' "== $1. $2"; }
# res GESTOR: imprime lo observado (entrada estándar) y lo agrega al CSV.
res() {
  local obt; obt="$(tr '\n' ' ' | sed 's/  */ /g; s/ $//')"
  printf '   %-15s %s\n' "$1" "$obt"
  printf '%s,"%s","%s","%s"\n' "$EXP" "${CASO//\"/\"\"}" "$1" "${obt//\"/\"\"}" >> "$CSV"
}

# ---------------------------------------------------------------------------
linea E1 "DDL dentro de una transacción: CREATE TABLE y luego ROLLBACK"
echo "START TRANSACTION; CREATE TABLE t_ddl (a INT); ROLLBACK;
SELECT IF(COUNT(*) = 1, 'la tabla sigue existiendo (commit implícito)', 'la tabla se deshizo')
FROM information_schema.tables WHERE table_schema = 'e' AND table_name = 't_ddl';" | my | res "MySQL 8.4"
for p in "${PGS[@]}"; do
  echo "BEGIN; CREATE TABLE t_ddl (a INT); ROLLBACK;
SELECT CASE WHEN to_regclass('t_ddl') IS NULL THEN 'la tabla se deshizo' ELSE 'la tabla sigue existiendo' END;" \
    | pg "${p%%:*}" | res "${p#*:}"
done

# ---------------------------------------------------------------------------
linea E2 "Restricciones: FK diferible, índice único parcial y dominio"
for caso in \
  "Clave foránea diferible|CREATE TABLE p (id INT PRIMARY KEY); CREATE TABLE h (id INT, FOREIGN KEY (id) REFERENCES p (id) DEFERRABLE INITIALLY DEFERRED);" \
  "Índice único parcial|CREATE TABLE m (id INT, estado VARCHAR(10)); CREATE UNIQUE INDEX ux ON m (id) WHERE estado = 'ACTIVA';" \
  "Dominio|CREATE DOMAIN importe AS DECIMAL(15,2) CHECK (VALUE > 0);"; do
  stmt="${caso#*|}"
  CASO="${caso%%|*}"
  echo "   -- $CASO"
  r="$(echo "$stmt" | my | grep -m1 ERROR | sed -E 's/^ERROR [0-9]+ \([0-9A-Z]+\) at line [0-9]+: //' | cut -c1-90 || true)"
  echo "${r:-aceptado}" | res "MySQL 8.4"
  for p in "${PGS[@]}"; do
    r="$(echo "$stmt" | pg "${p%%:*}" | grep -m1 ERROR | sed 's/ERROR: *//' || true)"
    echo "${r:-aceptado}" | res "${p#*:}"
  done
done

# ---------------------------------------------------------------------------
linea E3 "Verificación al confirmar: asiento descuadrado (solo debe) en partida doble"
echo "CREATE TRIGGER x AFTER INSERT ON p FOR EACH ROW BEGIN END;
CREATE CONSTRAINT TRIGGER y AFTER INSERT ON p DEFERRABLE INITIALLY DEFERRED FOR EACH ROW BEGIN END;" \
  | my | grep -m1 ERROR | sed -E 's/^ERROR [0-9]+ \([0-9A-Z]+\) at line [0-9]+: /CREATE CONSTRAINT TRIGGER: /' | cut -c1-110 | res "MySQL 8.4"
for p in "${PGS[@]}"; do
  cat <<'SQL' | pg "${p%%:*}" | grep -oE 'asiento [0-9]+ descuadrado|asientos guardados: .*' | res "${p#*:}"
CREATE TABLE det (asiento INT, debe NUMERIC(15,2) DEFAULT 0, haber NUMERIC(15,2) DEFAULT 0);
CREATE FUNCTION cuadra() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT sum(debe) - sum(haber) FROM det WHERE asiento = NEW.asiento) <> 0 THEN
    RAISE EXCEPTION 'asiento % descuadrado', NEW.asiento;
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER tg AFTER INSERT ON det DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION cuadra();
BEGIN; INSERT INTO det VALUES (1, 100, 0); INSERT INTO det VALUES (1, 0, 100); COMMIT;
BEGIN; INSERT INTO det VALUES (2, 100, 0); COMMIT;
SELECT 'asientos guardados: ' || string_agg(DISTINCT asiento::text, ',') FROM det;
SQL
done

# ---------------------------------------------------------------------------
linea E4 "Modo de sesión: SET sql_mode = '' e inserción de valores inválidos"
echo "CREATE TABLE s (e ENUM('A','B'), d DECIMAL(5,2), f DATE);
SET SESSION sql_mode = '';
INSERT INTO s VALUES ('Z', 123456.789, '2026-02-31');
SET @w = @@warning_count;
SELECT CONCAT('guardado sin error: e=''', e, ''', d=', d, ', f=', f, '; advertencias: ', @w) FROM s;" | my | res "MySQL 8.4"
for p in "${PGS[@]}"; do
  echo "CREATE TABLE s (d NUMERIC(5,2), f DATE);
INSERT INTO s VALUES (123456.789, '2026-01-01');
INSERT INTO s VALUES (1, '2026-02-31');
SELECT 'filas guardadas: ' || count(*) FROM s;" | pg "${p%%:*}" | grep -E 'ERROR|filas' | sed 's/ERROR: *//' | res "${p#*:}"
done

# ---------------------------------------------------------------------------
linea E5 "Tipos: marca de tiempo de 2039, BOOLEAN = 5 y UUID 'c2'"
CASO="Marca de tiempo de 2039"
echo "CREATE TABLE ts (t TIMESTAMP NULL); INSERT INTO ts VALUES ('2039-01-01 00:00:00');" \
  | my | sed 's/.*ERROR [0-9]* ([0-9A-Z]*) at line [0-9]*: /TIMESTAMP: /' | res "MySQL 8.4"
CASO="BOOLEAN = 5"
echo "CREATE TABLE b (x BOOLEAN); INSERT INTO b VALUES (5); SELECT CONCAT('BOOLEAN guarda ', x) FROM b;" | my | res "MySQL 8.4"
CASO="UUID 'c2'"
echo "CREATE TABLE u (id CHAR(36)); INSERT INTO u VALUES ('c2'); SELECT CONCAT('CHAR(36) guarda ''', id, '''') FROM u;" | my | res "MySQL 8.4"
for p in "${PGS[@]}"; do
  CASO="Marca de tiempo de 2039"
  echo "SELECT 'TIMESTAMPTZ guarda ' || '2039-01-01 00:00:00-05'::timestamptz;" | pg "${p%%:*}" | res "${p#*:}"
  CASO="BOOLEAN = 5"
  echo "SELECT 5::int::boolean IS NOT NULL; CREATE TABLE b (x BOOLEAN); INSERT INTO b VALUES (5);" \
    | pg "${p%%:*}" | grep ERROR | sed 's/ERROR: */BOOLEAN: /' | res "${p#*:}"
  CASO="UUID 'c2'"
  echo "SELECT 'c2'::uuid;" | pg "${p%%:*}" | grep ERROR | sed 's/ERROR: */UUID: /' | res "${p#*:}"
done

# ---------------------------------------------------------------------------
linea E6 "Auditoría: trigger AFTER DELETE en la tabla hija y borrado en cascada desde la madre"
echo "CREATE TABLE padre (id INT PRIMARY KEY);
CREATE TABLE hijo (id INT PRIMARY KEY, p INT, FOREIGN KEY (p) REFERENCES padre (id) ON DELETE CASCADE);
CREATE TABLE bitacora (msg VARCHAR(50));
CREATE TRIGGER tg AFTER DELETE ON hijo FOR EACH ROW INSERT INTO bitacora VALUES ('borrado');
INSERT INTO padre VALUES (1); INSERT INTO hijo VALUES (10, 1);
DELETE FROM padre WHERE id = 1;
SELECT CONCAT('hijos borrados: 1; filas en la bitácora: ', COUNT(*)) FROM bitacora;" | my | res "MySQL 8.4"
for p in "${PGS[@]}"; do
  cat <<'SQL' | pg "${p%%:*}" | res "${p#*:}"
CREATE TABLE padre (id INT PRIMARY KEY);
CREATE TABLE hijo (id INT PRIMARY KEY, p INT REFERENCES padre (id) ON DELETE CASCADE);
CREATE TABLE bitacora (msg TEXT);
CREATE FUNCTION f() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO bitacora VALUES ('borrado'); RETURN OLD; END $$;
CREATE TRIGGER tg AFTER DELETE ON hijo FOR EACH ROW EXECUTE FUNCTION f();
INSERT INTO padre VALUES (1); INSERT INTO hijo VALUES (10, 1);
DELETE FROM padre WHERE id = 1;
SELECT 'hijos borrados: 1; filas en la bitácora: ' || count(*) FROM bitacora;
SQL
done

# ---------------------------------------------------------------------------
linea E7 "Actualización perdida: A lee el saldo (100), B resta 30 y confirma, A escribe 100 - 50"
perdida_my() {
  CASO="$1"
  echo "DROP TABLE IF EXISTS cta; CREATE TABLE cta (id INT PRIMARY KEY, saldo DECIMAL(15,2)); INSERT INTO cta VALUES (1, 100);" | my >/dev/null
  echo "SET SESSION TRANSACTION ISOLATION LEVEL $1; START TRANSACTION;
SELECT saldo INTO @s FROM cta WHERE id = 1; DO SLEEP(2);
UPDATE cta SET saldo = @s - 50 WHERE id = 1; COMMIT;" | my > "$TMP/a" &
  sleep 1
  echo "SET SESSION TRANSACTION ISOLATION LEVEL $1; START TRANSACTION; UPDATE cta SET saldo = saldo - 30 WHERE id = 1; COMMIT;" | my > "$TMP/b"
  wait
  local a; a="$(grep -o 'ERROR.*' "$TMP/a" || echo 'A confirma')"
  echo "$1: $a; saldo final $(echo 'SELECT saldo FROM cta' | my)" | res "MySQL 8.4"
}
perdida_pg() {
  CASO="$1"
  echo "DROP TABLE IF EXISTS cta; CREATE TABLE cta (id INT PRIMARY KEY, saldo NUMERIC(15,2)); INSERT INTO cta VALUES (1, 100);" | pg "$2" >/dev/null
  printf "BEGIN ISOLATION LEVEL %s;\nSELECT saldo AS s FROM cta WHERE id = 1 \\\\gset\nSELECT pg_sleep(2);\nUPDATE cta SET saldo = :s - 50 WHERE id = 1;\nCOMMIT;\n" "$1" \
    | pg "$2" > "$TMP/a" &
  sleep 1
  echo "BEGIN ISOLATION LEVEL $1; UPDATE cta SET saldo = saldo - 30 WHERE id = 1; COMMIT;" | pg "$2" > "$TMP/b"
  wait
  local a; a="$(grep -o 'ERROR.*' "$TMP/a" | sed 's/ERROR: *//' || echo 'A confirma')"
  echo "$1: ${a:-A confirma}; saldo final $(echo 'SELECT saldo FROM cta' | pg "$2")" | res "$3"
}
perdida_my "REPEATABLE READ"
perdida_my "SERIALIZABLE"
for p in "${PGS[@]}"; do
  for nivel in "READ COMMITTED" "REPEATABLE READ" "SERIALIZABLE"; do perdida_pg "$nivel" "${p%%:*}" "${p#*:}"; done
done
echo "   (correcto: 20, o un error que obligue a A a reintentar; 50 = se perdió la resta de B)"

metadatos "$OUT/metadatos.txt" "mysql=$V_MY" "imagen_mysql=$MYSQL_IMAGE" \
  "postgresql16=$V_PG16" "imagen16=$PG16_IMAGE" "postgresql17=$V_PG17" "imagen17=$PG17_IMAGE"
