#!/usr/bin/env bash
# Pruebas de la base integrada (sql/bna_core.sql) en PostgreSQL 16 y 17.
# Cada versión corre en un contenedor temporal que se elimina al terminar.
# Además de pruebas/postgres/pruebas.sql, ejecuta las pruebas que necesitan una
# confirmación real o dos sesiones (M20b, C01 a C03) y la de carga (L01).
# Resultados: pruebas/postgres/resultados.md e informe/pruebas-*.tex.
#
# Uso: pruebas/postgres/run_tests.sh
#      DDL=otro.sql pruebas/postgres/run_tests.sh   (control: prueba otro
#                                                    script y solo informa los conteos)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DDL="${DDL:-}"
OUT="$HERE/out"
[ -n "$DDL" ] && OUT="$HERE/out/control"
mkdir -p "$OUT"
TAG="bna-pruebas-$$"
VERSIONS=(16 17)

cleanup() { for v in "${VERSIONS[@]}"; do docker rm -f "$TAG-pg$v" >/dev/null 2>&1 || true; done; }
trap cleanup EXIT

for v in "${VERSIONS[@]}"; do
  docker run -d --rm --name "$TAG-pg$v" -e POSTGRES_PASSWORD=x "postgres:$v" >/dev/null
done
for v in "${VERSIONS[@]}"; do
  for _ in $(seq 1 60); do
    docker exec "$TAG-pg$v" pg_isready -h 127.0.0.1 -q && break
    sleep 1
  done
done

for v in "${VERSIONS[@]}"; do
  C="$TAG-pg$v"
  psql_() { docker exec -i "$C" psql -U postgres -X -q "$@"; }
  version="$(psql_ -tAc "SELECT split_part(version(), ' ', 2)")"
  echo "== PostgreSQL $version"
  psql_ -c "CREATE DATABASE bna" >/dev/null

  # L01: el script completo carga sin errores.
  if psql_ -d bna -v ON_ERROR_STOP=1 < "${DDL:-$ROOT/sql/bna_core.sql}" > "$OUT/carga-pg$v.log" 2>&1; then
    carga_ok=TRUE; carga="Carga sin errores"
  else
    carga_ok=FALSE; carga="Error: $(grep -m1 ERROR "$OUT/carga-pg$v.log")"
  fi
  psql_ -d bna -v ON_ERROR_STOP=1 < "$HERE/arnes.sql" >/dev/null
  psql_ -d bna -v ON_ERROR_STOP=1 -c "INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
    VALUES ('L01', 'Carga', 'Script DDL', 'El script completo se ejecuta sobre una base vacía',
            'Carga sin errores', \$r\$$carga\$r\$, $carga_ok)" >/dev/null
  [ "$carga_ok" = TRUE ] || { echo "   la carga falló; ver $OUT/carga-pg$v.log"; continue; }

  psql_ -d bna -v ON_ERROR_STOP=1 < "$HERE/datos.sql" >/dev/null
  psql_ -d bna < "$HERE/pruebas.sql" > "$OUT/pruebas-pg$v.log" 2>&1

  # M20b: el asiento descuadrado se rechaza en un COMMIT real, no solo con
  # SET CONSTRAINTS ALL IMMEDIATE.
  salida="$(psql_ -d bna 2>&1 <<'SQL' || true
BEGIN;
INSERT INTO core.asiento_contable (id_asiento, numero_asiento, fecha_contable, fecha_valor, glosa, moneda, correlation_id)
VALUES ('9a000000-0000-4000-8000-000000000002', 'T-COMMIT', current_date, current_date, 'Solo debe', 'PEN', gen_random_uuid());
INSERT INTO core.detalle_asiento VALUES ('9a000000-0000-4000-8000-000000000002', 1, 'DEBE', 100, '1101');
COMMIT;
SQL
)"
  quedo="$(psql_ -d bna -tAc "SELECT count(*) FROM core.asiento_contable WHERE numero_asiento = 'T-COMMIT'")"
  ok=FALSE; echo "$salida" | grep -q 'BNA-PARTIDA-DOBLE' && [ "$quedo" = 0 ] && ok=TRUE
  msg="$(echo "$salida" | grep -o 'BNA-PARTIDA-DOBLE[^"]*' | head -1 || true)"
  obt="${msg:+Rechazo: $msg}"; obt="${obt:-COMMIT aceptado}; asientos guardados: $quedo"
  psql_ -d bna -c "INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
    VALUES ('M20b', 'MySQL', 'Comprobación 20 (bug 7)', 'Un asiento descuadrado se rechaza en un COMMIT real',
            'Rechazo: BNA-PARTIDA-DOBLE; asientos guardados: 0', \$r\$$obt\$r\$, $ok)" >/dev/null

  # Pruebas de concurrencia: la sesión A ejecuta SQL_A dentro de una
  # transacción que espera 2 s antes de confirmar; la sesión B ejecuta SQL_B
  # un segundo después. B debe rechazarse con PATRON y el estado final debe
  # cumplir COND.
  # concurrente ID REF DESC SQL_A SQL_B PATRON COND ESPERADO OBTENIDO_SQL
  concurrente() {
    local id="$1" ref="$2" desc="$3" sql_a="$4" sql_b="$5" patron="$6" cond="$7" esperado="$8" obt_sql="$9"
    printf 'BEGIN;\n%s;\nSELECT pg_sleep(2);\nCOMMIT;\n' "$sql_a" | psql_ -d bna > "$OUT/$id-a-pg$v.log" 2>&1 &
    sleep 1
    psql_ -d bna -c "$sql_b" > "$OUT/$id-b-pg$v.log" 2>&1 || true
    wait
    local ok=FALSE estado b
    estado="$(psql_ -d bna -tAc "$obt_sql")"
    b="$(grep -oE "($patron)[^(]*" "$OUT/$id-b-pg$v.log" | head -1 || true)"
    if grep -qE "ERROR.*($patron)" "$OUT/$id-b-pg$v.log" && [ "$(psql_ -d bna -tAc "$cond")" = t ]; then ok=TRUE; fi
    psql_ -d bna -c "INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
      VALUES ('$id', 'Concurrencia', \$r\$$ref\$r\$, \$r\$$desc\$r\$, \$r\$$esperado\$r\$,
              \$r\$$estado; segunda operación: ${b:-aceptada}\$r\$, $ok)" >/dev/null
  }

  # C01: dos retiros de 3000 sobre un saldo de 5000, en ventanilla (sin tope).
  concurrente C01 'Requisito 3 (E7)' 'Dos retiros simultáneos no dejan el saldo en negativo' \
    "SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 3000, 'VEN')" \
    "SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 3000, 'VEN')" \
    'BNA-SALDO' \
    "SELECT saldo_contable = 2000 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'" \
    'saldo 2000.00; segunda operación: BNA-SALDO' \
    "SELECT 'saldo ' || saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'"

  # C02: dos retiros de 1000 en cajero (tope 1500 PEN): cada uno cabe solo,
  # juntos no.
  concurrente C02 'RN-TOP-001 (bug 5)' 'Dos retiros simultáneos en cajero no superan juntos el tope diario' \
    "SELECT prueba.movimiento('CTA-PEN-1', 'RETIRO', 1000, 'ATM')" \
    "SELECT prueba.movimiento('CTA-PEN-1', 'RETIRO', 1000, 'ATM')" \
    'RN-TOP-001' \
    "SELECT monto_acumulado = 1000 FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM'" \
    'consumido 1000.00; segunda operación: RN-TOP-001' \
    "SELECT 'consumido ' || coalesce((SELECT monto_acumulado FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')::text, '0.00')"

  # C03: dos autorizaciones de 300 en cajero sobre la cuenta en dólares (tope
  # 500 USD), sin movimiento todavía: cada una cabe sola, juntas no.
  concurrente C03 'RN-TOP-001 (bug 5)' 'Dos autorizaciones simultáneas sin movimiento no superan juntas el tope diario' \
    "INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta) VALUES ('RETIRO', 300, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-USD-1')" \
    "INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta) VALUES ('RETIRO', 300, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-USD-1')" \
    'ERR-TAR-007' \
    "SELECT count(*) = 1 FROM tarjetas.autorizacion WHERE num_cuenta = 'CTA-USD-1' AND estado_autorizacion = 'AUTORIZADA'" \
    'autorizadas 1; segunda operación: ERR-TAR-007' \
    "SELECT 'autorizadas ' || count(*) FROM tarjetas.autorizacion WHERE num_cuenta = 'CTA-USD-1' AND estado_autorizacion = 'AUTORIZADA'"

  psql_ -d bna -c "COPY (SELECT id, grupo, referencia, descripcion, esperado, obtenido,
                        CASE WHEN ok IS NULL THEN 'N/A' WHEN ok THEN 'pasa' ELSE 'falla' END
                   FROM prueba.resultado ORDER BY n) TO STDOUT WITH (FORMAT csv)" > "$OUT/resultado-pg$v.csv"
  psql_ -d bna -tAc "SELECT count(*) FILTER (WHERE ok) || ' pasan, ' || count(*) FILTER (WHERE NOT ok) || ' fallan, '
                            || count(*) FILTER (WHERE ok IS NULL) || ' N/A' FROM prueba.resultado" | sed 's/^/   /'
  echo "$version" > "$OUT/version-pg$v.txt"
done

[ -n "$DDL" ] && exit 0
python3 -I "$HERE/combinar.py" "$OUT" "$HERE/resultados.md" "$ROOT/informe" "${VERSIONS[@]}"
