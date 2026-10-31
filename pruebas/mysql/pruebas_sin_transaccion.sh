# Pruebas de sql/bna_extension.sql fuera de una transacción. El arnés siempre abre
# una, así que estas corren con el cliente mysql en autocommit, como bna_app_user.
# Las carga run_tests.sh, que define root_, app_ y registrar.
# shellcheck shell=bash

seguridad_() { docker exec -i -e MYSQL_PWD=seg "$C" mysql -ubna_seguridad_user --default-character-set=utf8mb4 "$@"; }
root_ -e "CREATE ROLE IF NOT EXISTS bna_seguridad;
          CREATE USER 'bna_seguridad_user'@'%' IDENTIFIED BY 'seg' DEFAULT ROLE bna_seguridad"

# caso ID DESCRIPCION CONDICION < sentencias: tras ejecutarlas, CONDICION debe ser 1.
# CLIENTE elige la sesión: app_ por omisión.
caso() {
  local id="$1" desc="$2" cond="$3" salida obtenido
  salida="$("${CLIENTE:-app_}" --force 2>&1 || true)"
  obtenido="$(root_ -N -e "SELECT coalesce(($cond), 0)" 2>&1 || true)"
  registrar "$id" bna_app_user Extensión 'Sin transacción' "$desc" procedimiento 1 \
    "$obtenido; $(echo "$salida" | grep -m1 ERROR | cut -c1-120 | tr -d "'")" "$([ "$obtenido" = 1 ] && echo 1 || echo 0)"
}
asientos() { root_ -N -e "SELECT COUNT(*) FROM core.asiento_contable"; }

root_ <<'SQL'
INSERT INTO cuentas.cuenta_ahorro (num_cuenta, cci, moneda, regimen, estado_cuenta, id_agencia) VALUES
  ('AC-1', '00000000000000000071', 'PEN', 'INDIVIDUAL', 'ACTIVA', 'AQP01'),
  ('AC-2', '00000000000000000072', 'PEN', 'INDIVIDUAL', 'ACTIVA', 'AQP01'),
  ('AC-B', '00000000000000000073', 'PEN', 'INDIVIDUAL', 'BLOQUEADA', 'AQP01');
INSERT INTO cuentas.titularidad (cod_cliente, num_cuenta) VALUES ('C001', 'AC-1'), ('C002', 'AC-2'), ('C002', 'AC-B');
START TRANSACTION;
CALL prueba.movimiento('AC-1', 'DEPOSITO', 1000, 'VEN', NULL, NULL, @m);
COMMIT;
SQL

n="$(asientos)"
caso X70 'Una transferencia a una cuenta bloqueada no deja nada (C1)' \
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-1') = 1000
      AND (SELECT COUNT(*) FROM cuentas.idempotencia_movimiento WHERE llave = 'k70') = 0
      AND (SELECT COUNT(*) FROM core.asiento_contable) = $n" <<'SQL'
CALL cuentas.registrar_transferencia('AC-1', 'AC-B', 300, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k70', REPEAT('a', 64), 'pruebas', @d, @c, @r);
SQL
caso X71 'Repetir la llave tras un fallo no informa éxito (C1)' \
  "SELECT COUNT(*) = 0 FROM cuentas.idempotencia_movimiento WHERE llave = 'k70'" <<'SQL'
CALL cuentas.registrar_transferencia('AC-1', 'AC-B', 300, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k70', REPEAT('a', 64), 'pruebas', @d, @c, @r);
SQL
n="$(asientos)"
caso X72 'Un retiro sin saldo no deja asiento ni llave (C1)' \
  "SELECT (SELECT COUNT(*) FROM cuentas.idempotencia_movimiento WHERE llave = 'k72') = 0
      AND (SELECT COUNT(*) FROM core.asiento_contable) = $n" <<'SQL'
CALL cuentas.registrar_movimiento('AC-2', 'RETIRO', 5, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k72', REPEAT('a', 64), 'pruebas', @m, @r);
SQL
caso X73 'Un titular inexistente no deja la cuenta (C1)' \
  "SELECT COUNT(*) = 0 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-X73'" <<'SQL'
CALL cuentas.abrir_cuenta('AC-X73', '00000000000000000075', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('NOEXISTE'), 'pruebas');
SQL
# Fallo a mitad de cada procedimiento: el evento es su último paso y un actor nulo
# lo rechaza después de las escrituras.
root_ <<'SQL'
INSERT INTO core.usuario_sistema (id_usuario, username, nombre, rol, hash_password, algoritmo_hash, version_hash)
VALUES (UUID_TO_BIN('77777777-7777-4777-8777-777777777777'), 'ac-rol', 'R', 'ASESOR', 'viejo', 'SHA256', 'v1');
INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
VALUES (UUID_TO_BIN('77777777-7777-4777-8777-777777777778'), 'tok-ac', '455788', '1234', '2026-01-01', '2030-01-01', 'ACTIVA', 'C001');
SQL
USUARIO="UUID_TO_BIN('77777777-7777-4777-8777-777777777777')"
PLASTICO="UUID_TO_BIN('77777777-7777-4777-8777-777777777778')"
caso X74 'crear_usuario no deja la fila si falla el evento (C1)' \
  "SELECT COUNT(*) = 0 FROM core.usuario_sistema WHERE username = 'ac-x74'" <<SQL
CALL core.crear_usuario(UUID_TO_BIN(UUID()), 'ac-x74', 'A', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE, NULL);
SQL
caso X75 'asignar_rol no cambia el rol si falla el evento (C1)' \
  "SELECT rol = 'ASESOR' FROM core.usuario_sistema WHERE username = 'ac-rol'" <<SQL
CALL core.asignar_rol($USUARIO, 'AUDITOR', NULL, @f);
SQL
caso X76 'migrar_hash_usuario no cambia el hash si falla el evento (C1)' \
  "SELECT hash_password = 'viejo' FROM core.usuario_sistema WHERE username = 'ac-rol'" <<SQL
CALL core.migrar_hash_usuario($USUARIO, 'SHA256', 'nuevo', 'BCRYPT', 'v2', NULL, @f);
SQL
n="$(asientos)"
caso X77 'registrar_movimiento no deja saldo, asiento ni llave si falla el evento (C1)' \
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-1') = 1000
      AND (SELECT COUNT(*) FROM cuentas.idempotencia_movimiento WHERE llave = 'k77') = 0
      AND (SELECT COUNT(*) FROM core.asiento_contable) = $n" <<'SQL'
CALL cuentas.registrar_movimiento('AC-1', 'DEPOSITO', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k77', REPEAT('a', 64), NULL, @m, @r);
SQL
caso X78 'registrar_transferencia no mueve saldos si falla el evento (C1)' \
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-1') = 1000
      AND (SELECT COUNT(*) FROM cuentas.idempotencia_movimiento WHERE llave = 'k78') = 0
      AND (SELECT COUNT(*) FROM core.asiento_contable) = $n" <<'SQL'
CALL cuentas.registrar_transferencia('AC-1', 'AC-2', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k78', REPEAT('a', 64), NULL, @d, @c, @r);
SQL
caso X79 'abrir_cuenta no deja la cuenta si falla el evento (C1)' \
  "SELECT COUNT(*) = 0 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-X79'" <<'SQL'
CALL cuentas.abrir_cuenta('AC-X79', '00000000000000000079', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C001'), NULL);
SQL
caso X80 'emitir_tarjeta no deja la tarjeta si falla el evento (C1)' \
  "SELECT COUNT(*) = 0 FROM tarjetas.tarjeta WHERE pan_token = 'tok-x80'" <<'SQL'
CALL tarjetas.emitir_tarjeta(UUID_TO_BIN(UUID()), 'tok-x80', '455788', '1234', '2026-01-01', '2030-01-01', 'C001', 'AC-1', NULL);
SQL
caso X81 'cambiar_estado_tarjeta no cambia el estado si falla el evento (C1)' \
  "SELECT estado_tarjeta = 'ACTIVA' FROM tarjetas.tarjeta WHERE pan_token = 'tok-ac'" <<SQL
CALL tarjetas.cambiar_estado_tarjeta($PLASTICO, 'BLOQUEADA', 'x', 'CLIENTE', NULL, @h);
SQL

caso X82 'Una operación válida se confirma sola y deja su evento (C1)' \
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-2') = 40
      AND (SELECT uuid_transaccion IS NOT NULL FROM cuentas.idempotencia_movimiento WHERE llave = 'k82')" <<'SQL'
CALL cuentas.registrar_movimiento('AC-2', 'DEPOSITO', 40, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k82', REPEAT('a', 64), 'pruebas', @m, @r);
SQL
caso X83 'Dentro de una transacción, un fallo solo deshace su operación (C1)' \
  "SELECT saldo_contable = 45 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-2'" <<'SQL'
START TRANSACTION;
CALL cuentas.registrar_movimiento('AC-2', 'DEPOSITO', 5, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r);
CALL cuentas.registrar_movimiento('AC-2', 'RETIRO', 9999, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r);
COMMIT;
SQL

# I1: la sesión 1 fija su instantánea, otra sesión desbloquea la tarjeta y la
# sesión 1 pide bloquearla.
root_ <<'SQL'
INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
VALUES (UUID_TO_BIN('66666666-6666-4666-8666-666666666666'), 'tok-x84', '455788', '1234', '2026-01-01', '2030-01-01', 'ACTIVA', 'C001');
INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
VALUES ('BLOQUEADA', 'x', 'SEGURIDAD', UUID_TO_BIN('66666666-6666-4666-8666-666666666666'));
SQL
TARJETA="UUID_TO_BIN('66666666-6666-4666-8666-666666666666')"
app_ > "$OUT/X84-sesion1.log" 2>&1 <<SQL &
START TRANSACTION;
SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = $TARJETA;
DO SLEEP(2);
CALL tarjetas.cambiar_estado_tarjeta($TARJETA, 'BLOQUEADA', 'robo', 'CLIENTE', 'pruebas', @h);
COMMIT;
SQL
sesion1=$!
sleep 1
seguridad_ -e "CALL tarjetas.desbloquear_tarjeta($TARJETA, 'y', 'pruebas', @h)" || true
wait "$sesion1" || true
caso X84 'Un bloqueo concurrente se aplica y avisa a SEGURIDAD (I1)' \
  "SELECT (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = $TARJETA) = 'BLOQUEADA'
      AND (SELECT COUNT(*) FROM tarjetas.evento_salida WHERE id_tarjeta = $TARJETA AND carga_json->>'\$.motivo' = 'robo') = 1" </dev/null

# I2: el desbloqueo solo existe para bna_seguridad.
root_ <<'SQL'
INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
VALUES (UUID_TO_BIN('88888888-8888-4888-8888-888888888881'), 'tok-x85', '455788', '1234', '2026-01-01', '2030-01-01', 'ACTIVA', 'C001'),
       (UUID_TO_BIN('88888888-8888-4888-8888-888888888882'), 'tok-x87', '455788', '1234', '2026-01-01', '2030-01-01', 'ACTIVA', 'C001'),
       (UUID_TO_BIN('88888888-8888-4888-8888-888888888883'), 'tok-x92', '455788', '1234', '2026-01-01', '2030-01-01', 'PENDIENTE_ACTIVACION', 'C001');
INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
VALUES ('BLOQUEADA', 'x', 'SEGURIDAD', UUID_TO_BIN('88888888-8888-4888-8888-888888888881')),
       ('RETENIDA', 'x', 'SISTEMA', UUID_TO_BIN('88888888-8888-4888-8888-888888888882'));
SQL
T1="UUID_TO_BIN('88888888-8888-4888-8888-888888888881')"
T2="UUID_TO_BIN('88888888-8888-4888-8888-888888888882')"
T3="UUID_TO_BIN('88888888-8888-4888-8888-888888888883')"
estado() { echo "SELECT estado_tarjeta = '$2' FROM tarjetas.tarjeta WHERE id_tarjeta = $1"; }
caso X85 'cambiar_estado_tarjeta no desbloquea con origen OPERADOR (I2)' "$(estado "$T1" BLOQUEADA)" <<SQL
CALL tarjetas.cambiar_estado_tarjeta($T1, 'ACTIVA', 'x', 'OPERADOR', 'pruebas', @h);
SQL
caso X86 'cambiar_estado_tarjeta no desbloquea con origen SEGURIDAD (I2)' "$(estado "$T1" BLOQUEADA)" <<SQL
CALL tarjetas.cambiar_estado_tarjeta($T1, 'ACTIVA', 'x', 'SEGURIDAD', 'pruebas', @h);
SQL
caso X87 'cambiar_estado_tarjeta no reactiva una tarjeta RETENIDA (I2)' "$(estado "$T2" RETENIDA)" <<SQL
CALL tarjetas.cambiar_estado_tarjeta($T2, 'ACTIVA', 'x', 'OPERADOR', 'pruebas', @h);
SQL
caso X88 'bna_app no ejecuta desbloquear_tarjeta (I2)' "$(estado "$T1" BLOQUEADA)" <<SQL
CALL tarjetas.desbloquear_tarjeta($T1, 'x', 'pruebas', @h);
SQL
CLIENTE=seguridad_ caso X89 'Sin actor no se desbloquea: la operación es atómica (I2)' "$(estado "$T1" BLOQUEADA)" <<SQL
CALL tarjetas.desbloquear_tarjeta($T1, 'x', NULL, @h);
SQL
CLIENTE=seguridad_ caso X90 'bna_seguridad desbloquea, con historial, aviso y auditoría (I2)' \
  "SELECT (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = $T1) = 'ACTIVA'
      AND (SELECT origen FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = $T1 ORDER BY id_historial DESC LIMIT 1) = 'SEGURIDAD'
      AND (SELECT COUNT(*) FROM tarjetas.evento_salida WHERE id_tarjeta = $T1 AND carga_json->>'\$.estado_nuevo' = 'ACTIVA') = 1
      AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'DESBLOQUEAR_TARJETA' AND id_entidad = BIN_TO_UUID($T1)) = 1" <<SQL
CALL tarjetas.desbloquear_tarjeta($T1, 'revisado', 'pruebas', @h);
SQL
CLIENTE=seguridad_ caso X91 'bna_seguridad también libera una tarjeta RETENIDA (I2)' "$(estado "$T2" ACTIVA)" <<SQL
CALL tarjetas.desbloquear_tarjeta($T2, 'revisado', 'pruebas', @h);
SQL
CLIENTE=seguridad_ caso X92 'desbloquear_tarjeta no activa una tarjeta que no está bloqueada (I2)' \
  "$(estado "$T3" PENDIENTE_ACTIVACION)" <<SQL
CALL tarjetas.desbloquear_tarjeta($T3, 'x', 'pruebas', @h);
SQL
CLIENTE=seguridad_ caso X93 'bna_seguridad no ejecuta los otros procedimientos (I2)' \
  "SELECT COUNT(*) = 0 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'AC-X93'" <<'SQL'
CALL cuentas.abrir_cuenta('AC-X93', '00000000000000000093', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C001'), 'pruebas');
SQL
