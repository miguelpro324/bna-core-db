-- Bugs 5 y 6: topes diarios y sp_bloquear_tarjeta.
-- Requiere 02_integridad.sql (usa la tarjeta k1).

DELETE FROM cta_control_tope_diario;
INSERT INTO tar_tarjeta_cuenta (id_tarjeta, num_cuenta) VALUES ('k1', '0011000001');

-- Bug 5a: un solo retiro de 600 en ATM, registrado por Tarjetas y por Cuentas, se cuenta dos veces.
INSERT INTO tar_autorizacion (uuid_transaccion, id_tarjeta, num_cuenta, id_canal, tipo_operacion, monto, estado)
VALUES ('au1', 'k1', '0011000001', 'ATM', 'RETIRO', 600, 'APROBADA');
INSERT INTO cta_transaccion (id_transaccion, uuid_transaccion, num_cuenta, tipo_operacion, tipo_movimiento,
                             monto, id_canal, saldo_posterior, fecha_valor)
VALUES ('t3', 'au1', '0011000001', 'RETIRO', 'D', 600, 'ATM', 0, CURRENT_DATE());
SELECT 'B5a un retiro de 600 (esperado 600)' AS prueba, monto_acumulado FROM cta_control_tope_diario;

SET @acum = (SELECT COALESCE(SUM(monto_acumulado), 0) FROM cta_control_tope_diario);
CALL repro.reg('5', 'Un retiro se cuenta una sola vez en el tope diario',
  'Se hizo UN retiro de S/600 en cajero: Tarjetas registra la autorizacion y Cuentas registra el debito (mismo uuid).',
  'Acumulado del dia = 600.00', CONCAT('Acumulado del dia = ', @acum), @acum = 600,
  'Dos triggers suman la misma operacion; el cliente llega a su tope con la mitad de lo que retiro.');

-- Bug 5b: una autorizacion PENDIENTE que luego pasa a APROBADA nunca se acumula,
-- y nada rechaza 5000 contra un tope ATM de 700.
INSERT INTO tar_autorizacion (uuid_transaccion, id_tarjeta, num_cuenta, id_canal, tipo_operacion, monto, estado)
VALUES ('au2', 'k1', '0011000001', 'ATM', 'RETIRO', 5000, 'PENDIENTE');
UPDATE tar_autorizacion SET estado = 'APROBADA' WHERE uuid_transaccion = 'au2';
SELECT 'B5b + 5000 aprobados despues (tope ATM 700)' AS prueba, monto_acumulado FROM cta_control_tope_diario;
SELECT 'B5b autorizaciones aprobadas hoy' AS prueba, SUM(monto) AS total
FROM tar_autorizacion WHERE estado = 'APROBADA' AND DATE(fecha_hora) = CURRENT_DATE();

SET @acum2 = (SELECT COALESCE(SUM(monto_acumulado), 0) FROM cta_control_tope_diario);
CALL repro.reg('5', 'Una autorizacion aprobada despues tambien cuenta para el tope',
  'Se registro un retiro de S/5000 como PENDIENTE y luego se cambio a APROBADA.',
  CONCAT('El acumulado sube de ', @acum, ' a ', CAST(@acum + 5000 AS DECIMAL(15,2))), CONCAT('El acumulado sigue en ', @acum2),
  @acum2 = @acum + 5000,
  'El trigger solo mira el INSERT; lo que se aprueba con UPDATE nunca se suma.');

SET @rechazada = NOT EXISTS (SELECT 1 FROM tar_autorizacion WHERE uuid_transaccion = 'au2' AND estado = 'APROBADA');
CALL repro.reg('5', 'Se respeta el tope diario del cajero',
  'Se aprobo un retiro de S/5000 en cajero; el tope ATM del seed es S/700 por dia.',
  'Rechazo: supera el tope diario del canal', IF(@rechazada, 'MySQL lo rechazo', 'MySQL lo acepto sin error'), @rechazada,
  'Los triggers solo acumulan; nada compara el acumulado con limite_canal.');

-- Bug 5c: la vista suma todas las cuentas del canal, pero el tope es por cuenta.
SELECT 'B5c v_tope_restante_hoy' AS prueba, v.* FROM v_tope_restante_hoy v;

CALL repro.reg('5', 'v_tope_restante_hoy muestra el tope de cada cuenta',
  'Se consulto la vista despues de los retiros anteriores.',
  'Una fila por cuenta y canal, con su tope restante',
  (SELECT CONCAT('Una sola fila para todo el canal ATM: consumido ', consumido_hoy, ' entre todas las cuentas')
     FROM v_tope_restante_hoy WHERE id_canal = 'ATM'),
  0,
  'Basta con que unos pocos clientes retiren para que la vista muestre el tope agotado para todos.');

-- Bug 6: sp_bloquear_tarjeta ignora motivo y origen.
CALL sp_bloquear_tarjeta('k1', 'Robo reportado', 'CLIENTE');
SELECT 'B6 historial (esperado: Robo reportado / CLIENTE)' AS prueba, estado_anterior, estado_nuevo, motivo, origen
FROM tar_historial_estado WHERE id_tarjeta = 'k1' ORDER BY fecha_hora;

SELECT motivo, origen INTO @motivo, @origen
FROM tar_historial_estado WHERE id_tarjeta = 'k1' AND estado_nuevo = 'BLOQUEADA'
ORDER BY fecha_hora DESC LIMIT 1;
CALL repro.reg('6', 'Al bloquear una tarjeta se guarda el motivo',
  'Se llamo sp_bloquear_tarjeta(k1, ''Robo reportado'', ''CLIENTE'').',
  'Historial: motivo = Robo reportado, origen = CLIENTE',
  CONCAT('Historial: motivo = ', @motivo, ', origen = ', @origen),
  @motivo = 'Robo reportado' AND @origen = 'CLIENTE',
  'El procedimiento recibe motivo y origen pero no los usa; el historial pierde por que se bloqueo.');
