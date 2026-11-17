-- Pruebas de sql/bna_extension.sql. Las ejecuta bna_app_user y son solo de la
-- rama mysql. Requiere arnes.sql, datos.sql y los periodos de 2001 y 2002 que
-- carga run_tests.sh.
SET @u1 = UUID_TO_BIN('11111111-1111-4111-8111-111111111111');
SET @h = REPEAT('a', 64);
SET @h2 = REPEAT('b', 64);

CALL prueba.verifica('X01', 'Extensión', 'Usuarios', 'hash_password admite 255 caracteres',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', REPEAT('x', 255), 'BCRYPT', 'v2', NULL, TRUE, 'pruebas')"),
  "SELECT CHAR_LENGTH(hash_password) = 255 FROM core.usuario_sistema WHERE username = 'ana'",
  '255', "SELECT CHAR_LENGTH(hash_password) FROM core.usuario_sistema WHERE username = 'ana'", 'procedimiento');

CALL prueba.rechaza('X02', 'Extensión', 'Usuarios', 'bna_app no escribe directamente usuarios',
  JSON_ARRAY("INSERT INTO core.usuario_sistema (id_usuario, username, nombre, rol, hash_password, algoritmo_hash, version_hash) VALUES (UUID_TO_BIN(UUID()), 'b', 'B', 'ASESOR', 'h', 'BCRYPT', 'v2')"),
  'denied', 'privilegio');

CALL prueba.rechaza('X03', 'Extensión', 'Usuarios', 'username es único',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE, 'pruebas')",
             "CALL core.crear_usuario(UUID_TO_BIN('22222222-2222-4222-8222-222222222222'), 'ana', 'Otra', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE, 'pruebas')"),
  'uk_usuario_sistema_1', 'declarativo');

CALL prueba.verifica('X04', 'Extensión', 'Usuarios', 'La migración de hash es condicional y deja un solo evento',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'ana', 'Ana', 'ASESOR', 'viejo', 'SHA256', 'v1', NULL, TRUE, 'pruebas')",
             "CALL core.migrar_hash_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'SHA256', 'nuevo', 'BCRYPT', 'v2', 'pruebas', @f1)",
             "CALL core.migrar_hash_usuario(UUID_TO_BIN('11111111-1111-4111-8111-111111111111'), 'SHA256', 'otro', 'BCRYPT', 'v2', 'pruebas', @f2)"),
  "SELECT @f1 = 1 AND @f2 = 0 AND (SELECT hash_password FROM core.usuario_sistema WHERE username = 'ana') = 'nuevo' AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'MIGRAR_HASH_PASSWORD' AND actor = 'pruebas') = 1",
  '1, 0 y un evento', "SELECT CONCAT(@f1, ', ', @f2)", 'procedimiento');

CALL prueba.rechaza('X05', 'Extensión', 'Productos', 'bna_app no escribe productos',
  JSON_ARRAY("INSERT INTO core.producto_credito (id_producto_credito, nombre, tasa_tea) VALUES (UUID_TO_BIN(UUID()), 'P', 0.1)"),
  'denied', 'privilegio');

CALL prueba.rechaza('X06', 'Extensión', 'Tipos de cambio', 'bna_app no escribe tipos de cambio',
  JSON_ARRAY("INSERT INTO core.tipo_cambio VALUES ('USD', 'PEN', '2026-01-01', 3.75)"),
  'denied', 'privilegio');

CALL prueba.rechaza('X07', 'Extensión', 'Periodos', 'No se registra un asiento en un periodo cerrado',
  JSON_ARRAY("CALL core.registrar_asiento(NULL, 'X07', '2001-01-15', '2001-01-15', 'g', 'PEN', UUID_TO_BIN(UUID()), NULL, JSON_ARRAY(JSON_OBJECT('partida', 'DEBE', 'importe', 10, 'cuenta', '1101'), JSON_OBJECT('partida', 'HABER', 'importe', 10, 'cuenta', '2101')), @a)"),
  'BNA-PERIODO', 'trigger');

CALL prueba.verifica('X08', 'Extensión', 'Periodos', 'Un periodo abierto admite el asiento',
  JSON_ARRAY("CALL core.registrar_asiento(NULL, 'X08', '2002-01-15', '2002-01-15', 'g', 'PEN', UUID_TO_BIN(UUID()), NULL, JSON_ARRAY(JSON_OBJECT('partida', 'DEBE', 'importe', 10, 'cuenta', '1101'), JSON_OBJECT('partida', 'HABER', 'importe', 10, 'cuenta', '2101')), @a)"),
  "SELECT COUNT(*) = 1 FROM core.asiento_contable WHERE numero_asiento = 'X08'", 'asiento registrado',
  "SELECT COUNT(*) FROM core.asiento_contable WHERE numero_asiento = 'X08'", 'trigger');

CALL prueba.verifica('X09', 'Extensión', 'Movimientos', 'El depósito actualiza el saldo y guarda la llave',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k1', REPEAT('a', 64), 'pruebas', @m, @r)"),
  "SELECT @r = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 + 100 AND (SELECT uuid_transaccion FROM cuentas.idempotencia_movimiento WHERE llave = 'k1') = @m",
  'saldo + 100 y llave', "SELECT @r", 'procedimiento');

CALL prueba.verifica('X10', 'Extensión', 'Movimientos', 'Repetir la llave devuelve la operación sin aplicarla',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k2', REPEAT('a', 64), 'pruebas', @m1, @r1)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k2', REPEAT('a', 64), 'pruebas', @m2, @r2)"),
  "SELECT @r2 = 1 AND @m1 = @m2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 + 100",
  'una sola aplicación', "SELECT @r2", 'procedimiento');

CALL prueba.rechaza('X11', 'Extensión', 'Movimientos', 'La misma llave con otros parámetros se rechaza',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k3', REPEAT('a', 64), 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 200, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k3', REPEAT('b', 64), 'pruebas', @m, @r)"),
  'BNA-IDEMPOTENCIA', 'procedimiento');

CALL prueba.rechaza('X12', 'Extensión', 'Movimientos', 'El retiro sin saldo sigue rechazándose por el trigger',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'RETIRO', 99999999, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-SALDO|RN-TOP-001', 'trigger');

CALL prueba.verifica('X13', 'Extensión', 'Movimientos', 'La transferencia mueve el saldo con un asiento por tramo',
  JSON_ARRAY("SET @o0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "SET @d0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), 'k4', REPEAT('a', 64), 'pruebas', @d, @c, @r)"),
  "SELECT (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @o0 - 50 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @d0 + 50 AND (SELECT id_asiento FROM cuentas.movimiento WHERE uuid_transaccion = @d) <> (SELECT id_asiento FROM cuentas.movimiento WHERE uuid_transaccion = @c)",
  'dos saldos y dos asientos', "SELECT @r", 'procedimiento');

CALL prueba.rechaza('X14', 'Extensión', 'Movimientos', 'No se transfiere entre monedas distintas',
  JSON_ARRAY("CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-USD-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'BNA-MONEDA', 'procedimiento');

CALL prueba.rechaza('X15', 'Extensión', 'Movimientos', 'No se transfiere a la misma cuenta',
  JSON_ARRAY("CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-PEN-1', 50, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'BNA-TRANSFERENCIA', 'procedimiento');

CALL prueba.verifica('X16', 'Extensión', 'Auditoría', 'El movimiento deja su evento en la misma operación',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 1, 'g', 'VEN', UUID_TO_BIN(UUID()), 'kX16', REPEAT('a', 64), 'pruebas', @m, @r)"),
  "SELECT COUNT(*) = 1 FROM core.evento_auditoria WHERE id_entidad = BIN_TO_UUID(@m) AND accion = 'DEPOSITO'", 'un evento',
  "SELECT COUNT(*) FROM core.evento_auditoria WHERE id_entidad = BIN_TO_UUID(@m)", 'procedimiento');

CALL prueba.rechaza('X17', 'Extensión', 'Auditoría', 'bna_app no modifica la bitácora',
  JSON_ARRAY("UPDATE core.evento_auditoria SET actor = 'x'"),
  'denied', 'privilegio');

CALL prueba.rechaza('X18', 'Extensión', 'Cuentas', 'Una mancomunada exige sus titulares',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X18', '00000000000000000018', 'PEN', 'MANCOMUNADA_CONJUNTA', 'AQP01', JSON_ARRAY('C001'), 'pruebas')"),
  'BNA-REGIMEN', 'procedimiento');

CALL prueba.verifica('X19', 'Extensión', 'Cuentas', 'La cuenta se abre con su titular',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X19', '00000000000000000019', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C001'), 'pruebas')"),
  "SELECT COUNT(*) = 1 FROM cuentas.titularidad WHERE num_cuenta = 'CTA-X19' AND cod_cliente = 'C001'", 'un titular',
  "SELECT COUNT(*) FROM cuentas.titularidad WHERE num_cuenta = 'CTA-X19'", 'procedimiento');

CALL prueba.verifica('X20', 'Extensión', 'Tarjetas', 'La tarjeta se emite y cambia de estado por el historial',
  JSON_ARRAY("CALL tarjetas.emitir_tarjeta(UUID_TO_BIN('33333333-3333-4333-8333-333333333333'), 'tok-x20', '455788', '1234', '2026-01-01', '2030-01-01', 'C001', 'CTA-PEN-1', 'pruebas')",
             "CALL tarjetas.cambiar_estado_tarjeta(UUID_TO_BIN('33333333-3333-4333-8333-333333333333'), 'ACTIVA', 'Activación', 'CLIENTE', 'pruebas', @h1)"),
  "SELECT estado_tarjeta = 'ACTIVA' FROM tarjetas.tarjeta WHERE pan_token = 'tok-x20'", 'ACTIVA',
  "SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE pan_token = 'tok-x20'", 'trigger');

CALL prueba.verifica('X21', 'Extensión', 'Catálogos', 'Un valor de la API con equivalente exacto se traduce',
  JSON_ARRAY("SET @v = (SELECT valor_bd FROM core.equivalencia_catalogo WHERE catalogo = 'estado_tarjeta' AND valor_api = 'ANULADA')"),
  "SELECT @v = 'CANCELADA'", 'CANCELADA', "SELECT @v", 'declarativo');

-- Hallazgos de la revisión independiente.
CALL prueba.rechaza('X40', 'Extensión', 'Canal', 'Un movimiento sin canal se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'RETIRO', 1, 'g', NULL, UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-CANAL', 'procedimiento');

CALL prueba.rechaza('X41', 'Extensión', 'Canal', 'Una transferencia sin canal se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 1, 'g', NULL, UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'BNA-CANAL', 'procedimiento');

CALL prueba.rechaza('X42', 'Extensión', 'Canal', 'El tope diario se aplica a la transferencia (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 20000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-PEN-2', 11000, 'g', 'HB', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'RN-TOP-001', 'trigger');

CALL prueba.rechaza('X43', 'Extensión', 'Canal', 'Un débito por ATM exige autorización de tarjeta (I7)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-CONJ', 'RETIRO', 1, 'g', 'ATM', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-CANAL', 'procedimiento');

CALL prueba.rechaza('X44', 'Extensión', 'Tarjetas', 'La tarjeta exige que el cliente sea titular de la cuenta (I3)',
  JSON_ARRAY("CALL tarjetas.emitir_tarjeta(UUID_TO_BIN('44444444-4444-4444-8444-444444444444'), 'tok-x44', '455788', '1234', '2026-01-01', '2030-01-01', 'C002', 'CTA-PEN-1', 'pruebas')"),
  'BNA-TARJETA', 'procedimiento');

CALL prueba.rechaza('X46', 'Extensión', 'Cuentas', 'Una cuenta individual tiene un solo titular (I4)',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X46', '00000000000000000046', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C001', 'C002'), 'pruebas')"),
  'BNA-REGIMEN', 'procedimiento');

CALL prueba.rechaza('X47', 'Extensión', 'Cuentas', 'El titular debe poder operar (I4)',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X47', '00000000000000000047', 'PEN', 'INDIVIDUAL', 'AQP01', JSON_ARRAY('C004'), 'pruebas')"),
  'BNA-TITULAR', 'procedimiento');

CALL prueba.rechaza('X48', 'Extensión', 'Cuentas', 'Los titulares son una lista JSON (I4)',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X48', '00000000000000000048', 'PEN', 'MANCOMUNADA_CONJUNTA', 'AQP01', JSON_OBJECT('a', 1, 'b', 2), 'pruebas')"),
  'BNA-REGIMEN', 'procedimiento');

CALL prueba.rechaza('X49', 'Extensión', 'Cuentas', 'Los titulares no se repiten (I4)',
  JSON_ARRAY("CALL cuentas.abrir_cuenta('CTA-X49', '00000000000000000049', 'PEN', 'MANCOMUNADA_CONJUNTA', 'AQP01', JSON_ARRAY('C001', 'C001'), 'pruebas')"),
  'BNA-REGIMEN', 'procedimiento');

CALL prueba.rechaza('X50', 'Extensión', 'Movimientos', 'registrar_movimiento solo admite depósito y retiro (I6)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'EXTORNO', 777, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-MOVIMIENTO', 'procedimiento');

CALL prueba.rechaza('X51', 'Extensión', 'Movimientos', 'Una transferencia de un solo tramo se rechaza (I6)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'TRANSFERENCIA_RECIBIDA', 1, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-MOVIMIENTO', 'procedimiento');

CALL prueba.verifica('X52', 'Extensión', 'Auditoría', 'crear_usuario deja su evento (I11)',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('55555555-5555-4555-8555-555555555555'), 'x52', 'A', 'ADMINISTRADOR', 'h', 'BCRYPT', 'v2', NULL, TRUE, 'pruebas')"),
  "SELECT COUNT(*) = 1 FROM core.evento_auditoria WHERE accion = 'CREAR_USUARIO' AND id_entidad = '55555555-5555-4555-8555-555555555555'", 'un evento',
  "SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'CREAR_USUARIO'", 'procedimiento');

CALL prueba.verifica('X53', 'Extensión', 'Auditoría', 'asignar_rol deja el rol anterior y el nuevo (I11, M11)',
  JSON_ARRAY("CALL core.crear_usuario(UUID_TO_BIN('55555555-5555-4555-8555-555555555556'), 'x53', 'A', 'ASESOR', 'h', 'BCRYPT', 'v2', NULL, TRUE, 'pruebas')",
             "CALL core.asignar_rol(UUID_TO_BIN('55555555-5555-4555-8555-555555555556'), 'AUDITOR', 'pruebas', @f)"),
  "SELECT COUNT(*) = 1 FROM core.evento_auditoria WHERE accion = 'ASIGNAR_ROLES' AND detalle->>'$.rol_anterior' = 'ASESOR' AND detalle->>'$.rol_nuevo' = 'AUDITOR'",
  'un evento con los dos roles', "SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'ASIGNAR_ROLES'", 'procedimiento');

CALL prueba.rechaza('X54', 'Extensión', 'Auditoría', 'bna_app no fabrica eventos de auditoría (I11)',
  JSON_ARRAY("CALL core.registrar_evento('CORE', 'e', '1', 'FALSO', 'nadie', NULL, NULL)"),
  'denied', 'privilegio');

CALL prueba.rechaza('X55', 'Extensión', 'Movimientos', 'Una cuenta nula da un error de regla (M9)',
  JSON_ARRAY("CALL cuentas.registrar_transferencia(NULL, 'CTA-PEN-1', 1, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'BNA-CUENTA', 'procedimiento');

CALL prueba.verifica('X57', 'Extensión', 'Movimientos', 'Repetir una transferencia devuelve la misma operación (I13)',
  JSON_ARRAY("SET @o0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'kX57', REPEAT('a', 64), 'pruebas', @d1, @c1, @r1)",
             "CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'kX57', REPEAT('a', 64), 'pruebas', @d2, @c2, @r2)"),
  "SELECT @r2 = 1 AND @d1 = @d2 AND @c1 = @c2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @o0 - 10",
  'una sola aplicación', "SELECT @r2", 'procedimiento');

CALL prueba.rechaza('X58', 'Extensión', 'Movimientos', 'Una llave de depósito no sirve para una transferencia (I13)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-2', 'DEPOSITO', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'kX58', REPEAT('a', 64), 'pruebas', @m, @r)",
             "CALL cuentas.registrar_transferencia('CTA-PEN-2', 'CTA-PEN-1', 10, 'g', 'VEN', UUID_TO_BIN(UUID()), 'kX58', REPEAT('b', 64), 'pruebas', @d, @c, @r)"),
  'BNA-IDEMPOTENCIA', 'procedimiento');

CALL prueba.verifica('X59', 'Extensión', 'Periodos', 'La fecha de negocio se corta a medianoche de Arequipa (I13)',
  JSON_ARRAY("SET @f = core.fn_fecha_negocio('2026-01-01 04:59:59')", "SET @g = core.fn_fecha_negocio('2026-01-01 05:00:00')"),
  "SELECT @f = '2025-12-31' AND @g = '2026-01-01'", '2025-12-31 y 2026-01-01', "SELECT CONCAT(@f, ' y ', @g)", 'procedimiento');

-- C2 reabierto: un débito sin fila en core.limite_canal se rechaza.
CALL prueba.rechaza('X60', 'Extensión', 'Canal', 'Un retiro por AGE, sin tope en las fuentes, se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 20000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-1', 'RETIRO', 2000, 'g', 'AGE', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-CANAL: el canal', 'trigger');

CALL prueba.rechaza('X61', 'Extensión', 'Canal', 'Una transferencia por AGE se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 20000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-PEN-2', 15000, 'g', 'AGE', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  'BNA-CANAL: el canal', 'trigger');

CALL prueba.rechaza('X62', 'Extensión', 'Canal', 'Un retiro en USD por HB, sin tope en las fuentes, se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-USD-1', 'DEPOSITO', 5000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-USD-1', 'RETIRO', 1000, 'g', 'HB', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-CANAL: el canal', 'trigger');

CALL prueba.rechaza('X63', 'Extensión', 'Canal', 'Un retiro en USD por AGE se rechaza (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-USD-1', 'DEPOSITO', 5000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-USD-1', 'RETIRO', 1000, 'g', 'AGE', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'BNA-CANAL: el canal', 'trigger');

CALL prueba.rechaza('X149', 'Extensión', 'Canal', 'Un débito en USD por BD, con fila deshabilitada, se rechaza con RN-BD-002 (R5)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-USD-1', 'DEPOSITO', 5000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-USD-1', 'RETIRO', 1, 'g', 'BD', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  'RN-BD-002: el canal BD', 'trigger');

CALL prueba.verifica('X64', 'Extensión', 'Canal', 'Ventanilla no tiene tope automático: retiro de 2000 (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 20000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-PEN-1', 'RETIRO', 2000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  "SELECT @m IS NOT NULL AND @r = 0", 'retiro aplicado', "SELECT @r", 'trigger');

CALL prueba.verifica('X65', 'Extensión', 'Canal', 'Ventanilla no tiene tope automático: transferencia de 15000 (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 20000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_transferencia('CTA-PEN-1', 'CTA-PEN-2', 15000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @d, @c, @r)"),
  "SELECT @d IS NOT NULL AND @r = 0", 'transferencia aplicada', "SELECT @r", 'trigger');

CALL prueba.verifica('X66', 'Extensión', 'Canal', 'Ventanilla opera en USD sin tope automático (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-USD-1', 'DEPOSITO', 5000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)",
             "CALL cuentas.registrar_movimiento('CTA-USD-1', 'RETIRO', 1000, 'g', 'VEN', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  "SELECT @m IS NOT NULL AND @r = 0", 'retiro aplicado', "SELECT @r", 'trigger');

CALL prueba.verifica('X67', 'Extensión', 'Canal', 'Un crédito por AGE no depende del tope (C2)',
  JSON_ARRAY("CALL cuentas.registrar_movimiento('CTA-PEN-1', 'DEPOSITO', 100, 'g', 'AGE', UUID_TO_BIN(UUID()), NULL, NULL, 'pruebas', @m, @r)"),
  "SELECT @m IS NOT NULL", 'depósito aplicado', "SELECT @r", 'trigger');

CALL prueba.rechaza('X68', 'Extensión', 'Canal', 'Una autorización por HB en USD se rechaza como en el movimiento (C2)',
  JSON_ARRAY("INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_canal, id_tarjeta, num_cuenta) VALUES ('RETIRO', 10, 'AUTORIZADA', 'HB', UUID_TO_BIN('a0000000-0000-4000-8000-000000000001'), 'CTA-USD-1')"),
  'ERR-TAR-006: el canal HB no opera en USD$', 'trigger');

-- Autorizaciones, extornos y credenciales de tarjeta (v1.5). T1 es la tarjeta de C001
-- y opera CTA-PEN-1, CTA-USD-1 y CTA-CONJ.
SET @t1 = UUID_TO_BIN('a0000000-0000-4000-8000-000000000001');

CALL prueba.verifica('X357', 'Extensión', 'Autorización', 'Un retiro en cajero dentro del tope se autoriza y retiene el saldo',
  JSON_ARRAY("SET @s0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000001'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e, @c)"),
  "SELECT @e = 'AUTORIZADA' AND @c = '00' AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 - 100 AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'AUTORIZAR_OPERACION') = 1",
  'AUTORIZADA, 00 y saldo disponible - 100', "SELECT CONCAT(@e, ', ', @c)", 'procedimiento');

CALL prueba.verifica('X358', 'Extensión', 'Autorización', 'Repetir el uuid con los mismos datos no vuelve a retener el saldo',
  JSON_ARRAY("SET @s0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000002'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e1, @c1)",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000002'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e2, @c2)"),
  "SELECT @e2 = 'AUTORIZADA' AND @c2 = '00' AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 - 100 AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'AUTORIZAR_OPERACION') = 1",
  'una sola retención y un evento', "SELECT CONCAT(@e2, ', ', @c2)", 'procedimiento');

CALL prueba.rechaza('X359', 'Extensión', 'Autorización', 'El mismo uuid con otro monto se rechaza',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000003'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000003'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 200, NULL, 'pruebas', @e, @c)"),
  'BNA-IDEMPOTENCIA: la autorización', 'procedimiento');

CALL prueba.verifica('X360', 'Extensión', 'Autorización', 'Sin saldo queda RECHAZADA con 51 y el saldo no cambia',
  JSON_ARRAY("SET @s0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-USD-1')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000004'), @t1, 'CTA-USD-1', 'VEN', NULL, 'RETIRO', 999999, NULL, 'pruebas', @e, @c)"),
  "SELECT @e = 'RECHAZADA' AND @c = '51' AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-USD-1') = @s0 AND (SELECT estado_autorizacion FROM tarjetas.autorizacion WHERE uuid_autorizacion = UUID_TO_BIN('a2000000-0000-4000-8000-000000000004')) = 'RECHAZADA'",
  'RECHAZADA, 51, saldo igual', "SELECT CONCAT(@e, ', ', @c)", 'procedimiento');

CALL prueba.verifica('X361', 'Extensión', 'Autorización', 'Sobre el tope del cajero queda RECHAZADA con 61, sin montos en el motivo',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000005'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 2000, NULL, 'pruebas', @e, @c)"),
  "SELECT @e = 'RECHAZADA' AND @c = '61' AND (SELECT motivo_rechazo FROM tarjetas.autorizacion WHERE uuid_autorizacion = UUID_TO_BIN('a2000000-0000-4000-8000-000000000005')) = 'ERR-TAR-007: tope diario excedido (RN-TOP-001)'",
  'RECHAZADA y 61', "SELECT CONCAT(@e, ', ', @c)", 'procedimiento');

CALL prueba.verifica('X362', 'Extensión', 'Autorización', 'Con la tarjeta bloqueada queda RECHAZADA con 62',
  JSON_ARRAY("CALL tarjetas.cambiar_estado_tarjeta(@t1, 'BLOQUEADA', 'prueba', 'CLIENTE', 'pruebas', @h)",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000006'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e, @c)"),
  "SELECT @e = 'RECHAZADA' AND @c = '62'", 'RECHAZADA y 62', "SELECT CONCAT(@e, ', ', @c)", 'procedimiento');

CALL prueba.verifica('X363', 'Extensión', 'Autorización', 'Una cuenta mancomunada conjunta en cajero queda RECHAZADA con 57 (RN-ATM-005)',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000007'), @t1, 'CTA-CONJ', NULL, 'ATM-AQP-001', 'RETIRO', 10, NULL, 'pruebas', @e, @c)"),
  "SELECT @e = 'RECHAZADA' AND @c = '57'", 'RECHAZADA y 57', "SELECT CONCAT(@e, ', ', @c)", 'procedimiento');

CALL prueba.rechaza('X364', 'Extensión', 'Autorización', 'Una tarjeta no autoriza en una cuenta que no opera',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000008'), @t1, 'CTA-PEN-2', 'VEN', NULL, 'RETIRO', 10, NULL, 'pruebas', @e, @c)"),
  'BNA-TARJETA: la tarjeta no opera esa cuenta', 'procedimiento');

CALL prueba.rechaza('X365', 'Extensión', 'Autorización', 'Un monto de cero se rechaza',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000009'), @t1, 'CTA-PEN-1', 'VEN', NULL, 'RETIRO', 0, NULL, 'pruebas', @e, @c)"),
  'BNA-MONTO', 'procedimiento');

CALL prueba.verifica('X366', 'Extensión', 'Extorno', 'El extorno libera el saldo retenido y el tope del día (RN-ATM-003)',
  JSON_ARRAY("SET @s0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @k0 = (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000010'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 300, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000010'), 'Cajero sin efectivo', 'pruebas', @x)"),
  "SELECT @x = 'EXTORNADA' AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 AND (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM') = @k0 AND (SELECT codigo_respuesta FROM tarjetas.autorizacion WHERE uuid_autorizacion = UUID_TO_BIN('a2000000-0000-4000-8000-000000000010')) = 'EXT'",
  'EXTORNADA, saldo y tope como antes', "SELECT @x", 'procedimiento');

CALL prueba.verifica('X367', 'Extensión', 'Extorno', 'Repetir el extorno no cambia nada y deja un solo evento',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000011'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 50, NULL, 'pruebas', @e, @c)",
             "SET @s0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000011'), 'x', 'pruebas', @x1)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000011'), 'x', 'pruebas', @x2)"),
  "SELECT @x2 = 'EXTORNADA' AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 + 50 AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE accion = 'EXTORNAR_AUTORIZACION') = 1",
  'una sola liberación', "SELECT @x2", 'procedimiento');

CALL prueba.rechaza('X368', 'Extensión', 'Extorno', 'No se extorna una autorización que no existe',
  JSON_ARRAY("CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-0000000000ff'), 'x', 'pruebas', @x)"),
  'BNA-AUTORIZACION: la autorización no existe', 'procedimiento');

CALL prueba.rechaza('X369', 'Extensión', 'Extorno', 'No se extorna una autorización rechazada',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000012'), @t1, 'CTA-USD-1', 'VEN', NULL, 'RETIRO', 999999, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000012'), 'x', 'pruebas', @x)"),
  'BNA-EXTORNO: una autorización rechazada', 'procedimiento');

CALL prueba.rechaza('X370', 'Extensión', 'Extorno', 'No se extorna una operación que ya tiene su movimiento',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000013'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e, @c)",
             "CALL prueba.movimiento('CTA-PEN-1', 'RETIRO', 100, 'ATM', NULL, UUID_TO_BIN('a2000000-0000-4000-8000-000000000013'), @m)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a2000000-0000-4000-8000-000000000013'), 'x', 'pruebas', @x)"),
  'BNA-EXTORNO: la operación ya tiene su movimiento', 'procedimiento');

CALL prueba.verifica('X371', 'Extensión', 'Credenciales', 'Un PIN registrado se valida y no queda en claro',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '4821', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '4821', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)"),
  "SELECT @r = 'EXITOSO' AND @i = 3 AND (SELECT COUNT(*) FROM tarjetas.credencial WHERE id_tarjeta = @t1 AND (hash_credencial LIKE '%4821%' OR sal LIKE '%4821%' OR hash_credencial = SHA2('4821', 256))) = 0 AND (SELECT COUNT(*) FROM core.evento_auditoria WHERE detalle LIKE '%4821%') = 0",
  'EXITOSO y 3 intentos', "SELECT CONCAT(@r, ', ', @i)", 'procedimiento');

CALL prueba.verifica('X372', 'Extensión', 'Credenciales', 'Un PIN equivocado registra el intento FALLIDO y descuenta uno',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '4821', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '0000', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)"),
  "SELECT @r = 'FALLIDO' AND @i = 2 AND (SELECT COUNT(*) FROM tarjetas.intento_autenticacion WHERE id_tarjeta = @t1 AND resultado = 'FALLIDO') = 1",
  'FALLIDO y 2 intentos', "SELECT CONCAT(@r, ', ', @i)", 'procedimiento');

CALL prueba.verifica('X373', 'Extensión', 'Credenciales', 'El tercer PIN equivocado bloquea la tarjeta (RN-TAR-004)',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '4821', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '0000', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '0001', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '0002', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)"),
  "SELECT @r = 'FALLIDO' AND @i = 0 AND (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = @t1) = 'BLOQUEADA'",
  'BLOQUEADA y 0 intentos', "SELECT (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = @t1)", 'procedimiento');

CALL prueba.rechaza('X374', 'Extensión', 'Credenciales', 'Con la tarjeta bloqueada no se valida el PIN ni se registra el intento',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '4821', 'pruebas')",
             "CALL tarjetas.cambiar_estado_tarjeta(@t1, 'BLOQUEADA', 'prueba', 'CLIENTE', 'pruebas', @h)",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '4821', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)"),
  'ERR-TAR-003: la tarjeta no es operativa', 'procedimiento');

CALL prueba.rechaza('X375', 'Extensión', 'Credenciales', 'Un PIN de cinco dígitos se rechaza sin mostrarlo (RN-TAR-001)',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '48213', 'pruebas')"),
  'BNA-CREDENCIAL: PIN_ATM debe tener 4 dígitos$', 'procedimiento');

CALL prueba.verifica('X376', 'Extensión', 'Credenciales', 'Cambiar el PIN reemplaza el anterior y reinicia los intentos',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '4821', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '0000', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r, @i)",
             "CALL tarjetas.registrar_credencial(@t1, 'PIN_ATM', '7390', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '4821', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r1, @i1)",
             "CALL tarjetas.validar_credencial(@t1, 'PIN_ATM', '7390', NULL, 'ATM-AQP-001', NULL, NULL, 'pruebas', @r2, @i2)"),
  "SELECT @r1 = 'FALLIDO' AND @i1 = 2 AND @r2 = 'EXITOSO' AND @i2 = 3",
  'el PIN anterior falla y el nuevo pasa', "SELECT CONCAT(@r1, ', ', @r2)", 'procedimiento');

CALL prueba.verifica('X377', 'Extensión', 'Credenciales', 'La clave web de seis dígitos se valida por Home Banking',
  JSON_ARRAY("CALL tarjetas.registrar_credencial(@t1, 'CLAVE_WEB', '615243', 'pruebas')",
             "CALL tarjetas.validar_credencial(@t1, 'CLAVE_WEB', '615243', 'HB', NULL, '10.0.0.8', NULL, 'pruebas', @r, @i)"),
  "SELECT @r = 'EXITOSO' AND @i = 3", 'EXITOSO', "SELECT @r", 'procedimiento');

-- Empleados (v1.6): solo la API registra empleados.
CALL prueba.rechaza('X397', 'Extensión', 'Empleados', 'bna_app no puede registrar empleados (solo bna_api)',
  JSON_ARRAY("CALL core.registrar_empleado(UUID_TO_BIN(UUID()), 'EMP-X397', 'E', 'ANALISTA', 'AQP01', NULL, 'pruebas')"),
  'denied', 'privilegio');

-- Captación (v1.7): solo la API trabaja el expediente del prospecto.
CALL prueba.rechaza('X444', 'Extensión', 'Captación', 'bna_app no puede registrar solicitantes (solo bna_api)',
  JSON_ARRAY("CALL clientes.registrar_solicitante_captacion(UUID_TO_BIN(UUID()), 'DNI', '71000444', 'R', 'P', NULL, '951000444', 'r@example.com', 'pruebas', UUID_TO_BIN(UUID()), @id, @dup)"),
  'denied', 'privilegio');

-- Confirmación de autorización (v1.8): convierte la retención en débito real al dispensar.
SET @t1 = UUID_TO_BIN('a0000000-0000-4000-8000-000000000001');

CALL prueba.verifica('X500', 'Extensión', 'Confirmación', 'Confirmación feliz: débito real, saldo contable y disponible iguales (retención liberada), tope ya comprometido',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @d0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @k0 = (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000001'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 100, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000001'), 'llave-confirmar-001', REPEAT('x', 64), 'pruebas', 'ATM', NULL, @trx, @estado)"),
  "SELECT @estado = 'DISPENSADA' AND @trx IS NOT NULL AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 - 100 AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @d0 - 100 AND (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM') = @k0 + 100 AND (SELECT estado_autorizacion FROM tarjetas.autorizacion WHERE uuid_autorizacion = UUID_TO_BIN('a3000000-0000-4000-8000-000000000001')) = 'DISPENSADA' AND (SELECT uuid_transaccion FROM tarjetas.autorizacion WHERE uuid_autorizacion = UUID_TO_BIN('a3000000-0000-4000-8000-000000000001')) = @trx",
  'DISPENSADA, contable -100, disponible -100, tope +100', "SELECT CONCAT(@estado, ', ', HEX(@trx))", 'procedimiento');

CALL prueba.verifica('X501', 'Extensión', 'Confirmación', 'Repetición idempotente con la misma llave devuelve el mismo resultado sin debitar dos veces',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @d0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @k0 = (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000002'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 200, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000002'), 'llave-confirmar-002', REPEAT('y', 64), 'pruebas', 'ATM', NULL, @trx1, @estado1)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000002'), 'llave-confirmar-002', REPEAT('y', 64), 'pruebas', 'ATM', NULL, @trx2, @estado2)"),
  "SELECT @estado2 = 'DISPENSADA' AND @trx1 = @trx2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 - 200 AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @d0 - 200 AND (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM') = @k0 + 200",
  'una sola aplicación', "SELECT CONCAT(@estado2, ', ', HEX(@trx1), ' = ', HEX(@trx2))", 'procedimiento');

CALL prueba.rechaza('X502', 'Extensión', 'Confirmación', 'Otra llave sobre autorización ya confirmada da error',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000003'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 50, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000003'), 'llave-confirmar-003', REPEAT('z', 64), 'pruebas', 'ATM', NULL, @trx, @estado)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000003'), 'otra-llave-003', REPEAT('w', 64), 'pruebas', 'ATM', NULL, @trx, @estado)"),
  'BNA-IDEMPOTENCIA|BNA-CONFIRMACION', 'procedimiento');

CALL prueba.rechaza('X503', 'Extensión', 'Confirmación', 'No se confirma una autorización extornada',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000004'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 75, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000004'), 'Cajero sin efectivo', 'pruebas', @x)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000004'), 'llave-confirmar-004', REPEAT('a', 64), 'pruebas', 'ATM', NULL, @trx, @estado)"),
  'BNA-CONFIRMACION: la autorización no está en estado vigente', 'procedimiento');

CALL prueba.verifica('X504', 'Extensión', 'Confirmación', 'Repetir con la misma llave sobre autorización ya confirmada es idempotente',
  JSON_ARRAY("SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @d0 = (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @k0 = (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')",
             "CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000005'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 30, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000005'), 'llave-confirmar-005', REPEAT('b', 64), 'pruebas', 'ATM', NULL, @trx1, @estado1)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000005'), 'llave-confirmar-005', REPEAT('b', 64), 'pruebas', 'ATM', NULL, @trx2, @estado2)"),
  "SELECT @estado2 = 'DISPENSADA' AND @trx1 = @trx2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0 - 30 AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @d0 - 30 AND (SELECT coalesce(max(monto_acumulado), 0) FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM') = @k0 + 30",
  'idempotente: mismo resultado', "SELECT CONCAT(@estado2, ', ', HEX(@trx1), ' = ', HEX(@trx2))", 'procedimiento');

CALL prueba.rechaza('X505', 'Extensión', 'Confirmación', 'No se confirma una autorización rechazada',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000006'), @t1, 'CTA-USD-1', 'VEN', NULL, 'RETIRO', 999999, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000006'), 'llave-confirmar-006', REPEAT('c', 64), 'pruebas', 'VEN', NULL, @trx, @estado)"),
  'BNA-CONFIRMACION: la autorización no está en estado vigente', 'procedimiento');

CALL prueba.rechaza('X506', 'Extensión', 'Confirmación', 'Extorno tras confirmar falla (el extorno es solo sin movimiento)',
  JSON_ARRAY("CALL tarjetas.autorizar_operacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000007'), @t1, 'CTA-PEN-1', NULL, 'ATM-AQP-001', 'RETIRO', 40, NULL, 'pruebas', @e, @c)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000007'), 'llave-confirmar-007', REPEAT('d', 64), 'pruebas', 'ATM', NULL, @trx, @estado)",
             "CALL tarjetas.extornar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000007'), 'Intento de extorno', 'pruebas', @x)"),
  'BNA-EXTORNO: la operación ya tiene su movimiento', 'procedimiento');

CALL prueba.rechaza('X507', 'Extensión', 'Confirmación', 'No se confirma una autorización INICIADA (sin haber pasado a AUTORIZADA)',
  JSON_ARRAY("INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, codigo_respuesta, id_terminal, ip_origen, id_tarjeta, num_cuenta, id_canal) VALUES (UUID_TO_BIN('a3000000-0000-4000-8000-000000000008'), 'RETIRO', 10, 'INICIADA', NULL, 'ATM-AQP-001', NULL, @t1, 'CTA-PEN-1', NULL)",
             "CALL tarjetas.confirmar_autorizacion(UUID_TO_BIN('a3000000-0000-4000-8000-000000000008'), 'llave-confirmar-008', REPEAT('e', 64), 'pruebas', 'ATM', NULL, @trx, @estado)"),
  'BNA-CONFIRMACION: la autorización no está en estado vigente', 'procedimiento');

-- =====================================================================
-- Billetera Digital Chaski (v1.9)
-- =====================================================================

-- 1. Credencial de cliente para el canal BD
-- Cada prueba usa sus propios datos (celular único, cliente existente) y es independiente.

CALL prueba.rechaza('X600', 'Billetera', 'Credencial Cliente', 'Registrar credencial: cliente inexistente',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('CLI999999999', '999999999', '123456', 'pruebas')"),
  'BNA-CLIENTE: el cliente no existe o no puede operar', 'procedimiento');

CALL prueba.rechaza('X601', 'Billetera', 'Credencial Cliente', 'Registrar credencial: cliente no puede operar (BLOQUEADO)',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C004', '999999999', '123456', 'pruebas')"),
  'BNA-CLIENTE: el cliente no existe o no puede operar', 'procedimiento');

CALL prueba.rechaza('X602', 'Billetera', 'Credencial Cliente', 'Registrar credencial: celular ya registrado',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C001', '959000001', '123456', 'pruebas')",
             "CALL clientes.registrar_credencial_cliente('C002', '959000001', '654321', 'pruebas')"),
  'BNA-CELULAR-DUPLICADO', 'procedimiento');

CALL prueba.rechaza('X603', 'Billetera', 'Credencial Cliente', 'Registrar credencial: PIN inválido (no 6 dígitos)',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '999999999', '12345', 'pruebas')"),
  'BNA-CREDENCIAL: PIN_BD debe tener 6 dígitos', 'procedimiento');

CALL prueba.verifica('X604', 'Billetera', 'Credencial Cliente', 'Registrar credencial feliz',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '988000001', '123456', 'pruebas')"),
  "SELECT (SELECT COUNT(*) FROM clientes.credencial_cliente WHERE cod_cliente = 'C003') = 1",
  'credencial registrada', "SELECT COUNT(*) FROM clientes.credencial_cliente WHERE cod_cliente = 'C003'", 'procedimiento');

CALL prueba.verifica('X605', 'Billetera', 'Credencial Cliente', 'Validar credencial: PIN correcto',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '988000002', '123456', 'pruebas')",
             "CALL clientes.validar_credencial_cliente('988000002', '123456', NULL, NULL, NULL, 'pruebas', @cod, @intentos)"),
  "SELECT @cod = 'C003' AND @intentos = 3",
  'C003 con 3 intentos', "SELECT CONCAT(@cod, ', ', @intentos)", 'procedimiento');

CALL prueba.verifica('X606', 'Billetera', 'Credencial Cliente', 'Validar credencial: PIN incorrecto cuenta intento',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '988000003', '123456', 'pruebas')",
             "CALL clientes.validar_credencial_cliente('988000003', '000000', NULL, NULL, NULL, 'pruebas', @cod, @intentos)"),
  "SELECT @cod IS NULL AND @intentos = 2",
  'NULL con 2 intentos', "SELECT CONCAT(COALESCE(@cod, 'NULL'), ', ', @intentos)", 'procedimiento');

CALL prueba.verifica('X607', 'Billetera', 'Credencial Cliente', 'Tercer fallo bloquea la credencial',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '988000004', '123456', 'pruebas')",
             "CALL clientes.validar_credencial_cliente('988000004', '000000', NULL, NULL, NULL, 'pruebas', @c1, @i1)",
             "CALL clientes.validar_credencial_cliente('988000004', '000001', NULL, NULL, NULL, 'pruebas', @c2, @i2)",
             "CALL clientes.validar_credencial_cliente('988000004', '000002', NULL, NULL, NULL, 'pruebas', @c3, @i3)"),
  "SELECT @c3 IS NULL AND @i3 = 0 AND (SELECT estado FROM clientes.credencial_cliente WHERE cod_cliente = 'C003') = 'BLOQUEADA'",
  'BLOQUEADA y 0 intentos', "SELECT (SELECT estado FROM clientes.credencial_cliente WHERE cod_cliente = 'C003')", 'procedimiento');

CALL prueba.rechaza('X608', 'Billetera', 'Credencial Cliente', 'Credencial bloqueada no se valida',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C003', '988000005', '123456', 'pruebas')",
             "CALL clientes.validar_credencial_cliente('988000005', '000000', NULL, NULL, NULL, 'pruebas', @c1, @i1)",
             "CALL clientes.validar_credencial_cliente('988000005', '000001', NULL, NULL, NULL, 'pruebas', @c2, @i2)",
             "CALL clientes.validar_credencial_cliente('988000005', '000002', NULL, NULL, NULL, 'pruebas', @c3, @i3)",
             "CALL clientes.validar_credencial_cliente('988000005', '123456', NULL, NULL, NULL, 'pruebas', @c4, @i4)"),
  'BNA-CREDENCIAL-BLOQUEADA', 'procedimiento');

-- 2. Esquema billetera: comercio

CALL prueba.rechaza('X610', 'Billetera', 'Comercio', 'bna_app no escribe comercios',
  JSON_ARRAY("INSERT INTO billetera.comercio (id_comercio, ruc, razon_social, num_cuenta_abono, estado) VALUES (UUID_TO_BIN(UUID()), '20100000099', 'Test', 'CTA-PEN-1', 'ACTIVO')"),
  'denied', 'privilegio');

CALL prueba.verifica('X611', 'Billetera', 'Comercio', 'Registrar comercio feliz',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('77777777-7777-4777-8777-777777777777'), '20100000099', 'Comercio Test', 'CTA-PEN-1', 'pruebas', @id)"),
  "SELECT (SELECT COUNT(*) FROM billetera.comercio WHERE ruc = '20100000099') = 1",
  'comercio registrado', "SELECT COUNT(*) FROM billetera.comercio WHERE ruc = '20100000099'", 'procedimiento');

CALL prueba.rechaza('X612', 'Billetera', 'Comercio', 'Comercio: RUC duplicado',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('77777777-7777-4777-8777-777777777777'), '20100000099', 'Comercio Test', 'CTA-PEN-1', 'pruebas', @id)",
             "CALL billetera.registrar_comercio(UUID_TO_BIN('88888888-8888-4888-8888-888888888888'), '20100000099', 'Otro', 'CTA-PEN-1', 'pruebas', @id)"),
  'uk_comercio_ruc', 'declarativo');

CALL prueba.rechaza('X613', 'Billetera', 'Comercio', 'Comercio: cuenta de abono inexistente',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('99999999-9999-4999-8999-999999999999'), '20200000099', 'Comercio X', 'CTA-NOEXISTE', 'pruebas', @id)"),
  'BNA-CUENTA: no existe la cuenta', 'procedimiento');

-- 3. Código QR

CALL prueba.rechaza('X620', 'Billetera', 'QR', 'bna_app no escribe códigos QR',
  JSON_ARRAY("INSERT INTO billetera.codigo_qr (id_qr, id_comercio, id_cuenta, tipo, monto, estado) VALUES (UUID_TO_BIN(UUID()), UUID_TO_BIN('77777777-7777-4777-8777-777777777777'), NULL, 'ESTATICO', NULL, 'ACTIVO')"),
  'denied', 'privilegio');

CALL prueba.verifica('X621', 'Billetera', 'QR', 'QR estático de comercio',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '20300000099', 'Comercio QR', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), @idc, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)"),
  "SELECT (SELECT tipo FROM billetera.codigo_qr WHERE id_qr = @idqr) = 'ESTATICO' AND (SELECT monto FROM billetera.codigo_qr WHERE id_qr = @idqr) IS NULL",
  'QR estático sin monto', "SELECT CONCAT((SELECT tipo FROM billetera.codigo_qr WHERE id_qr = @idqr), ', ', COALESCE((SELECT monto FROM billetera.codigo_qr WHERE id_qr = @idqr), 'NULL'))", 'procedimiento');

CALL prueba.verifica('X622', 'Billetera', 'QR', 'QR dinámico de cliente con monto fijo',
  JSON_ARRAY("CALL billetera.crear_qr(UUID_TO_BIN('cccccccc-cccc-4ccc-8ccc-cccccccccccc'), NULL, 'CTA-PEN-2', 'DINAMICO', 50.00, NULL, 'pruebas', @idqr)"),
  "SELECT (SELECT tipo FROM billetera.codigo_qr WHERE id_qr = @idqr) = 'DINAMICO' AND (SELECT monto FROM billetera.codigo_qr WHERE id_qr = @idqr) = 50.00",
  'QR dinámico con monto 50', "SELECT CONCAT((SELECT tipo FROM billetera.codigo_qr WHERE id_qr = @idqr), ', ', COALESCE((SELECT monto FROM billetera.codigo_qr WHERE id_qr = @idqr), 'NULL'))", 'procedimiento');

CALL prueba.rechaza('X623', 'Billetera', 'QR', 'QR: ni comercio ni cuenta',
  JSON_ARRAY("CALL billetera.crear_qr(UUID_TO_BIN('dddddddd-dddd-4ddd-8ddd-dddddddddddd'), NULL, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)"),
  'BNA-QR: exige comercio o cuenta', 'procedimiento');

CALL prueba.rechaza('X624', 'Billetera', 'QR', 'QR estático con monto no permitido',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'), '20400000099', 'Comercio QR2', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('ffffffff-ffff-4fff-8fff-ffffffffffff'), @idc, NULL, 'ESTATICO', 100.00, NULL, 'pruebas', @idqr)"),
  'BNA-QR: QR estático no admite monto', 'procedimiento');

CALL prueba.rechaza('X625', 'Billetera', 'QR', 'QR dinámico sin monto',
  JSON_ARRAY("CALL billetera.crear_qr(UUID_TO_BIN('11111111-1111-4111-8111-111111111112'), NULL, 'CTA-PEN-2', 'DINAMICO', NULL, NULL, 'pruebas', @idqr)"),
  'BNA-QR: QR dinámico exige monto', 'procedimiento');

-- 4. Pago QR

CALL prueba.verifica('X630', 'Billetera', 'Pago QR', 'Pagar QR comercio feliz con saldos',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('22222222-2222-4222-8222-222222222222'), '20500000099', 'Comercio Pago', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('33333333-3333-4333-8333-333333333333'), @idc, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)",
             "SET @s0o = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "SET @s0d = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL billetera.pagar_qr(UUID_TO_BIN('44444444-4444-4444-8444-444444444444'), @idqr, 'CTA-PEN-2', 100.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-qr-001', REPEAT('x', 64), 'pruebas', @uuid, @repetido)"),
  "SELECT @repetido = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0o - 100 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0d + 100 AND @uuid IS NOT NULL",
  'saldo origen -100, destino +100', "SELECT CONCAT('origen: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'), ', destino: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1'))", 'procedimiento');

CALL prueba.rechaza('X631', 'Billetera', 'Pago QR', 'QR vencido',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('55555555-5555-4555-8555-555555555556'), '20600000099', 'Comercio Vencido', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('66666666-6666-4666-8666-666666666666'), @idc, NULL, 'ESTATICO', NULL, DATE_SUB(UTC_TIMESTAMP(6), INTERVAL 1 DAY), 'pruebas', @idqr)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('77777777-7777-4777-8777-777777777778'), @idqr, 'CTA-PEN-2', 50.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-qr-002', REPEAT('y', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-QR-VENCIDO', 'procedimiento');

CALL prueba.rechaza('X632', 'Billetera', 'Pago QR', 'Pagar dos veces el mismo QR dinámico (segunda falla)',
  JSON_ARRAY("CALL billetera.crear_qr(UUID_TO_BIN('88888888-8888-4888-8888-888888888889'), NULL, 'CTA-PEN-2', 'DINAMICO', 75.00, NULL, 'pruebas', @idqr)",
             "SET @s0o = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL billetera.pagar_qr(UUID_TO_BIN('99999999-9999-4999-8999-99999999999a'), @idqr, 'CTA-PEN-1', 75.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-qr-003', REPEAT('z', 64), 'pruebas', @uuid1, @r1)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), @idqr, 'CTA-PEN-1', 75.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-qr-004', REPEAT('w', 64), 'pruebas', @uuid2, @r2)"),
  'BNA-QR-YA-PAGADO', 'procedimiento');

-- 5. Solicitud de cobro (cliente a cliente por celular)

CALL prueba.verifica('X640', 'Billetera', 'Solicitud Cobro', 'Crear solicitud de cobro feliz',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C002', '959000002', '123456', 'pruebas')",
             "CALL billetera.crear_solicitud_cobro(UUID_TO_BIN('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'C001', '959000002', 200.00, 'Cena', 'BD', UUID_TO_BIN(UUID()), 'llave-solicitud-001', REPEAT('x', 64), 'pruebas', @id)"),
  "SELECT (SELECT estado FROM billetera.solicitud_cobro WHERE id_solicitud = @id) = 'PENDIENTE'",
  'PENDIENTE', "SELECT (SELECT estado FROM billetera.solicitud_cobro WHERE id_solicitud = @id)", 'procedimiento');

CALL prueba.rechaza('X641', 'Billetera', 'Solicitud Cobro', 'Solicitud: celular no registrado en billetera',
  JSON_ARRAY("CALL billetera.crear_solicitud_cobro(UUID_TO_BIN('cccccccc-cccc-4ccc-8ccc-cccccccccccc'), 'C001', '999999999', 100.00, 'Test', 'BD', UUID_TO_BIN(UUID()), 'llave-solicitud-002', REPEAT('y', 64), 'pruebas', @id)"),
  'BNA-CELULAR-NO-REGISTRADO', 'procedimiento');

CALL prueba.rechaza('X642', 'Billetera', 'Solicitud Cobro', 'Solicitud: no puedes cobrarte a ti mismo',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C001', '959000001', '123456', 'pruebas')",
             "CALL billetera.crear_solicitud_cobro(UUID_TO_BIN('dddddddd-dddd-4ddd-8ddd-dddddddddddd'), 'C001', '959000001', 100.00, 'Test', 'BD', UUID_TO_BIN(UUID()), 'llave-solicitud-003', REPEAT('z', 64), 'pruebas', @id)"),
  'BNA-AUTOSOLICITUD', 'procedimiento');

CALL prueba.verifica('X643', 'Billetera', 'Solicitud Cobro', 'Pagar solicitud de cobro feliz',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C002', '959000002', '123456', 'pruebas')",
             "CALL billetera.crear_solicitud_cobro(UUID_TO_BIN('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'), 'C001', '959000002', 150.00, 'Almuerzo', 'BD', UUID_TO_BIN(UUID()), 'llave-solicitud-004', REPEAT('a', 64), 'pruebas', @ids)",
             "SET @s0o = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "SET @s0d = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL billetera.pagar_solicitud_cobro(UUID_TO_BIN('ffffffff-ffff-4fff-8fff-ffffffffffff'), @ids, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-solicitud-001', REPEAT('b', 64), 'pruebas', @uuid, @repetido)"),
  "SELECT @repetido = 0 AND (SELECT estado FROM billetera.solicitud_cobro WHERE id_solicitud = @ids) = 'PAGADA' AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0o - 150 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0d + 150",
  'PAGADA, saldos correctos', "SELECT CONCAT('estado: ', (SELECT estado FROM billetera.solicitud_cobro WHERE id_solicitud = @ids), ', origen: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'), ', destino: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1'))", 'procedimiento');

CALL prueba.rechaza('X644', 'Billetera', 'Solicitud Cobro', 'Pagar dos veces la misma solicitud (segunda falla)',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C002', '959000002', '123456', 'pruebas')",
             "CALL billetera.crear_solicitud_cobro(UUID_TO_BIN('11111111-1111-4111-8111-111111111113'), 'C001', '959000002', 80.00, 'Test', 'BD', UUID_TO_BIN(UUID()), 'llave-solicitud-005', REPEAT('c', 64), 'pruebas', @ids)",
             "CALL billetera.pagar_solicitud_cobro(UUID_TO_BIN('22222222-2222-4222-8222-222222222223'), @ids, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-solicitud-002', REPEAT('d', 64), 'pruebas', @uuid1, @r1)",
             "CALL billetera.pagar_solicitud_cobro(UUID_TO_BIN('33333333-3333-4333-8333-333333333334'), @ids, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-solicitud-003', REPEAT('e', 64), 'pruebas', @uuid2, @r2)"),
  'BNA-SOLICITUD-YA-PAGADA', 'procedimiento');

-- 6. Transferencia P2P por celular

CALL prueba.verifica('X650', 'Billetera', 'Transferencia P2P', 'Transferencia P2P por celular feliz',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C002', '959000002', '123456', 'pruebas')",
             "SET @s0o = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "SET @s0d = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL billetera.transferir_celular(UUID_TO_BIN('44444444-4444-4444-8444-444444444445'), 'C001', '959000002', 300.00, 'Regalo', 'BD', UUID_TO_BIN(UUID()), 'llave-p2p-001', REPEAT('f', 64), 'pruebas', @uuid, @repetido)"),
  "SELECT @repetido = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0o - 300 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0d + 300",
  'saldos correctos', "SELECT CONCAT('origen: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1'), ', destino: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'))", 'procedimiento');

CALL prueba.rechaza('X651', 'Billetera', 'Transferencia P2P', 'P2P: celular no registrado',
  JSON_ARRAY("CALL billetera.transferir_celular(UUID_TO_BIN('55555555-5555-4555-8555-555555555557'), 'C001', '999999999', 100.00, 'Test', 'BD', UUID_TO_BIN(UUID()), 'llave-p2p-002', REPEAT('g', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-CELULAR-NO-REGISTRADO', 'procedimiento');

CALL prueba.rechaza('X652', 'Billetera', 'Transferencia P2P', 'P2P: no te puedes transferir a ti mismo',
  JSON_ARRAY("CALL clientes.registrar_credencial_cliente('C001', '959000001', '123456', 'pruebas')",
             "CALL billetera.transferir_celular(UUID_TO_BIN('66666666-6666-4666-8666-666666666667'), 'C001', '959000001', 100.00, 'Test', 'BD', UUID_TO_BIN(UUID()), 'llave-p2p-003', REPEAT('h', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-AUTOTRANSFERENCIA', 'procedimiento');

-- 7. Recarga celular

CALL prueba.verifica('X660', 'Billetera', 'Recarga', 'Recarga celular feliz',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('00000000-0000-4000-8000-000000000099'), '20100000099', 'Banco Servicios', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.registrar_operador_servicio('Claro', 'RECARGA', TRUE, 'pruebas')",
             "SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL billetera.recargar_celular(UUID_TO_BIN('77777777-7777-4777-8777-777777777779'), 'C002', 'Claro', '987654321', 20.00, 'BD', UUID_TO_BIN(UUID()), 'llave-recarga-001', REPEAT('i', 64), 'pruebas', @uuid, @repetido)"),
  "SELECT @repetido = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 - 20 AND (SELECT COUNT(*) FROM billetera.recarga WHERE operador = 'Claro' AND celular = '987654321') = 1",
  'saldo -20 y recarga registrada', "SELECT CONCAT('saldo: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'))", 'procedimiento');

CALL prueba.rechaza('X661', 'Billetera', 'Recarga', 'Recarga: operador no existe',
  JSON_ARRAY("CALL billetera.recargar_celular(UUID_TO_BIN('88888888-8888-4888-8888-88888888888a'), 'C001', 'Inexistente', '987654321', 20.00, 'BD', UUID_TO_BIN(UUID()), 'llave-recarga-002', REPEAT('j', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-OPERADOR-NO-EXISTE', 'procedimiento');

CALL prueba.rechaza('X662', 'Billetera', 'Recarga', 'Recarga: monto no permitido',
  JSON_ARRAY("CALL billetera.registrar_operador_servicio('Claro', 'RECARGA', TRUE, 'pruebas')",
             "CALL billetera.recargar_celular(UUID_TO_BIN('99999999-9999-4999-8999-99999999999b'), 'C001', 'Claro', '987654321', 99.00, 'BD', UUID_TO_BIN(UUID()), 'llave-recarga-003', REPEAT('k', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-MONTO-NO-PERMITIDO', 'procedimiento');

-- 8. Pago de servicio

CALL prueba.verifica('X670', 'Billetera', 'Pago Servicio', 'Pago de servicio feliz',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('00000000-0000-4000-8000-000000000099'), '20100000099', 'Banco Servicios', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.registrar_operador_servicio('Sedapal', 'SERVICIO', TRUE, 'pruebas')",
             "SET @s0 = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "CALL billetera.pagar_servicio(UUID_TO_BIN('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'C002', 'Sedapal', '12345678', '2026-01', 150.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-serv-001', REPEAT('l', 64), 'pruebas', @uuid, @repetido)"),
  "SELECT @repetido = 0 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0 - 150 AND (SELECT COUNT(*) FROM billetera.pago_servicio WHERE operador = 'Sedapal' AND referencia = '12345678') = 1",
  'saldo -150 y pago registrado', "SELECT CONCAT('saldo: ', (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'))", 'procedimiento');

CALL prueba.rechaza('X671', 'Billetera', 'Pago Servicio', 'Pago servicio: operador no existe',
  JSON_ARRAY("CALL billetera.pagar_servicio(UUID_TO_BIN('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'C001', 'Inexistente', '12345678', '2026-01', 100.00, 'BD', UUID_TO_BIN(UUID()), 'llave-pago-serv-002', REPEAT('m', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-OPERADOR-NO-EXISTE', 'procedimiento');

-- 9. Idempotencia

CALL prueba.verifica('X680', 'Billetera', 'Idempotencia', 'Repetición idempotente con la misma llave (pago QR)',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('cccccccc-cccc-4ccc-8ccc-cccccccccccd'), '20700000099', 'Comercio Idem', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('dddddddd-dddd-4ddd-8ddd-dddddddddddd'), @idc, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)",
             "SET @s0o = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2')",
             "SET @s0d = (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')",
             "CALL billetera.pagar_qr(UUID_TO_BIN('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeef'), @idqr, 'CTA-PEN-2', 60.00, 'BD', UUID_TO_BIN(UUID()), 'llave-idem-001', REPEAT('n', 64), 'pruebas', @uuid1, @r1)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('ffffffff-ffff-4fff-8fff-ffffffffffff'), @idqr, 'CTA-PEN-2', 60.00, 'BD', UUID_TO_BIN(UUID()), 'llave-idem-001', REPEAT('n', 64), 'pruebas', @uuid2, @r2)"),
  "SELECT @r2 = 1 AND @uuid1 = @uuid2 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2') = @s0o - 60 AND (SELECT saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = @s0d + 60",
  'idempotente: mismo uuid', "SELECT CONCAT(@r2, ', ', HEX(@uuid1), ' = ', HEX(@uuid2))", 'procedimiento');

CALL prueba.rechaza('X681', 'Billetera', 'Idempotencia', 'Llave reutilizada con otro contenido (pago QR)',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('11111111-1111-4111-8111-111111111114'), '20800000099', 'Comercio Idem2', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('22222222-2222-4222-8222-222222222224'), @idc, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('33333333-3333-4333-8333-333333333335'), @idqr, 'CTA-PEN-2', 50.00, 'BD', UUID_TO_BIN(UUID()), 'llave-idem-002', REPEAT('o', 64), 'pruebas', @uuid1, @r1)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('44444444-4444-4444-8444-444444444446'), @idqr, 'CTA-PEN-2', 100.00, 'BD', UUID_TO_BIN(UUID()), 'llave-idem-002', REPEAT('p', 64), 'pruebas', @uuid2, @r2)"),
  'BNA-IDEMPOTENCIA', 'procedimiento');

-- 10. Fondos insuficientes

CALL prueba.rechaza('X690', 'Billetera', 'Fondos', 'Pago QR con fondos insuficientes',
  JSON_ARRAY("CALL billetera.registrar_comercio(UUID_TO_BIN('55555555-5555-4555-8555-555555555558'), '20900000099', 'Comercio Fondos', 'CTA-PEN-1', 'pruebas', @idc)",
             "CALL billetera.crear_qr(UUID_TO_BIN('66666666-6666-4666-8666-666666666668'), @idc, NULL, 'ESTATICO', NULL, NULL, 'pruebas', @idqr)",
             "CALL billetera.pagar_qr(UUID_TO_BIN('77777777-7777-4777-8777-77777777777a'), @idqr, 'CTA-PEN-2', 999999.00, 'BD', UUID_TO_BIN(UUID()), 'llave-fondos-001', REPEAT('q', 64), 'pruebas', @uuid, @repetido)"),
  'BNA-SALDO', 'procedimiento');

-- 11. Vistas _api

CALL prueba.verifica('X700', 'Billetera', 'Vistas API', 'Vista v_comercio_api existe y es legible por bna_api',
  JSON_ARRAY("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_comercio_api'"),
  '1', '1', "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_comercio_api'", 'declarativo');

CALL prueba.verifica('X701', 'Billetera', 'Vistas API', 'Vista v_qr_api existe',
  JSON_ARRAY("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_qr_api'"),
  '1', '1', "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_qr_api'", 'declarativo');

CALL prueba.verifica('X702', 'Billetera', 'Vistas API', 'Vista v_solicitud_cobro_api existe',
  JSON_ARRAY("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_solicitud_cobro_api'"),
  '1', '1', "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_solicitud_cobro_api'", 'declarativo');

CALL prueba.verifica('X703', 'Billetera', 'Vistas API', 'Vista v_notificacion_api existe',
  JSON_ARRAY("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_notificacion_api'"),
  '1', '1', "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_notificacion_api'", 'declarativo');

CALL prueba.verifica('X704', 'Billetera', 'Vistas API', 'Vista v_operador_servicio_api existe',
  JSON_ARRAY("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_operador_servicio_api'"),
  '1', '1', "SELECT COUNT(*) FROM information_schema.views WHERE table_schema = 'billetera' AND table_name = 'v_operador_servicio_api'", 'declarativo');