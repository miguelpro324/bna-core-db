-- Pruebas de la base integrada. Requiere arnes.sql y datos.sql.
-- Grupos:
--   M  equivalentes de las 25 fallas reproducidas en la base unificada para
--      MySQL (bna_mysql_repro); el número es el de esa comprobación.
--   F  objetos portados o implementados (triggers, funciones, vistas, índices).
--   R  pruebas negativas originales del informe (regresión).
-- Las pruebas que solo pueden hacerse fuera de una transacción (confirmación
-- real y concurrencia) las ejecuta run_tests.sh.
\set ON_ERROR_STOP on
\set QUIET on
SET client_min_messages = warning;

-- =====================================================================
-- M: fallas de la base unificada para MySQL
-- =====================================================================
SELECT prueba.na('M01', 'MySQL', 'Comprobación 1 (bug 1)', 'El script de carga encuentra el archivo SQL',
  'N/A — prevenido por diseño: no hay script de carga con rutas; el DDL es un único archivo (sql/bna_core.sql) que se carga directamente, y su carga se prueba en L01.');

SELECT prueba.verifica('M04', 'MySQL', 'Comprobación 4 (bug 3)', 'Un depósito actualiza el saldo de la cuenta',
  $q$SELECT prueba.movimiento('CTA-PEN-2', 'DEPOSITO', 500, 'VEN')$q$,
  $q$SELECT saldo_contable = 5500 AND saldo_disponible = 5500 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'$q$,
  'saldo 5000.00 -> 5500.00',
  $q$SELECT 'saldo 5000.00 -> ' || saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'$q$);

SELECT prueba.verifica('M05', 'MySQL', 'Comprobación 5 (bug 4)', 'Pagar reduce la deuda del crédito',
  $q$SELECT creditos.aplicar_pago('f0000000-0000-4000-8000-000000000001')$q$,
  $q$SELECT sum(saldo_pendiente) = 7200 FROM creditos.cuota WHERE id_calendario = 'd0000000-0000-4000-8000-000000000001'$q$,
  'deuda 10300.00 -> 7200.00',
  $q$SELECT 'deuda 10300.00 -> ' || sum(saldo_pendiente) FROM creditos.cuota WHERE id_calendario = 'd0000000-0000-4000-8000-000000000001'$q$);

SELECT prueba.na('M06', 'MySQL', 'Comprobación 6 (bug 2)', 'fn_uuid_v7() guarda la hora correcta',
  'N/A — no aplica: la función no se porta; los UUID los genera gen_random_uuid(), nativa de PostgreSQL (versión 4, sin marca de tiempo).');
SELECT prueba.na('M07', 'MySQL', 'Comprobación 7 (bug 2)', 'Los UUID v7 se ordenan por fecha de creación',
  'N/A — no aplica: por la misma razón que M06; el orden de las bitácoras lo da su identificador IDENTITY y su marca de tiempo.');

SELECT prueba.rechaza('M08', 'MySQL', 'Comprobación 8 (bug 7)', 'Un identificador debe ser un UUID válido',
  $q$INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('c2', 'tok-x', '455788', '1111', '2026-01-01', '2030-01-01', 'ACTIVA', 'C002')$q$,
  'invalid input syntax for type uuid');

SELECT prueba.rechaza('M09a', 'MySQL', 'Comprobación 9 (bug 7)', 'La orden no abona en la cuenta de otro cliente',
  $q$INSERT INTO creditos.orden_desembolso (codigo_orden, importe, estado_orden, idempotency_key, request_hash, usuario_preparacion,
       correlation_id, id_evaluacion, num_cuenta, id_canal)
     VALUES ('DES-T-1', 1000, 'PREPARADA', gen_random_uuid(), repeat('x', 64), 'u', gen_random_uuid(),
       'c0000000-0000-4000-8000-000000000002', 'CTA-PEN-1', 'VEN')$q$,
  'BNA-CUENTA-DESTINO.*no pertenece');
SELECT prueba.rechaza('M09b', 'MySQL', 'Comprobación 9 (bug 7)', 'La orden no abona en una cuenta de otra moneda',
  $q$INSERT INTO creditos.orden_desembolso (codigo_orden, importe, estado_orden, idempotency_key, request_hash, usuario_preparacion,
       correlation_id, id_evaluacion, num_cuenta, id_canal)
     VALUES ('DES-T-2', 1000, 'PREPARADA', gen_random_uuid(), repeat('x', 64), 'u', gen_random_uuid(),
       'c0000000-0000-4000-8000-000000000001', 'CTA-USD-1', 'VEN')$q$,
  'BNA-CUENTA-DESTINO.*USD');
SELECT prueba.rechaza('M09c', 'MySQL', 'Comprobación 9 (bug 7)', 'La orden no supera el límite aprobado',
  $q$INSERT INTO creditos.orden_desembolso (codigo_orden, importe, estado_orden, idempotency_key, request_hash, usuario_preparacion,
       correlation_id, id_evaluacion, num_cuenta, id_canal)
     VALUES ('DES-T-3', 99999, 'PREPARADA', gen_random_uuid(), repeat('x', 64), 'u', gen_random_uuid(),
       'c0000000-0000-4000-8000-000000000001', 'CTA-PEN-1', 'VEN')$q$,
  'BNA-IMPORTE');

SELECT prueba.rechaza('M10a', 'MySQL', 'Comprobación 10 (bug 7)', 'Un retiro no deja el saldo en negativo',
  $q$SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 6000, 'VEN')$q$,
  'BNA-SALDO');
SELECT prueba.rechaza('M10b', 'MySQL', 'Comprobación 10 (bug 7)', 'Un movimiento va en la moneda de su cuenta',
  $q$SELECT prueba.movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'VEN', 'USD')$q$,
  'BNA-MONEDA');

SELECT prueba.rechaza('M11', 'MySQL', 'Comprobación 11 (bug 7)', 'El saldo disponible no supera al contable',
  $q$UPDATE cuentas.cuenta_ahorro SET saldo_disponible = 9000 WHERE num_cuenta = 'CTA-PEN-2'$q$,
  'ck_cuenta_ahorro_1');

SELECT prueba.na('M12', 'MySQL', 'Comprobación 12 (bug 7)', 'El total de la cuota es la suma de sus partes',
  'N/A — prevenido por diseño: CUOTA no guarda el total; es un dato derivado de capital, interés y otros conceptos, eliminado en la normalización.');

SELECT prueba.rechaza('M13a', 'MySQL', 'Comprobación 13 (bug 4)', 'No se aplica más de lo pagado',
  $q$INSERT INTO creditos.aplicacion_pago VALUES ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 3, 3500)$q$,
  'BNA-PAGO.*se aplicarían');
SELECT prueba.rechaza('M13b', 'MySQL', 'Comprobación 13 (bug 4)', 'No se aplica más del saldo de la cuota',
  $q$INSERT INTO creditos.aplicacion_pago VALUES ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 1, 3101)$q$,
  'BNA-PAGO.*solo debe');

SELECT prueba.rechaza('M14a', 'MySQL', 'Comprobación 14 (bug 7)', 'Una orden genera un solo crédito',
  $q$INSERT INTO creditos.credito VALUES ('CR-0002', 'AL_DIA', 'e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001')$q$,
  'uk_credito');
SELECT prueba.rechaza('M14b', 'MySQL', 'Comprobación 14 (bug 7)', 'Una solicitud tiene una sola orden confirmada, aun en otra ronda',
  $q$INSERT INTO creditos.evaluacion (id_evaluacion, ronda, score_calculado, limite_aprobado, id_solicitud, id_consulta, id_regla)
     VALUES ('c0000000-0000-4000-8000-0000000000e2', 2, 700, 10000, 'b0000000-0000-4000-8000-000000000001',
       'b1000000-0000-4000-8000-000000000001', 'R-A');
     INSERT INTO creditos.orden_desembolso (codigo_orden, importe, estado_orden, idempotency_key, request_hash, usuario_preparacion,
       correlation_id, id_evaluacion, num_cuenta, id_canal)
     VALUES ('DES-T-4', 5000, 'CONFIRMADA', gen_random_uuid(), repeat('x', 64), 'u', gen_random_uuid(),
       'c0000000-0000-4000-8000-0000000000e2', 'CTA-PEN-1', 'VEN')$q$,
  'BNA-ORDEN-UNICA');

SELECT prueba.rechaza('M15a', 'MySQL', 'Comprobación 15 (bug 7)', 'Los últimos cuatro dígitos son numéricos',
  $q$INSERT INTO tarjetas.tarjeta (pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('tok-x', '455788', 'ABCD', '2026-01-01', '2030-01-01', 'ACTIVA', 'C002')$q$,
  'ck_tarjeta_2');
SELECT prueba.rechaza('M15b', 'MySQL', 'Comprobación 15 (bug 7)', 'La tarjeta vence después de emitirse',
  $q$INSERT INTO tarjetas.tarjeta (pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('tok-x', '455788', '1111', '2026-01-01', '2020-01-01', 'ACTIVA', 'C002')$q$,
  'ck_tarjeta_1');

SELECT prueba.rechaza('M16', 'MySQL', 'Comprobación 16 (bug 7)', 'La matriz no es una credencial de la tarjeta',
  $q$INSERT INTO tarjetas.credencial (id_tarjeta, tipo_credencial, hash_credencial, sal)
     VALUES ('a0000000-0000-4000-8000-000000000002', 'TOKEN_MATRIZ', repeat('a', 64), repeat('b', 32))$q$,
  'ck_credencial_1');

SELECT prueba.rechaza('M17', 'MySQL', 'Comprobación 17 (bug 7)', 'La coordenada pedida existe en la matriz',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, coord_fila, coord_columna, id_canal, resultado, id_tarjeta)
     VALUES ('TOKEN_MATRIZ', 'Z', 9, 'HB', 'FALLIDO', 'a0000000-0000-4000-8000-000000000001')$q$,
  'ck_intento_autenticacion_1');

SELECT prueba.rechaza('M18', 'MySQL', 'Comprobación 18 (bug 7)', 'Una referencia apunta a un registro real',
  $q$INSERT INTO creditos.evaluacion (ronda, score_calculado, limite_aprobado, id_solicitud, id_consulta, id_regla)
     VALUES (1, 700, 1000, 'b0000000-0000-4000-8000-0000000000ff', 'b1000000-0000-4000-8000-000000000001', 'R-A')$q$,
  'violates foreign key constraint');

SELECT prueba.rechaza('M19', 'MySQL', 'Comprobación 19', 'La auditoría solo registra eventos sobre registros reales',
  $q$INSERT INTO creditos.evento_auditoria (modulo_emisor, id_entidad, accion, actor, correlation_id)
     VALUES (13, 'tabla_que_no_existe', 'x', 'y', gen_random_uuid())$q$,
  'fk_evento_auditoria_2');

SELECT prueba.rechaza('M20a', 'MySQL', 'Comprobación 20 (bug 7)', 'Un asiento descuadrado se rechaza al confirmar',
  $q$INSERT INTO core.asiento_contable (id_asiento, numero_asiento, fecha_contable, fecha_valor, glosa, moneda, correlation_id)
     VALUES ('9a000000-0000-4000-8000-000000000001', 'T-DESC', current_date, current_date, 'Solo debe', 'PEN', gen_random_uuid());
     INSERT INTO core.detalle_asiento VALUES ('9a000000-0000-4000-8000-000000000001', 1, 'DEBE', 100, '1101')$q$,
  'BNA-PARTIDA-DOBLE');

SELECT prueba.na('M21', 'MySQL', 'Comprobación 21', 'Una reversión la autoriza otra persona',
  'N/A — prevenido por diseño: el modelo no guarda usuarios ni empleados; el solicitante y la autorización son identificadores que emite Seguridad, que es quien controla a las personas.');

SELECT prueba.verifica('M22', 'MySQL', 'Comprobación 22 (bug 5)', 'Un retiro se cuenta una sola vez en el tope y en el saldo',
  $q$INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, codigo_respuesta,
       id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000001', 'RETIRO', 600, 'AUTORIZADA', '00', 'ATM-AQP-001',
       'a0000000-0000-4000-8000-000000000002', 'CTA-PEN-2');
     SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 600, 'ATM', NULL, '9b000000-0000-4000-8000-000000000001');
     UPDATE tarjetas.autorizacion SET estado_autorizacion = 'DISPENSADA'
      WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000001'$q$,
  $q$SELECT cd.monto_acumulado = 600 AND cu.saldo_contable = 4400 AND cu.saldo_disponible = 4400
        AND a.uuid_transaccion = a.uuid_autorizacion
       FROM core.consumo_diario cd
       JOIN cuentas.cuenta_ahorro cu ON cu.num_cuenta = cd.num_cuenta
       JOIN tarjetas.autorizacion a ON a.uuid_autorizacion = '9b000000-0000-4000-8000-000000000001'
      WHERE cd.num_cuenta = 'CTA-PEN-2' AND cd.id_canal = 'ATM'$q$,
  'consumido 600.00; contable 4400.00; disponible 4400.00; movimiento vinculado',
  $q$SELECT 'consumido ' || coalesce((SELECT monto_acumulado FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-2' AND id_canal = 'ATM')::text, '0')
       || '; contable ' || cu.saldo_contable || '; disponible ' || cu.saldo_disponible || '; movimiento '
       || CASE WHEN a.uuid_transaccion = a.uuid_autorizacion THEN 'vinculado' ELSE 'sin vincular' END
       FROM cuentas.cuenta_ahorro cu, tarjetas.autorizacion a
      WHERE cu.num_cuenta = 'CTA-PEN-2' AND a.uuid_autorizacion = '9b000000-0000-4000-8000-000000000001'$q$);

SELECT prueba.rechaza('M23', 'MySQL', 'Comprobación 23 (bug 5)', 'Una autorización aprobada después también respeta el tope',
  $q$SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 600, 'ATM');
     INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000002', 'RETIRO', 1000, 'INICIADA', 'ATM-AQP-001',
       'a0000000-0000-4000-8000-000000000002', 'CTA-PEN-2');
     UPDATE tarjetas.autorizacion SET estado_autorizacion = 'AUTORIZADA'
      WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000002'$q$,
  'ERR-TAR-007');

SELECT prueba.rechaza('M24a', 'MySQL', 'Comprobación 24 (bug 5)', 'Se respeta el tope diario del cajero (movimiento)',
  $q$SELECT prueba.movimiento('CTA-PEN-1', 'RETIRO', 1600, 'ATM')$q$,
  'RN-TOP-001');
SELECT prueba.rechaza('M24b', 'MySQL', 'Comprobación 24 (bug 5)', 'Se respeta el tope diario del cajero (autorización)',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 1600, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  'ERR-TAR-007');

SELECT prueba.rechaza('M24c', 'MySQL', 'Comprobación 24 (bug 5)', 'Dos autorizaciones aprobadas sin movimiento no superan juntas el tope',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 1000, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1');
     INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 1000, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  'ERR-TAR-007');

SELECT prueba.verifica('M25', 'MySQL', 'Comprobación 25 (bug 5)', 'v_tope_restante_hoy muestra el tope de cada tarjeta y cuenta',
  $q$SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 600, 'ATM')$q$,
  $q$SELECT (SELECT disponible_hoy FROM tarjetas.v_tope_restante_hoy WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001'
              AND num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM') = 1500
        AND (SELECT disponible_hoy FROM tarjetas.v_tope_restante_hoy WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002'
              AND num_cuenta = 'CTA-PEN-2' AND id_canal = 'ATM') = 900$q$,
  'T1 1500.00; T2 900.00',
  $q$SELECT string_agg(left(id_tarjeta::text, 1) || right(id_tarjeta::text, 1) || ' ' || disponible_hoy, '; ' ORDER BY id_tarjeta)
       FROM tarjetas.v_tope_restante_hoy WHERE id_canal = 'ATM' AND moneda = 'PEN' AND num_cuenta IN ('CTA-PEN-1', 'CTA-PEN-2')$q$);

SELECT prueba.verifica('M26', 'MySQL', 'Comprobación 26 (bug 6)', 'Al bloquear una tarjeta se guarda el motivo',
  $q$SELECT tarjetas.bloquear_tarjeta('a0000000-0000-4000-8000-000000000002', 'Robo reportado', 'CLIENTE')$q$,
  $q$SELECT motivo = 'Robo reportado' AND origen = 'CLIENTE' FROM tarjetas.historial_estado_tarjeta
      WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002' ORDER BY id_historial DESC LIMIT 1$q$,
  'Robo reportado / CLIENTE',
  $q$SELECT motivo || ' / ' || origen FROM tarjetas.historial_estado_tarjeta
      WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002' ORDER BY id_historial DESC LIMIT 1$q$);

SELECT prueba.na('M28', 'MySQL', 'Comprobación 28', 'El diagrama muestra todas las relaciones',
  'N/A — prevenido por diseño: los diagramas, las tablas del informe y el DDL se generan del mismo modelo (modelo/modelo_bna.py), de modo que no pueden divergir.');

-- =====================================================================
-- F: objetos portados e implementados
-- =====================================================================
SELECT prueba.rechaza('F01', 'Tarjetas', 'trg_tarjeta_bi (RF-TAR-005)', 'Solo se emite tarjeta a un cliente ACTIVO',
  $q$INSERT INTO tarjetas.tarjeta (pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('tok-x', '455788', '1111', '2026-01-01', '2030-01-01', 'ACTIVA', 'C004')$q$,
  'ERR-TAR-001');
SELECT prueba.verifica('F02', 'Tarjetas', 'trg_tarjeta_ai (RN-SEG-002)', 'La emisión queda en el historial y en la bandeja hacia Seguridad',
  $q$INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('a0000000-0000-4000-8000-0000000000f2', 'tok-f2', '455788', '2222', '2026-01-01', '2030-01-01', 'PENDIENTE_ACTIVACION', 'C002')$q$,
  $q$SELECT (SELECT count(*) FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f2') = 1
        AND (SELECT count(*) FROM tarjetas.evento_salida WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f2'
              AND tipo_evento = 'EMISION_TARJETA') = 1$q$,
  'historial 1; evento EMISION_TARJETA 1',
  $q$SELECT 'historial ' || (SELECT count(*) FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f2')
       || '; evento EMISION_TARJETA ' || (SELECT count(*) FROM tarjetas.evento_salida
          WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f2' AND tipo_evento = 'EMISION_TARJETA')$q$);
SELECT prueba.rechaza('F03', 'Tarjetas', 'trg_tarjeta_bu (RN-TAR-003)', 'Una tarjeta CANCELADA no cambia de estado',
  $q$INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, origen, id_tarjeta) VALUES ('CANCELADA', 'OPERADOR', 'a0000000-0000-4000-8000-000000000003');
     INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, origen, id_tarjeta) VALUES ('ACTIVA', 'OPERADOR', 'a0000000-0000-4000-8000-000000000003')$q$,
  'ERR-TAR-002');
SELECT prueba.rechaza('F04', 'Tarjetas', 'trg_tarjeta_bu (RN-TAR-003)', 'Una tarjeta VENCIDA solo se cancela',
  $q$INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, origen, id_tarjeta) VALUES ('VENCIDA', 'SISTEMA', 'a0000000-0000-4000-8000-000000000003');
     INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, origen, id_tarjeta) VALUES ('ACTIVA', 'OPERADOR', 'a0000000-0000-4000-8000-000000000003')$q$,
  'ERR-TAR-002');
SELECT prueba.rechaza('F05', 'Tarjetas', 'trg_tarjeta_bu (RN-TAR-004)', 'El cliente no puede desbloquear su tarjeta',
  $q$SELECT tarjetas.bloquear_tarjeta('a0000000-0000-4000-8000-000000000001', 'Sospecha de fraude', 'SEGURIDAD');
     INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, origen, id_tarjeta) VALUES ('ACTIVA', 'CLIENTE', 'a0000000-0000-4000-8000-000000000001')$q$,
  'ERR-TAR-004');
SELECT prueba.verifica('F06', 'Tarjetas', 'trg_tarjeta_au (RN-TAR-004)', 'El desbloqueo por un operador reinicia los intentos',
  $q$UPDATE tarjetas.credencial SET intentos_fallidos = 2 WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001' AND tipo_credencial = 'PIN_ATM';
     SELECT tarjetas.bloquear_tarjeta('a0000000-0000-4000-8000-000000000001', 'Sospecha de fraude', 'SEGURIDAD');
     INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
     VALUES ('ACTIVA', 'Desbloqueo en ventanilla con huella dactilar', 'OPERADOR', 'a0000000-0000-4000-8000-000000000001')$q$,
  $q$SELECT t.estado_tarjeta = 'ACTIVA' AND c.intentos_fallidos = 0 FROM tarjetas.tarjeta t
       JOIN tarjetas.credencial c ON c.id_tarjeta = t.id_tarjeta AND c.tipo_credencial = 'PIN_ATM'
      WHERE t.id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$,
  'ACTIVA; intentos 0',
  $q$SELECT t.estado_tarjeta || '; intentos ' || c.intentos_fallidos FROM tarjetas.tarjeta t
       JOIN tarjetas.credencial c ON c.id_tarjeta = t.id_tarjeta AND c.tipo_credencial = 'PIN_ATM'
      WHERE t.id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$);
SELECT prueba.rechaza('F07', 'Tarjetas', 'Historial (RN-SEG-002)', 'El estado de la tarjeta solo cambia registrando el historial',
  $q$UPDATE tarjetas.tarjeta SET estado_tarjeta = 'BLOQUEADA' WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$,
  'RN-SEG-002');
SELECT prueba.verifica('F08', 'Tarjetas', 'trg_intento_ai (RN-TAR-004)', 'El tercer intento fallido bloquea la tarjeta y avisa a Seguridad',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, id_terminal, resultado, id_tarjeta)
     SELECT 'PIN_ATM', 'ATM-AQP-001', 'FALLIDO', 'a0000000-0000-4000-8000-000000000002' FROM generate_series(1, 3)$q$,
  $q$SELECT (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002') = 'BLOQUEADA'
        AND (SELECT count(*) FROM tarjetas.evento_salida WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002'
              AND tipo_evento = 'BLOQUEO_POR_INTENTOS') = 1$q$,
  'BLOQUEADA; evento BLOQUEO_POR_INTENTOS 1',
  $q$SELECT (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002')
       || '; evento BLOQUEO_POR_INTENTOS ' || (SELECT count(*) FROM tarjetas.evento_salida
          WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002' AND tipo_evento = 'BLOQUEO_POR_INTENTOS')$q$);
SELECT prueba.verifica('F09', 'Tarjetas', 'trg_intento_ai (RN-TAR-004)', 'Un intento exitoso reinicia el contador',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, id_terminal, resultado, id_tarjeta)
     VALUES ('PIN_ATM', 'ATM-AQP-001', 'FALLIDO', 'a0000000-0000-4000-8000-000000000002'),
            ('PIN_ATM', 'ATM-AQP-001', 'FALLIDO', 'a0000000-0000-4000-8000-000000000002'),
            ('PIN_ATM', 'ATM-AQP-001', 'EXITOSO', 'a0000000-0000-4000-8000-000000000002')$q$,
  $q$SELECT intentos_fallidos = 0 FROM tarjetas.credencial WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002'$q$,
  'intentos 0',
  $q$SELECT 'intentos ' || intentos_fallidos FROM tarjetas.credencial WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000002'$q$);
SELECT prueba.verifica('F10', 'Tarjetas', 'trg_intento_ai (RN-TAR-004)', 'El tercer fallo de la matriz la bloquea junto con la tarjeta',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, coord_fila, coord_columna, id_canal, resultado, id_tarjeta)
     SELECT 'TOKEN_MATRIZ', 'B', 4, 'HB', 'FALLIDO', 'a0000000-0000-4000-8000-000000000001' FROM generate_series(1, 3)$q$,
  $q$SELECT (SELECT estado_matriz FROM tarjetas.matriz_token WHERE numero_serie = 'MTZ-0001') = 'BLOQUEADA'
        AND (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001') = 'BLOQUEADA'$q$,
  'matriz BLOQUEADA; tarjeta BLOQUEADA',
  $q$SELECT 'matriz ' || (SELECT estado_matriz FROM tarjetas.matriz_token WHERE numero_serie = 'MTZ-0001')
       || '; tarjeta ' || (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001')$q$);

SELECT prueba.rechaza('F11a', 'Tarjetas', 'trg_intento_bu (RN-SEG-002)', 'La bitácora de intentos no se modifica',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, id_terminal, resultado, id_tarjeta)
     VALUES ('PIN_ATM', 'ATM-AQP-001', 'EXITOSO', 'a0000000-0000-4000-8000-000000000002');
     UPDATE tarjetas.intento_autenticacion SET resultado = 'FALLIDO'$q$,
  'ERR-TAR-009');
SELECT prueba.rechaza('F11b', 'Tarjetas', 'trg_historial_bd (RN-SEG-002)', 'El historial de estados no se borra',
  $q$DELETE FROM tarjetas.historial_estado_tarjeta$q$,
  'ERR-TAR-009');
SELECT prueba.rechaza('F11c', 'Tarjetas', 'trg_historial (RN-SEG-002)', 'El historial no se vacía con TRUNCATE',
  $q$TRUNCATE tarjetas.historial_estado_tarjeta CASCADE$q$,
  'ERR-TAR-009');
SELECT prueba.rechaza('F11d', 'Cobranza', 'Bitácora de auditoría', 'La auditoría no se modifica',
  $q$UPDATE creditos.evento_auditoria SET resultado = 'ALTERADO'$q$,
  'BNA-SOLO-INSERCION');
SELECT prueba.rechaza('F11e', 'CORE', 'Asientos inmutables', 'Un asiento no se modifica',
  $q$UPDATE core.detalle_asiento SET importe = importe + 1$q$,
  'BNA-SOLO-INSERCION');
SELECT prueba.rechaza('F11f', 'Solicitud', 'Historial de la solicitud', 'El historial de la solicitud no se borra',
  $q$DELETE FROM creditos.historial_estado_solicitud$q$,
  'BNA-SOLO-INSERCION');

SELECT prueba.rechaza('F12a', 'Tarjetas', 'trg_autorizacion_bi (RN-TAR-003)', 'No se autoriza con una tarjeta bloqueada',
  $q$SELECT tarjetas.bloquear_tarjeta('a0000000-0000-4000-8000-000000000001', 'Pérdida', 'CLIENTE');
     INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  'ERR-TAR-003.*no es operativa');
SELECT prueba.rechaza('F12b', 'Tarjetas', 'trg_autorizacion_bi (RN-TAR-003)', 'No se autoriza con una tarjeta vencida',
  $q$INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('a0000000-0000-4000-8000-0000000000f3', 'tok-f3', '455788', '3333', '2020-01-01', '2021-01-31', 'ACTIVA', 'C002');
     INSERT INTO tarjetas.tarjeta_cuenta (id_tarjeta, num_cuenta) VALUES ('a0000000-0000-4000-8000-0000000000f3', 'CTA-PEN-2');
     INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-0000000000f3', 'CTA-PEN-2')$q$,
  'ERR-TAR-003.*venció');
SELECT prueba.rechaza('F12c', 'Tarjetas', 'trg_autorizacion_bi (RN-ATM-005)', 'El cajero no opera una cuenta mancomunada conjunta',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-CONJ')$q$,
  'ERR-TAR-008');
SELECT prueba.rechaza('F12d', 'Tarjetas', 'trg_autorizacion_bi (RN-BD-002)', 'La Billetera Digital no opera en dólares',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_canal, id_tarjeta, num_cuenta)
     VALUES ('FONDEO_BILLETERA', 100, 'AUTORIZADA', 'BD', 'a0000000-0000-4000-8000-000000000001', 'CTA-USD-1')$q$,
  'ERR-TAR-006');
SELECT prueba.rechaza('F12e', 'Tarjetas', 'trg_autorizacion_bi', 'No se autoriza en una terminal inactiva',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-OFF', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  'ERR-TAR-006.*terminal');
SELECT prueba.rechaza('F12f', 'Tarjetas', 'sp_validar_reglas_autorizacion', 'No se autoriza más que el saldo disponible',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_canal, id_tarjeta, num_cuenta)
     VALUES ('TRANSFERENCIA_ENVIADA', 8000, 'AUTORIZADA', 'HB', 'a0000000-0000-4000-8000-000000000002', 'CTA-PEN-2')$q$,
  'BNA-SALDO');
SELECT prueba.rechaza('F12g', 'Tarjetas', 'trg_autorizacion_bu (RN-ATM-007)', 'Una autorización rechazada no pasa a autorizada',
  $q$INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000003', 'RETIRO', 100, 'RECHAZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1');
     UPDATE tarjetas.autorizacion SET estado_autorizacion = 'AUTORIZADA' WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000003'$q$,
  'RN-ATM-007');
SELECT prueba.verifica('F12h', 'Tarjetas', 'trg_autorizacion_bi (C06)', 'Una autorización válida se registra',
  $q$INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, codigo_respuesta, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000004', 'RETIRO', 200, 'AUTORIZADA', '00', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  $q$SELECT EXISTS (SELECT 1 FROM tarjetas.autorizacion WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000004')$q$,
  'registrada',
  $q$SELECT CASE WHEN EXISTS (SELECT 1 FROM tarjetas.autorizacion WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000004')
             THEN 'registrada' ELSE 'no registrada' END$q$);
SELECT prueba.rechaza('F12i', 'Tarjetas', 'sp_validar_reglas_autorizacion', 'Dos autorizaciones aprobadas sin movimiento no superan juntas el saldo',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_canal, id_tarjeta, num_cuenta)
     VALUES ('TRANSFERENCIA_ENVIADA', 3000, 'AUTORIZADA', 'HB', 'a0000000-0000-4000-8000-000000000002', 'CTA-PEN-2');
     INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_canal, id_tarjeta, num_cuenta)
     VALUES ('TRANSFERENCIA_ENVIADA', 3000, 'AUTORIZADA', 'HB', 'a0000000-0000-4000-8000-000000000002', 'CTA-PEN-2')$q$,
  'BNA-SALDO');
SELECT prueba.verifica('F12j', 'Tarjetas', 'trg_autorizacion_bu (C07)', 'Extornar una autorización sin movimiento libera el tope y el saldo',
  $q$INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000005', 'RETIRO', 1000, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1');
     UPDATE tarjetas.autorizacion SET estado_autorizacion = 'EXTORNADA', codigo_respuesta = 'EXT'
      WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000005'$q$,
  $q$SELECT coalesce((SELECT monto_acumulado FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM'), 0) = 0
        AND (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1') = 15000$q$,
  'consumido 0.00; disponible 15000.00',
  $q$SELECT 'consumido ' || coalesce((SELECT monto_acumulado FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM')::text, '0.00')
       || '; disponible ' || (SELECT saldo_disponible FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-1')$q$);
SELECT prueba.rechaza('F12k', 'Tarjetas', 'Operación única (RN-BUS-002)', 'Una autorización solo se vincula al movimiento de su misma operación',
  $q$INSERT INTO tarjetas.autorizacion (uuid_autorizacion, tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('9b000000-0000-4000-8000-000000000006', 'RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1');
     UPDATE tarjetas.autorizacion SET uuid_transaccion = prueba.movimiento('CTA-PEN-1', 'RETIRO', 100, 'ATM')
      WHERE uuid_autorizacion = '9b000000-0000-4000-8000-000000000006'$q$,
  'ck_autorizacion_3');
SELECT prueba.rechaza('F13', 'Tarjetas', 'trg_autorizacion_bd (RN-ATM-003)', 'Una autorización no se borra; se extorna',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'AUTORIZADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1');
     DELETE FROM tarjetas.autorizacion$q$,
  'ERR-TAR-009');

SELECT prueba.verifica('F14a', 'Tarjetas', 'trg_cliente_ref_au (INT-T07)', 'Si Clientes bloquea al cliente, se bloquean sus tarjetas',
  $q$UPDATE clientes.cliente SET estado_cliente = 'BLOQUEADO' WHERE cod_cliente = 'C002'$q$,
  $q$SELECT t.estado_tarjeta = 'BLOQUEADA' AND h.origen = 'MODULO_CLIENTES' FROM tarjetas.tarjeta t
       JOIN tarjetas.historial_estado_tarjeta h ON h.id_tarjeta = t.id_tarjeta
      WHERE t.id_tarjeta = 'a0000000-0000-4000-8000-000000000002' ORDER BY h.id_historial DESC LIMIT 1$q$,
  'BLOQUEADA por MODULO_CLIENTES',
  $q$SELECT t.estado_tarjeta || ' por ' || h.origen FROM tarjetas.tarjeta t
       JOIN tarjetas.historial_estado_tarjeta h ON h.id_tarjeta = t.id_tarjeta
      WHERE t.id_tarjeta = 'a0000000-0000-4000-8000-000000000002' ORDER BY h.id_historial DESC LIMIT 1$q$);
SELECT prueba.verifica('F14b', 'Tarjetas', 'trg_cliente_ref_au (INT-T07)', 'Si Clientes da de baja al cliente, se cancelan sus tarjetas',
  $q$UPDATE clientes.cliente SET estado_cliente = 'BAJA' WHERE cod_cliente = 'C003'$q$,
  $q$SELECT estado_tarjeta = 'CANCELADA' FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000003'$q$,
  'CANCELADA',
  $q$SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000003'$q$);
SELECT prueba.verifica('F15', 'Tarjetas', 'ev_marcar_tarjetas_vencidas (RN-TAR-003)', 'marcar_tarjetas_vencidas() vence las tarjetas cuya fecha pasó',
  $q$INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento, estado_tarjeta, cod_cliente)
     VALUES ('a0000000-0000-4000-8000-0000000000f4', 'tok-f4', '455788', '4444', '2020-01-01', '2021-01-31', 'ACTIVA', 'C002');
     CREATE TEMP TABLE prueba_f15 AS SELECT tarjetas.marcar_tarjetas_vencidas() AS n$q$,
  $q$SELECT (SELECT n FROM prueba_f15) = 1
        AND (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f4') = 'VENCIDA'
        AND (SELECT origen FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f4'
              ORDER BY id_historial DESC LIMIT 1) = 'SISTEMA'$q$,
  '1 tarjeta; VENCIDA por SISTEMA',
  $q$SELECT (SELECT n FROM prueba_f15) || ' tarjeta; '
       || (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f4') || ' por '
       || (SELECT origen FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = 'a0000000-0000-4000-8000-0000000000f4'
           ORDER BY id_historial DESC LIMIT 1)$q$);

SELECT prueba.rechaza('F16a', 'Cobranza', 'Crédito (decisión I15)', 'El crédito nace de una orden CONFIRMADA',
  $q$INSERT INTO creditos.credito VALUES ('CR-T1', 'AL_DIA', 'e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002')$q$,
  'BNA-CREDITO.*CONFIRMADA');
SELECT prueba.rechaza('F16b', 'Cobranza', 'Crédito (decisión I15)', 'El calendario del crédito es de la solicitud de su orden',
  $q$INSERT INTO creditos.credito VALUES ('CR-T2', 'AL_DIA', 'e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002')$q$,
  'BNA-CREDITO.*no pertenece');
SELECT prueba.rechaza('F16c', 'Cobranza', 'Crédito (Solicitud)', 'El crédito usa el calendario OFICIAL',
  $q$INSERT INTO creditos.credito VALUES ('CR-T3', 'AL_DIA', 'e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000000')$q$,
  'BNA-CREDITO.*OFICIAL');
SELECT prueba.rechaza('F17a', 'Cobranza', 'Aplicación de pagos', 'Un pago no se aplica a cuotas de otro crédito',
  $q$INSERT INTO creditos.aplicacion_pago VALUES ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 1, 100)$q$,
  'BNA-PAGO.*no pertenece');
SELECT prueba.rechaza('F17b', 'Cobranza', 'Aplicación de pagos', 'Solo se aplica un pago CONFIRMADO',
  $q$INSERT INTO creditos.pago (id_pago, monto_pago, referencia_transaccion, estado_confirmacion, cod_credito, id_canal)
     VALUES ('f0000000-0000-4000-8000-0000000000f1', 100, 'OP-T1', 'PENDIENTE', 'CR-0001', 'VEN');
     INSERT INTO creditos.aplicacion_pago VALUES ('f0000000-0000-4000-8000-0000000000f1', 'd0000000-0000-4000-8000-000000000001', 1, 100)$q$,
  'BNA-PAGO.*CONFIRMADO');
SELECT prueba.verifica('F18', 'Cobranza', 'sp_aplicar_pago (Cobranza)', 'aplicar_pago() reparte el pago de la cuota más antigua a la siguiente',
  $q$SELECT creditos.aplicar_pago('f0000000-0000-4000-8000-000000000001');
     SELECT creditos.aplicar_pago('f0000000-0000-4000-8000-000000000002')$q$,
  $q$SELECT string_agg(estado_cuota || ' ' || saldo_pendiente, '; ' ORDER BY numero_cuota)
          = 'PAGADA 0.00; PAGADA 0.00; PARCIAL 3200.00'
       FROM creditos.cuota WHERE id_calendario = 'd0000000-0000-4000-8000-000000000001'$q$,
  'PAGADA 0.00; PAGADA 0.00; PARCIAL 3200.00',
  $q$SELECT string_agg(estado_cuota || ' ' || saldo_pendiente, '; ' ORDER BY numero_cuota)
       FROM creditos.cuota WHERE id_calendario = 'd0000000-0000-4000-8000-000000000001'$q$);
SELECT prueba.verifica('F19', 'Cobranza', 'Estado del crédito (Cobranza)', 'Pagadas todas las cuotas, el crédito queda CANCELADO',
  $q$INSERT INTO creditos.pago (id_pago, monto_pago, referencia_transaccion, estado_confirmacion, cod_credito, id_canal)
     VALUES ('f0000000-0000-4000-8000-0000000000f2', 10300, 'OP-T2', 'CONFIRMADO', 'CR-0001', 'VEN');
     SELECT creditos.aplicar_pago('f0000000-0000-4000-8000-0000000000f2')$q$,
  $q$SELECT estado_credito = 'CANCELADO' FROM creditos.credito WHERE cod_credito = 'CR-0001'$q$,
  'CANCELADO',
  $q$SELECT estado_credito FROM creditos.credito WHERE cod_credito = 'CR-0001'$q$);
SELECT prueba.rechaza('F20', 'Cobranza', 'Aplicación de pagos', 'Una aplicación de pago no se modifica',
  $q$SELECT creditos.aplicar_pago('f0000000-0000-4000-8000-000000000001');
     UPDATE creditos.aplicacion_pago SET monto_aplicado = 1$q$,
  'BNA-SOLO-INSERCION|BNA-PAGO');

SELECT prueba.rechaza('F21a', 'Cuentas', 'Estado de la cuenta (Cuentas)', 'Una cuenta BLOQUEADA no admite débitos',
  $q$UPDATE cuentas.cuenta_ahorro SET estado_cuenta = 'BLOQUEADA' WHERE num_cuenta = 'CTA-PEN-2';
     SELECT prueba.movimiento('CTA-PEN-2', 'RETIRO', 100, 'VEN')$q$,
  'BNA-ESTADO-CUENTA');
SELECT prueba.verifica('F21b', 'Cuentas', 'Estado de la cuenta (Cuentas)', 'Una cuenta BLOQUEADA_PREVENTIVA admite créditos',
  $q$UPDATE cuentas.cuenta_ahorro SET estado_cuenta = 'BLOQUEADA_PREVENTIVA' WHERE num_cuenta = 'CTA-PEN-2';
     SELECT prueba.movimiento('CTA-PEN-2', 'DEPOSITO', 100, 'VEN')$q$,
  $q$SELECT saldo_contable = 5100 FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'$q$,
  'saldo 5100.00',
  $q$SELECT 'saldo ' || saldo_contable FROM cuentas.cuenta_ahorro WHERE num_cuenta = 'CTA-PEN-2'$q$);
SELECT prueba.verifica('F22', 'Cuentas', 'Extorno (Tarjetas, C07)', 'El extorno devuelve el monto al tope del día',
  $q$DO $d$
     DECLARE v UUID;
     BEGIN
         v := prueba.movimiento('CTA-PEN-1', 'RETIRO', 600, 'ATM');
         UPDATE cuentas.movimiento SET estado_transaccion = 'EXTORNADO' WHERE uuid_transaccion = v;
     END $d$$q$,
  $q$SELECT monto_acumulado = 0 FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM'$q$,
  'consumido hoy 0.00',
  $q$SELECT 'consumido hoy ' || monto_acumulado FROM core.consumo_diario WHERE num_cuenta = 'CTA-PEN-1' AND id_canal = 'ATM'$q$);
SELECT prueba.rechaza('F23', 'Cuentas', 'Movimiento inmutable', 'El importe de un movimiento no se modifica',
  $q$UPDATE cuentas.movimiento SET monto = 1 WHERE num_cuenta = 'CTA-PEN-2'$q$,
  'BNA-MOVIMIENTO');
SELECT prueba.rechaza('F24', 'CORE', 'Partida doble', 'Un asiento sin líneas se rechaza al confirmar',
  $q$INSERT INTO core.asiento_contable (id_asiento, numero_asiento, fecha_contable, fecha_valor, glosa, moneda, correlation_id)
     VALUES ('9a000000-0000-4000-8000-000000000003', 'T-VACIO', current_date, current_date, 'Sin líneas', 'PEN', gen_random_uuid())$q$,
  'BNA-PARTIDA-DOBLE');

SELECT prueba.verifica('F25', 'Tarjetas', 'v_tarjeta_resumen (PCI-DSS)', 'La vista enmascara el número y muestra el vencimiento MM/AA',
  '',
  $q$SELECT numero_enmascarado = '4557 88** **** 1234' AND vencimiento_mm_aa = '01/31' AND operativa
       FROM tarjetas.v_tarjeta_resumen WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$,
  '4557 88** **** 1234; 01/31; operativa',
  $q$SELECT numero_enmascarado || '; ' || vencimiento_mm_aa || '; ' || CASE WHEN operativa THEN 'operativa' ELSE 'no operativa' END
       FROM tarjetas.v_tarjeta_resumen WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$);
SELECT prueba.verifica('F26', 'Tarjetas', 'v_consumo_diario (RN-TOP-001)', 'La vista suma lo autorizado por tarjeta, canal, moneda y día',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, codigo_respuesta, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 200, 'AUTORIZADA', '00', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1'),
            ('RETIRO', 300, 'AUTORIZADA', '00', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'CTA-PEN-1')$q$,
  $q$SELECT monto_consumido = 500 AND operaciones = 2 FROM tarjetas.v_consumo_diario
      WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001' AND id_canal = 'ATM' AND moneda = 'PEN'
        AND fecha = core.fn_fecha_negocio(now())$q$,
  'ATM PEN hoy: 500.00 en 2 operaciones',
  $q$SELECT id_canal || ' ' || moneda || ' hoy: ' || monto_consumido || ' en ' || operaciones || ' operaciones'
       FROM tarjetas.v_consumo_diario WHERE id_tarjeta = 'a0000000-0000-4000-8000-000000000001'$q$);
SELECT prueba.verifica('F27', 'Tarjetas', 'v_credenciales_en_riesgo (RN-TAR-004)', 'La vista muestra los intentos acumulados y restantes',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, id_terminal, resultado, id_tarjeta)
     VALUES ('PIN_ATM', 'ATM-AQP-001', 'FALLIDO', 'a0000000-0000-4000-8000-000000000001')$q$,
  $q$SELECT count(*) = 1 AND min(intentos_fallidos) = 1 AND min(intentos_restantes) = 2 FROM tarjetas.v_credenciales_en_riesgo$q$,
  'PIN_ATM: 1 fallido, 2 restantes',
  $q$SELECT string_agg(credencial || ': ' || intentos_fallidos || ' fallido, ' || intentos_restantes || ' restantes', '; ')
       FROM tarjetas.v_credenciales_en_riesgo$q$);
SELECT prueba.verifica('F28', 'Desembolso', 'des_v_ordenes_inciertas', 'La vista lista las órdenes con resultado incierto en el CORE',
  '',
  $q$SELECT array_agg(codigo_orden) = ARRAY['DES-2026-000003']::varchar[] FROM creditos.v_ordenes_inciertas$q$,
  'DES-2026-000003',
  $q$SELECT string_agg(codigo_orden || ' (' || estado_orden || ')', ', ') FROM creditos.v_ordenes_inciertas$q$);
SELECT prueba.verifica('F29', 'Desembolso', 'des_v_entregas_pendientes', 'La vista lista las entregas que superan dos reintentos',
  '',
  $q$SELECT count(*) = 1 AND min(intentos) = 3 FROM creditos.v_entregas_pendientes$q$,
  '1 entrega, 3 intentos',
  $q$SELECT count(*) || ' entrega, ' || min(intentos) || ' intentos' FROM creditos.v_entregas_pendientes$q$);
SELECT prueba.verifica('F30', 'Desembolso', 'des_v_conciliacion_diaria', 'La vista cuadra lo ordenado con lo abonado por fecha y moneda',
  '',
  $q$SELECT importe_ordenes = 10000 AND importe_abonado = 10000 AND ordenes_sin_abono = 0
       FROM creditos.v_conciliacion_diaria WHERE moneda = 'PEN'$q$,
  'PEN: ordenado 10000.00, abonado 10000.00, sin abono 0',
  $q$SELECT moneda || ': ordenado ' || importe_ordenes || ', abonado ' || importe_abonado || ', sin abono ' || ordenes_sin_abono
       FROM creditos.v_conciliacion_diaria$q$);
SELECT prueba.verifica('F31', 'Índices', 'Consultas de Tarjetas y Desembolso', 'Existen los índices de consulta y ninguno repite a otro de clave foránea',
  '',
  $q$SELECT count(*) FILTER (WHERE indexname IN ('ix_movimiento_cuenta_fecha', 'ix_autorizacion_tarjeta_fecha',
             'ix_intento_tarjeta_fecha', 'ix_historial_tarjeta_fecha', 'ix_orden_estado_fecha', 'ix_evento_salida_pendiente',
             'ix_evento_entrega_pendiente', 'ix_evento_auditoria_correlacion')) = 8
        AND count(*) FILTER (WHERE indexname IN ('ix_movimiento_num_cuenta', 'ix_autorizacion_id_tarjeta',
             'ix_intento_autenticacion_id_tarjeta', 'ix_historial_estado_tarjeta_id_tarjeta', 'ix_orden_desembolso_estado_orden')) = 0
       FROM pg_indexes$q$,
  '8 índices de consulta; 0 redundantes',
  $q$SELECT count(*) FILTER (WHERE indexname IN ('ix_movimiento_cuenta_fecha', 'ix_autorizacion_tarjeta_fecha',
             'ix_intento_tarjeta_fecha', 'ix_historial_tarjeta_fecha', 'ix_orden_estado_fecha', 'ix_evento_salida_pendiente',
             'ix_evento_entrega_pendiente', 'ix_evento_auditoria_correlacion')) || ' índices de consulta; '
        || count(*) FILTER (WHERE indexname IN ('ix_movimiento_num_cuenta', 'ix_autorizacion_id_tarjeta',
             'ix_intento_autenticacion_id_tarjeta', 'ix_historial_estado_tarjeta_id_tarjeta', 'ix_orden_desembolso_estado_orden'))
        || ' redundantes'
       FROM pg_indexes$q$);

-- =====================================================================
-- R: pruebas negativas originales del informe
-- =====================================================================
SELECT prueba.rechaza('R1', 'Regresión', 'Pruebas negativas del DDL', 'Evento de auditoría sobre un registro no registrado como auditable',
  $q$INSERT INTO creditos.evento_auditoria (modulo_emisor, id_entidad, accion, actor, correlation_id)
     VALUES (14, 'CR-0001', 'PAGO', 'cobranza', gen_random_uuid())$q$,
  'fk_evento_auditoria_2');
SELECT prueba.rechaza('R2', 'Regresión', 'Pruebas negativas del DDL', 'Intento con coordenada para una credencial que no es la matriz',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, coord_fila, coord_columna, id_canal, resultado, id_tarjeta)
     VALUES ('PIN_ATM', 'A', 1, 'ATM', 'FALLIDO', 'a0000000-0000-4000-8000-000000000001')$q$,
  'ck_intento_autenticacion_4');
SELECT prueba.rechaza('R3', 'Regresión', 'Pruebas negativas del DDL', 'Intento con terminal y canal a la vez',
  $q$INSERT INTO tarjetas.intento_autenticacion (tipo_credencial, id_terminal, id_canal, resultado, id_tarjeta)
     VALUES ('PIN_ATM', 'ATM-AQP-001', 'ATM', 'FALLIDO', 'a0000000-0000-4000-8000-000000000001')$q$,
  'ck_intento_autenticacion_5');
SELECT prueba.rechaza('R4', 'Regresión', 'Pruebas negativas del DDL', 'Credencial de tipo TOKEN_MATRIZ',
  $q$INSERT INTO tarjetas.credencial (id_tarjeta, tipo_credencial, hash_credencial, sal)
     VALUES ('a0000000-0000-4000-8000-000000000001', 'TOKEN_MATRIZ', repeat('a', 64), repeat('b', 32))$q$,
  'ck_credencial_1');
SELECT prueba.rechaza('R5', 'Regresión', 'Pruebas negativas del DDL', 'Autorización sobre una cuenta inexistente',
  $q$INSERT INTO tarjetas.autorizacion (tipo_operacion, monto, estado_autorizacion, id_terminal, id_tarjeta, num_cuenta)
     VALUES ('RETIRO', 100, 'INICIADA', 'ATM-AQP-001', 'a0000000-0000-4000-8000-000000000001', 'NO-EXISTE')$q$,
  'violates foreign key constraint');
SELECT prueba.rechaza('R6', 'Regresión', 'Pruebas negativas del DDL', 'Segundo cliente con el mismo DNI',
  $q$INSERT INTO clientes.verificacion_captacion (id_verificacion_captacion, estado_habilitante) VALUES ('VC-9', 'HABILITADO');
     INSERT INTO clientes.cliente (cod_cliente, tipo_documento, numero_documento, nombres, apellido_paterno, correo, celular,
       estado_cliente, id_verificacion_captacion, version_contrato)
     VALUES ('C009', 'DNI', '70000001', 'Otro', 'Cliente', 'otro@example.com', '959000009', 'ACTIVO', 'VC-9', 'v1')$q$,
  'uk_cliente_1');
SELECT prueba.rechaza('R7', 'Regresión', 'Pruebas negativas del DDL', 'Segunda orden CONFIRMADA para la misma aprobación',
  $q$INSERT INTO creditos.orden_desembolso (codigo_orden, importe, estado_orden, idempotency_key, request_hash, usuario_preparacion,
       correlation_id, id_evaluacion, num_cuenta, id_canal)
     VALUES ('DES-T-5', 1000, 'CONFIRMADA', gen_random_uuid(), repeat('x', 64), 'u', gen_random_uuid(),
       'c0000000-0000-4000-8000-000000000001', 'CTA-PEN-1', 'VEN')$q$,
  'BNA-ORDEN-UNICA|ux_orden_confirmada');
SELECT prueba.rechaza('R8', 'Regresión', 'Pruebas negativas del DDL', 'Borrar una moneda en uso',
  $q$DELETE FROM core.moneda WHERE cod_moneda = 'PEN'$q$,
  'violates foreign key constraint');
