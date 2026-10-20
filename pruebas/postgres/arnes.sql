-- Arnés de pruebas de la base integrada (esquema prueba).
-- Cada prueba corre dentro de un subbloque que termina siempre con una
-- excepción, de modo que sus cambios se deshacen y las pruebas no se
-- afectan entre sí; solo el veredicto queda en prueba.resultado.
-- SET CONSTRAINTS ALL IMMEDIATE adelanta dentro del subbloque las
-- verificaciones diferidas que, fuera de una prueba, ocurren al confirmar.
CREATE SCHEMA prueba;

CREATE TABLE prueba.resultado (
    n           SERIAL PRIMARY KEY,
    id          TEXT NOT NULL,
    grupo       TEXT NOT NULL,
    referencia  TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    esperado    TEXT NOT NULL,
    obtenido    TEXT NOT NULL,
    ok          BOOLEAN           -- NULL = N/A
);

CREATE SEQUENCE prueba.seq_asiento;

-- La operación debe rechazarse con un mensaje que cumpla p_patron.
CREATE FUNCTION prueba.rechaza(p_id TEXT, p_grupo TEXT, p_ref TEXT, p_desc TEXT,
                               p_sql TEXT, p_patron TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_msg TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'PRUEBA_ACEPTADA';
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
    VALUES (p_id, p_grupo, p_ref, p_desc, 'Rechazo: ' || p_patron,
            CASE WHEN v_msg = 'PRUEBA_ACEPTADA' THEN 'Aceptada sin error' ELSE 'Rechazo: ' || v_msg END,
            v_msg <> 'PRUEBA_ACEPTADA' AND v_msg ~ p_patron);
END $$;

-- La operación debe aceptarse y dejar el estado que describe p_cond.
CREATE FUNCTION prueba.verifica(p_id TEXT, p_grupo TEXT, p_ref TEXT, p_desc TEXT,
                                p_sql TEXT, p_cond TEXT, p_esperado TEXT, p_obtenido TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_ok  BOOLEAN;
    v_obt TEXT;
BEGIN
    BEGIN
        IF p_sql <> '' THEN
            EXECUTE p_sql;
        END IF;
        SET CONSTRAINTS ALL IMMEDIATE;
        EXECUTE p_cond INTO v_ok;
        EXECUTE p_obtenido INTO v_obt;
        RAISE EXCEPTION 'PRUEBA_FIN';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM <> 'PRUEBA_FIN' THEN
            v_ok := FALSE;
            v_obt := 'Error: ' || SQLERRM;
        END IF;
    END;
    INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
    VALUES (p_id, p_grupo, p_ref, p_desc, p_esperado, coalesce(v_obt, '(sin dato)'), coalesce(v_ok, FALSE));
END $$;

-- Falla que no tiene una prueba de ejecución con sentido.
CREATE FUNCTION prueba.na(p_id TEXT, p_grupo TEXT, p_ref TEXT, p_desc TEXT, p_razon TEXT)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO prueba.resultado (id, grupo, referencia, descripcion, esperado, obtenido, ok)
    VALUES (p_id, p_grupo, p_ref, p_desc, '—', p_razon, NULL);
$$;

-- Registra un movimiento con su asiento de partida doble cuadrado
-- (cuentas contables 1101 Caja y 2101 Depósitos de ahorro). p_uuid permite
-- registrar el movimiento de una autorización con el identificador de su
-- operación.
CREATE FUNCTION prueba.movimiento(p_cuenta VARCHAR, p_tipo VARCHAR, p_monto NUMERIC,
                                  p_canal VARCHAR DEFAULT NULL, p_moneda CHAR(3) DEFAULT NULL,
                                  p_uuid UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_asiento UUID := gen_random_uuid();
    v_mov     UUID := coalesce(p_uuid, gen_random_uuid());
    v_nat     CHAR(1);
    v_moneda  CHAR(3);
BEGIN
    SELECT naturaleza INTO v_nat FROM cuentas.tipo_operacion WHERE tipo_operacion = p_tipo;
    SELECT coalesce(p_moneda, moneda) INTO v_moneda FROM cuentas.cuenta_ahorro WHERE num_cuenta = p_cuenta;
    INSERT INTO core.asiento_contable (id_asiento, numero_asiento, fecha_contable, fecha_valor, glosa,
                                       moneda, correlation_id)
    VALUES (v_asiento, 'P-' || nextval('prueba.seq_asiento'), current_date, current_date,
            p_tipo || ' ' || p_cuenta, v_moneda, gen_random_uuid());
    INSERT INTO core.detalle_asiento (id_asiento, nro_linea, tipo_partida, importe, codigo_contable) VALUES
        (v_asiento, 1, CASE v_nat WHEN 'C' THEN 'DEBE' ELSE 'HABER' END, p_monto, '1101'),
        (v_asiento, 2, CASE v_nat WHEN 'C' THEN 'HABER' ELSE 'DEBE' END, p_monto, '2101');
    INSERT INTO cuentas.movimiento (uuid_transaccion, tipo_operacion, monto, glosa, estado_transaccion,
                                    id_asiento, num_cuenta, id_canal)
    VALUES (v_mov, p_tipo, p_monto, 'Prueba', 'APROBADO', v_asiento, p_cuenta, p_canal);
    RETURN v_mov;
END $$;
