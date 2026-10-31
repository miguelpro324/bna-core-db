-- =====================================================================
-- Extensiones de integración de la rama mysql (MySQL 8.4)
-- =====================================================================
-- Lo que la API de integración necesita y el modelo normalizado no tiene.
-- Se carga después de sql/bna_core.sql. Queda fuera del modelo: no está en
-- modelo_bna.py, ni en el MER, ni en la rama main, y es una divergencia
-- deliberada de la versión MySQL.
-- DECISIÓN: bna_app no escribe directamente en estas tablas; lo hace solo por
--   los procedimientos de este archivo, que corren como bna_owner.
-- DECISIÓN: los catálogos de la API que no tienen equivalente exacto no se
--   agregan a la base (core.equivalencia_catalogo solo guarda los exactos).

-- ---------------------------------------------------------------------
-- 1. Usuarios y empleados
-- ---------------------------------------------------------------------
CREATE TABLE core.empleado (
    id_empleado     BINARY(16) NOT NULL,
    codigo_empleado VARCHAR(20) NOT NULL,
    nombre_completo VARCHAR(100) NOT NULL,
    cargo           VARCHAR(30) NOT NULL,
    id_agencia      VARCHAR(10),
    activo          TINYINT(1) DEFAULT TRUE NOT NULL,
    CONSTRAINT pk_empleado PRIMARY KEY (id_empleado),
    CONSTRAINT uk_empleado_1 UNIQUE (codigo_empleado),
    CONSTRAINT fk_empleado_agencia FOREIGN KEY (id_agencia) REFERENCES core.agencia (id_agencia),
    CONSTRAINT ck_empleado_activo CHECK (activo IN (0, 1))
) ENGINE = InnoDB COMMENT = 'Extensión de integración: empleados del banco.';

CREATE TABLE core.usuario_sistema (
    id_usuario     BINARY(16) NOT NULL,
    username       VARCHAR(40) NOT NULL,
    nombre         VARCHAR(100) NOT NULL,
    rol            VARCHAR(15) NOT NULL,
    hash_password  VARCHAR(255) NOT NULL,
    algoritmo_hash VARCHAR(20) NOT NULL,
    version_hash   VARCHAR(10) NOT NULL,
    id_empleado    BINARY(16),
    activo         TINYINT(1) DEFAULT TRUE NOT NULL,
    creado_en      DATETIME(6) DEFAULT (UTC_TIMESTAMP(6)) NOT NULL,
    CONSTRAINT pk_usuario_sistema PRIMARY KEY (id_usuario),
    CONSTRAINT uk_usuario_sistema_1 UNIQUE (username),
    CONSTRAINT fk_usuario_empleado FOREIGN KEY (id_empleado) REFERENCES core.empleado (id_empleado),
    CONSTRAINT ck_usuario_rol CHECK (rol IN ('ADMINISTRADOR', 'ASESOR', 'ANALISTA', 'OPERADOR', 'AUDITOR')),
    CONSTRAINT ck_usuario_activo CHECK (activo IN (0, 1)),
    CONSTRAINT ck_usuario_id CHECK ((ASCII(SUBSTR(id_usuario, 7, 1)) >> 4) BETWEEN 1 AND 8
                                    AND (ASCII(SUBSTR(id_usuario, 9, 1)) & 0xC0) = 0x80)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: usuarios; VARCHAR(255) admite bcrypt y Argon2.';

-- ---------------------------------------------------------------------
-- 2. Productos
-- ---------------------------------------------------------------------
CREATE TABLE core.producto_ahorro (
    id_producto_ahorro BINARY(16) NOT NULL,
    nombre             VARCHAR(60) NOT NULL,
    moneda             CHAR(3) NOT NULL,
    tasa_tea           DECIMAL(6,4) DEFAULT 0 NOT NULL,
    activo             TINYINT(1) DEFAULT TRUE NOT NULL,
    CONSTRAINT pk_producto_ahorro PRIMARY KEY (id_producto_ahorro),
    CONSTRAINT fk_producto_ahorro_moneda FOREIGN KEY (moneda) REFERENCES core.moneda (cod_moneda),
    CONSTRAINT ck_producto_ahorro_tea CHECK (tasa_tea >= 0)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: catálogo de productos de ahorro.';

CREATE TABLE core.producto_credito (
    id_producto_credito BINARY(16) NOT NULL,
    nombre              VARCHAR(60) NOT NULL,
    tasa_tea            DECIMAL(6,4) NOT NULL,
    plazo_min_meses     SMALLINT DEFAULT 1 NOT NULL,
    plazo_max_meses     SMALLINT DEFAULT 60 NOT NULL,
    activo              TINYINT(1) DEFAULT TRUE NOT NULL,
    CONSTRAINT pk_producto_credito PRIMARY KEY (id_producto_credito),
    CONSTRAINT ck_producto_credito_tea CHECK (tasa_tea >= 0),
    CONSTRAINT ck_producto_credito_plazo CHECK (plazo_min_meses BETWEEN 1 AND plazo_max_meses)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: catálogo de productos de crédito.';

-- ---------------------------------------------------------------------
-- 3. Tipos de cambio
-- ---------------------------------------------------------------------
CREATE TABLE core.tipo_cambio (
    cod_moneda_origen  CHAR(3) NOT NULL,
    cod_moneda_destino CHAR(3) NOT NULL,
    fecha              DATE NOT NULL,
    tasa               DECIMAL(12,6) NOT NULL,
    CONSTRAINT pk_tipo_cambio PRIMARY KEY (cod_moneda_origen, cod_moneda_destino, fecha),
    CONSTRAINT fk_tipo_cambio_origen FOREIGN KEY (cod_moneda_origen) REFERENCES core.moneda (cod_moneda),
    CONSTRAINT fk_tipo_cambio_destino FOREIGN KEY (cod_moneda_destino) REFERENCES core.moneda (cod_moneda),
    CONSTRAINT ck_tipo_cambio_tasa CHECK (tasa > 0),
    CONSTRAINT ck_tipo_cambio_monedas CHECK (cod_moneda_origen <> cod_moneda_destino)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: tipo de cambio diario, lo mantiene bna_admin.';

-- ---------------------------------------------------------------------
-- 4. Periodos contables
-- ---------------------------------------------------------------------
-- DECISIÓN: la base solo rechaza un periodo CERRADO. Una fecha sin periodo se
--   acepta en la base, para no exigir periodos a quien no los usa; la API
--   rechaza ese caso.
CREATE TABLE core.periodo_contable (
    anio         SMALLINT NOT NULL,
    mes          TINYINT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin    DATE NOT NULL,
    estado       VARCHAR(10) DEFAULT 'ABIERTO' NOT NULL,
    CONSTRAINT pk_periodo_contable PRIMARY KEY (anio, mes),
    CONSTRAINT ck_periodo_mes CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_periodo_fechas CHECK (fecha_inicio <= fecha_fin),
    CONSTRAINT ck_periodo_estado CHECK (estado IN ('ABIERTO', 'CERRADO'))
) ENGINE = InnoDB COMMENT = 'Extensión de integración: periodos contables, los mantiene bna_admin.';

-- ---------------------------------------------------------------------
-- 5. Idempotencia de movimientos
-- ---------------------------------------------------------------------
CREATE TABLE cuentas.idempotencia_movimiento (
    llave              VARCHAR(64) NOT NULL,
    huella             CHAR(64) NOT NULL,
    uuid_transaccion   BINARY(16),
    uuid_abono         BINARY(16),
    creado_en          DATETIME(6) DEFAULT (UTC_TIMESTAMP(6)) NOT NULL,
    CONSTRAINT pk_idempotencia_movimiento PRIMARY KEY (llave),
    CONSTRAINT fk_idempotencia_movimiento FOREIGN KEY (uuid_transaccion)
        REFERENCES cuentas.movimiento (uuid_transaccion),
    CONSTRAINT fk_idempotencia_abono FOREIGN KEY (uuid_abono)
        REFERENCES cuentas.movimiento (uuid_transaccion)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: llave de idempotencia y huella de la petición.';

-- ---------------------------------------------------------------------
-- 6. Auditoría general del CORE
-- ---------------------------------------------------------------------
CREATE TABLE core.evento_auditoria (
    id_evento      BIGINT AUTO_INCREMENT,
    id_modulo      SMALLINT NOT NULL,
    entidad        VARCHAR(40) NOT NULL,
    id_entidad     VARCHAR(40) NOT NULL,
    accion         VARCHAR(60) NOT NULL,
    actor          VARCHAR(40) NOT NULL,
    correlation_id BINARY(16),
    detalle        JSON,
    fecha_hora     DATETIME(6) DEFAULT (UTC_TIMESTAMP(6)) NOT NULL,
    CONSTRAINT pk_evento_auditoria_core PRIMARY KEY (id_evento),
    CONSTRAINT fk_evento_auditoria_modulo FOREIGN KEY (id_modulo) REFERENCES core.modulo (id_modulo)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: bitácora general de solo inserción.';

-- ---------------------------------------------------------------------
-- 7. Valores de catálogo
-- ---------------------------------------------------------------------
CREATE TABLE core.equivalencia_catalogo (
    catalogo  VARCHAR(30) NOT NULL,
    valor_api VARCHAR(30) NOT NULL,
    valor_bd  VARCHAR(30) NOT NULL,
    CONSTRAINT pk_equivalencia_catalogo PRIMARY KEY (catalogo, valor_api)
) ENGINE = InnoDB COMMENT = 'Extensión de integración: valores de la API con equivalente exacto.';

INSERT INTO core.equivalencia_catalogo (catalogo, valor_api, valor_bd) VALUES
    ('estado_tarjeta', 'ANULADA', 'CANCELADA'),
    ('origen_cambio', 'BANCO', 'OPERADOR');

-- Datos de referencia que los procedimientos y la API necesitan.
INSERT IGNORE INTO core.cuenta_contable VALUES
    ('1101', 'Caja', 'DEUDORA', NULL), ('2101', 'Depósitos de ahorro', 'ACREEDORA', NULL);
INSERT IGNORE INTO tarjetas.bin_tarjeta VALUES ('004499', 'FISICA', 'Débito BNA física');

-- ---------------------------------------------------------------------
-- 8. Procedimientos y reglas
-- ---------------------------------------------------------------------
DELIMITER //

CREATE DEFINER = 'bna_owner'@'%' TRIGGER core.tg_asiento_periodo_abierto BEFORE INSERT ON core.asiento_contable
FOR EACH ROW BEGIN
    IF EXISTS (SELECT 1 FROM core.periodo_contable
                WHERE NEW.fecha_contable BETWEEN fecha_inicio AND fecha_fin AND estado = 'CERRADO') THEN
        CALL core.fallar(CONCAT('BNA-PERIODO: el periodo de ', NEW.fecha_contable, ' está cerrado'));
    END IF;
END //

CREATE DEFINER = 'bna_owner'@'%' TRIGGER core.tg_evento_auditoria_solo_insercion_bu
BEFORE UPDATE ON core.evento_auditoria
FOR EACH ROW BEGIN CALL core.rechazar_cambio('BNA-AUDITORIA', 'core.evento_auditoria', 'UPDATE'); END //

CREATE DEFINER = 'bna_owner'@'%' TRIGGER core.tg_evento_auditoria_solo_insercion_bd
BEFORE DELETE ON core.evento_auditoria
FOR EACH ROW BEGIN CALL core.rechazar_cambio('BNA-AUDITORIA', 'core.evento_auditoria', 'DELETE'); END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE core.registrar_evento(
    IN p_modulo VARCHAR(100), IN p_entidad VARCHAR(40), IN p_id_entidad VARCHAR(40), IN p_accion VARCHAR(60),
    IN p_actor VARCHAR(40), IN p_correlation_id BINARY(16), IN p_detalle JSON)
    COMMENT 'Registra un evento en la bitácora general.'
BEGIN
    DECLARE v_id SMALLINT;
    SELECT id_modulo INTO v_id FROM core.modulo WHERE nombre = p_modulo;
    IF v_id IS NULL THEN
        CALL core.fallar(CONCAT('BNA-AUDITORIA: módulo desconocido ', coalesce(p_modulo, '(nulo)')));
    END IF;
    INSERT INTO core.evento_auditoria (id_modulo, entidad, id_entidad, accion, actor, correlation_id, detalle)
    VALUES (v_id, p_entidad, p_id_entidad, p_accion, p_actor, p_correlation_id, p_detalle);
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE core.crear_usuario(
    IN p_id BINARY(16), IN p_username VARCHAR(40), IN p_nombre VARCHAR(100), IN p_rol VARCHAR(15),
    IN p_hash VARCHAR(255), IN p_algoritmo VARCHAR(20), IN p_version VARCHAR(10),
    IN p_id_empleado BINARY(16), IN p_activo BOOLEAN)
    COMMENT 'Crea un usuario del sistema.'
BEGIN
    INSERT INTO core.usuario_sistema (id_usuario, username, nombre, rol, hash_password, algoritmo_hash,
                                      version_hash, id_empleado, activo)
    VALUES (p_id, p_username, p_nombre, p_rol, p_hash, p_algoritmo, p_version, p_id_empleado, p_activo);
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE core.asignar_rol(IN p_id BINARY(16), IN p_rol VARCHAR(15),
                                                            OUT p_filas INT)
    COMMENT 'Cambia el rol de un usuario.'
BEGIN
    UPDATE core.usuario_sistema SET rol = p_rol WHERE id_usuario = p_id;
    SET p_filas = ROW_COUNT();
END //

-- Con logins simultáneos solo uno actualiza la fila y deja el evento.
CREATE DEFINER = 'bna_owner'@'%' PROCEDURE core.migrar_hash_usuario(
    IN p_id BINARY(16), IN p_algoritmo_anterior VARCHAR(20), IN p_hash VARCHAR(255),
    IN p_algoritmo VARCHAR(20), IN p_version VARCHAR(10), OUT p_filas INT)
    COMMENT 'Migra el hash de un usuario si sigue en el algoritmo anterior.'
BEGIN
    DECLARE v_username VARCHAR(40);
    UPDATE core.usuario_sistema
       SET hash_password = p_hash, algoritmo_hash = p_algoritmo, version_hash = p_version
     WHERE id_usuario = p_id AND algoritmo_hash = p_algoritmo_anterior;
    SET p_filas = ROW_COUNT();
    IF p_filas = 1 THEN
        SELECT username INTO v_username FROM core.usuario_sistema WHERE id_usuario = p_id;
        CALL core.registrar_evento('CORE', 'usuario_sistema', BIN_TO_UUID(p_id), 'MIGRAR_HASH_PASSWORD',
                                   v_username, NULL,
                                   JSON_OBJECT('algoritmo_anterior', p_algoritmo_anterior,
                                               'algoritmo_nuevo', p_algoritmo));
    END IF;
END //

-- Reserva la llave antes de operar: una petición simultánea con la misma llave
-- espera en el índice único hasta que la primera confirme o deshaga.
CREATE DEFINER = 'bna_owner'@'%' PROCEDURE cuentas.reservar_llave(
    IN p_llave VARCHAR(64), IN p_huella CHAR(64), OUT p_repetido BOOLEAN,
    OUT p_uuid BINARY(16), OUT p_abono BINARY(16))
    COMMENT 'Reserva una llave de idempotencia o devuelve la operación que ya la usó.'
BEGIN
    DECLARE v_duplicada BOOLEAN DEFAULT FALSE;
    DECLARE v_huella CHAR(64);
    DECLARE CONTINUE HANDLER FOR 1062 SET v_duplicada = TRUE;
    SET p_repetido = FALSE;
    IF p_llave IS NOT NULL THEN
        INSERT INTO cuentas.idempotencia_movimiento (llave, huella) VALUES (p_llave, p_huella);
        IF v_duplicada THEN
            SELECT huella, uuid_transaccion, uuid_abono INTO v_huella, p_uuid, p_abono
              FROM cuentas.idempotencia_movimiento WHERE llave = p_llave FOR UPDATE;
            IF NOT (v_huella <=> p_huella) THEN
                CALL core.fallar(CONCAT('BNA-IDEMPOTENCIA: la llave ', p_llave, ' se usó con otros parámetros'));
            END IF;
            SET p_repetido = TRUE;
        END IF;
    END IF;
END //

-- Un movimiento con su asiento de partida doble (1101 Caja, 2101 Depósitos).
-- Los triggers de cuentas.movimiento validan el saldo, el estado y el tope.
CREATE DEFINER = 'bna_owner'@'%' PROCEDURE cuentas.aplicar_movimiento(
    IN p_cuenta VARCHAR(20), IN p_tipo VARCHAR(25), IN p_monto DECIMAL(15,2), IN p_glosa VARCHAR(200),
    IN p_canal VARCHAR(5), IN p_correlation_id BINARY(16), OUT p_uuid BINARY(16))
    COMMENT 'Registra un movimiento y su asiento.'
BEGIN
    DECLARE v_nat CHAR(1);
    DECLARE v_moneda CHAR(3);
    DECLARE v_asiento BINARY(16);
    DECLARE v_fecha DATE DEFAULT core.fn_fecha_negocio(UTC_TIMESTAMP(6));
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = p_tipo;
    SELECT moneda INTO v_moneda FROM cuentas.cuenta_ahorro WHERE num_cuenta = p_cuenta;
    IF v_nat IS NULL THEN
        CALL core.fallar(CONCAT('BNA-MOVIMIENTO: tipo de operación desconocido ', coalesce(p_tipo, '(nulo)')));
    END IF;
    IF v_moneda IS NULL THEN
        CALL core.fallar(CONCAT('BNA-CUENTA: no existe la cuenta ', coalesce(p_cuenta, '(nula)')));
    END IF;
    CALL core.registrar_asiento(NULL, CONCAT('A-', HEX(RANDOM_BYTES(8))), v_fecha, v_fecha, p_glosa, v_moneda,
        p_correlation_id, NULL,
        JSON_ARRAY(JSON_OBJECT('partida', IF(v_nat = 'C', 'DEBE', 'HABER'), 'importe', p_monto, 'cuenta', '1101'),
                   JSON_OBJECT('partida', IF(v_nat = 'C', 'HABER', 'DEBE'), 'importe', p_monto, 'cuenta', '2101')),
        v_asiento);
    SET p_uuid = core.uuid_v4();
    INSERT INTO cuentas.movimiento (uuid_transaccion, tipo_operacion, monto, glosa, estado_transaccion,
                                    id_asiento, num_cuenta, id_canal)
    VALUES (p_uuid, p_tipo, p_monto, p_glosa, 'APROBADO', v_asiento, p_cuenta, p_canal);
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE cuentas.registrar_movimiento(
    IN p_cuenta VARCHAR(20), IN p_tipo VARCHAR(25), IN p_monto DECIMAL(15,2), IN p_glosa VARCHAR(200),
    IN p_canal VARCHAR(5), IN p_correlation_id BINARY(16), IN p_llave VARCHAR(64), IN p_huella CHAR(64),
    OUT p_uuid BINARY(16), OUT p_repetido BOOLEAN)
    COMMENT 'Depósito o retiro idempotente.'
BEGIN
    DECLARE v_abono BINARY(16);
    CALL cuentas.reservar_llave(p_llave, p_huella, p_repetido, p_uuid, v_abono);
    IF NOT p_repetido THEN
        CALL cuentas.aplicar_movimiento(p_cuenta, p_tipo, p_monto, p_glosa, p_canal, p_correlation_id, p_uuid);
        IF p_llave IS NOT NULL THEN
            UPDATE cuentas.idempotencia_movimiento SET uuid_transaccion = p_uuid WHERE llave = p_llave;
        END IF;
    END IF;
END //

-- Bloquea las dos cuentas en orden de num_cuenta, para que dos transferencias
-- opuestas no se bloqueen entre sí. Cada tramo lleva su propio asiento
-- (uk_movimiento_1).
-- DECISIÓN: entre monedas distintas se rechaza hasta que se defina la regla de
--   conversión.
CREATE DEFINER = 'bna_owner'@'%' PROCEDURE cuentas.registrar_transferencia(
    IN p_origen VARCHAR(20), IN p_destino VARCHAR(20), IN p_monto DECIMAL(15,2), IN p_glosa VARCHAR(200),
    IN p_canal VARCHAR(5), IN p_correlation_id BINARY(16), IN p_llave VARCHAR(64), IN p_huella CHAR(64),
    OUT p_debito BINARY(16), OUT p_abono BINARY(16), OUT p_repetido BOOLEAN)
    COMMENT 'Transferencia idempotente entre dos cuentas de la misma moneda.'
BEGIN
    DECLARE v_moneda_1, v_moneda_2 CHAR(3);
    IF p_origen = p_destino THEN
        CALL core.fallar('BNA-TRANSFERENCIA: la cuenta de origen y la de destino son la misma');
    END IF;
    CALL cuentas.reservar_llave(p_llave, p_huella, p_repetido, p_debito, p_abono);
    IF NOT p_repetido THEN
        SELECT moneda INTO v_moneda_1 FROM cuentas.cuenta_ahorro
         WHERE num_cuenta = LEAST(p_origen, p_destino) FOR UPDATE;
        SELECT moneda INTO v_moneda_2 FROM cuentas.cuenta_ahorro
         WHERE num_cuenta = GREATEST(p_origen, p_destino) FOR UPDATE;
        IF v_moneda_1 IS NULL OR v_moneda_2 IS NULL THEN
            CALL core.fallar(CONCAT('BNA-CUENTA: no existe ', p_origen, ' o ', p_destino));
        END IF;
        IF v_moneda_1 <> v_moneda_2 THEN
            CALL core.fallar('BNA-MONEDA: transferencia entre monedas distintas');
        END IF;
        CALL cuentas.aplicar_movimiento(p_origen, 'TRANSFERENCIA_ENVIADA', p_monto, p_glosa, p_canal,
                                        p_correlation_id, p_debito);
        CALL cuentas.aplicar_movimiento(p_destino, 'TRANSFERENCIA_RECIBIDA', p_monto, p_glosa, p_canal,
                                        p_correlation_id, p_abono);
        IF p_llave IS NOT NULL THEN
            UPDATE cuentas.idempotencia_movimiento SET uuid_transaccion = p_debito, uuid_abono = p_abono
             WHERE llave = p_llave;
        END IF;
    END IF;
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE cuentas.abrir_cuenta(
    IN p_num_cuenta VARCHAR(20), IN p_cci CHAR(20), IN p_moneda CHAR(3), IN p_regimen VARCHAR(25),
    IN p_id_agencia VARCHAR(10), IN p_titulares JSON)
    COMMENT 'Abre una cuenta con sus titulares ["C001", ...].'
BEGIN
    DECLARE v_minimo SMALLINT;
    SELECT min_titulares INTO v_minimo FROM cuentas.regimen_cuenta WHERE cod_regimen = p_regimen;
    IF v_minimo IS NULL THEN
        CALL core.fallar(CONCAT('BNA-REGIMEN: régimen desconocido ', coalesce(p_regimen, '(nulo)')));
    END IF;
    IF coalesce(JSON_LENGTH(p_titulares), 0) < v_minimo THEN
        CALL core.fallar(CONCAT('BNA-REGIMEN: el régimen ', p_regimen, ' exige ', v_minimo, ' titulares'));
    END IF;
    INSERT INTO cuentas.cuenta_ahorro (num_cuenta, cci, moneda, regimen, estado_cuenta, id_agencia)
    VALUES (p_num_cuenta, p_cci, p_moneda, p_regimen, 'ACTIVA', p_id_agencia);
    INSERT INTO cuentas.titularidad (cod_cliente, num_cuenta)
    SELECT t.cod_cliente, p_num_cuenta
      FROM JSON_TABLE(p_titulares, '$[*]' COLUMNS (cod_cliente VARCHAR(12) PATH '$')) AS t;
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE tarjetas.emitir_tarjeta(
    IN p_id BINARY(16), IN p_pan_token VARCHAR(32), IN p_bin CHAR(6), IN p_ultimos4 CHAR(4),
    IN p_emision DATE, IN p_vencimiento DATE, IN p_cod_cliente VARCHAR(12), IN p_num_cuenta VARCHAR(20))
    COMMENT 'Emite una tarjeta PENDIENTE_ACTIVACION vinculada a su cuenta principal.'
BEGIN
    INSERT INTO tarjetas.tarjeta (id_tarjeta, pan_token, bin, ultimos4, fecha_emision, fecha_vencimiento,
                                  estado_tarjeta, cod_cliente)
    VALUES (p_id, p_pan_token, p_bin, p_ultimos4, p_emision, p_vencimiento, 'PENDIENTE_ACTIVACION', p_cod_cliente);
    INSERT INTO tarjetas.tarjeta_cuenta (id_tarjeta, num_cuenta, es_principal) VALUES (p_id, p_num_cuenta, TRUE);
END //

CREATE DEFINER = 'bna_owner'@'%' PROCEDURE tarjetas.cambiar_estado_tarjeta(
    IN p_id BINARY(16), IN p_estado VARCHAR(25), IN p_motivo VARCHAR(255), IN p_origen VARCHAR(20),
    OUT p_id_historial BIGINT)
    COMMENT 'Cambia el estado de una tarjeta por su historial.'
BEGIN
    INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
    VALUES (p_estado, p_motivo, p_origen, p_id);
    SET p_id_historial = LAST_INSERT_ID();
END //

DELIMITER ;

GRANT EXECUTE ON PROCEDURE core.registrar_evento TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE core.crear_usuario TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE core.asignar_rol TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE core.migrar_hash_usuario TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE cuentas.registrar_movimiento TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE cuentas.registrar_transferencia TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE cuentas.abrir_cuenta TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE tarjetas.emitir_tarjeta TO bna_app, bna_admin;
GRANT EXECUTE ON PROCEDURE tarjetas.cambiar_estado_tarjeta TO bna_app, bna_admin;
