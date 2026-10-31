-- Pruebas de sql/bna_extension.sql. Las ejecuta bna_app_user y son solo de la
-- rama mysql. Requiere arnes.sql, datos.sql y los periodos de 2001 y 2002 que
-- carga run_extension.sh.
SET @u1 = UUID_TO_BIN('11111111-1111-4111-8111-111111111111');
SET @h = REPEAT('a', 64);
SET @h2 = REPEAT('b', 64);

CALL prueba.verifica('X01', 'Extensión', 'Usuarios', 'hash_password admite 255 caracteres',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', REPEAT('x', 255), 'BCRYPT', 'v2', NULL, TRUE)"),
  "SELECT CHAR_LENGTH(hash_password) = 255 FROM core.usuario_sistema WHERE username = 'ana'",
  '255', "SELECT CHAR_LENGTH(hash_password) FROM core.usuario_sistema WHERE username = 'ana'", 'procedimiento');

CALL prueba.rechaza('X02', 'Extensión', 'Usuarios', 'bna_app no escribe directamente usuarios',
  JSON_ARRAY("INSERT INTO core.usuario_sistema (id_usuario, username, nombre, rol, hash_password, algoritmo_hash, version_hash) VALUES (UUID_TO_BIN(UUID()), 'b', 'B', 'ASESOR', 'h', 'BCRYPT', 'v2')"),
  'denied', 'privilegio');

CALL prueba.rechaza('X03', 'Extensión', 'Usuarios', 'username es único',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE)",
             "CALL core.crear_usuario(UUID_TO_BIN('22222222-2222-4222-8222-222222222222'), 'ana', 'Otra', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE)"),
  'uk_usuario_sistema_1', 'declarativo');

CALL prueba.verifica('X04', 'Extensión', 'Usuarios', 'La migración de hash es condicional y deja un solo evento',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', 'viejo', 'SHA256', 'v1', NULL, TRUE)",
             "CALL core.migrar_hash_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'SHA256', 'nuevo', 'BCRYPT', 'v2', @f1)",
             "CALL core.migrar_hash_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'SHA256', 'otro', 'BCRYPT', 'v2', @f2)"),
  "SELECT @f1 = 1 AND @f2 = 0 AND (SELECT hash_password FROM core.usuario_sistema WHERE username = 'ana') = 'nuevo' AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'MIGRAR_HASH_PASSWORD' AND actor = 'ana') = 1",
  '1, 0 y un evento', "SELECT CONCAT(@f1, ', ', @f2)", 'procedimiento');

CALL prueba.rechaza('X05', 'Extensión', 'Productos', 'bna_app no escribe productos',
  JSON_ARRAY("INSERT INTO core.producto_credito (id_producto_credito, nombre, tasa_tea) VALUES (UUID_TO_BIN(UUID()), 'P', 0.1)"),
  'denied', 'privilegio');

CALL prueba.rechaza('X06', 'Extensión', 'Tipos de cambio', 'bna_app no escribe tipos de cambio',
  JSON_ARRAY("INSERT INTO core.tipo_cambio VALUES ('USD', 'PEN', '2026-01-01', 3.75)"), 'denied', 'privilegio');

CALL prueba.rechaza('X07', 'Extensión', 'Periodos', 'No se registra un asiento en un periodo cerrado',
  JSON_ARRAY("CALL core.registrar_asiento(NULL, 'X07', '2001-01-15', '2001-01-15', 'g', 'PEN', UUID_TO_BIN(UUID()), NULL, JSON_ARRAY(JSON_OBJECT('partida', 'DEBE', 'importe', 10, 'cuenta', '1101'), JSON_OBJECT('partida', 'HABER', 'importe', 10, 'cuenta', '2101')), @a)"),
  'BNA-PERIODO', 'trigger');

CALL prueba.verifica('X08', 'Extensión', 'Periodos', 'Un periodo abierto admite el asiento',
  JSON_ARRAY("CALL core.registrar_asiento(NULL, 'X08', '2002-01-15', '2002-01-15', 'g', 'PEN', UUID_TO_BIN(UUID()), NULL, JSON_ARRAY(JSON_OBJECT('partida', 'DEBE', 'importe', 10, 'cuenta', '1101'), JSON_OBJECT('partida', 'HABER', 'importe', 10, 'cuenta', '2101')), @a)"),
  "SELECT COUNT(*) = 1 FROM core.asiento_contable WHERE numero_asiento = 'X08'", 'asiento registrado',
  "SELECT COUNT(*) FROM core.asiento_contable WHERE numero_asiento = 'X08'", 'trigger');

CALL prueba.verifica('X09', 'Extensión', 'Movimientos', 'El depósito actualiza el saldo y guarda la llave',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k1', REPEAT('a', 64), @m, @r)"),
  "SELECT @r = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 + 100 AND (SELECT uuid_transaccion FROM cuentas.idempotencia_movimiento WHERE llave = 'k1') = @m",
  'saldo + 100 y llave', "SELECT @r", 'procedimiento');

CALL prueba.verifica('X10', 'Extensión', 'Movimientos', 'Repetir la llave devuelve la operación sin aplicarla',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k2', REPEAT('a', 64), @m1, @r1)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k2', REPEAT('a', 64), @m2, @r2)"),
  "SELECT @r2 = 1 AND @m1 = @m2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 + 100",
  'una sola aplicación', "SELECT @r2", 'procedimiento');

CALL prueba.rechaza('X11', 'Extensión', 'Movimientos', 'La misma llave con otros parámetros se rechaza',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k3', REPEAT('a', 64), @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 200, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k3', REPEAT('b', 64), @m, @r)"),
  'BNA-IDEMPOTENCIA', 'procedimiento');

CALL prueba.rechaza('X12', 'Extensión', 'Movimientos', 'El retiro sin saldo sigue rechazándose por el trigger',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'RETIRO', 99999999, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, @m, @r)"),
  'BNA-SALDO|RN-TOP-001', 'trigger');

CALL prueba.verifica('X13', 'Extensión', 'Movimientos', 'La transferencia mueve el saldo con un asiento por tramo',
  JSON_ARRAY("SET @o0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "SET @d0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k4', REPEAT('a', 64), @d, @c, @r)"),
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @o0 - 50 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @d0 + 50 AND (SELECT id_asiento FROM cuentas.movimiento WHERE uuid_transaccion = @d) <> (SELECT id_asiento FROM cuentas.movimiento WHERE uuid_transaccion = @c)",
  'dos saldos y dos asientos', "SELECT @r", 'procedimiento');

CALL prueba.rechaza('X14', 'Extensión', 'Movimientos', 'No se transfiere entre monedas distintas',
  JSON_ARRAY("CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-USD-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, @d, @c, @r)"),
  'BNA-MONEDA', 'procedimiento');

CALL prueba.rechaza('X15', 'Extensión', 'Movimientos', 'No se transfiere a la misma cuenta',
  JSON_ARRAY("CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-PEN-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, @d, @c, @r)"),
  'BNA-TRANSFERENCIA', 'procedimiento');

CALL prueba.verifica('X16', 'Extensión', 'Auditoría', 'El evento general se registra por el procedimiento',
  JSON_ARRAY("CALL core.registrar_evento('CUENTAS', 'cuenta_ahorro', 'CTA-1', 'ACCION_X16', 'ana', NULL, JSON_OBJECT('a', 1))"),
  "SELECT COUNT(*) = 1 FROM core.evento_auditoria WHERE accion = 'ACCION_X16'", 'un evento',
  "SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'ACCION_X16'", 'procedimiento');

CALL prueba.rechaza('X17', 'Extensión', 'Auditoría', 'bna_app no modifica la bitácora',
  JSON_ARRAY("UPDATE core.evento_auditoria SET actor = 'x'"), 'denied', 'privilegio');

CALL prueba.rechaza('X18', 'Extensión', 'Cuentas', 'Una mancomunada exige sus titulares',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X18', '00000000000000000018', 'PEN', 'MANCOMUNADA_CONJUNTA', 'AQP01', JSON_ARRAY('C001'))"),
  'BNA-CUENTA', 'procedimiento');

CALL prueba.verifica('X19', 'Extensión', 'Cuentas', 'La cuenta se abre con su titular',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X19', '00000000000000000019', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C001'))"),
  "SELECT COUNT(*) = 1 FROM cuentas.titularidad WHERE num_cuenta = 'CTA-X19' AND cod_cliente = 'C001'", 'un titular',
  "SELECT COUNT(*) FROM cuentas.titularidad WHERE num_cuenta = 'CTA-X19'", 'procedimiento');

CALL prueba.verifica('X20', 'Extensión', 'Tarjetas', 'La tarjeta se emite y cambia de estado por el historial',
  JSON_ARRAY("CALL tarjetas.emitir_tarjeta(UUID_TO_BIN('33333333-3333-4333-8333-333333333333'), 'tok-x20', '455788', '1234', '2026-01-01', '2030-01-01', 'C001', 'CTA-PEN-1')",
             "CALL tarjetas.cambiar_estado_tarjeta(UUID_TO_BIN('33333333-3333-4333-8333-333333333333'), 'ACTIVA', 'Activación', 'CLIENTE', @h1)"),
  "SELECT estado_tarjeta = 'ACTIVA' FROM tarjetas.tarjeta WHERE pan_token = 'tok-x20'", 'ACTIVA',
  "SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE pan_token = 'tok-x20'", 'trigger');

CALL prueba.verifica('X21', 'Extensión', 'Catálogos', 'Un valor de la API con equivalente exacto se traduce',
  JSON_ARRAY("SET @v = (SELECT valor_bd FROM core.equivalencia_catalogo WHERE catalogo = 'estado_tarjeta' AND valor_api = 'ANULADA')"),
  "SELECT @v = 'CANCELADA'", 'CANCELADA', "SELECT @v", 'declarativo');
