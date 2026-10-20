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
    v_nat     CHAR(1);
    v_canal   VARCHAR(5);
    v_momento TIMESTAMPTZ;
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
    ELSIF v_nat = 'D' THEN
        -- Extorno: el monto deja de contar para el tope del día y el canal en
        -- que se comprometió (Tarjetas, C07): los de su autorización, si la
        -- tiene, aunque el movimiento se haya registrado otro día.
        SELECT coalesce(a.id_canal, t.id_canal), a.fecha_hora INTO v_canal, v_momento
          FROM tarjetas.autorizacion a LEFT JOIN core.terminal t ON t.id_terminal = a.id_terminal
         WHERE a.uuid_autorizacion = NEW.uuid_transaccion;
        IF NOT FOUND THEN
            v_canal := NEW.id_canal;
            v_momento := NEW.fecha_hora;
        END IF;
        IF v_canal IS NOT NULL THEN
            PERFORM core.fn_consumo_sumar(NEW.num_cuenta, v_canal, core.fn_fecha_negocio(v_momento), -NEW.monto);
        END IF;
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
