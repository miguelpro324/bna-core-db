-- Bugs 2, 3 y 4: estado que deja 13_consultas.sql y fn_uuid_v7().
-- Ejecutar justo despues de cargar 99_bna_unificado.sql.

-- Bug 3: el deposito de 500 registra saldo_posterior = 500, pero la cuenta sigue en 0.
SELECT 'B3 saldo de la cuenta tras deposito de 500' AS prueba, num_cuenta, saldo_contable, saldo_disponible
FROM cuenta_ahorro;
SELECT 'B3 transaccion registrada' AS prueba, saldo_posterior, monto FROM cta_transaccion;

CALL repro.reg('3', 'Un deposito actualiza el saldo de la cuenta',
  'El propio script (13_consultas.sql) abre la cuenta 0011000001 con saldo 0 y le deposita S/500.',
  'saldo_contable = 500.00',
  (SELECT CONCAT('saldo_contable = ', saldo_contable) FROM cuenta_ahorro WHERE num_cuenta = '0011000001'),
  (SELECT saldo_contable = 500 FROM cuenta_ahorro WHERE num_cuenta = '0011000001'),
  'El movimiento queda registrado pero el saldo nunca cambia: ningun trigger ni procedimiento lo actualiza.');

-- Bug 4: se pago capital 300, pero el saldo de capital del credito no baja.
SELECT 'B4 cuota tras sp_aplicar_pago' AS prueba, numero_cuota, cuota_total, monto_pagado, estado_cuota FROM cob_cuota;
SELECT 'B4 saldo_capital del credito (esperado 9700)' AS prueba, saldo_capital FROM cob_credito;

CALL repro.reg('4', 'Pagar capital reduce la deuda del credito',
  'El script crea un credito de S/10000 y paga la cuota 1 con sp_aplicar_pago (S/300 de capital).',
  'saldo_capital = 9700.00',
  (SELECT CONCAT('saldo_capital = ', saldo_capital) FROM cob_credito WHERE id_credito = '0198b000-0000-700b-8000-000000000001'),
  (SELECT saldo_capital = 9700 FROM cob_credito WHERE id_credito = '0198b000-0000-700b-8000-000000000001'),
  'La cuota figura PAGADA, pero el cliente sigue debiendo los S/10000 completos.');

-- Bug 2: fn_uuid_v7 suma dos veces los milisegundos.
-- ms_en_uuid deberia ser igual a ms_real; la diferencia es igual a ms_parte.
SET @ts = CURRENT_TIMESTAMP(3);
SET @uuid = fn_uuid_v7();
SET @ms_uuid = CAST(CONV(REPLACE(LEFT(@uuid, 13), '-', ''), 16, 10) AS UNSIGNED);
SET @ms_real = FLOOR(UNIX_TIMESTAMP(@ts) * 1000);
SELECT 'B2 timestamp dentro del UUID v7' AS prueba, @uuid AS uuid, @ms_uuid AS ms_en_uuid, @ms_real AS ms_real,
       MICROSECOND(@ts) DIV 1000 AS ms_parte;

CALL repro.reg('2', 'fn_uuid_v7() guarda la hora correcta',
  'Se genero un UUID v7 con fn_uuid_v7() y se leyo la hora que lleva dentro (sus primeros 48 bits).',
  'La hora del UUID coincide con la hora actual (diferencia 0 ms, a lo sumo 1-2 ms)',
  CONCAT('La hora del UUID esta ', @ms_uuid - @ms_real, ' ms en el futuro'),
  ABS(@ms_uuid - @ms_real) <= 2,
  'La funcion suma dos veces los milisegundos; el error va de 0 a 999 ms segun el instante.');

-- Bug 2 (orden): misma formula que usa fn_uuid_v7, aplicada a dos instantes consecutivos.
SET @t1 = TIMESTAMP('2026-10-15 12:00:00.900');
SET @t2 = TIMESTAMP('2026-10-15 12:00:01.100');
SET @v1 = FLOOR(UNIX_TIMESTAMP(@t1) * 1000) + FLOOR(MICROSECOND(@t1) / 1000);
SET @v2 = FLOOR(UNIX_TIMESTAMP(@t2) * 1000) + FLOOR(MICROSECOND(@t2) / 1000);
SELECT 'B2 orden roto entre segundos' AS prueba, @v1 AS ms_12_00_00_900, @v2 AS ms_12_00_01_100, @v1 > @v2 AS primero_ordena_despues;

CALL repro.reg('2', 'Los UUID v7 se ordenan por fecha de creacion',
  'Con la formula de fn_uuid_v7() se calculo la hora para 12:00:00.900 y para 12:00:01.100 (200 ms despues).',
  'El UUID de 12:00:00.900 se ordena antes que el de 12:00:01.100',
  IF(@v1 > @v2, 'El UUID de 12:00:00.900 se ordena DESPUES que el de 12:00:01.100',
                'El UUID de 12:00:00.900 se ordena antes'),
  @v1 < @v2,
  'La documentacion promete IDs "ordenables por tiempo"; cerca del cambio de segundo eso no se cumple.');
