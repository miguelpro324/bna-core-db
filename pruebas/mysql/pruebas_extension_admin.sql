-- Pruebas de sql/bna_extension.sql con bna_admin_user, que tiene los
-- privilegios y debe toparse con la restricción o el trigger.
CALL prueba.rechaza('X30', 'Extensión', 'Usuarios', 'El empleado exige una agencia existente',
  JSON_ARRAY("INSERT INTO core.empleado (id_empleado, codigo_empleado, nombre_completo, cargo, id_agencia) VALUES (UUID_TO_BIN(UUID()), 'E1', 'E', 'CAJERO', 'NOEXISTE')"),
  'fk_empleado_agencia', 'declarativo');

CALL prueba.rechaza('X31', 'Extensión', 'Tipos de cambio', 'La tasa debe ser positiva',
  JSON_ARRAY("INSERT INTO core.tipo_cambio VALUES ('USD', 'PEN', '2026-01-01', 0)"),
  'ck_tipo_cambio_tasa', 'declarativo');

CALL prueba.rechaza('X32', 'Extensión', 'Productos', 'El plazo mínimo no supera al máximo',
  JSON_ARRAY("INSERT INTO core.producto_credito (id_producto_credito, nombre, tasa_tea, plazo_min_meses, plazo_max_meses) VALUES (UUID_TO_BIN(UUID()), 'P', 0.1, 10, 5)"),
  'ck_producto_credito_plazo', 'declarativo');

CALL prueba.rechaza('X33', 'Extensión', 'Auditoría', 'La bitácora rechaza UPDATE aun con privilegios',
  JSON_ARRAY("CALL core.registrar_evento('CORE', 'e', '1', 'A', 'x', NULL, NULL)",
             "UPDATE core.evento_auditoria SET actor = 'y'"),
  'BNA-AUDITORIA', 'trigger');

CALL prueba.rechaza('X34', 'Extensión', 'Auditoría', 'La bitácora rechaza DELETE aun con privilegios',
  JSON_ARRAY("CALL core.registrar_evento('CORE', 'e', '1', 'A', 'x', NULL, NULL)",
             "DELETE FROM core.evento_auditoria"),
  'BNA-AUDITORIA', 'trigger');
