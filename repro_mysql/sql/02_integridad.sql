-- Bug 7 y auditoria: datos inconsistentes que el esquema acepta.
-- Cada INSERT deberia fallar en un modelo normalizado; aqui todos pasan.
-- Ejecutar con --force para que un error no detenga el resto.

SET @acepto  = 'MySQL lo acepto sin error';
SET @rechazo = 'MySQL lo rechazo';

-- Segundo cliente para las pruebas (el id 'c2' tambien muestra que CHAR(36) no valida UUID).
INSERT INTO cliente (id_cliente, cod_tipo_documento, numero_documento, nombres, apellido_paterno, numero_celular)
VALUES ('c2', 'DNI', '70000002', 'Ana', 'Diaz', '959000002');
SELECT 'ID c2 aceptado como UUID' AS prueba, COUNT(*) AS filas FROM cliente WHERE id_cliente = 'c2';
SET @ok = NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = 'c2');
CALL repro.reg('7', 'Los IDs tienen que ser UUID validos',
  'Se inserto un cliente con id_cliente = ''c2'' (no es un UUID).',
  'Rechazo: un UUID tiene 36 caracteres con formato 8-4-4-4-12', IF(@ok, @rechazo, @acepto), @ok,
  'CHAR(36) admite cualquier texto; en PostgreSQL el tipo UUID lo impide.');

-- Orden con cliente distinto al de la solicitud, en USD sobre cuenta PEN, por 99999.
INSERT INTO des_orden (id_orden, id_solicitud, id_cliente, num_cuenta, monto, moneda, tipo_desembolso)
VALUES ('o2', '0198b000-0000-700a-8000-000000000001', 'c2', '0011000001', 99999, 'USD', 'EFECTIVO');
SELECT 'Orden: cliente != solicitud, USD en cuenta PEN, monto > solicitado' AS prueba, COUNT(*) AS filas
FROM des_orden WHERE id_orden = 'o2';
SET @ok = NOT EXISTS (SELECT 1 FROM des_orden WHERE id_orden = 'o2');
CALL repro.reg('7', 'Una orden de desembolso respeta su solicitud',
  'Se creo una orden para la solicitud de Juan Perez (S/10000) a nombre de otra clienta, en dolares y por 99999.',
  'Rechazo: el cliente, la moneda y el monto salen de la solicitud aprobada', IF(@ok, @rechazo, @acepto), @ok,
  'des_orden repite id_cliente y moneda en vez de tomarlos de la solicitud, asi que pueden contradecirla.');

-- RETIRO registrado como credito, en USD, con saldo posterior negativo.
INSERT INTO cta_transaccion (id_transaccion, uuid_transaccion, num_cuenta, tipo_operacion, tipo_movimiento,
                             monto, moneda, id_canal, saldo_posterior, fecha_valor)
VALUES ('t2', 'u2', '0011000001', 'RETIRO', 'C', 100, 'USD', 'ATM', -12345, CURRENT_DATE());
SELECT 'RETIRO como C, USD, saldo_posterior negativo' AS prueba, COUNT(*) AS filas
FROM cta_transaccion WHERE id_transaccion = 't2';
SET @ok = NOT EXISTS (SELECT 1 FROM cta_transaccion WHERE id_transaccion = 't2');
CALL repro.reg('7', 'Un movimiento de cuenta es coherente',
  'En la cuenta en soles se registro un RETIRO marcado como abono (C), en dolares, con saldo posterior -12345.',
  'Rechazo: un retiro es siempre debito, la moneda es la de la cuenta y el saldo no puede ser negativo',
  IF(@ok, @rechazo, @acepto), @ok,
  'tipo_movimiento y moneda se guardan aparte aunque dependen del tipo de operacion y de la cuenta.');

-- saldo_disponible mayor que saldo_contable (el informe lo impide con CHECK).
UPDATE cuenta_ahorro SET saldo_disponible = 1000, saldo_contable = 0 WHERE num_cuenta = '0011000001';
SELECT 'saldo_disponible > saldo_contable' AS prueba, saldo_disponible, saldo_contable
FROM cuenta_ahorro WHERE num_cuenta = '0011000001';
SET @ok = NOT EXISTS (SELECT 1 FROM cuenta_ahorro WHERE num_cuenta = '0011000001' AND saldo_disponible > saldo_contable);
CALL repro.reg('7', 'El saldo disponible no supera al contable',
  'Se puso saldo_disponible = 1000 y saldo_contable = 0 en la misma cuenta.',
  'Rechazo: no se puede disponer de mas dinero del que hay (CHECK del informe)', IF(@ok, @rechazo, @acepto), @ok,
  'Una cuenta podria permitir retirar dinero que no existe.');

-- cuota_total distinta de capital + interes.
INSERT INTO cob_cuota (id_cuota_credito, id_credito, numero_cuota, fecha_vencimiento, capital, interes,
                       cuota_total, saldo_capital)
VALUES ('q2', '0198b000-0000-700b-8000-000000000001', 2, CURRENT_DATE(), 1, 1, 9999, 0);
SELECT 'cuota_total != capital + interes' AS prueba, capital, interes, cuota_total
FROM cob_cuota WHERE id_cuota_credito = 'q2';
SET @ok = NOT EXISTS (SELECT 1 FROM cob_cuota WHERE id_cuota_credito = 'q2');
CALL repro.reg('7', 'El total de una cuota es la suma de sus partes',
  'Se creo una cuota con capital 1 e interes 1, pero con cuota_total 9999.',
  'Rechazo, o mejor aun: que cuota_total no se guarde y se calcule (1 + 1 = 2)', IF(@ok, @rechazo, @acepto), @ok,
  'Al guardar un dato derivado, el total cobrado puede no coincidir con lo que se debe.');

-- Bug 4: un pago de 1 con 9999 aplicados a mora deja la cuota PAGADA.
INSERT INTO cob_pago (id_pago, id_credito, id_canal_pago, monto, num_operacion)
VALUES ('p2', '0198b000-0000-700b-8000-000000000001', '0198b000-0000-7008-8000-000000000001', 1, 'OP-2');
CALL sp_aplicar_pago('p2', 'q2', 0, 0, 0, 9999);
SELECT 'B4 pago de 1, 9999 aplicados a mora' AS prueba, monto_pagado, estado_cuota
FROM cob_cuota WHERE id_cuota_credito = 'q2';
CALL repro.reg('4', 'sp_aplicar_pago no aplica mas de lo pagado ni cuenta la mora como cuota',
  'Se registro un pago de S/1 y con sp_aplicar_pago se aplicaron 9999 a la mora de la cuota 2.',
  'Error: no se pueden aplicar 9999 de un pago de 1; y pagar mora no cancela capital ni interes',
  (SELECT CONCAT('Se aplico sin error; la cuota quedo ', estado_cuota, ' con monto_pagado = ', monto_pagado)
     FROM cob_cuota WHERE id_cuota_credito = 'q2'),
  (SELECT estado_cuota <> 'PAGADA' FROM cob_cuota WHERE id_cuota_credito = 'q2'),
  'Una cuota puede darse por pagada sin que se haya pagado su capital ni su interes.');

-- Dos creditos para la misma solicitud, el segundo con otro cliente.
INSERT INTO cob_credito (id_credito, id_solicitud, id_cliente, num_cuenta_desembolso, monto_aprobado,
                         tasa_tea, plazo_meses, fecha_desembolso)
VALUES ('cr2', '0198b000-0000-700a-8000-000000000001', 'c2', '0011000001', 5, 0.1, 1, CURRENT_DATE());
SELECT 'Dos creditos para una solicitud' AS prueba, COUNT(*) AS creditos
FROM cob_credito WHERE id_solicitud = '0198b000-0000-700a-8000-000000000001';
SET @ok = NOT EXISTS (SELECT 1 FROM cob_credito WHERE id_credito = 'cr2');
CALL repro.reg('7', 'Una solicitud genera un solo credito',
  'Se creo un segundo credito para la misma solicitud, a nombre de otra clienta.',
  'Rechazo: en el informe el credito es 1:1 con su orden y su calendario', IF(@ok, @rechazo, @acepto), @ok,
  'Un mismo prestamo aprobado podria cobrarse dos veces, incluso a personas distintas.');

-- Tarjeta con ultimos4 no numerico y vencimiento anterior a la emision.
INSERT INTO tar_tarjeta (id_tarjeta, pan_token, bin, ultimos4, id_cliente, tipo_tarjeta, fecha_emision, fecha_vencimiento)
VALUES ('k1', 'tok1', '123456', 'ABCD', 'c2', 'DEBITO', '2026-01-01', '2020-01-01');
SELECT 'ultimos4 = ABCD, vence antes de emitirse' AS prueba, ultimos4, fecha_emision, fecha_vencimiento
FROM tar_tarjeta WHERE id_tarjeta = 'k1';
SET @ok = NOT EXISTS (SELECT 1 FROM tar_tarjeta WHERE id_tarjeta = 'k1');
CALL repro.reg('7', 'Una tarjeta tiene datos validos',
  'Se emitio una tarjeta con ultimos4 = ''ABCD'', emitida en 2026 y que vence en 2020.',
  'Rechazo: ultimos4 son 4 digitos y el vencimiento es posterior a la emision', IF(@ok, @rechazo, @acepto), @ok,
  'El informe tiene CHECK para ambos casos; aqui no existen.');

-- Matriz colgada de una credencial PIN_ATM, con longitud 99.
INSERT INTO tar_credencial (id_credencial, id_tarjeta, tipo, longitud, hash_credencial, sal)
VALUES ('cr-pin', 'k1', 'PIN_ATM', 99, 'h', 's');
INSERT INTO tar_matriz_token (id_matriz, id_credencial, fecha_emision) VALUES ('m1', 'cr-pin', CURRENT_DATE());
SELECT 'Matriz sobre credencial PIN_ATM' AS prueba, c.tipo, c.longitud
FROM tar_matriz_token m JOIN tar_credencial c ON c.id_credencial = m.id_credencial WHERE m.id_matriz = 'm1';
SET @ok = NOT EXISTS (SELECT 1 FROM tar_matriz_token WHERE id_matriz = 'm1');
CALL repro.reg('7', 'Una tarjeta matriz cuelga de una credencial de tipo matriz',
  'Se creo un PIN de 99 digitos y se le colgo una tarjeta matriz de coordenadas.',
  'Rechazo: el PIN tiene 4 digitos y la matriz no pertenece a un PIN', IF(@ok, @rechazo, @acepto), @ok,
  'La longitud depende del tipo de credencial (problema de 2FN que el informe resolvio con TIPO_CREDENCIAL).');

-- Coordenada fuera de A-H / 1-8 (el CHECK solo mira la longitud).
INSERT INTO tar_intento_autenticacion (id_intento, id_tarjeta, tipo_credencial, coordenada_solicitada, id_canal, resultado)
VALUES ('i1', 'k1', 'TOKEN_MATRIZ', 'Z9', 'HB', 'FALLIDO');
SELECT 'Coordenada Z9 aceptada' AS prueba, coordenada_solicitada FROM tar_intento_autenticacion WHERE id_intento = 'i1';
SET @ok = NOT EXISTS (SELECT 1 FROM tar_intento_autenticacion WHERE id_intento = 'i1');
CALL repro.reg('7', 'La coordenada pedida existe en la matriz',
  'Se registro un intento pidiendo la coordenada Z9 (la matriz va de A1 a H8).',
  'Rechazo: fila A-H y columna 1-8', IF(@ok, @rechazo, @acepto), @ok,
  'El comentario dice "coordenada validada por CHECK", pero el CHECK solo verifica que tenga 2 caracteres.');

-- cap_caso.id_solicitud no tiene clave foranea.
INSERT INTO cap_solicitante (id_solicitante, cod_tipo_documento, numero_documento, nombres, apellidos, celular)
VALUES ('s1', 'DNI', '1', 'x', 'y', '1');
INSERT INTO cap_caso (id_caso, id_solicitante, canal_captacion, id_solicitud) VALUES ('caso1', 's1', 'WEB', 'no-existe');
SELECT 'cap_caso apunta a solicitud inexistente' AS prueba, id_solicitud FROM cap_caso WHERE id_caso = 'caso1';
SET @ok = NOT EXISTS (SELECT 1 FROM cap_caso WHERE id_caso = 'caso1');
CALL repro.reg('7', 'Un caso de captacion apunta a una solicitud real',
  'Se creo un caso con id_solicitud = ''no-existe''.',
  'Rechazo por clave foranea', IF(@ok, @rechazo, @acepto), @ok,
  'cap_caso.id_solicitud no tiene FK; ademas sol_solicitud.id_caso guarda el mismo vinculo al reves.');

-- Auditoria con referencia libre: el caso que ENTIDAD_AUDITADA resuelve en el informe.
INSERT INTO auditoria_evento (id_evento, modulo, entidad, id_entidad, accion, actor)
VALUES ('a1', 'XYZ', 'tabla_que_no_existe', 'nada', 'x', 'y');
SELECT 'auditoria_evento sobre entidad inexistente' AS prueba, modulo, entidad, id_entidad
FROM auditoria_evento WHERE id_evento = 'a1';
SET @ok = NOT EXISTS (SELECT 1 FROM auditoria_evento WHERE id_evento = 'a1');
CALL repro.reg('-', 'La auditoria solo registra eventos sobre registros reales',
  'Se audito una accion del modulo ''XYZ'' sobre la tabla ''tabla_que_no_existe'', registro ''nada''.',
  'Rechazo: en el informe la entidad auditada es una FK a ENTIDAD_AUDITADA', IF(@ok, @rechazo, @acepto), @ok,
  'Es el caso de 3FN que se resolvio en el informe; aqui la referencia sigue siendo texto libre.');

-- Asiento descuadrado (solo debe) y con fecha fuera de su periodo (enero).
INSERT INTO asiento_contable (id_asiento, id_periodo, fecha, glosa)
VALUES ('as1', '0198b000-0000-7010-8000-000000000001', '2026-10-15', 'x');
INSERT INTO asiento_detalle (id_detalle, id_asiento, cod_cuenta_contable, debe, haber, importe_moneda_base)
VALUES ('d1', 'as1', '1101', 100, 0, 100);
SELECT 'Asiento solo con debe, fecha fuera del periodo' AS prueba, SUM(d.debe) AS debe, SUM(d.haber) AS haber,
       p.fecha_inicio, p.fecha_fin, a.fecha
FROM asiento_contable a
JOIN asiento_detalle d ON d.id_asiento = a.id_asiento
JOIN periodo_contable p ON p.id_periodo = a.id_periodo
WHERE a.id_asiento = 'as1'
GROUP BY p.fecha_inicio, p.fecha_fin, a.fecha;
SET @ok = NOT EXISTS (SELECT 1 FROM asiento_detalle WHERE id_detalle = 'd1');
CALL repro.reg('7', 'Un asiento contable cuadra y cae en su periodo',
  'Se registro un asiento del 15 de octubre en el periodo de enero, con S/100 en el debe y nada en el haber.',
  'Rechazo: en partida doble el debe y el haber suman lo mismo, y la fecha cae dentro del periodo',
  IF(@ok, @rechazo, @acepto), @ok,
  'La contabilidad puede quedar descuadrada; ninguna regla lo controla.');

-- admin.bna y asesor.bna comparten empleado: la regla de autorizador distinto pasa.
INSERT INTO des_solicitud_reversion (id_reversion, id_orden, id_solicitante, id_autorizador, motivo)
VALUES ('r1', 'o2', '0198b000-0000-7003-8000-000000000001', '0198b000-0000-7003-8000-000000000002', 'x');
SELECT 'Reversion: usuarios distintos, mismo empleado' AS prueba, u.username, u.id_empleado
FROM des_solicitud_reversion r
JOIN usuario_sistema u ON u.id_usuario IN (r.id_solicitante, r.id_autorizador)
WHERE r.id_reversion = 'r1';
SET @ok = NOT EXISTS (SELECT 1 FROM des_solicitud_reversion WHERE id_reversion = 'r1');
CALL repro.reg('-', 'Una reversion la autoriza otra persona',
  'Se pidio una reversion con admin.bna y se autorizo con asesor.bna. En el seed, ambos usuarios son el mismo empleado.',
  'Rechazo: quien solicita y quien autoriza deben ser personas distintas', IF(@ok, @rechazo, @acepto), @ok,
  'El CHECK compara usuarios, no personas; con los datos de ejemplo una misma persona se autoriza a si misma.');
