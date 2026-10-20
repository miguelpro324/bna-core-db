-- =====================================================================
-- Banco Nacional de Arequipa (BNA) - base de datos integrada del CORE
-- PostgreSQL 13 o superior. Generado por tools/modelo_bna.py desde el
-- esquema relacional normalizado (3FN) y con tablas de catálogo.
-- =====================================================================
-- DECISIÓN: PostgreSQL, motor propuesto en la arquitectura del CORE.
-- DECISIÓN: una base con esquemas lógicos por dueño del dato; los
--   identificadores se escriben en minúsculas y sin comillas.
-- DECISIÓN: las claves foráneas se agregan al final con ALTER TABLE para
--   no depender del orden de creación; ON DELETE RESTRICT por omisión,
--   porque los registros financieros no se borran, se anulan o revierten.

BEGIN;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS clientes;
CREATE SCHEMA IF NOT EXISTS cuentas;
CREATE SCHEMA IF NOT EXISTS tarjetas;
CREATE SCHEMA IF NOT EXISTS creditos;

-- ---------------------------------------------------------------------
CREATE TABLE core.agencia (
    id_agencia                  VARCHAR(10),
    nombre                      VARCHAR(100) NOT NULL,
    calle                       VARCHAR(120) NOT NULL,
    distrito                    VARCHAR(60) NOT NULL,
    ciudad                      VARCHAR(60) NOT NULL,
    estado_agencia              VARCHAR(25) NOT NULL
        CHECK (estado_agencia IN ('ACTIVA', 'INACTIVA')),
    CONSTRAINT pk_agencia PRIMARY KEY (id_agencia)
);
COMMENT ON TABLE core.agencia IS 'Agencia física del BNA; las cuatro agencias iniciales de Arequipa.';

-- ---------------------------------------------------------------------
CREATE TABLE core.cuenta_contable (
    codigo_contable             VARCHAR(20),
    nombre                      VARCHAR(100) NOT NULL,
    naturaleza                  VARCHAR(25) NOT NULL
        CHECK (naturaleza IN ('DEUDORA', 'ACREEDORA')),
    codigo_padre                VARCHAR(20),
    CONSTRAINT pk_cuenta_contable PRIMARY KEY (codigo_contable)
);
COMMENT ON TABLE core.cuenta_contable IS 'Cuenta del plan de cuentas sobre la que se registran los asientos.';

-- ---------------------------------------------------------------------
CREATE TABLE core.asiento_contable (
    id_asiento                  UUID DEFAULT gen_random_uuid(),
    numero_asiento              VARCHAR(20) NOT NULL,
    fecha_contable              DATE NOT NULL,
    fecha_valor                 DATE NOT NULL,
    glosa                       VARCHAR(200) NOT NULL,
    moneda                      CHAR(3) NOT NULL,
    correlation_id              UUID NOT NULL,
    id_asiento_revertido        UUID,
    CONSTRAINT pk_asiento_contable PRIMARY KEY (id_asiento),
    CONSTRAINT uk_asiento_contable_1 UNIQUE (numero_asiento),
    CONSTRAINT uk_asiento_contable_2 UNIQUE (id_asiento_revertido)
);
COMMENT ON TABLE core.asiento_contable IS 'Cabecera del asiento de partida doble; es inmutable y se corrige con un asiento de reversa.';

-- ---------------------------------------------------------------------
CREATE TABLE core.detalle_asiento (
    id_asiento                  UUID,
    nro_linea                   SMALLINT,
    tipo_partida                VARCHAR(25) NOT NULL
        CHECK (tipo_partida IN ('DEBE', 'HABER')),
    importe                     NUMERIC(15,2) NOT NULL,
    codigo_contable             VARCHAR(20) NOT NULL,
    CONSTRAINT pk_detalle_asiento PRIMARY KEY (id_asiento, nro_linea),
    CONSTRAINT ck_detalle_asiento_1 CHECK (importe > 0)
);
COMMENT ON TABLE core.detalle_asiento IS 'Línea de débito o crédito de un asiento; no existe ni se identifica sin su asiento.';

-- ---------------------------------------------------------------------
CREATE TABLE core.moneda (
    cod_moneda                  CHAR(3),
    nombre                      VARCHAR(100) NOT NULL,
    simbolo                     VARCHAR(4) NOT NULL,
    decimales                   SMALLINT NOT NULL,
    CONSTRAINT pk_moneda PRIMARY KEY (cod_moneda)
);
COMMENT ON TABLE core.moneda IS 'Catálogo. Parámetro del CORE junto con los tipos de cambio; código ISO 4217.';

-- ---------------------------------------------------------------------
CREATE TABLE core.modulo (
    id_modulo                   SMALLINT,
    nombre                      VARCHAR(40) NOT NULL,
    CONSTRAINT pk_modulo PRIMARY KEY (id_modulo),
    CONSTRAINT uk_modulo_1 UNIQUE (nombre)
);
COMMENT ON TABLE core.modulo IS 'Catálogo. Numeración oficial: CORE (1), CLIENTES (2), CUENTAS (3), ..., COBRANZA (14).';

-- ---------------------------------------------------------------------
CREATE TABLE core.canal (
    id_canal                    VARCHAR(5),
    nombre                      VARCHAR(40) NOT NULL,
    es_presencial               BOOLEAN NOT NULL,
    tipo_integracion            VARCHAR(30) NOT NULL,
    activo                      BOOLEAN DEFAULT TRUE NOT NULL,
    regla_tope                  VARCHAR(20) NOT NULL,
    CONSTRAINT pk_canal PRIMARY KEY (id_canal),
    CONSTRAINT uk_canal_1 UNIQUE (nombre)
);
COMMENT ON TABLE core.canal IS 'Canal de atención; unifica canal (TARJETAS), CANAL_PAGO (COBRANZA) e idCanal (CUENTAS).';

-- ---------------------------------------------------------------------
CREATE TABLE core.canal_validacion (
    id_canal                    VARCHAR(5),
    tipo_validacion             VARCHAR(15),
    CONSTRAINT pk_canal_validacion PRIMARY KEY (id_canal, tipo_validacion)
);
COMMENT ON TABLE core.canal_validacion IS 'Credenciales que exige cada canal (atributo multivaluado).';

-- ---------------------------------------------------------------------
CREATE TABLE core.limite_canal (
    id_canal                    VARCHAR(5),
    moneda                      CHAR(3),
    monto_maximo_diario         NUMERIC(15,2),
    habilitado                  BOOLEAN DEFAULT TRUE NOT NULL,
    CONSTRAINT pk_limite_canal PRIMARY KEY (id_canal, moneda),
    CONSTRAINT ck_limite_canal_1 CHECK (monto_maximo_diario IS NULL OR monto_maximo_diario > 0)
);
COMMENT ON TABLE core.limite_canal IS 'Tope diario de un canal en una moneda (RN-TOP-001).';

-- ---------------------------------------------------------------------
CREATE TABLE core.consumo_diario (
    num_cuenta                  VARCHAR(20),
    id_canal                    VARCHAR(5),
    fecha_corte                 DATE,
    monto_acumulado             NUMERIC(15,2) DEFAULT 0 NOT NULL,
    CONSTRAINT pk_consumo_diario PRIMARY KEY (num_cuenta, id_canal, fecha_corte),
    CONSTRAINT ck_consumo_diario_1 CHECK (monto_acumulado >= 0)
);
COMMENT ON TABLE core.consumo_diario IS 'Acumulado de salidas de una cuenta por canal y jornada; base del tope diario (RN-TOP-001).';

-- ---------------------------------------------------------------------
CREATE TABLE core.terminal (
    id_terminal                 VARCHAR(30),
    descripcion                 VARCHAR(255) NOT NULL,
    activo                      BOOLEAN DEFAULT TRUE NOT NULL,
    id_canal                    VARCHAR(5) NOT NULL,
    id_agencia                  VARCHAR(10),
    CONSTRAINT pk_terminal PRIMARY KEY (id_terminal)
);
COMMENT ON TABLE core.terminal IS 'Terminales físicas (cajeros, agentes, ventanillas) y su canal (3FN).';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.cliente (
    cod_cliente                 VARCHAR(12),
    tipo_documento              VARCHAR(10) NOT NULL,
    numero_documento            VARCHAR(12) NOT NULL,
    nombres                     VARCHAR(100) NOT NULL,
    apellido_paterno            VARCHAR(100) NOT NULL,
    apellido_materno            VARCHAR(100),
    correo                      VARCHAR(150) NOT NULL,
    celular                     CHAR(9) NOT NULL,
    estado_cliente              VARCHAR(25) NOT NULL,
    id_verificacion_captacion   VARCHAR(36) NOT NULL,
    version_contrato            VARCHAR(10) NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (cod_cliente),
    CONSTRAINT uk_cliente_1 UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT uk_cliente_2 UNIQUE (correo),
    CONSTRAINT uk_cliente_3 UNIQUE (celular),
    CONSTRAINT uk_cliente_4 UNIQUE (id_verificacion_captacion),
    CONSTRAINT ck_cliente_1 CHECK (celular ~ '^9[0-9]{8}$')
);
COMMENT ON TABLE clientes.cliente IS 'Maestro único de la persona natural cliente del banco; reemplaza a CLIENTE_REF, cliente_ref y CLIENTES.';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.biometria_cliente (
    id_biometria                UUID DEFAULT gen_random_uuid(),
    tipo_biometria              VARCHAR(10) NOT NULL,
    datos_biometricos           BYTEA NOT NULL,
    estado_activo               BOOLEAN DEFAULT TRUE NOT NULL,
    cod_cliente                 VARCHAR(12) NOT NULL,
    CONSTRAINT pk_biometria_cliente PRIMARY KEY (id_biometria)
);
COMMENT ON TABLE clientes.biometria_cliente IS 'Plantilla biométrica registrada del cliente, cifrada con AES-256.';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.codigo_verificacion (
    id_codigo                   UUID DEFAULT gen_random_uuid(),
    tipo_contacto               VARCHAR(10) NOT NULL,
    codigo_otp                  CHAR(64) NOT NULL,
    fecha_expiracion            TIMESTAMPTZ NOT NULL,
    estado_codigo               VARCHAR(25) NOT NULL
        CHECK (estado_codigo IN ('PENDIENTE', 'VALIDADO', 'EXPIRADO', 'BLOQUEADO')),
    intentos_fallidos           SMALLINT DEFAULT 0 NOT NULL,
    cod_cliente                 VARCHAR(12) NOT NULL,
    CONSTRAINT pk_codigo_verificacion PRIMARY KEY (id_codigo)
);
COMMENT ON TABLE clientes.codigo_verificacion IS 'Código OTP temporal enviado al celular o al correo del cliente.';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.validacion_identidad (
    id_validacion               BIGINT GENERATED ALWAYS AS IDENTITY,
    tipo_validacion             VARCHAR(15) NOT NULL,
    resultado                   VARCHAR(25) NOT NULL
        CHECK (resultado IN ('APROBADO', 'RECHAZADO')),
    correlation_id              UUID NOT NULL,
    fecha_evento                TIMESTAMPTZ DEFAULT now() NOT NULL,
    cod_cliente                 VARCHAR(12),
    CONSTRAINT pk_validacion_identidad PRIMARY KEY (id_validacion)
);
COMMENT ON TABLE clientes.validacion_identidad IS 'Bitácora inmutable de cada intento de validación de identidad (antes AUDITORIA_VALIDACION).';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.verificacion_captacion (
    id_verificacion_captacion   VARCHAR(36),
    fecha_verificacion          TIMESTAMPTZ DEFAULT now() NOT NULL,
    estado_habilitante          VARCHAR(25) NOT NULL
        CHECK (estado_habilitante IN ('HABILITADO', 'OBSERVADO')),
    CONSTRAINT pk_verificacion_captacion PRIMARY KEY (id_verificacion_captacion)
);
COMMENT ON TABLE clientes.verificacion_captacion IS 'Verificación de captación del cliente (3FN).';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.tipo_documento (
    cod_tipo_documento          VARCHAR(10),
    descripcion                 VARCHAR(255) NOT NULL,
    longitud_min                SMALLINT NOT NULL,
    longitud_max                SMALLINT NOT NULL,
    es_alfanumerico             BOOLEAN NOT NULL,
    CONSTRAINT pk_tipo_documento PRIMARY KEY (cod_tipo_documento),
    CONSTRAINT ck_tipo_documento_1 CHECK (longitud_min <= longitud_max)
);
COMMENT ON TABLE clientes.tipo_documento IS 'Catálogo. DNI de 8 dígitos, PTP de 9, pasaporte alfanumérico de hasta 12 (RN-CLI-001).';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.tipo_biometria (
    cod_tipo_biometria          VARCHAR(10),
    descripcion                 VARCHAR(255) NOT NULL,
    umbral_similitud            NUMERIC(5,4),
    CONSTRAINT pk_tipo_biometria PRIMARY KEY (cod_tipo_biometria)
);
COMMENT ON TABLE clientes.tipo_biometria IS 'Catálogo. El umbral de similitud es el punto abierto R-03 de CLIENTES.';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.tipo_contacto (
    cod_tipo_contacto           VARCHAR(10),
    descripcion                 VARCHAR(255) NOT NULL,
    vigencia_minutos            SMALLINT NOT NULL,
    max_intentos                SMALLINT NOT NULL,
    CONSTRAINT pk_tipo_contacto PRIMARY KEY (cod_tipo_contacto),
    CONSTRAINT ck_tipo_contacto_1 CHECK (vigencia_minutos > 0),
    CONSTRAINT ck_tipo_contacto_2 CHECK (max_intentos > 0)
);
COMMENT ON TABLE clientes.tipo_contacto IS 'Catálogo. Parametriza la expiración y el bloqueo al tercer intento (RF-CLI-005).';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.tipo_validacion (
    cod_tipo_validacion         VARCHAR(15),
    descripcion                 VARCHAR(255) NOT NULL,
    endpoint                    VARCHAR(80) NOT NULL,
    CONSTRAINT pk_tipo_validacion PRIMARY KEY (cod_tipo_validacion),
    CONSTRAINT uk_tipo_validacion_1 UNIQUE (endpoint)
);
COMMENT ON TABLE clientes.tipo_validacion IS 'Catálogo. Los cinco flujos de KYC y su endpoint /api/v1/kyc/....';

-- ---------------------------------------------------------------------
CREATE TABLE clientes.estado_cliente (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    permite_operar              BOOLEAN NOT NULL,
    CONSTRAINT pk_estado_cliente PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE clientes.estado_cliente IS 'Catálogo. Los módulos usan listas distintas (ACTIVO/BLOQUEADO/SUSPENDIDO frente a OBSERVADO/BAJA).';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.cuenta_ahorro (
    num_cuenta                  VARCHAR(20),
    cci                         CHAR(20) NOT NULL,
    moneda                      CHAR(3) NOT NULL,
    regimen                     VARCHAR(25) NOT NULL,
    saldo_contable              NUMERIC(15,2) DEFAULT 0 NOT NULL,
    saldo_disponible            NUMERIC(15,2) DEFAULT 0 NOT NULL,
    estado_cuenta               VARCHAR(25) NOT NULL,
    fecha_apertura              TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_agencia                  VARCHAR(10),
    CONSTRAINT pk_cuenta_ahorro PRIMARY KEY (num_cuenta),
    CONSTRAINT uk_cuenta_ahorro_1 UNIQUE (cci),
    CONSTRAINT ck_cuenta_ahorro_1 CHECK (saldo_disponible <= saldo_contable),
    CONSTRAINT ck_cuenta_ahorro_2 CHECK (saldo_disponible >= 0)
);
COMMENT ON TABLE cuentas.cuenta_ahorro IS 'Cuenta de ahorros individual o mancomunada; reemplaza a cuenta_ref de TARJETAS.';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.movimiento (
    uuid_transaccion            UUID DEFAULT gen_random_uuid(),
    tipo_operacion              VARCHAR(25) NOT NULL,
    monto                       NUMERIC(15,2) NOT NULL,
    glosa                       VARCHAR(200) NOT NULL,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    estado_transaccion          VARCHAR(25) NOT NULL
        CHECK (estado_transaccion IN ('APROBADO', 'EXTORNADO')),
    id_asiento                  UUID NOT NULL,
    num_cuenta                  VARCHAR(20) NOT NULL,
    id_canal                    VARCHAR(5),
    CONSTRAINT pk_movimiento PRIMARY KEY (uuid_transaccion),
    CONSTRAINT uk_movimiento_1 UNIQUE (id_asiento),
    CONSTRAINT ck_movimiento_1 CHECK (monto > 0)
);
COMMENT ON TABLE cuentas.movimiento IS 'Débito o crédito aplicado a una cuenta (antes TRANSACCIONES_HISTORICO).';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.titularidad (
    cod_cliente                 VARCHAR(12),
    num_cuenta                  VARCHAR(20),
    fecha_vinculacion           TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT pk_titularidad PRIMARY KEY (cod_cliente, num_cuenta)
);
COMMENT ON TABLE cuentas.titularidad IS 'Titulares de cada cuenta (relación N:M ES_TITULAR).';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.tipo_operacion (
    tipo_operacion              VARCHAR(25),
    naturaleza                  CHAR(1) NOT NULL
        CHECK (naturaleza IN ('D', 'C', 'N')),
    CONSTRAINT pk_tipo_operacion PRIMARY KEY (tipo_operacion)
);
COMMENT ON TABLE cuentas.tipo_operacion IS 'Catálogo. Tabla creada en 3FN; ahora también la referencia AUTORIZACION.';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.regimen_cuenta (
    cod_regimen                 VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    min_titulares               SMALLINT NOT NULL,
    firma_conjunta              BOOLEAN NOT NULL,
    CONSTRAINT pk_regimen_cuenta PRIMARY KEY (cod_regimen),
    CONSTRAINT ck_regimen_cuenta_1 CHECK (min_titulares >= 1)
);
COMMENT ON TABLE cuentas.regimen_cuenta IS 'Catálogo. Indistinta (o) y conjunta (y) cambian la regla de autorización (RN-CTA-002).';

-- ---------------------------------------------------------------------
CREATE TABLE cuentas.estado_cuenta (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    permite_debito              BOOLEAN NOT NULL,
    permite_credito             BOOLEAN NOT NULL,
    CONSTRAINT pk_estado_cuenta PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE cuentas.estado_cuenta IS 'Catálogo. BLOQUEADA_PREVENTIVA impide débitos pero no abonos.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.tarjeta (
    id_tarjeta                  UUID DEFAULT gen_random_uuid(),
    pan_token                   VARCHAR(32) NOT NULL,
    bin                         CHAR(6) NOT NULL,
    ultimos4                    CHAR(4) NOT NULL,
    fecha_emision               DATE NOT NULL,
    fecha_vencimiento           DATE NOT NULL,
    estado_tarjeta              VARCHAR(25) NOT NULL,
    cod_cliente                 VARCHAR(12) NOT NULL,
    CONSTRAINT pk_tarjeta PRIMARY KEY (id_tarjeta),
    CONSTRAINT uk_tarjeta_1 UNIQUE (pan_token),
    CONSTRAINT ck_tarjeta_1 CHECK (fecha_vencimiento > fecha_emision),
    CONSTRAINT ck_tarjeta_2 CHECK (ultimos4 ~ '^[0-9]{4}$')
);
COMMENT ON TABLE tarjetas.tarjeta IS 'Tarjeta de débito física o virtual; no guarda el PAN completo (PCI-DSS).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.bin_tarjeta (
    bin                         CHAR(6),
    tipo_tarjeta                VARCHAR(25) NOT NULL
        CHECK (tipo_tarjeta IN ('FISICA', 'VIRTUAL')),
    descripcion                 VARCHAR(100) NOT NULL,
    CONSTRAINT pk_bin_tarjeta PRIMARY KEY (bin),
    CONSTRAINT ck_bin_tarjeta_1 CHECK (bin ~ '^[0-9]{6}$')
);
COMMENT ON TABLE tarjetas.bin_tarjeta IS 'BIN emitidos por el BNA y el tipo de tarjeta que identifican (3FN).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.tarjeta_cuenta (
    id_tarjeta                  UUID,
    num_cuenta                  VARCHAR(20),
    es_principal                BOOLEAN DEFAULT FALSE NOT NULL,
    habilitada_atm              BOOLEAN DEFAULT TRUE NOT NULL,
    fecha_vinculacion           TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT pk_tarjeta_cuenta PRIMARY KEY (id_tarjeta, num_cuenta)
);
COMMENT ON TABLE tarjetas.tarjeta_cuenta IS 'Cuentas que opera cada tarjeta (relación N:M VINCULA).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.credencial (
    id_tarjeta                  UUID,
    tipo_credencial             VARCHAR(15),
    hash_credencial             CHAR(64) NOT NULL,
    sal                         CHAR(32) NOT NULL,
    intentos_fallidos           SMALLINT DEFAULT 0 NOT NULL,
    fecha_creacion              TIMESTAMPTZ DEFAULT now() NOT NULL,
    fecha_ultimo_cambio         TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT pk_credencial PRIMARY KEY (id_tarjeta, tipo_credencial),
    CONSTRAINT ck_credencial_1 CHECK (tipo_credencial IN ('PIN_ATM', 'CLAVE_WEB')),
    CONSTRAINT ck_credencial_2 CHECK (intentos_fallidos BETWEEN 0 AND 3)
);
COMMENT ON TABLE tarjetas.credencial IS 'Clave de acceso de una tarjeta; se identifica por la tarjeta y su tipo.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.tipo_credencial (
    tipo_credencial             VARCHAR(15),
    longitud                    SMALLINT,
    CONSTRAINT pk_tipo_credencial PRIMARY KEY (tipo_credencial)
);
COMMENT ON TABLE tarjetas.tipo_credencial IS 'Catálogo. Tabla creada en 2FN; se amplía con TOKEN_MATRIZ, BIOMETRIA y TOKEN_PAGO.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.matriz_token (
    id_matriz                   UUID DEFAULT gen_random_uuid(),
    numero_serie                VARCHAR(20) NOT NULL,
    tipo_matriz                 VARCHAR(25) NOT NULL
        CHECK (tipo_matriz IN ('FISICA', 'VIRTUAL')),
    sal                         CHAR(32) NOT NULL,
    estado_matriz               VARCHAR(25) NOT NULL
        CHECK (estado_matriz IN ('ACTIVA', 'BLOQUEADA', 'REEMPLAZADA')),
    intentos_fallidos           SMALLINT DEFAULT 0 NOT NULL,
    fecha_emision               DATE NOT NULL,
    id_tarjeta                  UUID NOT NULL,
    CONSTRAINT pk_matriz_token PRIMARY KEY (id_matriz),
    CONSTRAINT uk_matriz_token_1 UNIQUE (numero_serie),
    CONSTRAINT ck_matriz_token_1 CHECK (intentos_fallidos BETWEEN 0 AND 3)
);
COMMENT ON TABLE tarjetas.matriz_token IS 'Tarjeta matriz de coordenadas A--G por 0--9 (RN-TAR-002).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.matriz_coordenada (
    id_matriz                   UUID,
    fila                        CHAR(1),
    columna                     SMALLINT,
    hash_valor                  CHAR(64) NOT NULL,
    CONSTRAINT pk_matriz_coordenada PRIMARY KEY (id_matriz, fila, columna),
    CONSTRAINT ck_matriz_coordenada_1 CHECK (fila BETWEEN 'A' AND 'G'),
    CONSTRAINT ck_matriz_coordenada_2 CHECK (columna BETWEEN 0 AND 9)
);
COMMENT ON TABLE tarjetas.matriz_coordenada IS 'Cada una de las 70 celdas de una tarjeta matriz.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.token_pago (
    id_token_pago               UUID DEFAULT gen_random_uuid(),
    valor_token                 VARCHAR(64) NOT NULL,
    proveedor_pasarela          VARCHAR(20) NOT NULL,
    estado_token                VARCHAR(25) NOT NULL
        CHECK (estado_token IN ('ACTIVO', 'SUSPENDIDO', 'REVOCADO')),
    fecha_creacion              TIMESTAMPTZ DEFAULT now() NOT NULL,
    fecha_expiracion            TIMESTAMPTZ NOT NULL,
    id_tarjeta                  UUID NOT NULL,
    CONSTRAINT pk_token_pago PRIMARY KEY (id_token_pago),
    CONSTRAINT uk_token_pago_1 UNIQUE (valor_token)
);
COMMENT ON TABLE tarjetas.token_pago IS 'Token entregado a una pasarela externa para el fondeo de la Billetera Digital.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.pasarela_pago (
    id_pasarela                 VARCHAR(20),
    nombre                      VARCHAR(100) NOT NULL,
    CONSTRAINT pk_pasarela_pago PRIMARY KEY (id_pasarela)
);
COMMENT ON TABLE tarjetas.pasarela_pago IS 'Catálogo. Punto abierto R-05 sobre la propiedad de las pasarelas.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.intento_autenticacion (
    id_intento                  BIGINT GENERATED ALWAYS AS IDENTITY,
    tipo_credencial             VARCHAR(15) NOT NULL,
    coord_fila                  CHAR(1),
    coord_columna               SMALLINT,
    id_terminal                 VARCHAR(30),
    ip_origen                   INET,
    resultado                   VARCHAR(25) NOT NULL
        CHECK (resultado IN ('EXITOSO', 'FALLIDO')),
    motivo_rechazo              VARCHAR(255),
    uuid_correlacion            UUID,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_tarjeta                  UUID NOT NULL,
    id_canal                    VARCHAR(5),
    CONSTRAINT pk_intento_autenticacion PRIMARY KEY (id_intento),
    CONSTRAINT ck_intento_autenticacion_1 CHECK (coord_fila IS NULL OR coord_fila BETWEEN 'A' AND 'G'),
    CONSTRAINT ck_intento_autenticacion_2 CHECK (coord_columna IS NULL OR coord_columna BETWEEN 0 AND 9),
    CONSTRAINT ck_intento_autenticacion_3 CHECK ((coord_fila IS NULL) = (coord_columna IS NULL)),
    CONSTRAINT ck_intento_autenticacion_4 CHECK ((coord_fila IS NOT NULL) = (tipo_credencial = 'TOKEN_MATRIZ')),
    CONSTRAINT ck_intento_autenticacion_5 CHECK (num_nonnulls(id_terminal, id_canal) = 1)
);
COMMENT ON TABLE tarjetas.intento_autenticacion IS 'Bitácora inmutable de cada intento de validar una credencial (RN-TAR-004).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.autorizacion (
    uuid_autorizacion           UUID DEFAULT gen_random_uuid(),
    tipo_operacion              VARCHAR(25) NOT NULL,
    monto                       NUMERIC(15,2) NOT NULL,
    estado_autorizacion         VARCHAR(25) NOT NULL
        CHECK (estado_autorizacion IN ('INICIADA', 'AUTORIZADA', 'RECHAZADA', 'DISPENSADA', 'EXTORNADA', 'PENDIENTE_REVERSION')),
    codigo_respuesta            VARCHAR(4),
    motivo_rechazo              VARCHAR(255),
    nivel_riesgo                VARCHAR(25)
        CHECK (nivel_riesgo IN ('BAJO', 'MEDIO', 'ALTO')),
    id_terminal                 VARCHAR(30),
    ip_origen                   INET,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    fecha_actualizacion         TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_tarjeta                  UUID NOT NULL,
    num_cuenta                  VARCHAR(20) NOT NULL,
    id_canal                    VARCHAR(5),
    uuid_transaccion            UUID,
    CONSTRAINT pk_autorizacion PRIMARY KEY (uuid_autorizacion),
    CONSTRAINT uk_autorizacion_1 UNIQUE (uuid_transaccion),
    CONSTRAINT ck_autorizacion_1 CHECK (monto >= 0),
    CONSTRAINT ck_autorizacion_2 CHECK (num_nonnulls(id_terminal, id_canal) = 1)
);
COMMENT ON TABLE tarjetas.autorizacion IS 'Autorización que TARJETAS emite antes de que la operación se contabilice.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.codigo_respuesta (
    cod_respuesta               VARCHAR(4),
    descripcion                 VARCHAR(255) NOT NULL,
    es_aprobacion               BOOLEAN NOT NULL,
    CONSTRAINT pk_codigo_respuesta PRIMARY KEY (cod_respuesta)
);
COMMENT ON TABLE tarjetas.codigo_respuesta IS 'Catálogo. 00 aprobado, 54 tarjeta vencida, EXT extorno.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.historial_estado_tarjeta (
    id_historial                BIGINT GENERATED ALWAYS AS IDENTITY,
    estado_nuevo                VARCHAR(25) NOT NULL,
    motivo                      VARCHAR(255),
    origen                      VARCHAR(20) NOT NULL,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_tarjeta                  UUID NOT NULL,
    CONSTRAINT pk_historial_estado_tarjeta PRIMARY KEY (id_historial)
);
COMMENT ON TABLE tarjetas.historial_estado_tarjeta IS 'Historial inmutable de cambios de estado de cada tarjeta (RN-SEG-002).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.estado_tarjeta (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    es_operativa                BOOLEAN NOT NULL,
    es_final                    BOOLEAN NOT NULL,
    CONSTRAINT pk_estado_tarjeta PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE tarjetas.estado_tarjeta IS 'Catálogo. Sustituye el cálculo de operativa de la vista v_tarjeta_resumen.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.origen_cambio (
    cod_origen                  VARCHAR(20),
    descripcion                 VARCHAR(255) NOT NULL,
    puede_desbloquear           BOOLEAN NOT NULL,
    CONSTRAINT pk_origen_cambio PRIMARY KEY (cod_origen)
);
COMMENT ON TABLE tarjetas.origen_cambio IS 'Catálogo. Solo OPERADOR y SEGURIDAD pueden desbloquear (RN-TAR-004).';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.evento_salida (
    id_evento                   BIGINT GENERATED ALWAYS AS IDENTITY,
    tipo_evento                 VARCHAR(30) NOT NULL,
    carga_json                  JSONB NOT NULL,
    estado_envio                VARCHAR(25) NOT NULL
        CHECK (estado_envio IN ('PENDIENTE', 'ENVIADO', 'ERROR')),
    fecha_registro              TIMESTAMPTZ DEFAULT now() NOT NULL,
    fecha_envio                 TIMESTAMPTZ,
    id_tarjeta                  UUID NOT NULL,
    CONSTRAINT pk_evento_salida PRIMARY KEY (id_evento)
);
COMMENT ON TABLE tarjetas.evento_salida IS 'Bandeja de eventos que el Bus entrega al log centralizado de SEGURIDAD.';

-- ---------------------------------------------------------------------
CREATE TABLE tarjetas.tipo_evento_salida (
    tipo_evento                 VARCHAR(30),
    descripcion                 VARCHAR(255) NOT NULL,
    id_modulo_destino           SMALLINT NOT NULL,
    CONSTRAINT pk_tipo_evento_salida PRIMARY KEY (tipo_evento)
);
COMMENT ON TABLE tarjetas.tipo_evento_salida IS 'Tipos de evento hacia otros módulos y su destino (3FN).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.solicitud_credito (
    id_solicitud                UUID DEFAULT gen_random_uuid(),
    version_solicitud           SMALLINT DEFAULT 1 NOT NULL,
    monto_solicitado            NUMERIC(15,2) NOT NULL,
    moneda                      CHAR(3) NOT NULL,
    plazo_meses                 SMALLINT NOT NULL,
    condicion_pago_doble        BOOLEAN DEFAULT FALSE NOT NULL,
    estado_solicitud            VARCHAR(25) NOT NULL,
    fecha_creacion              TIMESTAMPTZ DEFAULT now() NOT NULL,
    cod_cliente                 VARCHAR(12) NOT NULL,
    CONSTRAINT pk_solicitud_credito PRIMARY KEY (id_solicitud),
    CONSTRAINT ck_solicitud_credito_1 CHECK (monto_solicitado > 0),
    CONSTRAINT ck_solicitud_credito_2 CHECK (plazo_meses > 0)
);
COMMENT ON TABLE creditos.solicitud_credito IS 'Solicitud de crédito; reemplaza la réplica SOLICITUD_CREDITO de EVALUACIÓN.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.historial_estado_solicitud (
    id_historial                BIGINT GENERATED ALWAYS AS IDENTITY,
    estado_nuevo                VARCHAR(25) NOT NULL,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    actor                       VARCHAR(40) NOT NULL,
    motivo                      VARCHAR(255),
    id_solicitud                UUID NOT NULL,
    CONSTRAINT pk_historial_estado_solicitud PRIMARY KEY (id_historial)
);
COMMENT ON TABLE creditos.historial_estado_solicitud IS 'Registro de cada cambio de estado de una solicitud.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.estado_solicitud (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    es_final                    BOOLEAN NOT NULL,
    CONSTRAINT pk_estado_solicitud PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE creditos.estado_solicitud IS 'Catálogo. Dominio usado por la solicitud y por su historial.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.garantia (
    id_garantia                 UUID DEFAULT gen_random_uuid(),
    tipo_garantia               VARCHAR(20) NOT NULL,
    descripcion                 VARCHAR(255),
    valor_referencial           NUMERIC(15,2) NOT NULL,
    moneda                      CHAR(3) NOT NULL,
    estado_garantia             VARCHAR(25) NOT NULL
        CHECK (estado_garantia IN ('REGISTRADA', 'EN_TASACION', 'CONSTITUIDA', 'LEVANTADA')),
    id_solicitud                UUID NOT NULL,
    CONSTRAINT pk_garantia PRIMARY KEY (id_garantia),
    CONSTRAINT ck_garantia_1 CHECK (valor_referencial > 0)
);
COMMENT ON TABLE creditos.garantia IS 'Bien o instrumento que respalda una solicitud (RN-SOL-007).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.tipo_garantia (
    cod_tipo_garantia           VARCHAR(20),
    descripcion                 VARCHAR(255) NOT NULL,
    CONSTRAINT pk_tipo_garantia PRIMARY KEY (cod_tipo_garantia)
);
COMMENT ON TABLE creditos.tipo_garantia IS 'Catálogo. Lista abierta en la fuente (p. ej.).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.fiador (
    id_fiador                   UUID DEFAULT gen_random_uuid(),
    id_persona_externa          VARCHAR(36) NOT NULL,
    tipo_documento              VARCHAR(10) NOT NULL,
    numero_documento            VARCHAR(12) NOT NULL,
    CONSTRAINT pk_fiador PRIMARY KEY (id_fiador),
    CONSTRAINT uk_fiador_1 UNIQUE (id_persona_externa),
    CONSTRAINT uk_fiador_2 UNIQUE (tipo_documento, numero_documento)
);
COMMENT ON TABLE creditos.fiador IS 'Persona externa que respalda solicitudes de crédito (antes FIADOR_REF).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.fiador_solicitud (
    id_fiador                   UUID,
    id_solicitud                UUID,
    id_verificacion             VARCHAR(36) NOT NULL,
    CONSTRAINT pk_fiador_solicitud PRIMARY KEY (id_fiador, id_solicitud),
    CONSTRAINT uk_fiador_solicitud_1 UNIQUE (id_verificacion)
);
COMMENT ON TABLE creditos.fiador_solicitud IS 'Fiadores que respaldan cada solicitud (relación N:M RESPALDA).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.calendario_pago (
    id_calendario               UUID DEFAULT gen_random_uuid(),
    version                     SMALLINT NOT NULL,
    tipo_calendario             VARCHAR(25) NOT NULL
        CHECK (tipo_calendario IN ('PRELIMINAR', 'OFICIAL')),
    metodo_amortizacion         VARCHAR(20) NOT NULL,
    tasa_aplicada               NUMERIC(7,4) NOT NULL,
    fecha_generacion            TIMESTAMPTZ DEFAULT now() NOT NULL,
    estado_calendario           VARCHAR(25) NOT NULL
        CHECK (estado_calendario IN ('VIGENTE', 'HISTORICO', 'DESCARTADO')),
    id_solicitud                UUID NOT NULL,
    CONSTRAINT pk_calendario_pago PRIMARY KEY (id_calendario),
    CONSTRAINT uk_calendario_pago_1 UNIQUE (id_solicitud, version),
    CONSTRAINT ck_calendario_pago_1 CHECK (tasa_aplicada >= 0)
);
COMMENT ON TABLE creditos.calendario_pago IS 'Versión del calendario de pagos de una solicitud: PRELIMINAR (simulación) u OFICIAL.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.metodo_amortizacion (
    cod_metodo                  VARCHAR(20),
    descripcion                 VARCHAR(255) NOT NULL,
    CONSTRAINT pk_metodo_amortizacion PRIMARY KEY (cod_metodo)
);
COMMENT ON TABLE creditos.metodo_amortizacion IS 'Catálogo. Lista abierta en la fuente (p. ej.).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.cuota (
    id_calendario               UUID,
    numero_cuota                SMALLINT,
    fecha_vencimiento           DATE NOT NULL,
    capital                     NUMERIC(15,2) NOT NULL,
    interes                     NUMERIC(15,2) NOT NULL,
    otros_conceptos             NUMERIC(15,2) DEFAULT 0 NOT NULL,
    saldo_capital               NUMERIC(15,2) NOT NULL,
    saldo_pendiente             NUMERIC(15,2) NOT NULL,
    estado_cuota                VARCHAR(25) NOT NULL,
    CONSTRAINT pk_cuota PRIMARY KEY (id_calendario, numero_cuota),
    CONSTRAINT ck_cuota_1 CHECK (numero_cuota > 0),
    CONSTRAINT ck_cuota_2 CHECK (capital >= 0),
    CONSTRAINT ck_cuota_3 CHECK (interes >= 0),
    CONSTRAINT ck_cuota_4 CHECK (otros_conceptos >= 0),
    CONSTRAINT ck_cuota_5 CHECK (saldo_pendiente >= 0)
);
COMMENT ON TABLE creditos.cuota IS 'Cuota del calendario; unifica la CUOTA de SOLICITUD con la de COBRANZA.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.estado_cuota (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    CONSTRAINT pk_estado_cuota PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE creditos.estado_cuota IS 'Catálogo. Catálogo pendiente de aprobación según COBRANZA.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.situacion_financiera (
    id_consulta                 UUID DEFAULT gen_random_uuid(),
    resultado_verificacion      VARCHAR(20) NOT NULL,
    ingreso_mensual             NUMERIC(15,2) NOT NULL,
    deuda_reportada             NUMERIC(15,2) NOT NULL,
    fecha_consulta              TIMESTAMPTZ DEFAULT now() NOT NULL,
    cod_cliente                 VARCHAR(12) NOT NULL,
    CONSTRAINT pk_situacion_financiera PRIMARY KEY (id_consulta)
);
COMMENT ON TABLE creditos.situacion_financiera IS 'Resultado de la verificación financiera del cliente, insumo del score.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.evaluacion (
    id_evaluacion               UUID DEFAULT gen_random_uuid(),
    ronda                       SMALLINT NOT NULL,
    fecha_evaluacion            TIMESTAMPTZ DEFAULT now() NOT NULL,
    score_calculado             NUMERIC(6,2) NOT NULL,
    limite_aprobado             NUMERIC(15,2) NOT NULL,
    condiciones_propuestas      VARCHAR(300),
    observaciones               VARCHAR(500),
    id_solicitud                UUID NOT NULL,
    id_consulta                 UUID NOT NULL,
    id_regla                    VARCHAR(10) NOT NULL,
    id_analista                 VARCHAR(10),
    CONSTRAINT pk_evaluacion PRIMARY KEY (id_evaluacion),
    CONSTRAINT uk_evaluacion_1 UNIQUE (id_solicitud, ronda),
    CONSTRAINT ck_evaluacion_1 CHECK (limite_aprobado >= 0)
);
COMMENT ON TABLE creditos.evaluacion IS 'Evaluación crediticia de una solicitud; unifica EVALUACION y RESULTADO_EVALUACION.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.regla_evaluacion (
    id_regla                    VARCHAR(10),
    codigo_rn                   VARCHAR(20) NOT NULL,
    descripcion                 VARCHAR(255) NOT NULL,
    ratio_min                   NUMERIC(7,2),
    ratio_max                   NUMERIC(7,2),
    accion                      VARCHAR(12) NOT NULL,
    CONSTRAINT pk_regla_evaluacion PRIMARY KEY (id_regla),
    CONSTRAINT uk_regla_evaluacion_1 UNIQUE (codigo_rn),
    CONSTRAINT uk_regla_evaluacion_2 UNIQUE (ratio_min, ratio_max),
    CONSTRAINT ck_regla_evaluacion_1 CHECK (ratio_min IS NULL OR ratio_max IS NULL OR ratio_min < ratio_max)
);
COMMENT ON TABLE creditos.regla_evaluacion IS 'Regla de decisión por tramo del ratio monto/límite (RN-EVA-002-P).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.resultado_crediticio (
    cod_resultado               VARCHAR(12),
    descripcion                 VARCHAR(255) NOT NULL,
    CONSTRAINT pk_resultado_crediticio PRIMARY KEY (cod_resultado)
);
COMMENT ON TABLE creditos.resultado_crediticio IS 'Catálogo. APROBADO, OBSERVADO y RECHAZADO son el dominio oficial del Diccionario de Reglas.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.analista (
    id_analista                 VARCHAR(10),
    nombre                      VARCHAR(100) NOT NULL,
    codigo_empleado             VARCHAR(20) NOT NULL,
    CONSTRAINT pk_analista PRIMARY KEY (id_analista),
    CONSTRAINT uk_analista_1 UNIQUE (codigo_empleado)
);
COMMENT ON TABLE creditos.analista IS 'Analista de crédito habilitado para la revisión manual.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.decision_analista (
    id_decision                 UUID DEFAULT gen_random_uuid(),
    decision                    VARCHAR(12) NOT NULL,
    comentario                  VARCHAR(500) NOT NULL,
    fecha_decision              TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_evaluacion               UUID NOT NULL,
    CONSTRAINT pk_decision_analista PRIMARY KEY (id_decision),
    CONSTRAINT uk_decision_analista_1 UNIQUE (id_evaluacion)
);
COMMENT ON TABLE creditos.decision_analista IS 'Decisión final de un analista sobre una evaluación OBSERVADA (RN-EVA-004).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.orden_desembolso (
    id_orden                    UUID DEFAULT gen_random_uuid(),
    codigo_orden                VARCHAR(24) NOT NULL,
    importe                     NUMERIC(15,2) NOT NULL,
    estado_orden                VARCHAR(25) NOT NULL,
    motivo_rechazo              VARCHAR(255),
    idempotency_key             UUID NOT NULL,
    request_hash                CHAR(64) NOT NULL,
    usuario_preparacion         VARCHAR(40) NOT NULL,
    usuario_confirmacion        VARCHAR(40),
    correlation_id              UUID NOT NULL,
    version_registro            INTEGER DEFAULT 0 NOT NULL,
    creado_en                   TIMESTAMPTZ DEFAULT now() NOT NULL,
    actualizado_en              TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_evaluacion               UUID NOT NULL,
    num_cuenta                  VARCHAR(20) NOT NULL,
    id_canal                    VARCHAR(5) NOT NULL,
    id_agencia                  VARCHAR(10),
    uuid_transaccion_abono      UUID,
    CONSTRAINT pk_orden_desembolso PRIMARY KEY (id_orden),
    CONSTRAINT uk_orden_desembolso_1 UNIQUE (codigo_orden),
    CONSTRAINT uk_orden_desembolso_2 UNIQUE (idempotency_key),
    CONSTRAINT uk_orden_desembolso_3 UNIQUE (uuid_transaccion_abono),
    CONSTRAINT ck_orden_desembolso_1 CHECK (importe > 0)
);
COMMENT ON TABLE creditos.orden_desembolso IS 'Intención, ejecución y resultado de un desembolso (antes des_orden).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.estado_orden (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    es_final                    BOOLEAN NOT NULL,
    CONSTRAINT pk_estado_orden PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE creditos.estado_orden IS 'Catálogo. Base para la tabla de transiciones válidas (figura 2 de DESEMBOLSO).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.validacion_desembolso (
    id_validacion               UUID DEFAULT gen_random_uuid(),
    tipo_validacion             VARCHAR(15) NOT NULL,
    referencia_evidencia        VARCHAR(100) NOT NULL,
    resultado                   VARCHAR(25) NOT NULL
        CHECK (resultado IN ('APROBADA', 'RECHAZADA')),
    detalle                     VARCHAR(255),
    vence_en                    TIMESTAMPTZ,
    creado_en                   TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_orden                    UUID NOT NULL,
    CONSTRAINT pk_validacion_desembolso PRIMARY KEY (id_validacion)
);
COMMENT ON TABLE creditos.validacion_desembolso IS 'Evidencia de cada validación previa a la ejecución de la orden.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.tipo_validacion_desembolso (
    tipo_validacion             VARCHAR(15),
    descripcion                 VARCHAR(255) NOT NULL,
    id_modulo_proveedor         SMALLINT NOT NULL,
    CONSTRAINT pk_tipo_validacion_desembolso PRIMARY KEY (tipo_validacion)
);
COMMENT ON TABLE creditos.tipo_validacion_desembolso IS 'Tipos de validación previa al desembolso y su proveedor (3FN).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.evento_entrega (
    id_evento                   BIGINT GENERATED ALWAYS AS IDENTITY,
    tipo_evento                 VARCHAR(60) NOT NULL
        CHECK (tipo_evento IN ('desembolso.confirmado', 'desembolso.revertido')),
    version_esquema             VARCHAR(10) NOT NULL,
    payload                     JSONB NOT NULL,
    estado_entrega              VARCHAR(25) NOT NULL
        CHECK (estado_entrega IN ('PENDIENTE', 'ENVIADO', 'CONFIRMADO', 'FALLIDO')),
    intentos                    SMALLINT DEFAULT 0 NOT NULL,
    siguiente_intento           TIMESTAMPTZ,
    confirmacion_id             VARCHAR(60),
    ultimo_error                VARCHAR(255),
    creado_en                   TIMESTAMPTZ DEFAULT now() NOT NULL,
    actualizado_en              TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_orden                    UUID NOT NULL,
    CONSTRAINT pk_evento_entrega PRIMARY KEY (id_evento)
);
COMMENT ON TABLE creditos.evento_entrega IS 'Bandeja de salida hacia Cobranza con reintentos.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.solicitud_reversion (
    id_reversion                UUID DEFAULT gen_random_uuid(),
    motivo                      VARCHAR(255) NOT NULL,
    solicitante_id              VARCHAR(40) NOT NULL,
    autorizacion_id             VARCHAR(60),
    estado_reversion            VARCHAR(25) NOT NULL
        CHECK (estado_reversion IN ('SOLICITADA', 'AUTORIZADA', 'CONFIRMADA', 'RECHAZADA')),
    idempotency_key             UUID NOT NULL,
    creado_en                   TIMESTAMPTZ DEFAULT now() NOT NULL,
    actualizado_en              TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_orden                    UUID NOT NULL,
    uuid_transaccion_extorno    UUID,
    CONSTRAINT pk_solicitud_reversion PRIMARY KEY (id_reversion),
    CONSTRAINT uk_solicitud_reversion_1 UNIQUE (idempotency_key),
    CONSTRAINT uk_solicitud_reversion_2 UNIQUE (uuid_transaccion_extorno)
);
COMMENT ON TABLE creditos.solicitud_reversion IS 'Solicitud de reversión de un desembolso; preparada pero sin uso en la Fase I.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.credito (
    cod_credito                 VARCHAR(20),
    estado_credito              VARCHAR(25) NOT NULL,
    id_orden                    UUID NOT NULL,
    id_calendario               UUID NOT NULL,
    CONSTRAINT pk_credito PRIMARY KEY (cod_credito),
    CONSTRAINT uk_credito_1 UNIQUE (id_orden),
    CONSTRAINT uk_credito_2 UNIQUE (id_calendario)
);
COMMENT ON TABLE creditos.credito IS 'Préstamo ya desembolsado que debe cobrarse (RF-COB-015).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.estado_credito (
    cod_estado                  VARCHAR(25),
    descripcion                 VARCHAR(255) NOT NULL,
    CONSTRAINT pk_estado_credito PRIMARY KEY (cod_estado)
);
COMMENT ON TABLE creditos.estado_credito IS 'Catálogo. Catálogo pendiente de aprobación según COBRANZA.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.pago (
    id_pago                     UUID DEFAULT gen_random_uuid(),
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    monto_pago                  NUMERIC(15,2) NOT NULL,
    referencia_transaccion      VARCHAR(40) NOT NULL,
    estado_confirmacion         VARCHAR(25) NOT NULL
        CHECK (estado_confirmacion IN ('PENDIENTE', 'CONFIRMADO', 'RECHAZADO')),
    cod_credito                 VARCHAR(20) NOT NULL,
    id_canal                    VARCHAR(5) NOT NULL,
    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT uk_pago_1 UNIQUE (referencia_transaccion),
    CONSTRAINT ck_pago_1 CHECK (monto_pago > 0)
);
COMMENT ON TABLE creditos.pago IS 'Evento de pago realizado por el cliente.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.aplicacion_pago (
    id_pago                     UUID,
    id_calendario               UUID,
    numero_cuota                SMALLINT,
    monto_aplicado              NUMERIC(15,2) NOT NULL,
    CONSTRAINT pk_aplicacion_pago PRIMARY KEY (id_pago, id_calendario, numero_cuota),
    CONSTRAINT ck_aplicacion_pago_1 CHECK (monto_aplicado > 0)
);
COMMENT ON TABLE creditos.aplicacion_pago IS 'Reparto de cada pago entre cuotas (relación N:M APLICA).';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.mora (
    id_mora                     UUID DEFAULT gen_random_uuid(),
    monto_calculado             NUMERIC(15,2) NOT NULL,
    fecha_calculo               TIMESTAMPTZ DEFAULT now() NOT NULL,
    id_calendario               UUID NOT NULL,
    numero_cuota                SMALLINT NOT NULL,
    CONSTRAINT pk_mora PRIMARY KEY (id_mora),
    CONSTRAINT uk_mora_1 UNIQUE (id_calendario, numero_cuota, fecha_calculo),
    CONSTRAINT ck_mora_1 CHECK (monto_calculado >= 0)
);
COMMENT ON TABLE creditos.mora IS 'Cada cálculo de interés moratorio que el CORE realiza para una cuota atrasada.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.evento_auditoria (
    id_evento                   BIGINT GENERATED ALWAYS AS IDENTITY,
    modulo_emisor               SMALLINT NOT NULL,
    id_entidad                  VARCHAR(36),
    numero_cuota                SMALLINT,
    accion                      VARCHAR(60) NOT NULL,
    resultado                   VARCHAR(40),
    actor                       VARCHAR(40) NOT NULL,
    correlation_id              UUID NOT NULL,
    ip_origen                   INET,
    detalle                     JSONB,
    fecha_hora                  TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT pk_evento_auditoria PRIMARY KEY (id_evento),
    CONSTRAINT ck_evento_auditoria_1 CHECK (numero_cuota IS NULL OR id_entidad IS NOT NULL)
);
COMMENT ON TABLE creditos.evento_auditoria IS 'Bitácora de solo inserción; unifica des_auditoria y EVENTO_AUDITORIA de COBRANZA.';

-- ---------------------------------------------------------------------
CREATE TABLE creditos.entidad_auditada (
    id_entidad                  VARCHAR(36),
    tipo_entidad                VARCHAR(25) NOT NULL
        CHECK (tipo_entidad IN ('ORDEN', 'CREDITO', 'PAGO', 'CUOTA')),
    CONSTRAINT pk_entidad_auditada PRIMARY KEY (id_entidad)
);
COMMENT ON TABLE creditos.entidad_auditada IS 'Registros auditables y su tipo (3FN).';

-- =====================================================================
-- Claves foráneas
-- =====================================================================
ALTER TABLE core.cuenta_contable ADD CONSTRAINT fk_cuenta_contable_1 FOREIGN KEY (codigo_padre)
    REFERENCES core.cuenta_contable (codigo_contable);
ALTER TABLE core.asiento_contable ADD CONSTRAINT fk_asiento_contable_1 FOREIGN KEY (moneda)
    REFERENCES core.moneda (cod_moneda);
ALTER TABLE core.asiento_contable ADD CONSTRAINT fk_asiento_contable_2 FOREIGN KEY (id_asiento_revertido)
    REFERENCES core.asiento_contable (id_asiento);
ALTER TABLE core.detalle_asiento ADD CONSTRAINT fk_detalle_asiento_1 FOREIGN KEY (id_asiento)
    REFERENCES core.asiento_contable (id_asiento);
ALTER TABLE core.detalle_asiento ADD CONSTRAINT fk_detalle_asiento_2 FOREIGN KEY (codigo_contable)
    REFERENCES core.cuenta_contable (codigo_contable);
ALTER TABLE core.canal_validacion ADD CONSTRAINT fk_canal_validacion_1 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE core.canal_validacion ADD CONSTRAINT fk_canal_validacion_2 FOREIGN KEY (tipo_validacion)
    REFERENCES tarjetas.tipo_credencial (tipo_credencial);
ALTER TABLE core.limite_canal ADD CONSTRAINT fk_limite_canal_1 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE core.limite_canal ADD CONSTRAINT fk_limite_canal_2 FOREIGN KEY (moneda)
    REFERENCES core.moneda (cod_moneda);
ALTER TABLE core.consumo_diario ADD CONSTRAINT fk_consumo_diario_1 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE core.consumo_diario ADD CONSTRAINT fk_consumo_diario_2 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE core.terminal ADD CONSTRAINT fk_terminal_1 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE core.terminal ADD CONSTRAINT fk_terminal_2 FOREIGN KEY (id_agencia)
    REFERENCES core.agencia (id_agencia);
ALTER TABLE clientes.cliente ADD CONSTRAINT fk_cliente_1 FOREIGN KEY (tipo_documento)
    REFERENCES clientes.tipo_documento (cod_tipo_documento);
ALTER TABLE clientes.cliente ADD CONSTRAINT fk_cliente_2 FOREIGN KEY (estado_cliente)
    REFERENCES clientes.estado_cliente (cod_estado);
ALTER TABLE clientes.cliente ADD CONSTRAINT fk_cliente_3 FOREIGN KEY (id_verificacion_captacion)
    REFERENCES clientes.verificacion_captacion (id_verificacion_captacion);
ALTER TABLE clientes.biometria_cliente ADD CONSTRAINT fk_biometria_cliente_1 FOREIGN KEY (tipo_biometria)
    REFERENCES clientes.tipo_biometria (cod_tipo_biometria);
ALTER TABLE clientes.biometria_cliente ADD CONSTRAINT fk_biometria_cliente_2 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE clientes.codigo_verificacion ADD CONSTRAINT fk_codigo_verificacion_1 FOREIGN KEY (tipo_contacto)
    REFERENCES clientes.tipo_contacto (cod_tipo_contacto);
ALTER TABLE clientes.codigo_verificacion ADD CONSTRAINT fk_codigo_verificacion_2 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE clientes.validacion_identidad ADD CONSTRAINT fk_validacion_identidad_1 FOREIGN KEY (tipo_validacion)
    REFERENCES clientes.tipo_validacion (cod_tipo_validacion);
ALTER TABLE clientes.validacion_identidad ADD CONSTRAINT fk_validacion_identidad_2 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE cuentas.cuenta_ahorro ADD CONSTRAINT fk_cuenta_ahorro_1 FOREIGN KEY (moneda)
    REFERENCES core.moneda (cod_moneda);
ALTER TABLE cuentas.cuenta_ahorro ADD CONSTRAINT fk_cuenta_ahorro_2 FOREIGN KEY (regimen)
    REFERENCES cuentas.regimen_cuenta (cod_regimen);
ALTER TABLE cuentas.cuenta_ahorro ADD CONSTRAINT fk_cuenta_ahorro_3 FOREIGN KEY (estado_cuenta)
    REFERENCES cuentas.estado_cuenta (cod_estado);
ALTER TABLE cuentas.cuenta_ahorro ADD CONSTRAINT fk_cuenta_ahorro_4 FOREIGN KEY (id_agencia)
    REFERENCES core.agencia (id_agencia);
ALTER TABLE cuentas.movimiento ADD CONSTRAINT fk_movimiento_1 FOREIGN KEY (tipo_operacion)
    REFERENCES cuentas.tipo_operacion (tipo_operacion);
ALTER TABLE cuentas.movimiento ADD CONSTRAINT fk_movimiento_2 FOREIGN KEY (id_asiento)
    REFERENCES core.asiento_contable (id_asiento);
ALTER TABLE cuentas.movimiento ADD CONSTRAINT fk_movimiento_3 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE cuentas.movimiento ADD CONSTRAINT fk_movimiento_4 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE cuentas.titularidad ADD CONSTRAINT fk_titularidad_1 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE cuentas.titularidad ADD CONSTRAINT fk_titularidad_2 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE tarjetas.tarjeta ADD CONSTRAINT fk_tarjeta_1 FOREIGN KEY (bin)
    REFERENCES tarjetas.bin_tarjeta (bin);
ALTER TABLE tarjetas.tarjeta ADD CONSTRAINT fk_tarjeta_2 FOREIGN KEY (estado_tarjeta)
    REFERENCES tarjetas.estado_tarjeta (cod_estado);
ALTER TABLE tarjetas.tarjeta ADD CONSTRAINT fk_tarjeta_3 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE tarjetas.tarjeta_cuenta ADD CONSTRAINT fk_tarjeta_cuenta_1 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.tarjeta_cuenta ADD CONSTRAINT fk_tarjeta_cuenta_2 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE tarjetas.credencial ADD CONSTRAINT fk_credencial_1 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.credencial ADD CONSTRAINT fk_credencial_2 FOREIGN KEY (tipo_credencial)
    REFERENCES tarjetas.tipo_credencial (tipo_credencial);
ALTER TABLE tarjetas.matriz_token ADD CONSTRAINT fk_matriz_token_1 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.matriz_coordenada ADD CONSTRAINT fk_matriz_coordenada_1 FOREIGN KEY (id_matriz)
    REFERENCES tarjetas.matriz_token (id_matriz);
ALTER TABLE tarjetas.token_pago ADD CONSTRAINT fk_token_pago_1 FOREIGN KEY (proveedor_pasarela)
    REFERENCES tarjetas.pasarela_pago (id_pasarela);
ALTER TABLE tarjetas.token_pago ADD CONSTRAINT fk_token_pago_2 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.intento_autenticacion ADD CONSTRAINT fk_intento_autenticacion_1 FOREIGN KEY (tipo_credencial)
    REFERENCES tarjetas.tipo_credencial (tipo_credencial);
ALTER TABLE tarjetas.intento_autenticacion ADD CONSTRAINT fk_intento_autenticacion_2 FOREIGN KEY (id_terminal)
    REFERENCES core.terminal (id_terminal);
ALTER TABLE tarjetas.intento_autenticacion ADD CONSTRAINT fk_intento_autenticacion_3 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.intento_autenticacion ADD CONSTRAINT fk_intento_autenticacion_4 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_1 FOREIGN KEY (tipo_operacion)
    REFERENCES cuentas.tipo_operacion (tipo_operacion);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_2 FOREIGN KEY (codigo_respuesta)
    REFERENCES tarjetas.codigo_respuesta (cod_respuesta);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_3 FOREIGN KEY (id_terminal)
    REFERENCES core.terminal (id_terminal);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_4 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_5 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_6 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_7 FOREIGN KEY (uuid_transaccion)
    REFERENCES cuentas.movimiento (uuid_transaccion);
ALTER TABLE tarjetas.historial_estado_tarjeta ADD CONSTRAINT fk_historial_estado_tarjeta_1 FOREIGN KEY (estado_nuevo)
    REFERENCES tarjetas.estado_tarjeta (cod_estado);
ALTER TABLE tarjetas.historial_estado_tarjeta ADD CONSTRAINT fk_historial_estado_tarjeta_2 FOREIGN KEY (origen)
    REFERENCES tarjetas.origen_cambio (cod_origen);
ALTER TABLE tarjetas.historial_estado_tarjeta ADD CONSTRAINT fk_historial_estado_tarjeta_3 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.evento_salida ADD CONSTRAINT fk_evento_salida_1 FOREIGN KEY (tipo_evento)
    REFERENCES tarjetas.tipo_evento_salida (tipo_evento);
ALTER TABLE tarjetas.evento_salida ADD CONSTRAINT fk_evento_salida_2 FOREIGN KEY (id_tarjeta)
    REFERENCES tarjetas.tarjeta (id_tarjeta);
ALTER TABLE tarjetas.tipo_evento_salida ADD CONSTRAINT fk_tipo_evento_salida_1 FOREIGN KEY (id_modulo_destino)
    REFERENCES core.modulo (id_modulo);
ALTER TABLE creditos.solicitud_credito ADD CONSTRAINT fk_solicitud_credito_1 FOREIGN KEY (moneda)
    REFERENCES core.moneda (cod_moneda);
ALTER TABLE creditos.solicitud_credito ADD CONSTRAINT fk_solicitud_credito_2 FOREIGN KEY (estado_solicitud)
    REFERENCES creditos.estado_solicitud (cod_estado);
ALTER TABLE creditos.solicitud_credito ADD CONSTRAINT fk_solicitud_credito_3 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE creditos.historial_estado_solicitud ADD CONSTRAINT fk_historial_estado_solicitud_1 FOREIGN KEY (estado_nuevo)
    REFERENCES creditos.estado_solicitud (cod_estado);
ALTER TABLE creditos.historial_estado_solicitud ADD CONSTRAINT fk_historial_estado_solicitud_2 FOREIGN KEY (id_solicitud)
    REFERENCES creditos.solicitud_credito (id_solicitud);
ALTER TABLE creditos.garantia ADD CONSTRAINT fk_garantia_1 FOREIGN KEY (tipo_garantia)
    REFERENCES creditos.tipo_garantia (cod_tipo_garantia);
ALTER TABLE creditos.garantia ADD CONSTRAINT fk_garantia_2 FOREIGN KEY (moneda)
    REFERENCES core.moneda (cod_moneda);
ALTER TABLE creditos.garantia ADD CONSTRAINT fk_garantia_3 FOREIGN KEY (id_solicitud)
    REFERENCES creditos.solicitud_credito (id_solicitud);
ALTER TABLE creditos.fiador ADD CONSTRAINT fk_fiador_1 FOREIGN KEY (tipo_documento)
    REFERENCES clientes.tipo_documento (cod_tipo_documento);
ALTER TABLE creditos.fiador_solicitud ADD CONSTRAINT fk_fiador_solicitud_1 FOREIGN KEY (id_fiador)
    REFERENCES creditos.fiador (id_fiador);
ALTER TABLE creditos.fiador_solicitud ADD CONSTRAINT fk_fiador_solicitud_2 FOREIGN KEY (id_solicitud)
    REFERENCES creditos.solicitud_credito (id_solicitud);
ALTER TABLE creditos.calendario_pago ADD CONSTRAINT fk_calendario_pago_1 FOREIGN KEY (metodo_amortizacion)
    REFERENCES creditos.metodo_amortizacion (cod_metodo);
ALTER TABLE creditos.calendario_pago ADD CONSTRAINT fk_calendario_pago_2 FOREIGN KEY (id_solicitud)
    REFERENCES creditos.solicitud_credito (id_solicitud);
ALTER TABLE creditos.cuota ADD CONSTRAINT fk_cuota_1 FOREIGN KEY (id_calendario)
    REFERENCES creditos.calendario_pago (id_calendario);
ALTER TABLE creditos.cuota ADD CONSTRAINT fk_cuota_2 FOREIGN KEY (estado_cuota)
    REFERENCES creditos.estado_cuota (cod_estado);
ALTER TABLE creditos.situacion_financiera ADD CONSTRAINT fk_situacion_financiera_1 FOREIGN KEY (cod_cliente)
    REFERENCES clientes.cliente (cod_cliente);
ALTER TABLE creditos.evaluacion ADD CONSTRAINT fk_evaluacion_1 FOREIGN KEY (id_solicitud)
    REFERENCES creditos.solicitud_credito (id_solicitud);
ALTER TABLE creditos.evaluacion ADD CONSTRAINT fk_evaluacion_2 FOREIGN KEY (id_consulta)
    REFERENCES creditos.situacion_financiera (id_consulta);
ALTER TABLE creditos.evaluacion ADD CONSTRAINT fk_evaluacion_3 FOREIGN KEY (id_regla)
    REFERENCES creditos.regla_evaluacion (id_regla);
ALTER TABLE creditos.evaluacion ADD CONSTRAINT fk_evaluacion_4 FOREIGN KEY (id_analista)
    REFERENCES creditos.analista (id_analista);
ALTER TABLE creditos.regla_evaluacion ADD CONSTRAINT fk_regla_evaluacion_1 FOREIGN KEY (accion)
    REFERENCES creditos.resultado_crediticio (cod_resultado);
ALTER TABLE creditos.decision_analista ADD CONSTRAINT fk_decision_analista_1 FOREIGN KEY (decision)
    REFERENCES creditos.resultado_crediticio (cod_resultado);
ALTER TABLE creditos.decision_analista ADD CONSTRAINT fk_decision_analista_2 FOREIGN KEY (id_evaluacion)
    REFERENCES creditos.evaluacion (id_evaluacion);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_1 FOREIGN KEY (estado_orden)
    REFERENCES creditos.estado_orden (cod_estado);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_2 FOREIGN KEY (id_evaluacion)
    REFERENCES creditos.evaluacion (id_evaluacion);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_3 FOREIGN KEY (num_cuenta)
    REFERENCES cuentas.cuenta_ahorro (num_cuenta);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_4 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_5 FOREIGN KEY (id_agencia)
    REFERENCES core.agencia (id_agencia);
ALTER TABLE creditos.orden_desembolso ADD CONSTRAINT fk_orden_desembolso_6 FOREIGN KEY (uuid_transaccion_abono)
    REFERENCES cuentas.movimiento (uuid_transaccion);
ALTER TABLE creditos.validacion_desembolso ADD CONSTRAINT fk_validacion_desembolso_1 FOREIGN KEY (tipo_validacion)
    REFERENCES creditos.tipo_validacion_desembolso (tipo_validacion);
ALTER TABLE creditos.validacion_desembolso ADD CONSTRAINT fk_validacion_desembolso_2 FOREIGN KEY (id_orden)
    REFERENCES creditos.orden_desembolso (id_orden);
ALTER TABLE creditos.tipo_validacion_desembolso ADD CONSTRAINT fk_tipo_validacion_desembolso_1 FOREIGN KEY (id_modulo_proveedor)
    REFERENCES core.modulo (id_modulo);
ALTER TABLE creditos.evento_entrega ADD CONSTRAINT fk_evento_entrega_1 FOREIGN KEY (id_orden)
    REFERENCES creditos.orden_desembolso (id_orden);
ALTER TABLE creditos.solicitud_reversion ADD CONSTRAINT fk_solicitud_reversion_1 FOREIGN KEY (id_orden)
    REFERENCES creditos.orden_desembolso (id_orden);
ALTER TABLE creditos.solicitud_reversion ADD CONSTRAINT fk_solicitud_reversion_2 FOREIGN KEY (uuid_transaccion_extorno)
    REFERENCES cuentas.movimiento (uuid_transaccion);
ALTER TABLE creditos.credito ADD CONSTRAINT fk_credito_1 FOREIGN KEY (estado_credito)
    REFERENCES creditos.estado_credito (cod_estado);
ALTER TABLE creditos.credito ADD CONSTRAINT fk_credito_2 FOREIGN KEY (id_orden)
    REFERENCES creditos.orden_desembolso (id_orden);
ALTER TABLE creditos.credito ADD CONSTRAINT fk_credito_3 FOREIGN KEY (id_calendario)
    REFERENCES creditos.calendario_pago (id_calendario);
ALTER TABLE creditos.pago ADD CONSTRAINT fk_pago_1 FOREIGN KEY (cod_credito)
    REFERENCES creditos.credito (cod_credito);
ALTER TABLE creditos.pago ADD CONSTRAINT fk_pago_2 FOREIGN KEY (id_canal)
    REFERENCES core.canal (id_canal);
ALTER TABLE creditos.aplicacion_pago ADD CONSTRAINT fk_aplicacion_pago_1 FOREIGN KEY (id_pago)
    REFERENCES creditos.pago (id_pago);
ALTER TABLE creditos.aplicacion_pago ADD CONSTRAINT fk_aplicacion_pago_2 FOREIGN KEY (id_calendario, numero_cuota)
    REFERENCES creditos.cuota (id_calendario, numero_cuota);
ALTER TABLE creditos.mora ADD CONSTRAINT fk_mora_1 FOREIGN KEY (id_calendario, numero_cuota)
    REFERENCES creditos.cuota (id_calendario, numero_cuota);
ALTER TABLE creditos.evento_auditoria ADD CONSTRAINT fk_evento_auditoria_1 FOREIGN KEY (modulo_emisor)
    REFERENCES core.modulo (id_modulo);
ALTER TABLE creditos.evento_auditoria ADD CONSTRAINT fk_evento_auditoria_2 FOREIGN KEY (id_entidad)
    REFERENCES creditos.entidad_auditada (id_entidad);
-- DECISIÓN: la cuenta afectada debe estar vinculada a la tarjeta (trigger de TARJETAS).
ALTER TABLE tarjetas.autorizacion ADD CONSTRAINT fk_autorizacion_vinculo FOREIGN KEY (id_tarjeta, num_cuenta)
    REFERENCES tarjetas.tarjeta_cuenta (id_tarjeta, num_cuenta);

-- =====================================================================
-- Índices
-- =====================================================================
-- DECISIÓN: PostgreSQL no indexa las claves foráneas; se crea un índice por
--   cada una que no esté cubierta por la clave primaria o una única.
CREATE INDEX ix_cuenta_contable_codigo_padre ON core.cuenta_contable (codigo_padre);
CREATE INDEX ix_asiento_contable_moneda ON core.asiento_contable (moneda);
CREATE INDEX ix_detalle_asiento_codigo_contable ON core.detalle_asiento (codigo_contable);
CREATE INDEX ix_canal_validacion_tipo_validacion ON core.canal_validacion (tipo_validacion);
CREATE INDEX ix_limite_canal_moneda ON core.limite_canal (moneda);
CREATE INDEX ix_consumo_diario_id_canal ON core.consumo_diario (id_canal);
CREATE INDEX ix_terminal_id_canal ON core.terminal (id_canal);
CREATE INDEX ix_terminal_id_agencia ON core.terminal (id_agencia);
CREATE INDEX ix_cliente_estado_cliente ON clientes.cliente (estado_cliente);
CREATE INDEX ix_biometria_cliente_tipo_biometria ON clientes.biometria_cliente (tipo_biometria);
CREATE INDEX ix_biometria_cliente_cod_cliente ON clientes.biometria_cliente (cod_cliente);
CREATE INDEX ix_codigo_verificacion_tipo_contacto ON clientes.codigo_verificacion (tipo_contacto);
CREATE INDEX ix_codigo_verificacion_cod_cliente ON clientes.codigo_verificacion (cod_cliente);
CREATE INDEX ix_validacion_identidad_tipo_validacion ON clientes.validacion_identidad (tipo_validacion);
CREATE INDEX ix_validacion_identidad_cod_cliente ON clientes.validacion_identidad (cod_cliente);
CREATE INDEX ix_cuenta_ahorro_moneda ON cuentas.cuenta_ahorro (moneda);
CREATE INDEX ix_cuenta_ahorro_regimen ON cuentas.cuenta_ahorro (regimen);
CREATE INDEX ix_cuenta_ahorro_estado_cuenta ON cuentas.cuenta_ahorro (estado_cuenta);
CREATE INDEX ix_cuenta_ahorro_id_agencia ON cuentas.cuenta_ahorro (id_agencia);
CREATE INDEX ix_movimiento_tipo_operacion ON cuentas.movimiento (tipo_operacion);
CREATE INDEX ix_movimiento_num_cuenta ON cuentas.movimiento (num_cuenta);
CREATE INDEX ix_movimiento_id_canal ON cuentas.movimiento (id_canal);
CREATE INDEX ix_titularidad_num_cuenta ON cuentas.titularidad (num_cuenta);
CREATE INDEX ix_tarjeta_bin ON tarjetas.tarjeta (bin);
CREATE INDEX ix_tarjeta_estado_tarjeta ON tarjetas.tarjeta (estado_tarjeta);
CREATE INDEX ix_tarjeta_cod_cliente ON tarjetas.tarjeta (cod_cliente);
CREATE INDEX ix_tarjeta_cuenta_num_cuenta ON tarjetas.tarjeta_cuenta (num_cuenta);
CREATE INDEX ix_credencial_tipo_credencial ON tarjetas.credencial (tipo_credencial);
CREATE INDEX ix_matriz_token_id_tarjeta ON tarjetas.matriz_token (id_tarjeta);
CREATE INDEX ix_token_pago_proveedor_pasarela ON tarjetas.token_pago (proveedor_pasarela);
CREATE INDEX ix_token_pago_id_tarjeta ON tarjetas.token_pago (id_tarjeta);
CREATE INDEX ix_intento_autenticacion_tipo_credencial ON tarjetas.intento_autenticacion (tipo_credencial);
CREATE INDEX ix_intento_autenticacion_id_terminal ON tarjetas.intento_autenticacion (id_terminal);
CREATE INDEX ix_intento_autenticacion_id_tarjeta ON tarjetas.intento_autenticacion (id_tarjeta);
CREATE INDEX ix_intento_autenticacion_id_canal ON tarjetas.intento_autenticacion (id_canal);
CREATE INDEX ix_autorizacion_tipo_operacion ON tarjetas.autorizacion (tipo_operacion);
CREATE INDEX ix_autorizacion_codigo_respuesta ON tarjetas.autorizacion (codigo_respuesta);
CREATE INDEX ix_autorizacion_id_terminal ON tarjetas.autorizacion (id_terminal);
CREATE INDEX ix_autorizacion_id_tarjeta ON tarjetas.autorizacion (id_tarjeta);
CREATE INDEX ix_autorizacion_num_cuenta ON tarjetas.autorizacion (num_cuenta);
CREATE INDEX ix_autorizacion_id_canal ON tarjetas.autorizacion (id_canal);
CREATE INDEX ix_historial_estado_tarjeta_estado_nuevo ON tarjetas.historial_estado_tarjeta (estado_nuevo);
CREATE INDEX ix_historial_estado_tarjeta_origen ON tarjetas.historial_estado_tarjeta (origen);
CREATE INDEX ix_historial_estado_tarjeta_id_tarjeta ON tarjetas.historial_estado_tarjeta (id_tarjeta);
CREATE INDEX ix_evento_salida_tipo_evento ON tarjetas.evento_salida (tipo_evento);
CREATE INDEX ix_evento_salida_id_tarjeta ON tarjetas.evento_salida (id_tarjeta);
CREATE INDEX ix_tipo_evento_salida_id_modulo_destino ON tarjetas.tipo_evento_salida (id_modulo_destino);
CREATE INDEX ix_solicitud_credito_moneda ON creditos.solicitud_credito (moneda);
CREATE INDEX ix_solicitud_credito_estado_solicitud ON creditos.solicitud_credito (estado_solicitud);
CREATE INDEX ix_solicitud_credito_cod_cliente ON creditos.solicitud_credito (cod_cliente);
CREATE INDEX ix_historial_estado_solicitud_estado_nuevo ON creditos.historial_estado_solicitud (estado_nuevo);
CREATE INDEX ix_historial_estado_solicitud_id_solicitud ON creditos.historial_estado_solicitud (id_solicitud);
CREATE INDEX ix_garantia_tipo_garantia ON creditos.garantia (tipo_garantia);
CREATE INDEX ix_garantia_moneda ON creditos.garantia (moneda);
CREATE INDEX ix_garantia_id_solicitud ON creditos.garantia (id_solicitud);
CREATE INDEX ix_fiador_solicitud_id_solicitud ON creditos.fiador_solicitud (id_solicitud);
CREATE INDEX ix_calendario_pago_metodo_amortizacion ON creditos.calendario_pago (metodo_amortizacion);
CREATE INDEX ix_cuota_estado_cuota ON creditos.cuota (estado_cuota);
CREATE INDEX ix_situacion_financiera_cod_cliente ON creditos.situacion_financiera (cod_cliente);
CREATE INDEX ix_evaluacion_id_consulta ON creditos.evaluacion (id_consulta);
CREATE INDEX ix_evaluacion_id_regla ON creditos.evaluacion (id_regla);
CREATE INDEX ix_evaluacion_id_analista ON creditos.evaluacion (id_analista);
CREATE INDEX ix_regla_evaluacion_accion ON creditos.regla_evaluacion (accion);
CREATE INDEX ix_decision_analista_decision ON creditos.decision_analista (decision);
CREATE INDEX ix_orden_desembolso_estado_orden ON creditos.orden_desembolso (estado_orden);
CREATE INDEX ix_orden_desembolso_id_evaluacion ON creditos.orden_desembolso (id_evaluacion);
CREATE INDEX ix_orden_desembolso_num_cuenta ON creditos.orden_desembolso (num_cuenta);
CREATE INDEX ix_orden_desembolso_id_canal ON creditos.orden_desembolso (id_canal);
CREATE INDEX ix_orden_desembolso_id_agencia ON creditos.orden_desembolso (id_agencia);
CREATE INDEX ix_validacion_desembolso_tipo_validacion ON creditos.validacion_desembolso (tipo_validacion);
CREATE INDEX ix_validacion_desembolso_id_orden ON creditos.validacion_desembolso (id_orden);
CREATE INDEX ix_tipo_validacion_desembolso_id_modulo_proveedor ON creditos.tipo_validacion_desembolso (id_modulo_proveedor);
CREATE INDEX ix_evento_entrega_id_orden ON creditos.evento_entrega (id_orden);
CREATE INDEX ix_solicitud_reversion_id_orden ON creditos.solicitud_reversion (id_orden);
CREATE INDEX ix_credito_estado_credito ON creditos.credito (estado_credito);
CREATE INDEX ix_pago_cod_credito ON creditos.pago (cod_credito);
CREATE INDEX ix_pago_id_canal ON creditos.pago (id_canal);
CREATE INDEX ix_aplicacion_pago_id_calendario_numero_cuota ON creditos.aplicacion_pago (id_calendario, numero_cuota);
CREATE INDEX ix_evento_auditoria_modulo_emisor ON creditos.evento_auditoria (modulo_emisor);
CREATE INDEX ix_evento_auditoria_id_entidad ON creditos.evento_auditoria (id_entidad);
-- DECISIÓN: una sola matriz ACTIVA por tarjeta (RN-TAR-002); reemplaza tarjeta_si_activa.
CREATE UNIQUE INDEX ux_matriz_activa ON tarjetas.matriz_token (id_tarjeta) WHERE estado_matriz = 'ACTIVA';
-- DECISIÓN: una sola orden CONFIRMADA por aprobación; reemplaza credito_confirmado.
CREATE UNIQUE INDEX ux_orden_confirmada ON creditos.orden_desembolso (id_evaluacion) WHERE estado_orden = 'CONFIRMADA';
-- DECISIÓN: una sola cuenta principal por tarjeta.
CREATE UNIQUE INDEX ux_tarjeta_principal ON tarjetas.tarjeta_cuenta (id_tarjeta) WHERE es_principal;
-- DECISIÓN: una sola plantilla vigente por cliente y tipo.
CREATE UNIQUE INDEX ux_biometria_vigente ON clientes.biometria_cliente (cod_cliente, tipo_biometria) WHERE estado_activo;

-- =====================================================================
-- Reglas que requieren datos de otras tablas (se implementan con triggers)
-- =====================================================================
--   * CREDITO: el calendario debe pertenecer a la solicitud de la evaluación de su orden.
--   * ORDEN_DESEMBOLSO: una sola orden CONFIRMADA por solicitud (en todas sus rondas).
--   * ORDEN_DESEMBOLSO: la cuenta destino pertenece al cliente de la solicitud y tiene su moneda.
--   * APLICACION_PAGO: la cuota pertenece al calendario del crédito del pago.
--   * AUTORIZACION: el importe no supera el tope del canal ni el saldo (RN-TOP-001).
--   * CUENTA_AHORRO: los saldos se actualizan en la misma transacción que el movimiento.
--   * TARJETA: estado_tarjeta se actualiza al insertar en HISTORIAL_ESTADO_TARJETA.
--   * HISTORIAL_*, INTENTO_AUTENTICACION, EVENTO_AUDITORIA: solo inserción (sin UPDATE/DELETE).

-- =====================================================================
-- Datos iniciales: parámetros documentados por las fuentes
-- =====================================================================
-- DECISIÓN: solo se cargan valores que figuran en los documentos de los
--   módulos; los números de módulo sin asignar se agregan después.
INSERT INTO core.moneda (cod_moneda, nombre, simbolo, decimales) VALUES
    ('PEN', 'Sol', 'S/', 2),
    ('USD', 'Dólar estadounidense', 'US$', 2);
INSERT INTO core.modulo (id_modulo, nombre) VALUES
    (1, 'CORE'),
    (2, 'CLIENTES'),
    (3, 'CUENTAS'),
    (8, 'BUS DE SERVICIOS'),
    (9, 'SEGURIDAD'),
    (11, 'SOLICITUD DE CREDITO'),
    (12, 'EVALUACION'),
    (13, 'DESEMBOLSO'),
    (14, 'COBRANZA');
INSERT INTO clientes.tipo_documento (cod_tipo_documento, descripcion, longitud_min, longitud_max, es_alfanumerico) VALUES
    ('DNI', 'Documento Nacional de Identidad', 8, 8, FALSE),
    ('CE', 'Carné de extranjería', 9, 12, TRUE),
    ('PTP', 'Permiso Temporal de Permanencia', 9, 9, FALSE),
    ('PASAPORTE', 'Pasaporte', 6, 12, TRUE);
INSERT INTO clientes.tipo_biometria (cod_tipo_biometria, descripcion, umbral_similitud) VALUES
    ('DACTILAR', 'Huella dactilar', NULL),
    ('FACIAL', 'Reconocimiento facial', NULL);
INSERT INTO clientes.tipo_contacto (cod_tipo_contacto, descripcion, vigencia_minutos, max_intentos) VALUES
    ('SMS', 'Código enviado al celular', 5, 3),
    ('CORREO', 'Código enviado al correo', 10, 3);
INSERT INTO clientes.tipo_validacion (cod_tipo_validacion, descripcion, endpoint) VALUES
    ('DOCUMENTO', 'Validación de documento', '/api/v1/kyc/validar-documento'),
    ('HUELLA', 'Verificación dactilar', '/api/v1/kyc/validar-huella'),
    ('FACIAL', 'Verificación facial', '/api/v1/kyc/validar-facial'),
    ('CELULAR', 'Confirmación de celular', '/api/v1/kyc/celular/verificar-codigo'),
    ('CORREO', 'Confirmación de correo', '/api/v1/kyc/correo/verificar-codigo');
INSERT INTO clientes.estado_cliente (cod_estado, descripcion, permite_operar) VALUES
    ('ACTIVO', 'Cliente activo', TRUE),
    ('OBSERVADO', 'Cliente observado', TRUE),
    ('BLOQUEADO', 'Cliente bloqueado', FALSE),
    ('SUSPENDIDO', 'Cliente suspendido', FALSE),
    ('BAJA', 'Cliente dado de baja', FALSE);
INSERT INTO cuentas.regimen_cuenta (cod_regimen, descripcion, min_titulares, firma_conjunta) VALUES
    ('INDIVIDUAL', 'Un solo titular', 1, FALSE),
    ('MANCOMUNADA_INDISTINTA', 'Mancomunada (o): firma cualquier titular', 2, FALSE),
    ('MANCOMUNADA_CONJUNTA', 'Mancomunada (y): firman todos los titulares', 2, TRUE);
INSERT INTO cuentas.estado_cuenta (cod_estado, descripcion, permite_debito, permite_credito) VALUES
    ('ACTIVA', 'Cuenta activa', TRUE, TRUE),
    ('BLOQUEADA', 'Cuenta bloqueada', FALSE, FALSE),
    ('BLOQUEADA_PREVENTIVA', 'Bloqueo por seguridad', FALSE, TRUE),
    ('CANCELADA', 'Cuenta cancelada', FALSE, FALSE);
INSERT INTO cuentas.tipo_operacion (tipo_operacion, naturaleza) VALUES
    ('RETIRO', 'D'),
    ('TRANSFERENCIA_ENVIADA', 'D'),
    ('PAGO', 'D'),
    ('FONDEO_BILLETERA', 'D'),
    ('DEBITO_CUOTA', 'D'),
    ('DEPOSITO', 'C'),
    ('TRANSFERENCIA_RECIBIDA', 'C'),
    ('DESEMBOLSO', 'C'),
    ('ABONO_INTERES', 'C'),
    ('EXTORNO', 'C'),
    ('CONSULTA_SALDO', 'N');
INSERT INTO core.canal (id_canal, nombre, es_presencial, tipo_integracion, activo, regla_tope) VALUES
    ('ATM', 'Cajero automático', TRUE, 'BUS', TRUE, 'RN-TOP-001'),
    ('AGE', 'Agente BNA', TRUE, 'BUS', TRUE, 'RN-TOP-001'),
    ('VEN', 'Ventanilla', TRUE, 'BUS', TRUE, 'RN-TOP-001'),
    ('HB', 'Home Banking', FALSE, 'BUS', TRUE, 'RN-TOP-001'),
    ('BD', 'Billetera Digital', FALSE, 'BUS', TRUE, 'RN-BD-002');
INSERT INTO core.limite_canal (id_canal, moneda, monto_maximo_diario, habilitado) VALUES
    ('ATM', 'PEN', 1500, TRUE),
    ('ATM', 'USD', 500, TRUE),
    ('VEN', 'PEN', NULL, TRUE),
    ('VEN', 'USD', NULL, TRUE),
    ('HB', 'PEN', 10000, TRUE),
    ('BD', 'PEN', 500, TRUE),
    ('BD', 'USD', NULL, FALSE);
INSERT INTO tarjetas.tipo_credencial (tipo_credencial, longitud) VALUES
    ('PIN_ATM', 4),
    ('CLAVE_WEB', 6),
    ('TOKEN_MATRIZ', NULL),
    ('BIOMETRIA', NULL),
    ('TOKEN_PAGO', NULL);
INSERT INTO core.canal_validacion (id_canal, tipo_validacion) VALUES
    ('ATM', 'PIN_ATM'),
    ('HB', 'CLAVE_WEB'),
    ('HB', 'TOKEN_MATRIZ'),
    ('BD', 'TOKEN_PAGO'),
    ('VEN', 'BIOMETRIA'),
    ('AGE', 'BIOMETRIA');
INSERT INTO tarjetas.estado_tarjeta (cod_estado, descripcion, es_operativa, es_final) VALUES
    ('PENDIENTE_ACTIVACION', 'Emitida, sin activar', FALSE, FALSE),
    ('ACTIVA', 'Operativa', TRUE, FALSE),
    ('BLOQUEADA', 'Bloqueada', FALSE, FALSE),
    ('RETENIDA', 'Retenida por el cajero', FALSE, FALSE),
    ('VENCIDA', 'Vencida', FALSE, FALSE),
    ('CANCELADA', 'Cancelada', FALSE, TRUE);
INSERT INTO tarjetas.origen_cambio (cod_origen, descripcion, puede_desbloquear) VALUES
    ('CLIENTE', 'El propio cliente', FALSE),
    ('SISTEMA', 'Proceso automático', FALSE),
    ('SEGURIDAD', 'Módulo de seguridad', TRUE),
    ('OPERADOR', 'Operador de ventanilla', TRUE),
    ('MODULO_CLIENTES', 'Módulo de clientes', FALSE);
INSERT INTO tarjetas.codigo_respuesta (cod_respuesta, descripcion, es_aprobacion) VALUES
    ('00', 'Aprobada', TRUE),
    ('54', 'Tarjeta vencida', FALSE),
    ('EXT', 'Extorno', FALSE);
INSERT INTO tarjetas.tipo_evento_salida (tipo_evento, descripcion, id_modulo_destino) VALUES
    ('EMISION_TARJETA', 'Emisión de tarjeta', 9),
    ('CAMBIO_ESTADO_TARJETA', 'Cambio de estado de tarjeta', 9),
    ('BLOQUEO_POR_INTENTOS', 'Bloqueo por intentos fallidos', 9);
INSERT INTO creditos.estado_solicitud (cod_estado, descripcion, es_final) VALUES
    ('REGISTRADA', 'Registrada', FALSE),
    ('EN_EVALUACION', 'En evaluación', FALSE),
    ('APROBADA', 'Aprobada', FALSE),
    ('RECHAZADA', 'Rechazada', TRUE),
    ('DESEMBOLSADA', 'Desembolsada', TRUE);
INSERT INTO creditos.tipo_garantia (cod_tipo_garantia, descripcion) VALUES
    ('HIPOTECARIA', 'Hipoteca'),
    ('MOBILIARIA', 'Garantía mobiliaria'),
    ('PRENDARIA', 'Prenda');
INSERT INTO creditos.metodo_amortizacion (cod_metodo, descripcion) VALUES
    ('FRANCES', 'Cuota constante'),
    ('ALEMAN', 'Amortización constante'),
    ('AMERICANO', 'Capital al vencimiento');
INSERT INTO creditos.estado_cuota (cod_estado, descripcion) VALUES
    ('PENDIENTE', 'Pendiente'),
    ('PARCIAL', 'Pagada parcialmente'),
    ('PAGADA', 'Pagada'),
    ('VENCIDA', 'Vencida');
INSERT INTO creditos.estado_credito (cod_estado, descripcion) VALUES
    ('AL_DIA', 'Al día'),
    ('EN_MORA', 'En mora'),
    ('CANCELADO', 'Cancelado');
INSERT INTO creditos.resultado_crediticio (cod_resultado, descripcion) VALUES
    ('APROBADO', 'Aprobado'),
    ('OBSERVADO', 'Derivado a revisión manual'),
    ('RECHAZADO', 'Rechazado');
INSERT INTO creditos.regla_evaluacion (id_regla, codigo_rn, descripcion, ratio_min, ratio_max, accion) VALUES
    ('R-A', 'RN-EVA-002-P.a', 'Ratio monto/límite hasta 80 %', NULL, 80, 'APROBADO'),
    ('R-B', 'RN-EVA-002-P.b', 'Ratio monto/límite entre 80 % y 100 %', 80, 100, 'OBSERVADO'),
    ('R-C', 'RN-EVA-002-P.c', 'Ratio monto/límite mayor que 100 %', 100, NULL, 'RECHAZADO');
INSERT INTO creditos.estado_orden (cod_estado, descripcion, es_final) VALUES
    ('PREPARADA', 'Preparada', FALSE),
    ('VALIDADA', 'Validada', FALSE),
    ('EN_PROCESO', 'Enviada al CORE', FALSE),
    ('POR_VERIFICAR', 'Respuesta del CORE perdida', FALSE),
    ('CONFIRMADA', 'Confirmada', FALSE),
    ('RECHAZADA', 'Rechazada', TRUE),
    ('REVERTIDA', 'Revertida', TRUE);
INSERT INTO creditos.tipo_validacion_desembolso (tipo_validacion, descripcion, id_modulo_proveedor) VALUES
    ('IDENTIDAD', 'Identidad del titular', 2),
    ('CUENTA', 'Cuenta destino elegible', 3),
    ('AUTORIZACION', 'Autorización de la operación', 9),
    ('ANTIFRAUDE', 'Control antifraude', 9);

COMMIT;
