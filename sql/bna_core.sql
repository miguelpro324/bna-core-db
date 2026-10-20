-- =====================================================================
-- Banco Nacional de Arequipa (BNA) - base de datos integrada del CORE
-- PostgreSQL 16 o superior. Generado por modelo/modelo_bna.py desde el
-- esquema relacional normalizado (3FN) y con tablas de catálogo.
-- =====================================================================
-- DECISIÓN: PostgreSQL, elegido frente a MySQL en el informe (sección
--   «Selección del sistema gestor de base de datos»); versión 16 o
--   superior, la usada en la validación.
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
    CONSTRAINT ck_autorizacion_2 CHECK (num_nonnulls(id_terminal, id_canal) = 1),
    CONSTRAINT ck_autorizacion_3 CHECK (uuid_transaccion IS NULL OR uuid_transaccion = uuid_autorizacion)
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
CREATE INDEX ix_intento_autenticacion_id_canal ON tarjetas.intento_autenticacion (id_canal);
CREATE INDEX ix_autorizacion_tipo_operacion ON tarjetas.autorizacion (tipo_operacion);
CREATE INDEX ix_autorizacion_codigo_respuesta ON tarjetas.autorizacion (codigo_respuesta);
CREATE INDEX ix_autorizacion_id_terminal ON tarjetas.autorizacion (id_terminal);
CREATE INDEX ix_autorizacion_num_cuenta ON tarjetas.autorizacion (num_cuenta);
CREATE INDEX ix_autorizacion_id_canal ON tarjetas.autorizacion (id_canal);
CREATE INDEX ix_historial_estado_tarjeta_estado_nuevo ON tarjetas.historial_estado_tarjeta (estado_nuevo);
CREATE INDEX ix_historial_estado_tarjeta_origen ON tarjetas.historial_estado_tarjeta (origen);
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
-- DECISIÓN: índices de consulta para las vistas y las consultas documentadas.
-- Estado de cuenta: movimientos de una cuenta por fecha.
CREATE INDEX ix_movimiento_cuenta_fecha ON cuentas.movimiento (num_cuenta, fecha_hora);
-- Consumo diario por tarjeta (v_consumo_diario, Tarjetas).
CREATE INDEX ix_autorizacion_tarjeta_fecha ON tarjetas.autorizacion (id_tarjeta, fecha_hora);
-- Intentos de una tarjeta por fecha (Tarjetas, C08).
CREATE INDEX ix_intento_tarjeta_fecha ON tarjetas.intento_autenticacion (id_tarjeta, fecha_hora);
-- Historial de una tarjeta (Tarjetas, C10).
CREATE INDEX ix_historial_tarjeta_fecha ON tarjetas.historial_estado_tarjeta (id_tarjeta, fecha_hora);
-- Recuperación de órdenes inciertas por estado y fecha (Desembolso, idx_orden_estado).
CREATE INDEX ix_orden_estado_fecha ON creditos.orden_desembolso (estado_orden, actualizado_en);
-- Bandeja de salida hacia SEGURIDAD: solo los eventos por enviar.
CREATE INDEX ix_evento_salida_pendiente ON tarjetas.evento_salida (fecha_registro) WHERE estado_envio = 'PENDIENTE';
-- Búsqueda de entregas pendientes hacia Cobranza (Desembolso).
CREATE INDEX ix_evento_entrega_pendiente ON creditos.evento_entrega (siguiente_intento) WHERE estado_entrega IN ('PENDIENTE', 'ENVIADO', 'FALLIDO');
-- Reconstrucción de una operación completa desde la traza (Desembolso, idx_auditoria_correlation).
CREATE INDEX ix_evento_auditoria_correlacion ON creditos.evento_auditoria (correlation_id);

-- =====================================================================
-- Reglas, funciones y vistas (se implementan con triggers y PL/pgSQL)
-- =====================================================================
-- Fuente: la regla de cada objeto se indica en su comentario; las de
--   Tarjetas y Desembolso conservan sus códigos (RN-*, ERR-TAR-*).
-- DECISIÓN: los mensajes de error empiezan con la regla o el código de la
--   fuente (RN-*, ERR-TAR-*), o con un código BNA-* cuando la regla es una
--   decisión de este informe, para que la aplicación los traduzca sin leer
--   el texto.
-- DECISIÓN: el día de negocio se corta a las 00:00:00 de Arequipa
--   (America/Lima), como el tope diario de Tarjetas (RN-TOP-001).

CREATE FUNCTION core.fn_fecha_negocio(p_momento TIMESTAMPTZ)
RETURNS DATE LANGUAGE sql STABLE AS $$
    SELECT (p_momento AT TIME ZONE 'America/Lima')::date
$$;
COMMENT ON FUNCTION core.fn_fecha_negocio(TIMESTAMPTZ) IS 'Fecha de negocio (America/Lima) de una marca de tiempo.';

-- ---------------------------------------------------------------------
-- Bitácoras e históricos de solo inserción.
-- Fuentes: CORE (asientos inmutables), Tarjetas (RN-SEG-002, RN-ATM-003),
--   Desembolso y Cobranza (bitácora de solo inserción).
-- ---------------------------------------------------------------------
CREATE FUNCTION core.fn_solo_insercion()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '%: %.% es de solo inserción (% no permitido)',
        TG_ARGV[0], TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP;
END $$;

CREATE TRIGGER tg_asiento_contable_solo_insercion BEFORE UPDATE OR DELETE ON core.asiento_contable
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_detalle_asiento_solo_insercion BEFORE UPDATE OR DELETE ON core.detalle_asiento
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_intento_solo_insercion BEFORE UPDATE OR DELETE ON tarjetas.intento_autenticacion
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_historial_tarjeta_solo_insercion BEFORE UPDATE OR DELETE ON tarjetas.historial_estado_tarjeta
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_autorizacion_sin_borrado BEFORE DELETE ON tarjetas.autorizacion
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_historial_solicitud_solo_insercion BEFORE UPDATE OR DELETE ON creditos.historial_estado_solicitud
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_evento_auditoria_solo_insercion BEFORE UPDATE OR DELETE ON creditos.evento_auditoria
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
-- DECISIÓN: TRUNCATE tampoco borra una bitácora (trigger por sentencia).
CREATE TRIGGER tg_asiento_contable_sin_truncate BEFORE TRUNCATE ON core.asiento_contable
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_detalle_asiento_sin_truncate BEFORE TRUNCATE ON core.detalle_asiento
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_intento_sin_truncate BEFORE TRUNCATE ON tarjetas.intento_autenticacion
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_historial_tarjeta_sin_truncate BEFORE TRUNCATE ON tarjetas.historial_estado_tarjeta
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_autorizacion_sin_truncate BEFORE TRUNCATE ON tarjetas.autorizacion
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('ERR-TAR-009');
CREATE TRIGGER tg_historial_solicitud_sin_truncate BEFORE TRUNCATE ON creditos.historial_estado_solicitud
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');
CREATE TRIGGER tg_evento_auditoria_sin_truncate BEFORE TRUNCATE ON creditos.evento_auditoria
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_solo_insercion('BNA-SOLO-INSERCION');

-- ---------------------------------------------------------------------
-- Partida doble (CORE): un asiento tiene al menos una línea en el debe y
-- otra en el haber, y ambas sumas coinciden.
-- DECISIÓN: se verifica al confirmar la transacción (trigger de restricción
--   diferido), porque mientras se insertan las líneas el asiento está
--   descuadrado; también se dispara al crear la cabecera, para que no quede
--   un asiento sin líneas.
-- ---------------------------------------------------------------------
CREATE FUNCTION core.fn_asiento_cuadra()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_debe  NUMERIC(15,2);
    v_haber NUMERIC(15,2);
    v_nd    INTEGER;
    v_nh    INTEGER;
BEGIN
    SELECT coalesce(sum(importe) FILTER (WHERE tipo_partida = 'DEBE'), 0),
           coalesce(sum(importe) FILTER (WHERE tipo_partida = 'HABER'), 0),
           count(*) FILTER (WHERE tipo_partida = 'DEBE'),
           count(*) FILTER (WHERE tipo_partida = 'HABER')
      INTO v_debe, v_haber, v_nd, v_nh
      FROM core.detalle_asiento
     WHERE id_asiento = NEW.id_asiento;
    IF v_nd = 0 OR v_nh = 0 OR v_debe <> v_haber THEN
        RAISE EXCEPTION 'BNA-PARTIDA-DOBLE: el asiento % no cuadra (debe %, haber %)',
            NEW.id_asiento, v_debe, v_haber;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER tg_asiento_cuadra AFTER INSERT ON core.asiento_contable
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION core.fn_asiento_cuadra();
CREATE CONSTRAINT TRIGGER tg_detalle_asiento_cuadra AFTER INSERT ON core.detalle_asiento
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION core.fn_asiento_cuadra();

-- ---------------------------------------------------------------------
-- Movimientos de cuenta (Cuentas y CORE).
--   * La cuenta admite débitos o créditos según su estado (ESTADO_CUENTA).
--   * El asiento del movimiento está en la moneda de la cuenta.
--   * Un débito no supera el saldo disponible ni el tope diario del canal
--     (RN-TOP-001; RN-BD-002 cuando el canal no opera en esa moneda).
--   * Los saldos y el consumo del día se actualizan en la misma transacción.
-- DECISIÓN: el tope y el saldo se comprometen una sola vez por operación.
--   Un débito con autorización de Tarjetas los compromete al autorizarse:
--   la autorización suma su monto a CONSUMO_DIARIO y lo descuenta del saldo
--   disponible. Su movimiento comparte el identificador de la operación
--   (uuid_transaccion = uuid_autorizacion, como en Tarjetas, RN-BUS-002),
--   solo descuenta el saldo contable y queda vinculado a la autorización. Un
--   débito sin autorización compromete ambos al registrarse.
-- DECISIÓN: toda operación que compromete el tope o el saldo bloquea antes
--   la fila de su cuenta (FOR UPDATE), de modo que dos operaciones
--   simultáneas sobre la misma cuenta se serializan: la segunda espera y,
--   al continuar, lee lo que confirmó la primera.
-- DECISIÓN: si no hay fila en LIMITE_CANAL para el canal y la moneda, el
--   canal no tiene tope documentado; si la hay con habilitado = FALSE, el
--   canal no opera en esa moneda.
-- DECISIÓN: el movimiento es inmutable salvo el paso de APROBADO a
--   EXTORNADO; el extorno devuelve el consumo del día y el saldo se repone
--   con un movimiento EXTORNO.
-- ---------------------------------------------------------------------
-- Suma (o resta, con monto negativo) al consumo comprometido del día.
CREATE FUNCTION core.fn_consumo_sumar(p_cuenta VARCHAR, p_canal VARCHAR, p_fecha DATE, p_monto NUMERIC)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.consumo_diario (num_cuenta, id_canal, fecha_corte, monto_acumulado)
    VALUES (p_cuenta, p_canal, p_fecha, greatest(p_monto, 0))
    ON CONFLICT (num_cuenta, id_canal, fecha_corte)
    DO UPDATE SET monto_acumulado = greatest(core.consumo_diario.monto_acumulado + p_monto, 0);
END $$;

CREATE FUNCTION cuentas.fn_movimiento_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_cuenta   cuentas.cuenta_ahorro%ROWTYPE;
    v_estado   cuentas.estado_cuenta%ROWTYPE;
    v_nat      CHAR(1);
    v_moneda   CHAR(3);
    v_limite   core.limite_canal%ROWTYPE;
    v_consumo  NUMERIC(15,2);
    v_aut      tarjetas.autorizacion%ROWTYPE;
BEGIN
    IF NEW.estado_transaccion <> 'APROBADO' THEN
        RAISE EXCEPTION 'BNA-MOVIMIENTO: un movimiento nuevo se registra APROBADO';
    END IF;
    -- Bloquea la cuenta: dos débitos simultáneos no pueden leer el mismo saldo.
    SELECT * INTO v_cuenta FROM cuentas.cuenta_ahorro WHERE num_cuenta = NEW.num_cuenta FOR UPDATE;
    SELECT * INTO v_estado FROM cuentas.estado_cuenta WHERE cod_estado = v_cuenta.estado_cuenta;
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = NEW.tipo_operacion;
    IF v_nat = 'N' THEN
        RAISE EXCEPTION 'BNA-MOVIMIENTO: % no mueve saldo y no genera movimiento', NEW.tipo_operacion;
    END IF;
    IF (v_nat = 'D' AND NOT v_estado.permite_debito) OR (v_nat = 'C' AND NOT v_estado.permite_credito) THEN
        RAISE EXCEPTION 'BNA-ESTADO-CUENTA: la cuenta % (estado %) no admite %',
            NEW.num_cuenta, v_cuenta.estado_cuenta, CASE v_nat WHEN 'D' THEN 'débitos' ELSE 'créditos' END;
    END IF;
    SELECT moneda INTO v_moneda FROM core.asiento_contable WHERE id_asiento = NEW.id_asiento;
    IF v_moneda IS DISTINCT FROM v_cuenta.moneda THEN
        RAISE EXCEPTION 'BNA-MONEDA: el asiento está en % y la cuenta % en %',
            v_moneda, NEW.num_cuenta, v_cuenta.moneda;
    END IF;
    IF v_nat = 'D' THEN
        -- Movimiento de una autorización: el tope y el saldo disponible ya se
        -- comprometieron al autorizar.
        SELECT * INTO v_aut FROM tarjetas.autorizacion WHERE uuid_autorizacion = NEW.uuid_transaccion FOR UPDATE;
        IF FOUND THEN
            IF v_aut.estado_autorizacion NOT IN ('AUTORIZADA', 'DISPENSADA') OR v_aut.uuid_transaccion IS NOT NULL
               OR v_aut.num_cuenta <> NEW.num_cuenta OR v_aut.monto <> NEW.monto THEN
                RAISE EXCEPTION 'BNA-MOVIMIENTO: el movimiento no corresponde a la autorización % (estado %, cuenta %, monto %)',
                    v_aut.uuid_autorizacion, v_aut.estado_autorizacion, v_aut.num_cuenta, v_aut.monto;
            END IF;
            RETURN NEW;
        END IF;
        IF v_cuenta.saldo_disponible < NEW.monto THEN
            RAISE EXCEPTION 'BNA-SALDO: saldo disponible insuficiente en % (% < %)',
                NEW.num_cuenta, v_cuenta.saldo_disponible, NEW.monto;
        END IF;
        IF NEW.id_canal IS NOT NULL THEN
            SELECT * INTO v_limite FROM core.limite_canal
             WHERE id_canal = NEW.id_canal AND moneda = v_cuenta.moneda;
            IF FOUND AND NOT v_limite.habilitado THEN
                RAISE EXCEPTION 'RN-BD-002: el canal % no opera en %', NEW.id_canal, v_cuenta.moneda;
            END IF;
            IF FOUND AND v_limite.monto_maximo_diario IS NOT NULL THEN
                SELECT coalesce(max(monto_acumulado), 0) INTO v_consumo FROM core.consumo_diario
                 WHERE num_cuenta = NEW.num_cuenta AND id_canal = NEW.id_canal
                   AND fecha_corte = core.fn_fecha_negocio(NEW.fecha_hora);
                IF v_consumo + NEW.monto > v_limite.monto_maximo_diario THEN
                    RAISE EXCEPTION 'RN-TOP-001: tope diario de % excedido en % (consumido %, tope %, solicitado %)',
                        NEW.id_canal, NEW.num_cuenta, v_consumo, v_limite.monto_maximo_diario, NEW.monto;
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE FUNCTION cuentas.fn_movimiento_aplicar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_nat CHAR(1);
BEGIN
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = NEW.tipo_operacion;
    IF TG_OP = 'INSERT' AND v_nat = 'D'
       AND EXISTS (SELECT 1 FROM tarjetas.autorizacion WHERE uuid_autorizacion = NEW.uuid_transaccion) THEN
        -- Movimiento de una autorización: el disponible ya se descontó.
        UPDATE cuentas.cuenta_ahorro SET saldo_contable = saldo_contable - NEW.monto
         WHERE num_cuenta = NEW.num_cuenta;
        UPDATE tarjetas.autorizacion SET uuid_transaccion = NEW.uuid_transaccion
         WHERE uuid_autorizacion = NEW.uuid_transaccion;
    ELSIF TG_OP = 'INSERT' THEN
        UPDATE cuentas.cuenta_ahorro
           SET saldo_contable   = saldo_contable   + CASE v_nat WHEN 'D' THEN -NEW.monto ELSE NEW.monto END,
               saldo_disponible = saldo_disponible + CASE v_nat WHEN 'D' THEN -NEW.monto ELSE NEW.monto END
         WHERE num_cuenta = NEW.num_cuenta;
        IF v_nat = 'D' AND NEW.id_canal IS NOT NULL THEN
            PERFORM core.fn_consumo_sumar(NEW.num_cuenta, NEW.id_canal, core.fn_fecha_negocio(NEW.fecha_hora), NEW.monto);
        END IF;
    ELSIF v_nat = 'D' AND NEW.id_canal IS NOT NULL THEN
        -- Extorno: el monto deja de contar para el tope de su día (Tarjetas, C07).
        PERFORM core.fn_consumo_sumar(NEW.num_cuenta, NEW.id_canal, core.fn_fecha_negocio(NEW.fecha_hora), -NEW.monto);
    END IF;
    RETURN NULL;
END $$;

CREATE FUNCTION cuentas.fn_movimiento_inmutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'BNA-MOVIMIENTO: un movimiento no se borra; se extorna';
    END IF;
    IF NOT (OLD.estado_transaccion = 'APROBADO' AND NEW.estado_transaccion = 'EXTORNADO')
       OR (NEW.uuid_transaccion, NEW.tipo_operacion, NEW.monto, NEW.glosa, NEW.fecha_hora,
           NEW.id_asiento, NEW.num_cuenta, NEW.id_canal)
          IS DISTINCT FROM
          (OLD.uuid_transaccion, OLD.tipo_operacion, OLD.monto, OLD.glosa, OLD.fecha_hora,
           OLD.id_asiento, OLD.num_cuenta, OLD.id_canal) THEN
        RAISE EXCEPTION 'BNA-MOVIMIENTO: solo se admite el paso de APROBADO a EXTORNADO';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_movimiento_validar BEFORE INSERT ON cuentas.movimiento
    FOR EACH ROW EXECUTE FUNCTION cuentas.fn_movimiento_validar();
CREATE TRIGGER tg_movimiento_aplicar AFTER INSERT OR UPDATE OF estado_transaccion ON cuentas.movimiento
    FOR EACH ROW EXECUTE FUNCTION cuentas.fn_movimiento_aplicar();
CREATE TRIGGER tg_movimiento_inmutable BEFORE UPDATE OR DELETE ON cuentas.movimiento
    FOR EACH ROW EXECUTE FUNCTION cuentas.fn_movimiento_inmutable();

-- ---------------------------------------------------------------------
-- Tarjetas: emisión (trg_tarjeta_bi y trg_tarjeta_ai de Tarjetas).
--   * Solo se emite a un cliente ACTIVO (RF-TAR-005, ERR-TAR-001).
--   * La emisión queda en el historial y en la bandeja hacia SEGURIDAD
--     (RN-SEG-002).
-- ---------------------------------------------------------------------
CREATE FUNCTION tarjetas.fn_tarjeta_emitir()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_estado_cliente VARCHAR(25);
BEGIN
    SELECT estado_cliente INTO v_estado_cliente FROM clientes.cliente WHERE cod_cliente = NEW.cod_cliente;
    IF v_estado_cliente IS DISTINCT FROM 'ACTIVO' THEN
        RAISE EXCEPTION 'ERR-TAR-001: no se emite tarjeta al cliente % en estado %',
            NEW.cod_cliente, v_estado_cliente;
    END IF;
    IF NEW.estado_tarjeta NOT IN ('PENDIENTE_ACTIVACION', 'ACTIVA') THEN
        RAISE EXCEPTION 'ERR-TAR-002: una tarjeta se emite PENDIENTE_ACTIVACION o ACTIVA, no %',
            NEW.estado_tarjeta;
    END IF;
    RETURN NEW;
END $$;

CREATE FUNCTION tarjetas.fn_tarjeta_emitida()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
    VALUES (NEW.estado_tarjeta, 'Emisión de la tarjeta', 'SISTEMA', NEW.id_tarjeta);
    INSERT INTO tarjetas.evento_salida (tipo_evento, carga_json, estado_envio, id_tarjeta)
    VALUES ('EMISION_TARJETA',
            jsonb_build_object('id_tarjeta', NEW.id_tarjeta, 'cod_cliente', NEW.cod_cliente,
                               'bin', NEW.bin, 'ultimos4', NEW.ultimos4, 'estado', NEW.estado_tarjeta),
            'PENDIENTE', NEW.id_tarjeta);
    RETURN NULL;
END $$;

-- El estado solo cambia registrando el historial (trigger siguiente).
CREATE FUNCTION tarjetas.fn_tarjeta_estado_via_historial()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado_tarjeta IS DISTINCT FROM OLD.estado_tarjeta
       AND coalesce(current_setting('bna.cambio_por_historial', TRUE), '') <> 'on' THEN
        RAISE EXCEPTION 'RN-SEG-002: el estado de la tarjeta % solo cambia registrando el historial',
            OLD.id_tarjeta;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_tarjeta_emitir BEFORE INSERT ON tarjetas.tarjeta
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_tarjeta_emitir();
CREATE TRIGGER tg_tarjeta_emitida AFTER INSERT ON tarjetas.tarjeta
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_tarjeta_emitida();
CREATE TRIGGER tg_tarjeta_estado_via_historial BEFORE UPDATE ON tarjetas.tarjeta
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_tarjeta_estado_via_historial();

-- ---------------------------------------------------------------------
-- Tarjetas: cambios de estado (trg_tarjeta_bu y trg_tarjeta_au de Tarjetas).
--   * La CANCELADA no cambia; la VENCIDA solo se cancela (RN-TAR-003,
--     ERR-TAR-002).
--   * El desbloqueo lo hace un origen autorizado: OPERADOR o SEGURIDAD
--     (RN-TAR-004, ERR-TAR-004); al desbloquear, los intentos vuelven a 0.
--   * Cada cambio se avisa a SEGURIDAD por la bandeja de salida (RN-SEG-002).
-- DECISIÓN: el primer registro del historial de una tarjeta es su emisión y
--   no se valida como transición.
-- ---------------------------------------------------------------------
CREATE FUNCTION tarjetas.fn_historial_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_actual VARCHAR(25);
    v_final  BOOLEAN;
BEGIN
    SELECT t.estado_tarjeta, e.es_final INTO v_actual, v_final
      FROM tarjetas.tarjeta t JOIN tarjetas.estado_tarjeta e ON e.cod_estado = t.estado_tarjeta
     WHERE t.id_tarjeta = NEW.id_tarjeta
       FOR UPDATE OF t;
    IF NOT EXISTS (SELECT 1 FROM tarjetas.historial_estado_tarjeta WHERE id_tarjeta = NEW.id_tarjeta) THEN
        IF NEW.estado_nuevo IS DISTINCT FROM v_actual THEN
            RAISE EXCEPTION 'RN-SEG-002: el primer registro del historial debe ser la emisión en estado %', v_actual;
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.estado_nuevo = v_actual THEN
        RAISE EXCEPTION 'ERR-TAR-002: la tarjeta % ya está %', NEW.id_tarjeta, v_actual;
    END IF;
    IF v_final THEN
        RAISE EXCEPTION 'ERR-TAR-002: la tarjeta % está % y no cambia de estado', NEW.id_tarjeta, v_actual;
    END IF;
    IF v_actual = 'VENCIDA' AND NEW.estado_nuevo <> 'CANCELADA' THEN
        RAISE EXCEPTION 'ERR-TAR-002: una tarjeta VENCIDA solo se cancela (se pidió %)', NEW.estado_nuevo;
    END IF;
    IF NEW.estado_nuevo = 'PENDIENTE_ACTIVACION' THEN
        RAISE EXCEPTION 'ERR-TAR-002: una tarjeta no vuelve a PENDIENTE_ACTIVACION';
    END IF;
    IF v_actual IN ('BLOQUEADA', 'RETENIDA') AND NEW.estado_nuevo = 'ACTIVA'
       AND NOT (SELECT puede_desbloquear FROM tarjetas.origen_cambio WHERE cod_origen = NEW.origen) THEN
        RAISE EXCEPTION 'ERR-TAR-004: el origen % no puede desbloquear la tarjeta %', NEW.origen, NEW.id_tarjeta;
    END IF;
    RETURN NEW;
END $$;

CREATE FUNCTION tarjetas.fn_historial_aplicar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_anterior VARCHAR(25);
    v_tipo     VARCHAR(30);
BEGIN
    SELECT estado_tarjeta INTO v_anterior FROM tarjetas.tarjeta WHERE id_tarjeta = NEW.id_tarjeta;
    IF v_anterior = NEW.estado_nuevo THEN
        RETURN NULL;  -- registro de emisión: la tarjeta ya tiene ese estado
    END IF;
    PERFORM set_config('bna.cambio_por_historial', 'on', TRUE);
    UPDATE tarjetas.tarjeta SET estado_tarjeta = NEW.estado_nuevo WHERE id_tarjeta = NEW.id_tarjeta;
    PERFORM set_config('bna.cambio_por_historial', 'off', TRUE);
    IF v_anterior IN ('BLOQUEADA', 'RETENIDA') AND NEW.estado_nuevo = 'ACTIVA' THEN
        UPDATE tarjetas.credencial SET intentos_fallidos = 0 WHERE id_tarjeta = NEW.id_tarjeta;
        UPDATE tarjetas.matriz_token SET intentos_fallidos = 0
         WHERE id_tarjeta = NEW.id_tarjeta AND estado_matriz = 'ACTIVA';
    END IF;
    v_tipo := CASE WHEN coalesce(current_setting('bna.bloqueo_por_intentos', TRUE), '') = 'on'
                   THEN 'BLOQUEO_POR_INTENTOS' ELSE 'CAMBIO_ESTADO_TARJETA' END;
    INSERT INTO tarjetas.evento_salida (tipo_evento, carga_json, estado_envio, id_tarjeta)
    VALUES (v_tipo,
            jsonb_build_object('id_tarjeta', NEW.id_tarjeta, 'estado_anterior', v_anterior,
                               'estado_nuevo', NEW.estado_nuevo, 'origen', NEW.origen,
                               'motivo', NEW.motivo, 'id_historial', NEW.id_historial),
            'PENDIENTE', NEW.id_tarjeta);
    RETURN NULL;
END $$;

CREATE TRIGGER tg_historial_validar BEFORE INSERT ON tarjetas.historial_estado_tarjeta
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_historial_validar();
CREATE TRIGGER tg_historial_aplicar AFTER INSERT ON tarjetas.historial_estado_tarjeta
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_historial_aplicar();

-- ---------------------------------------------------------------------
-- Tarjetas: intentos de autenticación (trg_intento_ai de Tarjetas).
--   * Cada fallo suma un intento a la credencial o a la matriz activa; al
--     tercero consecutivo se bloquea la tarjeta (RN-TAR-004). Un intento
--     exitoso reinicia el contador.
-- ---------------------------------------------------------------------
CREATE FUNCTION tarjetas.fn_intento_contar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_intentos SMALLINT;
BEGIN
    IF NEW.tipo_credencial IN ('PIN_ATM', 'CLAVE_WEB') THEN
        UPDATE tarjetas.credencial
           SET intentos_fallidos = CASE WHEN NEW.resultado = 'FALLIDO' THEN least(intentos_fallidos + 1, 3) ELSE 0 END
         WHERE id_tarjeta = NEW.id_tarjeta AND tipo_credencial = NEW.tipo_credencial
        RETURNING intentos_fallidos INTO v_intentos;
    ELSIF NEW.tipo_credencial = 'TOKEN_MATRIZ' THEN
        UPDATE tarjetas.matriz_token
           SET intentos_fallidos = CASE WHEN NEW.resultado = 'FALLIDO' THEN least(intentos_fallidos + 1, 3) ELSE 0 END,
               estado_matriz = CASE WHEN NEW.resultado = 'FALLIDO' AND intentos_fallidos + 1 >= 3
                                    THEN 'BLOQUEADA' ELSE estado_matriz END
         WHERE id_tarjeta = NEW.id_tarjeta AND estado_matriz = 'ACTIVA'
        RETURNING intentos_fallidos INTO v_intentos;
    END IF;
    IF NEW.resultado = 'FALLIDO' AND v_intentos >= 3
       AND (SELECT estado_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = NEW.id_tarjeta) = 'ACTIVA' THEN
        PERFORM set_config('bna.bloqueo_por_intentos', 'on', TRUE);
        INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
        VALUES ('BLOQUEADA', 'Tercer intento fallido de ' || NEW.tipo_credencial, 'SISTEMA', NEW.id_tarjeta);
        PERFORM set_config('bna.bloqueo_por_intentos', 'off', TRUE);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER tg_intento_contar AFTER INSERT ON tarjetas.intento_autenticacion
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_intento_contar();

-- ---------------------------------------------------------------------
-- Tarjetas: autorizaciones (trg_autorizacion_bi/bu y
-- sp_validar_reglas_autorizacion de Tarjetas).
--   * Para autorizar, la tarjeta está operativa y vigente (RN-TAR-003,
--     ERR-TAR-003), el canal y la terminal están activos, la cuenta admite
--     débitos y, en cajero, está habilitada y no es mancomunada conjunta
--     (RN-ATM-005, ERR-TAR-008).
--   * Un débito no supera el saldo ni el tope del día (RN-TOP-001,
--     ERR-TAR-007) y el canal opera en la moneda (RN-BD-002, ERR-TAR-006).
--   * La secuencia de estados está controlada (RN-ATM-007).
-- DECISIÓN: secuencia de estados: INICIADA -> AUTORIZADA | RECHAZADA;
--   AUTORIZADA -> DISPENSADA | PENDIENTE_REVERSION | EXTORNADA;
--   DISPENSADA -> PENDIENTE_REVERSION | EXTORNADA;
--   PENDIENTE_REVERSION -> EXTORNADA. RECHAZADA y EXTORNADA son finales.
-- DECISIÓN: las reglas se validan cada vez que la autorización llega a
--   AUTORIZADA, sea al insertarla o al actualizarla desde INICIADA, con la
--   cuenta bloqueada; en ese momento se compromete el tope y se retiene el
--   monto en el saldo disponible. Si se extorna antes de registrar su
--   movimiento, se liberan ambos.
-- ---------------------------------------------------------------------
CREATE FUNCTION tarjetas.fn_validar_reglas_autorizacion(
    p_id_tarjeta UUID, p_num_cuenta VARCHAR, p_id_canal VARCHAR, p_id_terminal VARCHAR,
    p_tipo_operacion VARCHAR, p_monto NUMERIC, p_momento TIMESTAMPTZ)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_tarjeta   tarjetas.tarjeta%ROWTYPE;
    v_operativa BOOLEAN;
    v_canal     VARCHAR(5);
    v_cuenta    cuentas.cuenta_ahorro%ROWTYPE;
    v_debito    BOOLEAN;
    v_nat       CHAR(1);
    v_limite    core.limite_canal%ROWTYPE;
    v_consumo   NUMERIC(15,2);
BEGIN
    SELECT * INTO v_tarjeta FROM tarjetas.tarjeta WHERE id_tarjeta = p_id_tarjeta;
    SELECT es_operativa INTO v_operativa FROM tarjetas.estado_tarjeta WHERE cod_estado = v_tarjeta.estado_tarjeta;
    IF NOT v_operativa THEN
        RAISE EXCEPTION 'ERR-TAR-003: la tarjeta % no es operativa (estado %)', p_id_tarjeta, v_tarjeta.estado_tarjeta;
    END IF;
    IF v_tarjeta.fecha_vencimiento < core.fn_fecha_negocio(p_momento) THEN
        RAISE EXCEPTION 'ERR-TAR-003: la tarjeta % venció el %', p_id_tarjeta, v_tarjeta.fecha_vencimiento;
    END IF;
    IF p_id_terminal IS NOT NULL THEN
        SELECT id_canal INTO v_canal FROM core.terminal WHERE id_terminal = p_id_terminal AND activo;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ERR-TAR-006: la terminal % no está activa', p_id_terminal;
        END IF;
    ELSE
        v_canal := p_id_canal;
    END IF;
    IF NOT (SELECT activo FROM core.canal WHERE id_canal = v_canal) THEN
        RAISE EXCEPTION 'ERR-TAR-006: el canal % no está activo', v_canal;
    END IF;
    -- Bloquea la cuenta antes de leer el saldo y el consumo comprometido.
    SELECT * INTO v_cuenta FROM cuentas.cuenta_ahorro WHERE num_cuenta = p_num_cuenta FOR UPDATE;
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = p_tipo_operacion;
    v_debito := v_nat = 'D';
    IF v_canal = 'ATM' AND (
           NOT (SELECT habilitada_atm FROM tarjetas.tarjeta_cuenta
                 WHERE id_tarjeta = p_id_tarjeta AND num_cuenta = p_num_cuenta)
           OR (SELECT firma_conjunta FROM cuentas.regimen_cuenta WHERE cod_regimen = v_cuenta.regimen)) THEN
        RAISE EXCEPTION 'ERR-TAR-008: la cuenta % no puede operarse en cajero (RN-ATM-005)', p_num_cuenta;
    END IF;
    IF v_debito THEN
        IF NOT (SELECT permite_debito FROM cuentas.estado_cuenta WHERE cod_estado = v_cuenta.estado_cuenta) THEN
            RAISE EXCEPTION 'BNA-ESTADO-CUENTA: la cuenta % (estado %) no admite débitos', p_num_cuenta, v_cuenta.estado_cuenta;
        END IF;
        SELECT * INTO v_limite FROM core.limite_canal WHERE id_canal = v_canal AND moneda = v_cuenta.moneda;
        IF FOUND AND NOT v_limite.habilitado THEN
            RAISE EXCEPTION 'ERR-TAR-006: el canal % no opera en % (RN-BD-002)', v_canal, v_cuenta.moneda;
        END IF;
        IF FOUND AND v_limite.monto_maximo_diario IS NOT NULL THEN
            SELECT coalesce(max(monto_acumulado), 0) INTO v_consumo FROM core.consumo_diario
             WHERE num_cuenta = p_num_cuenta AND id_canal = v_canal
               AND fecha_corte = core.fn_fecha_negocio(p_momento);
            IF v_consumo + p_monto > v_limite.monto_maximo_diario THEN
                RAISE EXCEPTION 'ERR-TAR-007: tope diario excedido (RN-TOP-001); disponible hoy % %',
                    v_limite.monto_maximo_diario - v_consumo, v_cuenta.moneda;
            END IF;
        END IF;
        IF v_cuenta.saldo_disponible < p_monto THEN
            RAISE EXCEPTION 'BNA-SALDO: saldo disponible insuficiente en % (% < %)',
                p_num_cuenta, v_cuenta.saldo_disponible, p_monto;
        END IF;
    END IF;
END $$;

CREATE FUNCTION tarjetas.fn_autorizacion_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado_autorizacion NOT IN ('INICIADA', 'AUTORIZADA', 'RECHAZADA') THEN
            RAISE EXCEPTION 'RN-ATM-007: una autorización nueva no puede estar %', NEW.estado_autorizacion;
        END IF;
    ELSE
        IF (NEW.uuid_autorizacion, NEW.tipo_operacion, NEW.monto, NEW.id_tarjeta, NEW.num_cuenta,
            NEW.id_canal, NEW.id_terminal, NEW.ip_origen, NEW.fecha_hora)
           IS DISTINCT FROM
           (OLD.uuid_autorizacion, OLD.tipo_operacion, OLD.monto, OLD.id_tarjeta, OLD.num_cuenta,
            OLD.id_canal, OLD.id_terminal, OLD.ip_origen, OLD.fecha_hora) THEN
            RAISE EXCEPTION 'RN-ATM-007: los datos de la operación autorizada no se modifican';
        END IF;
        IF NEW.estado_autorizacion IS DISTINCT FROM OLD.estado_autorizacion AND NOT (
               (OLD.estado_autorizacion = 'INICIADA' AND NEW.estado_autorizacion IN ('AUTORIZADA', 'RECHAZADA'))
            OR (OLD.estado_autorizacion = 'AUTORIZADA'
                AND NEW.estado_autorizacion IN ('DISPENSADA', 'PENDIENTE_REVERSION', 'EXTORNADA'))
            OR (OLD.estado_autorizacion = 'DISPENSADA'
                AND NEW.estado_autorizacion IN ('PENDIENTE_REVERSION', 'EXTORNADA'))
            OR (OLD.estado_autorizacion = 'PENDIENTE_REVERSION' AND NEW.estado_autorizacion = 'EXTORNADA')) THEN
            RAISE EXCEPTION 'RN-ATM-007: transición no permitida de % a %',
                OLD.estado_autorizacion, NEW.estado_autorizacion;
        END IF;
        NEW.fecha_actualizacion := now();
    END IF;
    IF NEW.estado_autorizacion = 'AUTORIZADA'
       AND (TG_OP = 'INSERT' OR OLD.estado_autorizacion = 'INICIADA') THEN
        PERFORM tarjetas.fn_validar_reglas_autorizacion(
            NEW.id_tarjeta, NEW.num_cuenta, NEW.id_canal, NEW.id_terminal,
            NEW.tipo_operacion, NEW.monto, NEW.fecha_hora);
    END IF;
    RETURN NEW;
END $$;

-- Compromete el tope y retiene el saldo al autorizar; los libera si la
-- autorización se extorna antes de registrar su movimiento.
CREATE FUNCTION tarjetas.fn_autorizacion_aplicar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_nat   CHAR(1);
    v_canal VARCHAR(5);
    v_signo INTEGER;
BEGIN
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = NEW.tipo_operacion;
    IF v_nat <> 'D' THEN
        RETURN NULL;
    END IF;
    IF NEW.estado_autorizacion = 'AUTORIZADA' AND (TG_OP = 'INSERT' OR OLD.estado_autorizacion = 'INICIADA') THEN
        v_signo := 1;
    ELSIF TG_OP = 'UPDATE' AND NEW.estado_autorizacion = 'EXTORNADA' AND OLD.estado_autorizacion <> 'EXTORNADA'
          AND NEW.uuid_transaccion IS NULL THEN
        v_signo := -1;
    ELSE
        RETURN NULL;
    END IF;
    v_canal := coalesce(NEW.id_canal, (SELECT id_canal FROM core.terminal WHERE id_terminal = NEW.id_terminal));
    UPDATE cuentas.cuenta_ahorro SET saldo_disponible = saldo_disponible - v_signo * NEW.monto
     WHERE num_cuenta = NEW.num_cuenta;
    PERFORM core.fn_consumo_sumar(NEW.num_cuenta, v_canal, core.fn_fecha_negocio(NEW.fecha_hora), v_signo * NEW.monto);
    RETURN NULL;
END $$;

CREATE TRIGGER tg_autorizacion_validar BEFORE INSERT OR UPDATE ON tarjetas.autorizacion
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_autorizacion_validar();
CREATE TRIGGER tg_autorizacion_aplicar AFTER INSERT OR UPDATE OF estado_autorizacion ON tarjetas.autorizacion
    FOR EACH ROW EXECUTE FUNCTION tarjetas.fn_autorizacion_aplicar();

-- ---------------------------------------------------------------------
-- Tarjetas: estado del cliente (trg_cliente_ref_au de Tarjetas, INT-T07).
--   * Si Clientes bloquea o suspende al cliente, se bloquean sus tarjetas
--     activas o por activar; si lo da de baja, se cancelan todas.
-- ---------------------------------------------------------------------
CREATE FUNCTION clientes.fn_cliente_estado_tarjetas()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado_cliente IN ('BLOQUEADO', 'SUSPENDIDO') THEN
        INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
        SELECT 'BLOQUEADA', 'Cliente ' || NEW.estado_cliente || ' en Clientes', 'MODULO_CLIENTES', id_tarjeta
          FROM tarjetas.tarjeta
         WHERE cod_cliente = NEW.cod_cliente AND estado_tarjeta IN ('ACTIVA', 'PENDIENTE_ACTIVACION');
    ELSIF NEW.estado_cliente = 'BAJA' THEN
        INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
        SELECT 'CANCELADA', 'Cliente dado de baja en Clientes', 'MODULO_CLIENTES', t.id_tarjeta
          FROM tarjetas.tarjeta t JOIN tarjetas.estado_tarjeta e ON e.cod_estado = t.estado_tarjeta
         WHERE t.cod_cliente = NEW.cod_cliente AND NOT e.es_final;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER tg_cliente_estado_tarjetas AFTER UPDATE OF estado_cliente ON clientes.cliente
    FOR EACH ROW WHEN (NEW.estado_cliente IS DISTINCT FROM OLD.estado_cliente)
    EXECUTE FUNCTION clientes.fn_cliente_estado_tarjetas();

-- ---------------------------------------------------------------------
-- Tarjetas: funciones de operación.
--   * bloquear_tarjeta: bloqueo con su motivo y origen (Tarjetas).
--   * marcar_tarjetas_vencidas: reemplaza al evento programado
--     ev_marcar_tarjetas_vencidas de Tarjetas (RN-TAR-003).
-- DECISIÓN: PostgreSQL no trae un planificador de tareas; la función no
--   depende de extensiones y debe programarse fuera de la base (por ejemplo,
--   un cron del sistema o un job de la aplicación), una vez al día.
-- ---------------------------------------------------------------------
CREATE FUNCTION tarjetas.bloquear_tarjeta(p_id_tarjeta UUID, p_motivo VARCHAR, p_origen VARCHAR)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
    VALUES ('BLOQUEADA', p_motivo, p_origen, p_id_tarjeta)
    RETURNING id_historial INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION tarjetas.bloquear_tarjeta(UUID, VARCHAR, VARCHAR) IS 'Bloquea la tarjeta registrando el motivo y el origen en el historial.';

CREATE FUNCTION tarjetas.marcar_tarjetas_vencidas(p_fecha DATE DEFAULT core.fn_fecha_negocio(now()))
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    v_n INTEGER;
BEGIN
    INSERT INTO tarjetas.historial_estado_tarjeta (estado_nuevo, motivo, origen, id_tarjeta)
    SELECT 'VENCIDA', 'Vencimiento de la tarjeta', 'SISTEMA', id_tarjeta
      FROM tarjetas.tarjeta
     WHERE fecha_vencimiento < p_fecha AND estado_tarjeta NOT IN ('VENCIDA', 'CANCELADA');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;
COMMENT ON FUNCTION tarjetas.marcar_tarjetas_vencidas(DATE) IS 'Marca como VENCIDA cada tarjeta cuya fecha ya pasó; se programa fuera de la base, una vez al día.';

-- ---------------------------------------------------------------------
-- Desembolso: orden (reglas de integración del modelo).
--   * La cuenta destino pertenece al cliente de la solicitud y tiene su
--     moneda; el importe no supera el límite aprobado en la evaluación.
--   * Una sola orden CONFIRMADA por solicitud, en todas sus rondas
--     (Desembolso: un desembolso confirmado por crédito).
-- ---------------------------------------------------------------------
CREATE FUNCTION creditos.fn_orden_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_solicitud creditos.solicitud_credito%ROWTYPE;
    v_limite    NUMERIC(15,2);
    v_moneda    CHAR(3);
BEGIN
    SELECT s.* INTO v_solicitud
      FROM creditos.solicitud_credito s
      JOIN creditos.evaluacion e ON e.id_solicitud = s.id_solicitud
     WHERE e.id_evaluacion = NEW.id_evaluacion
       FOR UPDATE OF s;
    SELECT limite_aprobado INTO v_limite FROM creditos.evaluacion WHERE id_evaluacion = NEW.id_evaluacion;
    IF NOT EXISTS (SELECT 1 FROM cuentas.titularidad
                    WHERE cod_cliente = v_solicitud.cod_cliente AND num_cuenta = NEW.num_cuenta) THEN
        RAISE EXCEPTION 'BNA-CUENTA-DESTINO: la cuenta % no pertenece al cliente % de la solicitud',
            NEW.num_cuenta, v_solicitud.cod_cliente;
    END IF;
    SELECT moneda INTO v_moneda FROM cuentas.cuenta_ahorro WHERE num_cuenta = NEW.num_cuenta;
    IF v_moneda <> v_solicitud.moneda THEN
        RAISE EXCEPTION 'BNA-CUENTA-DESTINO: la cuenta % está en % y la solicitud en %',
            NEW.num_cuenta, v_moneda, v_solicitud.moneda;
    END IF;
    IF NEW.importe > v_limite THEN
        RAISE EXCEPTION 'BNA-IMPORTE: el importe % supera el límite aprobado %', NEW.importe, v_limite;
    END IF;
    IF NEW.estado_orden = 'CONFIRMADA' AND EXISTS (
           SELECT 1 FROM creditos.orden_desembolso o
             JOIN creditos.evaluacion e ON e.id_evaluacion = o.id_evaluacion
            WHERE e.id_solicitud = v_solicitud.id_solicitud
              AND o.estado_orden = 'CONFIRMADA' AND o.id_orden <> NEW.id_orden) THEN
        RAISE EXCEPTION 'BNA-ORDEN-UNICA: la solicitud % ya tiene una orden CONFIRMADA', v_solicitud.id_solicitud;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_orden_validar BEFORE INSERT OR UPDATE ON creditos.orden_desembolso
    FOR EACH ROW EXECUTE FUNCTION creditos.fn_orden_validar();

-- ---------------------------------------------------------------------
-- Cobranza: crédito (decisión I15 del informe).
--   * El crédito nace de una orden CONFIRMADA, y su calendario es OFICIAL y
--     pertenece a la solicitud de la evaluación de esa orden.
-- ---------------------------------------------------------------------
CREATE FUNCTION creditos.fn_credito_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_estado_orden VARCHAR(25);
    v_sol_orden    UUID;
    v_cal          creditos.calendario_pago%ROWTYPE;
BEGIN
    SELECT o.estado_orden, e.id_solicitud INTO v_estado_orden, v_sol_orden
      FROM creditos.orden_desembolso o JOIN creditos.evaluacion e ON e.id_evaluacion = o.id_evaluacion
     WHERE o.id_orden = NEW.id_orden;
    IF v_estado_orden <> 'CONFIRMADA' THEN
        RAISE EXCEPTION 'BNA-CREDITO: el crédito nace de una orden CONFIRMADA (la orden está %)', v_estado_orden;
    END IF;
    SELECT * INTO v_cal FROM creditos.calendario_pago WHERE id_calendario = NEW.id_calendario;
    IF v_cal.id_solicitud <> v_sol_orden THEN
        RAISE EXCEPTION 'BNA-CREDITO: el calendario % no pertenece a la solicitud % de la orden',
            NEW.id_calendario, v_sol_orden;
    END IF;
    IF v_cal.tipo_calendario <> 'OFICIAL' THEN
        RAISE EXCEPTION 'BNA-CREDITO: el crédito usa el calendario OFICIAL, no el %', v_cal.tipo_calendario;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_credito_validar BEFORE INSERT OR UPDATE OF id_orden, id_calendario ON creditos.credito
    FOR EACH ROW EXECUTE FUNCTION creditos.fn_credito_validar();

-- ---------------------------------------------------------------------
-- Cobranza: aplicación de pagos.
--   * Solo se aplica un pago CONFIRMADO, a cuotas del calendario de su
--     crédito, sin superar el saldo de la cuota ni el monto del pago.
--   * Aplicar actualiza el saldo pendiente y el estado de la cuota, y
--     cancela el crédito cuando todas sus cuotas quedan pagadas (Cobranza,
--     acciones de actualización).
-- DECISIÓN: la mora no se paga por APLICACION_PAGO: es el cálculo de CORE
--   guardado en MORA, de modo que pagarla no puede dar por pagada la cuota.
-- DECISIÓN: una aplicación no se modifica ni se borra; un error se corrige
--   con un nuevo pago o con su extorno en Cuentas.
-- ---------------------------------------------------------------------
CREATE FUNCTION creditos.fn_aplicacion_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_pago      creditos.pago%ROWTYPE;
    v_cal       UUID;
    v_saldo     NUMERIC(15,2);
    v_aplicado  NUMERIC(15,2);
BEGIN
    SELECT * INTO v_pago FROM creditos.pago WHERE id_pago = NEW.id_pago FOR UPDATE;
    IF v_pago.estado_confirmacion <> 'CONFIRMADO' THEN
        RAISE EXCEPTION 'BNA-PAGO: solo se aplica un pago CONFIRMADO (el pago está %)', v_pago.estado_confirmacion;
    END IF;
    SELECT id_calendario INTO v_cal FROM creditos.credito WHERE cod_credito = v_pago.cod_credito;
    IF NEW.id_calendario <> v_cal THEN
        RAISE EXCEPTION 'BNA-PAGO: la cuota no pertenece al calendario del crédito % del pago', v_pago.cod_credito;
    END IF;
    SELECT saldo_pendiente INTO v_saldo FROM creditos.cuota
     WHERE id_calendario = NEW.id_calendario AND numero_cuota = NEW.numero_cuota FOR UPDATE;
    IF NEW.monto_aplicado > v_saldo THEN
        RAISE EXCEPTION 'BNA-PAGO: se aplican % a la cuota %, que solo debe %',
            NEW.monto_aplicado, NEW.numero_cuota, v_saldo;
    END IF;
    SELECT coalesce(sum(monto_aplicado), 0) INTO v_aplicado FROM creditos.aplicacion_pago WHERE id_pago = NEW.id_pago;
    IF v_aplicado + NEW.monto_aplicado > v_pago.monto_pago THEN
        RAISE EXCEPTION 'BNA-PAGO: se aplicarían % de un pago de %',
            v_aplicado + NEW.monto_aplicado, v_pago.monto_pago;
    END IF;
    RETURN NEW;
END $$;

CREATE FUNCTION creditos.fn_aplicacion_aplicar()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE creditos.cuota
       SET saldo_pendiente = saldo_pendiente - NEW.monto_aplicado,
           estado_cuota = CASE WHEN saldo_pendiente - NEW.monto_aplicado = 0 THEN 'PAGADA'
                               WHEN estado_cuota = 'VENCIDA' THEN 'VENCIDA'
                               ELSE 'PARCIAL' END
     WHERE id_calendario = NEW.id_calendario AND numero_cuota = NEW.numero_cuota;
    IF NOT EXISTS (SELECT 1 FROM creditos.cuota
                    WHERE id_calendario = NEW.id_calendario AND estado_cuota <> 'PAGADA') THEN
        UPDATE creditos.credito SET estado_credito = 'CANCELADO' WHERE id_calendario = NEW.id_calendario;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER tg_aplicacion_validar BEFORE INSERT ON creditos.aplicacion_pago
    FOR EACH ROW EXECUTE FUNCTION creditos.fn_aplicacion_validar();
CREATE TRIGGER tg_aplicacion_aplicar AFTER INSERT ON creditos.aplicacion_pago
    FOR EACH ROW EXECUTE FUNCTION creditos.fn_aplicacion_aplicar();
CREATE TRIGGER tg_aplicacion_solo_insercion BEFORE UPDATE OR DELETE ON creditos.aplicacion_pago
    FOR EACH ROW EXECUTE FUNCTION core.fn_solo_insercion('BNA-PAGO');

-- Aplica el saldo libre de un pago a las cuotas con saldo, de la más antigua
-- a la más reciente (Cobranza: un pago puede ser parcial o alcanzar para la
-- cuota siguiente). Devuelve el monto aplicado en esta llamada.
CREATE FUNCTION creditos.aplicar_pago(p_id_pago UUID)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
    v_pago   creditos.pago%ROWTYPE;
    v_libre  NUMERIC(15,2);
    v_total  NUMERIC(15,2) := 0;
    v_monto  NUMERIC(15,2);
    r        RECORD;
BEGIN
    SELECT * INTO v_pago FROM creditos.pago WHERE id_pago = p_id_pago;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'BNA-PAGO: no existe el pago %', p_id_pago;
    END IF;
    SELECT v_pago.monto_pago - coalesce(sum(monto_aplicado), 0) INTO v_libre
      FROM creditos.aplicacion_pago WHERE id_pago = p_id_pago;
    FOR r IN
        SELECT q.id_calendario, q.numero_cuota, q.saldo_pendiente
          FROM creditos.cuota q JOIN creditos.credito c ON c.id_calendario = q.id_calendario
         WHERE c.cod_credito = v_pago.cod_credito AND q.saldo_pendiente > 0
         ORDER BY q.numero_cuota
    LOOP
        EXIT WHEN v_libre <= 0;
        v_monto := least(v_libre, r.saldo_pendiente);
        INSERT INTO creditos.aplicacion_pago (id_pago, id_calendario, numero_cuota, monto_aplicado)
        VALUES (p_id_pago, r.id_calendario, r.numero_cuota, v_monto);
        v_libre := v_libre - v_monto;
        v_total := v_total + v_monto;
    END LOOP;
    RETURN v_total;
END $$;
COMMENT ON FUNCTION creditos.aplicar_pago(UUID) IS 'Reparte el saldo libre de un pago entre las cuotas pendientes, de la más antigua a la más reciente.';

-- ---------------------------------------------------------------------
-- Vistas de Tarjetas (Tabla 17 de Tarjetas).
-- ---------------------------------------------------------------------
-- Tarjetas con número enmascarado, titular, vencimiento MM/AA y si están
-- operativas (PCI-DSS: nunca se muestra el número completo).
CREATE VIEW tarjetas.v_tarjeta_resumen AS
SELECT t.id_tarjeta,
       substr(t.bin, 1, 4) || ' ' || substr(t.bin, 5, 2) || '** **** ' || t.ultimos4 AS numero_enmascarado,
       b.tipo_tarjeta,
       t.cod_cliente,
       concat_ws(' ', c.nombres, c.apellido_paterno, c.apellido_materno) AS titular,
       to_char(t.fecha_vencimiento, 'MM/YY') AS vencimiento_mm_aa,
       t.estado_tarjeta,
       e.es_operativa AND t.fecha_vencimiento >= core.fn_fecha_negocio(now()) AS operativa
  FROM tarjetas.tarjeta t
  JOIN tarjetas.bin_tarjeta b ON b.bin = t.bin
  JOIN tarjetas.estado_tarjeta e ON e.cod_estado = t.estado_tarjeta
  JOIN clientes.cliente c ON c.cod_cliente = t.cod_cliente;

-- Monto consumido por tarjeta, canal, moneda y día (RN-TOP-001).
CREATE VIEW tarjetas.v_consumo_diario AS
SELECT a.id_tarjeta,
       coalesce(a.id_canal, te.id_canal) AS id_canal,
       cu.moneda,
       core.fn_fecha_negocio(a.fecha_hora) AS fecha,
       sum(a.monto) AS monto_consumido,
       count(*) AS operaciones
  FROM tarjetas.autorizacion a
  JOIN cuentas.cuenta_ahorro cu ON cu.num_cuenta = a.num_cuenta
  JOIN cuentas.tipo_operacion o ON o.tipo_operacion = a.tipo_operacion
  LEFT JOIN core.terminal te ON te.id_terminal = a.id_terminal
 WHERE a.estado_autorizacion IN ('AUTORIZADA', 'DISPENSADA') AND o.naturaleza = 'D'
 GROUP BY a.id_tarjeta, coalesce(a.id_canal, te.id_canal), cu.moneda, core.fn_fecha_negocio(a.fecha_hora);

-- Tope disponible del día por tarjeta y canal (RN-TOP-001). El consumo es el
-- de cada cuenta vinculada, porque el tope se controla por cuenta.
CREATE VIEW tarjetas.v_tope_restante_hoy AS
SELECT tc.id_tarjeta,
       tc.num_cuenta,
       l.id_canal,
       l.moneda,
       l.monto_maximo_diario,
       coalesce(cd.monto_acumulado, 0) AS consumido_hoy,
       l.monto_maximo_diario - coalesce(cd.monto_acumulado, 0) AS disponible_hoy
  FROM tarjetas.tarjeta_cuenta tc
  JOIN cuentas.cuenta_ahorro cu ON cu.num_cuenta = tc.num_cuenta
  JOIN core.limite_canal l ON l.moneda = cu.moneda AND l.habilitado
  LEFT JOIN core.consumo_diario cd
         ON cd.num_cuenta = tc.num_cuenta AND cd.id_canal = l.id_canal
        AND cd.fecha_corte = core.fn_fecha_negocio(now());

-- Credenciales y matrices con intentos fallidos acumulados (RN-TAR-004).
CREATE VIEW tarjetas.v_credenciales_en_riesgo AS
SELECT cr.id_tarjeta, cr.tipo_credencial AS credencial, cr.intentos_fallidos,
       3 - cr.intentos_fallidos AS intentos_restantes, t.estado_tarjeta
  FROM tarjetas.credencial cr JOIN tarjetas.tarjeta t ON t.id_tarjeta = cr.id_tarjeta
 WHERE cr.intentos_fallidos > 0
UNION ALL
SELECT m.id_tarjeta, 'TOKEN_MATRIZ', m.intentos_fallidos, 3 - m.intentos_fallidos, t.estado_tarjeta
  FROM tarjetas.matriz_token m JOIN tarjetas.tarjeta t ON t.id_tarjeta = m.id_tarjeta
 WHERE m.intentos_fallidos > 0 AND m.estado_matriz <> 'REEMPLAZADA';

-- ---------------------------------------------------------------------
-- Vistas de apoyo operativo de Desembolso (sección 8 de Desembolso).
-- ---------------------------------------------------------------------
-- Órdenes cuyo resultado en el CORE es incierto; alimenta el proceso de
-- recuperación que consulta el resultado por la misma referencia.
CREATE VIEW creditos.v_ordenes_inciertas AS
SELECT o.id_orden, o.codigo_orden, o.estado_orden, o.importe, s.moneda, o.num_cuenta,
       o.idempotency_key, o.correlation_id, o.actualizado_en,
       now() - o.actualizado_en AS tiempo_en_estado
  FROM creditos.orden_desembolso o
  JOIN creditos.evaluacion e ON e.id_evaluacion = o.id_evaluacion
  JOIN creditos.solicitud_credito s ON s.id_solicitud = e.id_solicitud
 WHERE o.estado_orden IN ('EN_PROCESO', 'POR_VERIFICAR');

-- Entregas a Cobranza que superan la política de reintentos.
-- DECISIÓN: la política es de dos reintentos como máximo (documento de
--   tecnologías del proyecto), es decir, tres intentos.
CREATE VIEW creditos.v_entregas_pendientes AS
SELECT ev.id_evento, ev.id_orden, o.codigo_orden, ev.tipo_evento, ev.estado_entrega,
       ev.intentos, ev.siguiente_intento, ev.ultimo_error, ev.creado_en
  FROM creditos.evento_entrega ev
  JOIN creditos.orden_desembolso o ON o.id_orden = ev.id_orden
 WHERE ev.estado_entrega IN ('PENDIENTE', 'ENVIADO', 'FALLIDO') AND ev.intentos > 2;

-- Base para cuadrar operaciones e importes por fecha y moneda contra el CORE:
-- importe de las órdenes confirmadas frente a lo abonado en las cuentas.
CREATE VIEW creditos.v_conciliacion_diaria AS
SELECT core.fn_fecha_negocio(coalesce(m.fecha_hora, o.actualizado_en)) AS fecha,
       s.moneda,
       count(*) AS ordenes_confirmadas,
       sum(o.importe) AS importe_ordenes,
       coalesce(sum(m.monto) FILTER (WHERE m.estado_transaccion = 'APROBADO'), 0) AS importe_abonado,
       count(*) FILTER (WHERE m.uuid_transaccion IS NULL) AS ordenes_sin_abono
  FROM creditos.orden_desembolso o
  JOIN creditos.evaluacion e ON e.id_evaluacion = o.id_evaluacion
  JOIN creditos.solicitud_credito s ON s.id_solicitud = e.id_solicitud
  LEFT JOIN cuentas.movimiento m ON m.uuid_transaccion = o.uuid_transaccion_abono
 WHERE o.estado_orden = 'CONFIRMADA'
 GROUP BY core.fn_fecha_negocio(coalesce(m.fecha_hora, o.actualizado_en)), s.moneda;

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
