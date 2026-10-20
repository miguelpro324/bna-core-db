# PostgreSQL DDL of the final (normalized) schema.  Called from modelo_bna.py.
# Every design decision taken while writing the DDL is marked "DECISIÓN" both
# here and, where it matters to the reader of the script, in the SQL output.
import os
import re

from modelo_bna import E, R, STAGES, CATALOGS

FIN = STAGES["fin"]

# ---------------------------------------------------------------------------
# Logical schemas.  DECISIÓN: one PostgreSQL database with the logical schemas
# of the CORE architecture; each table lives in the schema of the module that
# owns the data.  Channels, limits and daily consumption belong to CORE because
# CORE owns the daily limits (topes diarios).
# ---------------------------------------------------------------------------
SCHEMAS = {
    "core": ["AGENCIA", "CUENTA_CONTABLE", "ASIENTO_CONTABLE", "DETALLE_ASIENTO", "MONEDA",
             "MODULO", "CANAL", "CANAL_VALIDACION", "LIMITE_CANAL", "CONSUMO_DIARIO", "TERMINAL"],
    "clientes": ["CLIENTE", "BIOMETRIA_CLIENTE", "CODIGO_VERIFICACION", "VALIDACION_IDENTIDAD",
                 "VERIFICACION_CAPTACION", "TIPO_DOCUMENTO", "TIPO_BIOMETRIA", "TIPO_CONTACTO",
                 "TIPO_VALIDACION", "ESTADO_CLIENTE"],
    "cuentas": ["CUENTA_AHORRO", "MOVIMIENTO", "TITULARIDAD", "TIPO_OPERACION", "REGIMEN_CUENTA",
                "ESTADO_CUENTA"],
    "tarjetas": ["TARJETA", "BIN_TARJETA", "TARJETA_CUENTA", "CREDENCIAL", "TIPO_CREDENCIAL",
                 "MATRIZ_TOKEN", "MATRIZ_COORDENADA", "TOKEN_PAGO", "PASARELA_PAGO",
                 "INTENTO_AUTENTICACION", "AUTORIZACION", "CODIGO_RESPUESTA",
                 "HISTORIAL_ESTADO_TARJETA", "ESTADO_TARJETA", "ORIGEN_CAMBIO", "EVENTO_SALIDA",
                 "TIPO_EVENTO_SALIDA"],
    "creditos": ["SOLICITUD_CREDITO", "HISTORIAL_ESTADO_SOLICITUD", "ESTADO_SOLICITUD", "GARANTIA",
                 "TIPO_GARANTIA", "FIADOR", "FIADOR_SOLICITUD", "CALENDARIO_PAGO",
                 "METODO_AMORTIZACION", "CUOTA", "ESTADO_CUOTA", "SITUACION_FINANCIERA",
                 "EVALUACION", "REGLA_EVALUACION", "RESULTADO_CREDITICIO", "ANALISTA",
                 "DECISION_ANALISTA", "ORDEN_DESEMBOLSO", "ESTADO_ORDEN", "VALIDACION_DESEMBOLSO",
                 "TIPO_VALIDACION_DESEMBOLSO", "EVENTO_ENTREGA", "SOLICITUD_REVERSION", "CREDITO",
                 "ESTADO_CREDITO", "PAGO", "APLICACION_PAGO", "MORA", "EVENTO_AUDITORIA",
                 "ENTIDAD_AUDITADA"],
}
SCHEMA_OF = {t: s for s, ts in SCHEMAS.items() for t in ts}


def q(rel):
    return "%s.%s" % (SCHEMA_OF[rel], rel.lower())


# ---------------------------------------------------------------------------
# Types.  DECISIÓN (convenciones):
#   * identificadores de entidades de negocio: UUID generado por defecto
#     (la arquitectura del CORE fija UUID); bitácoras de solo inserción:
#     BIGINT GENERATED ALWAYS AS IDENTITY (orden de inserción, volumen);
#   * códigos legibles de negocio y de catálogo: VARCHAR del largo de la fuente;
#   * importes: NUMERIC(15,2) (nunca FLOAT); tasas y ratios: NUMERIC con 4 o 2
#     decimales; fechas de negocio: DATE; marcas de tiempo: TIMESTAMPTZ (UTC);
#   * hashes SHA-256: CHAR(64); sales: CHAR(32); plantillas biométricas: BYTEA;
#   * mensajes y detalles semiestructurados: JSONB.
# ---------------------------------------------------------------------------
IDENTITY = {"EVENTO_AUDITORIA.id_evento", "INTENTO_AUTENTICACION.id_intento",
            "HISTORIAL_ESTADO_TARJETA.id_historial", "HISTORIAL_ESTADO_SOLICITUD.id_historial",
            "EVENTO_SALIDA.id_evento", "VALIDACION_IDENTIDAD.id_validacion",
            "EVENTO_ENTREGA.id_evento"}

TYPES = {
    # códigos de negocio
    "id_agencia": "VARCHAR(10)", "codigo_contable": "VARCHAR(20)", "codigo_padre": "VARCHAR(20)",
    "numero_asiento": "VARCHAR(20)", "cod_cliente": "VARCHAR(12)", "num_cuenta": "VARCHAR(20)",
    "cci": "CHAR(20)", "id_canal": "VARCHAR(5)", "id_terminal": "VARCHAR(30)",
    "cod_credito": "VARCHAR(20)", "codigo_orden": "VARCHAR(24)", "bin": "CHAR(6)",
    "ultimos4": "CHAR(4)", "pan_token": "VARCHAR(32)", "numero_serie": "VARCHAR(20)",
    "valor_token": "VARCHAR(64)", "codigo_rn": "VARCHAR(20)", "codigo_empleado": "VARCHAR(20)",
    "id_regla": "VARCHAR(10)", "id_analista": "VARCHAR(10)",
    "id_persona_externa": "VARCHAR(36)", "id_verificacion": "VARCHAR(36)",
    "id_verificacion_captacion": "VARCHAR(36)", "referencia_transaccion": "VARCHAR(40)",
    "referencia_evidencia": "VARCHAR(100)", "confirmacion_id": "VARCHAR(60)",
    "autorizacion_id": "VARCHAR(60)", "solicitante_id": "VARCHAR(40)",
    "usuario_preparacion": "VARCHAR(40)", "usuario_confirmacion": "VARCHAR(40)",
    "actor": "VARCHAR(40)", "version_contrato": "VARCHAR(10)", "version_esquema": "VARCHAR(10)",
    # catálogos
    "cod_moneda": "CHAR(3)", "moneda": "CHAR(3)", "id_modulo": "SMALLINT",
    "id_modulo_destino": "SMALLINT", "id_modulo_proveedor": "SMALLINT", "modulo_emisor": "SMALLINT",
    "cod_tipo_documento": "VARCHAR(10)", "tipo_documento": "VARCHAR(10)",
    "cod_tipo_biometria": "VARCHAR(10)", "tipo_biometria": "VARCHAR(10)",
    "cod_tipo_contacto": "VARCHAR(10)", "tipo_contacto": "VARCHAR(10)",
    "cod_tipo_validacion": "VARCHAR(15)", "cod_regimen": "VARCHAR(25)", "regimen": "VARCHAR(25)",
    "cod_estado": "VARCHAR(25)", "estado_cliente": "VARCHAR(25)", "estado_cuenta": "VARCHAR(25)",
    "estado_tarjeta": "VARCHAR(25)", "estado_nuevo": "VARCHAR(25)", "estado_solicitud": "VARCHAR(25)",
    "estado_orden": "VARCHAR(25)", "estado_credito": "VARCHAR(25)", "estado_cuota": "VARCHAR(25)",
    "tipo_operacion": "VARCHAR(25)", "tipo_credencial": "VARCHAR(15)",
    "cod_respuesta": "VARCHAR(4)", "codigo_respuesta": "VARCHAR(4)", "cod_origen": "VARCHAR(20)",
    "origen": "VARCHAR(20)", "cod_tipo_garantia": "VARCHAR(20)", "tipo_garantia": "VARCHAR(20)",
    "cod_metodo": "VARCHAR(20)", "metodo_amortizacion": "VARCHAR(20)",
    "cod_resultado": "VARCHAR(12)", "accion": "VARCHAR(12)", "decision": "VARCHAR(12)",
    "id_pasarela": "VARCHAR(20)", "proveedor_pasarela": "VARCHAR(20)",
    # importes, tasas y contadores
    "importe": "NUMERIC(15,2)", "monto": "NUMERIC(15,2)", "monto_pago": "NUMERIC(15,2)",
    "monto_aplicado": "NUMERIC(15,2)", "monto_calculado": "NUMERIC(15,2)",
    "monto_solicitado": "NUMERIC(15,2)", "monto_maximo_diario": "NUMERIC(15,2)",
    "monto_acumulado": "NUMERIC(15,2)", "saldo_contable": "NUMERIC(15,2)",
    "saldo_disponible": "NUMERIC(15,2)", "capital": "NUMERIC(15,2)", "interes": "NUMERIC(15,2)",
    "otros_conceptos": "NUMERIC(15,2)", "saldo_capital": "NUMERIC(15,2)",
    "saldo_pendiente": "NUMERIC(15,2)", "valor_referencial": "NUMERIC(15,2)",
    "limite_aprobado": "NUMERIC(15,2)", "ingreso_mensual": "NUMERIC(15,2)",
    "deuda_reportada": "NUMERIC(15,2)", "tasa_aplicada": "NUMERIC(7,4)",
    "score_calculado": "NUMERIC(6,2)", "ratio_min": "NUMERIC(7,2)", "ratio_max": "NUMERIC(7,2)",
    "umbral_similitud": "NUMERIC(5,4)", "intentos_fallidos": "SMALLINT", "intentos": "SMALLINT",
    "max_intentos": "SMALLINT", "vigencia_minutos": "SMALLINT", "longitud": "SMALLINT",
    "longitud_min": "SMALLINT", "longitud_max": "SMALLINT", "decimales": "SMALLINT",
    "min_titulares": "SMALLINT", "plazo_meses": "SMALLINT", "numero_cuota": "SMALLINT",
    "nro_linea": "SMALLINT", "ronda": "SMALLINT", "version": "SMALLINT",
    "version_solicitud": "SMALLINT", "version_registro": "INTEGER", "columna": "SMALLINT",
    "coord_columna": "SMALLINT", "fila": "CHAR(1)", "coord_fila": "CHAR(1)",
    # fechas
    "fecha_vencimiento": "DATE", "fecha_emision": "DATE", "fecha_corte": "DATE",
    "fecha_contable": "DATE", "fecha_valor": "DATE", "fecha_expiracion": "TIMESTAMPTZ",
    # seguridad y datos opacos
    "hash_credencial": "CHAR(64)", "hash_valor": "CHAR(64)", "codigo_otp": "CHAR(64)",
    "request_hash": "CHAR(64)", "sal": "CHAR(32)", "datos_biometricos": "BYTEA",
    "carga_json": "JSONB", "payload": "JSONB", "detalle": "JSONB", "ip_origen": "INET",
    # textos
    "nombre": "VARCHAR(100)", "nombres": "VARCHAR(100)", "apellido_paterno": "VARCHAR(100)",
    "apellido_materno": "VARCHAR(100)", "correo": "VARCHAR(150)", "celular": "CHAR(9)",
    "numero_documento": "VARCHAR(12)", "calle": "VARCHAR(120)", "distrito": "VARCHAR(60)",
    "ciudad": "VARCHAR(60)", "glosa": "VARCHAR(200)", "descripcion": "VARCHAR(255)",
    "motivo": "VARCHAR(255)", "motivo_rechazo": "VARCHAR(255)", "comentario": "VARCHAR(500)",
    "condiciones_propuestas": "VARCHAR(300)", "observaciones": "VARCHAR(500)",
    "ultimo_error": "VARCHAR(255)", "endpoint": "VARCHAR(80)", "simbolo": "VARCHAR(4)",
    "regla_tope": "VARCHAR(20)", "tipo_integracion": "VARCHAR(30)",
    "resultado_verificacion": "VARCHAR(20)",
}
# Overrides by relation.attribute
TYPES_REL = {
    "VALIDACION_DESEMBOLSO.detalle": "VARCHAR(255)",
    "TIPO_OPERACION.naturaleza": "CHAR(1)",
    "TIPO_VALIDACION_DESEMBOLSO.tipo_validacion": "VARCHAR(15)",
    "VALIDACION_DESEMBOLSO.tipo_validacion": "VARCHAR(15)",
    "VALIDACION_IDENTIDAD.tipo_validacion": "VARCHAR(15)",
    "CANAL_VALIDACION.tipo_validacion": "VARCHAR(15)",
    "TIPO_EVENTO_SALIDA.tipo_evento": "VARCHAR(30)", "EVENTO_SALIDA.tipo_evento": "VARCHAR(30)",
    "EVENTO_ENTREGA.tipo_evento": "VARCHAR(60)",
    "EVENTO_AUDITORIA.accion": "VARCHAR(60)", "EVENTO_AUDITORIA.resultado": "VARCHAR(40)",
    "MODULO.nombre": "VARCHAR(40)", "CANAL.nombre": "VARCHAR(40)",
    "BIN_TARJETA.descripcion": "VARCHAR(100)",
    # DECISIÓN: id_entidad guarda UUID (orden, pago, calendario) o códigos
    #   (crédito), por eso es texto y no UUID.
    "ENTIDAD_AUDITADA.id_entidad": "VARCHAR(36)", "EVENTO_AUDITORIA.id_entidad": "VARCHAR(36)",
}


def col_type(rel, a):
    key = "%s.%s" % (rel, a["name"])
    if key in IDENTITY:
        return "BIGINT GENERATED ALWAYS AS IDENTITY"
    if key in TYPES_REL:
        return TYPES_REL[key]
    n = a["name"]
    if n in TYPES:
        return TYPES[n]
    if n.startswith(("id_", "uuid_")):
        return "UUID"
    if n.startswith(("es_", "permite_", "habilitad", "puede_")) or n in (
            "activo", "estado_activo", "firma_conjunta", "condicion_pago_doble"):
        return "BOOLEAN"
    if n.startswith(("fecha_", "creado_en", "actualizado_en", "vence_en", "siguiente_intento")):
        return "TIMESTAMPTZ"
    if n in ("correlation_id", "uuid_correlacion", "idempotency_key"):
        return "UUID"
    if n.startswith(("estado_", "tipo_", "resultado", "naturaleza", "nivel_")):
        return "VARCHAR(25)"
    raise KeyError("sin tipo: " + key)


# Base attributes that admit NULL (FK nullability comes from participation).
NULLABLE = {
    "CLIENTE.apellido_materno", "GARANTIA.descripcion", "HISTORIAL_ESTADO_TARJETA.motivo",
    "HISTORIAL_ESTADO_SOLICITUD.motivo", "INTENTO_AUTENTICACION.motivo_rechazo",
    "AUTORIZACION.motivo_rechazo", "AUTORIZACION.codigo_respuesta", "AUTORIZACION.nivel_riesgo",
    "ORDEN_DESEMBOLSO.motivo_rechazo", "ORDEN_DESEMBOLSO.usuario_confirmacion",
    "EVALUACION.condiciones_propuestas", "EVALUACION.observaciones",
    "VALIDACION_DESEMBOLSO.detalle", "VALIDACION_DESEMBOLSO.vence_en",
    "EVENTO_ENTREGA.siguiente_intento", "EVENTO_ENTREGA.confirmacion_id",
    "EVENTO_ENTREGA.ultimo_error", "SOLICITUD_REVERSION.autorizacion_id",
    "REGLA_EVALUACION.ratio_min", "REGLA_EVALUACION.ratio_max",
    "LIMITE_CANAL.monto_maximo_diario", "EVENTO_SALIDA.fecha_envio",
    "EVENTO_AUDITORIA.ip_origen", "EVENTO_AUDITORIA.detalle", "EVENTO_AUDITORIA.resultado",
    "INTENTO_AUTENTICACION.uuid_correlacion", "TIPO_CREDENCIAL.longitud",
    "TIPO_BIOMETRIA.umbral_similitud", "CUENTA_CONTABLE.codigo_padre",
}

DEFAULTS = {
    "saldo_contable": "0", "saldo_disponible": "0", "monto_acumulado": "0",
    "intentos_fallidos": "0", "intentos": "0", "otros_conceptos": "0",
    "version_solicitud": "1", "version_registro": "0", "condicion_pago_doble": "FALSE",
    "activo": "TRUE", "estado_activo": "TRUE", "habilitado": "TRUE",
    "es_principal": "FALSE", "habilitada_atm": "TRUE",
    "creado_en": "now()", "actualizado_en": "now()", "fecha_hora": "now()",
    "fecha_registro": "now()", "fecha_evento": "now()", "fecha_creacion": "now()",
    "fecha_calculo": "now()", "fecha_generacion": "now()", "fecha_evaluacion": "now()",
    "fecha_decision": "now()", "fecha_consulta": "now()", "fecha_apertura": "now()",
    "fecha_vinculacion": "now()", "fecha_actualizacion": "now()",
    "fecha_ultimo_cambio": "now()", "fecha_verificacion": "now()",
}

# Closed domains kept as CHECK (see the catalog section of the report).
ENUMS = {
    "AGENCIA.estado_agencia": ["ACTIVA", "INACTIVA"],
    "CUENTA_CONTABLE.naturaleza": ["DEUDORA", "ACREEDORA"],
    "DETALLE_ASIENTO.tipo_partida": ["DEBE", "HABER"],
    "TIPO_OPERACION.naturaleza": ["D", "C", "N"],
    "CODIGO_VERIFICACION.estado_codigo": ["PENDIENTE", "VALIDADO", "EXPIRADO", "BLOQUEADO"],
    "VALIDACION_IDENTIDAD.resultado": ["APROBADO", "RECHAZADO"],
    "VERIFICACION_CAPTACION.estado_habilitante": ["HABILITADO", "OBSERVADO"],
    "MOVIMIENTO.estado_transaccion": ["APROBADO", "EXTORNADO"],
    "BIN_TARJETA.tipo_tarjeta": ["FISICA", "VIRTUAL"],
    "MATRIZ_TOKEN.tipo_matriz": ["FISICA", "VIRTUAL"],
    "MATRIZ_TOKEN.estado_matriz": ["ACTIVA", "BLOQUEADA", "REEMPLAZADA"],
    "TOKEN_PAGO.estado_token": ["ACTIVO", "SUSPENDIDO", "REVOCADO"],
    "INTENTO_AUTENTICACION.resultado": ["EXITOSO", "FALLIDO"],
    "AUTORIZACION.estado_autorizacion": ["INICIADA", "AUTORIZADA", "RECHAZADA", "DISPENSADA",
                                         "EXTORNADA", "PENDIENTE_REVERSION"],
    "AUTORIZACION.nivel_riesgo": ["BAJO", "MEDIO", "ALTO"],
    "EVENTO_SALIDA.estado_envio": ["PENDIENTE", "ENVIADO", "ERROR"],
    "GARANTIA.estado_garantia": ["REGISTRADA", "EN_TASACION", "CONSTITUIDA", "LEVANTADA"],
    "CALENDARIO_PAGO.tipo_calendario": ["PRELIMINAR", "OFICIAL"],
    "CALENDARIO_PAGO.estado_calendario": ["VIGENTE", "HISTORICO", "DESCARTADO"],
    "VALIDACION_DESEMBOLSO.resultado": ["APROBADA", "RECHAZADA"],
    "EVENTO_ENTREGA.tipo_evento": ["desembolso.confirmado", "desembolso.revertido"],
    "EVENTO_ENTREGA.estado_entrega": ["PENDIENTE", "ENVIADO", "CONFIRMADO", "FALLIDO"],
    "SOLICITUD_REVERSION.estado_reversion": ["SOLICITADA", "AUTORIZADA", "CONFIRMADA", "RECHAZADA"],
    "PAGO.estado_confirmacion": ["PENDIENTE", "CONFIRMADO", "RECHAZADO"],
    "ENTIDAD_AUDITADA.tipo_entidad": ["ORDEN", "CREDITO", "PAGO", "CUOTA"],
}

CHECKS = {
    "CLIENTE": ["celular ~ '^9[0-9]{8}$'"],
    "CUENTA_AHORRO": ["saldo_disponible <= saldo_contable", "saldo_disponible >= 0"],
    "MOVIMIENTO": ["monto > 0"],
    "DETALLE_ASIENTO": ["importe > 0"],
    "CONSUMO_DIARIO": ["monto_acumulado >= 0"],
    "LIMITE_CANAL": ["monto_maximo_diario IS NULL OR monto_maximo_diario > 0"],
    "TARJETA": ["fecha_vencimiento > fecha_emision", "ultimos4 ~ '^[0-9]{4}$'"],
    "BIN_TARJETA": ["bin ~ '^[0-9]{6}$'"],
    "CREDENCIAL": ["tipo_credencial IN ('PIN_ATM', 'CLAVE_WEB')",
                   "intentos_fallidos BETWEEN 0 AND 3"],
    "MATRIZ_TOKEN": ["intentos_fallidos BETWEEN 0 AND 3"],
    "MATRIZ_COORDENADA": ["fila BETWEEN 'A' AND 'G'", "columna BETWEEN 0 AND 9"],
    "INTENTO_AUTENTICACION": [
        "coord_fila IS NULL OR coord_fila BETWEEN 'A' AND 'G'",
        "coord_columna IS NULL OR coord_columna BETWEEN 0 AND 9",
        "(coord_fila IS NULL) = (coord_columna IS NULL)",
        "(coord_fila IS NOT NULL) = (tipo_credencial = 'TOKEN_MATRIZ')",
        "num_nonnulls(id_terminal, id_canal) = 1"],
    "AUTORIZACION": ["monto >= 0", "num_nonnulls(id_terminal, id_canal) = 1"],
    "SOLICITUD_CREDITO": ["monto_solicitado > 0", "plazo_meses > 0"],
    "GARANTIA": ["valor_referencial > 0"],
    "CALENDARIO_PAGO": ["tasa_aplicada >= 0"],
    "CUOTA": ["numero_cuota > 0", "capital >= 0", "interes >= 0", "otros_conceptos >= 0",
              "saldo_pendiente >= 0"],
    "EVALUACION": ["limite_aprobado >= 0"],
    "REGLA_EVALUACION": ["ratio_min IS NULL OR ratio_max IS NULL OR ratio_min < ratio_max"],
    "ORDEN_DESEMBOLSO": ["importe > 0"],
    "PAGO": ["monto_pago > 0"],
    "APLICACION_PAGO": ["monto_aplicado > 0"],
    "MORA": ["monto_calculado >= 0"],
    "EVENTO_AUDITORIA": ["numero_cuota IS NULL OR id_entidad IS NOT NULL"],
    "TIPO_DOCUMENTO": ["longitud_min <= longitud_max"],
    "REGIMEN_CUENTA": ["min_titulares >= 1"],
    "TIPO_CONTACTO": ["vigencia_minutos > 0", "max_intentos > 0"],
}

# Candidate keys besides the PK that do not come from UK attributes or 1:1 FKs.
EXTRA_UNIQUE = {
    "CALENDARIO_PAGO": [("id_solicitud", "version")],
    "EVALUACION": [("id_solicitud", "ronda")],
    "MORA": [("id_calendario", "numero_cuota", "fecha_calculo")],
    "MODULO": [("nombre",)],
    "TIPO_VALIDACION": [("endpoint",)],
    "CLIENTE": [("id_verificacion_captacion",)],
    "FIADOR_SOLICITUD": [("id_verificacion",)],
    "REGLA_EVALUACION": [("ratio_min", "ratio_max")],
}

# Partial unique indexes (business rules expressible as indexes).
PARTIAL = [
    ("ux_matriz_activa", "MATRIZ_TOKEN", "id_tarjeta", "estado_matriz = 'ACTIVA'",
     "una sola matriz ACTIVA por tarjeta (RN-TAR-002); reemplaza tarjeta_si_activa"),
    ("ux_orden_confirmada", "ORDEN_DESEMBOLSO", "id_evaluacion", "estado_orden = 'CONFIRMADA'",
     "una sola orden CONFIRMADA por aprobación; reemplaza credito_confirmado"),
    ("ux_tarjeta_principal", "TARJETA_CUENTA", "id_tarjeta", "es_principal",
     "una sola cuenta principal por tarjeta"),
    ("ux_biometria_vigente", "BIOMETRIA_CLIENTE", "cod_cliente, tipo_biometria", "estado_activo",
     "una sola plantilla vigente por cliente y tipo"),
]

# Composite FKs that are not relationships of the MER but rules of the sources.
EXTRA_FK = [
    ("AUTORIZACION", ("id_tarjeta", "num_cuenta"), "TARJETA_CUENTA",
     "la cuenta afectada debe estar vinculada a la tarjeta (trigger de TARJETAS)"),
]

# Rules that need data of other tables: implemented with triggers (listed).
TRIGGER_RULES = [
    "CREDITO: el calendario debe pertenecer a la solicitud de la evaluación de su orden.",
    "ORDEN_DESEMBOLSO: una sola orden CONFIRMADA por solicitud (en todas sus rondas).",
    "ORDEN_DESEMBOLSO: la cuenta destino pertenece al cliente de la solicitud y tiene su moneda.",
    "APLICACION_PAGO: la cuota pertenece al calendario del crédito del pago.",
    "AUTORIZACION: el importe no supera el tope del canal ni el saldo (RN-TOP-001).",
    "CUENTA_AHORRO: los saldos se actualizan en la misma transacción que el movimiento.",
    "TARJETA: estado_tarjeta se actualiza al insertar en HISTORIAL_ESTADO_TARJETA.",
    "HISTORIAL_*, INTENTO_AUTENTICACION, EVENTO_AUDITORIA: solo inserción (sin UPDATE/DELETE).",
]


def uniques(rel):
    out = []
    cols = {a["name"] for a in FIN[rel]}
    if rel in E:
        for a in E[rel]["attrs"]:
            if a["key"] == "UK":
                names = [c for c, _ in a["comp"]] if a["comp"] else [a["name"]]
                if all(n in cols for n in names):
                    out.append(tuple(names))
    for r in R:
        if r["card"] == "1:1" and r["fk"] and r["fk"][0] == rel:
            names = tuple(fa for fa, _ in r["fk"][1])
            if all(n in cols for n in names):
                out.append(names)
    out += EXTRA_UNIQUE.get(rel, [])
    return out


def pk(rel):
    return [a["name"] for a in FIN[rel] if a["pk"]]


def fks(rel):
    """[(cols, target)] grouped as in the relational notation."""
    out, seen = [], set()
    for a in FIN[rel]:
        if not a["fk"]:
            continue
        if a["grp"]:
            if a["grp"] in seen:
                continue
            seen.add(a["grp"])
            out.append((tuple(x["name"] for x in FIN[rel] if x["grp"] == a["grp"]), a["fk"]))
        else:
            out.append(((a["name"],), a["fk"]))
    return out


def comment_text(rel):
    if rel in E:
        return re.sub(r"`", "", E[rel]["desc"])
    for t, cols, uses, crit, note in CATALOGS:
        if t == rel:
            return "Catálogo. " + re.sub(r"`", "", note)
    return {
        "TITULARIDAD": "Titulares de cada cuenta (relación N:M ES_TITULAR).",
        "TARJETA_CUENTA": "Cuentas que opera cada tarjeta (relación N:M VINCULA).",
        "FIADOR_SOLICITUD": "Fiadores que respaldan cada solicitud (relación N:M RESPALDA).",
        "APLICACION_PAGO": "Reparto de cada pago entre cuotas (relación N:M APLICA).",
        "CANAL_VALIDACION": "Credenciales que exige cada canal (atributo multivaluado).",
        "TIPO_CREDENCIAL": "Tipos de credencial y su longitud (2FN).",
        "VERIFICACION_CAPTACION": "Verificación de captación del cliente (3FN).",
        "TIPO_OPERACION": "Tipos de operación y su naturaleza D/C/N (3FN).",
        "BIN_TARJETA": "BIN emitidos por el BNA y el tipo de tarjeta que identifican (3FN).",
        "TERMINAL": "Terminales físicas (cajeros, agentes, ventanillas) y su canal (3FN).",
        "TIPO_VALIDACION_DESEMBOLSO": "Tipos de validación previa al desembolso y su proveedor (3FN).",
        "TIPO_EVENTO_SALIDA": "Tipos de evento hacia otros módulos y su destino (3FN).",
        "ENTIDAD_AUDITADA": "Registros auditables y su tipo (3FN).",
    }[rel]


def sql_str(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


# ---------------------------------------------------------------------------
# Seed data: only values documented by the sources (CORE loads parameters).
# ---------------------------------------------------------------------------
SEEDS = [
    ("MONEDA", ["cod_moneda", "nombre", "simbolo", "decimales"],
     [("PEN", "Sol", "S/", 2), ("USD", "Dólar estadounidense", "US$", 2)]),
    ("MODULO", ["id_modulo", "nombre"],
     [(1, "CORE"), (2, "CLIENTES"), (3, "CUENTAS"), (8, "BUS DE SERVICIOS"), (9, "SEGURIDAD"),
      (11, "SOLICITUD DE CREDITO"), (12, "EVALUACION"), (13, "DESEMBOLSO"), (14, "COBRANZA")]),
    ("TIPO_DOCUMENTO", ["cod_tipo_documento", "descripcion", "longitud_min", "longitud_max", "es_alfanumerico"],
     [("DNI", "Documento Nacional de Identidad", 8, 8, False),
      ("CE", "Carné de extranjería", 9, 12, True),
      ("PTP", "Permiso Temporal de Permanencia", 9, 9, False),
      ("PASAPORTE", "Pasaporte", 6, 12, True)]),
    ("TIPO_BIOMETRIA", ["cod_tipo_biometria", "descripcion", "umbral_similitud"],
     [("DACTILAR", "Huella dactilar", None), ("FACIAL", "Reconocimiento facial", None)]),
    ("TIPO_CONTACTO", ["cod_tipo_contacto", "descripcion", "vigencia_minutos", "max_intentos"],
     [("SMS", "Código enviado al celular", 5, 3), ("CORREO", "Código enviado al correo", 10, 3)]),
    ("TIPO_VALIDACION", ["cod_tipo_validacion", "descripcion", "endpoint"],
     [("DOCUMENTO", "Validación de documento", "/api/v1/kyc/validar-documento"),
      ("HUELLA", "Verificación dactilar", "/api/v1/kyc/validar-huella"),
      ("FACIAL", "Verificación facial", "/api/v1/kyc/validar-facial"),
      ("CELULAR", "Confirmación de celular", "/api/v1/kyc/celular/verificar-codigo"),
      ("CORREO", "Confirmación de correo", "/api/v1/kyc/correo/verificar-codigo")]),
    ("ESTADO_CLIENTE", ["cod_estado", "descripcion", "permite_operar"],
     [("ACTIVO", "Cliente activo", True), ("OBSERVADO", "Cliente observado", True),
      ("BLOQUEADO", "Cliente bloqueado", False), ("SUSPENDIDO", "Cliente suspendido", False),
      ("BAJA", "Cliente dado de baja", False)]),
    ("REGIMEN_CUENTA", ["cod_regimen", "descripcion", "min_titulares", "firma_conjunta"],
     [("INDIVIDUAL", "Un solo titular", 1, False),
      ("MANCOMUNADA_INDISTINTA", "Mancomunada (o): firma cualquier titular", 2, False),
      ("MANCOMUNADA_CONJUNTA", "Mancomunada (y): firman todos los titulares", 2, True)]),
    ("ESTADO_CUENTA", ["cod_estado", "descripcion", "permite_debito", "permite_credito"],
     [("ACTIVA", "Cuenta activa", True, True), ("BLOQUEADA", "Cuenta bloqueada", False, False),
      ("BLOQUEADA_PREVENTIVA", "Bloqueo por seguridad", False, True),
      ("CANCELADA", "Cuenta cancelada", False, False)]),
    ("TIPO_OPERACION", ["tipo_operacion", "naturaleza"],
     [("RETIRO", "D"), ("TRANSFERENCIA_ENVIADA", "D"), ("PAGO", "D"), ("FONDEO_BILLETERA", "D"),
      ("DEBITO_CUOTA", "D"), ("DEPOSITO", "C"), ("TRANSFERENCIA_RECIBIDA", "C"),
      ("DESEMBOLSO", "C"), ("ABONO_INTERES", "C"), ("EXTORNO", "C"), ("CONSULTA_SALDO", "N")]),
    ("CANAL", ["id_canal", "nombre", "es_presencial", "tipo_integracion", "activo", "regla_tope"],
     [("ATM", "Cajero automático", True, "BUS", True, "RN-TOP-001"),
      ("AGE", "Agente BNA", True, "BUS", True, "RN-TOP-001"),
      ("VEN", "Ventanilla", True, "BUS", True, "RN-TOP-001"),
      ("HB", "Home Banking", False, "BUS", True, "RN-TOP-001"),
      ("BD", "Billetera Digital", False, "BUS", True, "RN-BD-002")]),
    ("LIMITE_CANAL", ["id_canal", "moneda", "monto_maximo_diario", "habilitado"],
     [("ATM", "PEN", 1500, True), ("ATM", "USD", 500, True), ("VEN", "PEN", None, True),
      ("VEN", "USD", None, True), ("HB", "PEN", 10000, True), ("BD", "PEN", 500, True),
      ("BD", "USD", None, False)]),
    ("TIPO_CREDENCIAL", ["tipo_credencial", "longitud"],
     [("PIN_ATM", 4), ("CLAVE_WEB", 6), ("TOKEN_MATRIZ", None), ("BIOMETRIA", None),
      ("TOKEN_PAGO", None)]),
    ("CANAL_VALIDACION", ["id_canal", "tipo_validacion"],
     [("ATM", "PIN_ATM"), ("HB", "CLAVE_WEB"), ("HB", "TOKEN_MATRIZ"), ("BD", "TOKEN_PAGO"),
      ("VEN", "BIOMETRIA"), ("AGE", "BIOMETRIA")]),
    ("ESTADO_TARJETA", ["cod_estado", "descripcion", "es_operativa", "es_final"],
     [("PENDIENTE_ACTIVACION", "Emitida, sin activar", False, False),
      ("ACTIVA", "Operativa", True, False), ("BLOQUEADA", "Bloqueada", False, False),
      ("RETENIDA", "Retenida por el cajero", False, False), ("VENCIDA", "Vencida", False, False),
      ("CANCELADA", "Cancelada", False, True)]),
    ("ORIGEN_CAMBIO", ["cod_origen", "descripcion", "puede_desbloquear"],
     [("CLIENTE", "El propio cliente", False), ("SISTEMA", "Proceso automático", False),
      ("SEGURIDAD", "Módulo de seguridad", True), ("OPERADOR", "Operador de ventanilla", True),
      ("MODULO_CLIENTES", "Módulo de clientes", False)]),
    ("CODIGO_RESPUESTA", ["cod_respuesta", "descripcion", "es_aprobacion"],
     [("00", "Aprobada", True), ("54", "Tarjeta vencida", False), ("EXT", "Extorno", False)]),
    ("TIPO_EVENTO_SALIDA", ["tipo_evento", "descripcion", "id_modulo_destino"],
     [("EMISION_TARJETA", "Emisión de tarjeta", 9),
      ("CAMBIO_ESTADO_TARJETA", "Cambio de estado de tarjeta", 9),
      ("BLOQUEO_POR_INTENTOS", "Bloqueo por intentos fallidos", 9)]),
    ("ESTADO_SOLICITUD", ["cod_estado", "descripcion", "es_final"],
     [("REGISTRADA", "Registrada", False), ("EN_EVALUACION", "En evaluación", False),
      ("APROBADA", "Aprobada", False), ("RECHAZADA", "Rechazada", True),
      ("DESEMBOLSADA", "Desembolsada", True)]),
    ("TIPO_GARANTIA", ["cod_tipo_garantia", "descripcion"],
     [("HIPOTECARIA", "Hipoteca"), ("MOBILIARIA", "Garantía mobiliaria"), ("PRENDARIA", "Prenda")]),
    ("METODO_AMORTIZACION", ["cod_metodo", "descripcion"],
     [("FRANCES", "Cuota constante"), ("ALEMAN", "Amortización constante"),
      ("AMERICANO", "Capital al vencimiento")]),
    ("ESTADO_CUOTA", ["cod_estado", "descripcion"],
     [("PENDIENTE", "Pendiente"), ("PARCIAL", "Pagada parcialmente"), ("PAGADA", "Pagada"),
      ("VENCIDA", "Vencida")]),
    ("ESTADO_CREDITO", ["cod_estado", "descripcion"],
     [("AL_DIA", "Al día"), ("EN_MORA", "En mora"), ("CANCELADO", "Cancelado")]),
    ("RESULTADO_CREDITICIO", ["cod_resultado", "descripcion"],
     [("APROBADO", "Aprobado"), ("OBSERVADO", "Derivado a revisión manual"),
      ("RECHAZADO", "Rechazado")]),
    ("REGLA_EVALUACION", ["id_regla", "codigo_rn", "descripcion", "ratio_min", "ratio_max", "accion"],
     [("R-A", "RN-EVA-002-P.a", "Ratio monto/límite hasta 80 %", None, 80, "APROBADO"),
      ("R-B", "RN-EVA-002-P.b", "Ratio monto/límite entre 80 % y 100 %", 80, 100, "OBSERVADO"),
      ("R-C", "RN-EVA-002-P.c", "Ratio monto/límite mayor que 100 %", 100, None, "RECHAZADO")]),
    ("ESTADO_ORDEN", ["cod_estado", "descripcion", "es_final"],
     [("PREPARADA", "Preparada", False), ("VALIDADA", "Validada", False),
      ("EN_PROCESO", "Enviada al CORE", False), ("POR_VERIFICAR", "Respuesta del CORE perdida", False),
      ("CONFIRMADA", "Confirmada", False), ("RECHAZADA", "Rechazada", True),
      ("REVERTIDA", "Revertida", True)]),
    ("TIPO_VALIDACION_DESEMBOLSO", ["tipo_validacion", "descripcion", "id_modulo_proveedor"],
     [("IDENTIDAD", "Identidad del titular", 2), ("CUENTA", "Cuenta destino elegible", 3),
      ("AUTORIZACION", "Autorización de la operación", 9), ("ANTIFRAUDE", "Control antifraude", 9)]),
]


def gen(path):
    L = []
    w = L.append
    w("-- =====================================================================")
    w("-- Banco Nacional de Arequipa (BNA) - base de datos integrada del CORE")
    w("-- PostgreSQL 13 o superior. Generado por tools/modelo_bna.py desde el")
    w("-- esquema relacional normalizado (3FN) y con tablas de catálogo.")
    w("-- =====================================================================")
    w("-- DECISIÓN: PostgreSQL, motor propuesto en la arquitectura del CORE.")
    w("-- DECISIÓN: una base con esquemas lógicos por dueño del dato; los")
    w("--   identificadores se escriben en minúsculas y sin comillas.")
    w("-- DECISIÓN: las claves foráneas se agregan al final con ALTER TABLE para")
    w("--   no depender del orden de creación; ON DELETE RESTRICT por omisión,")
    w("--   porque los registros financieros no se borran, se anulan o revierten.")
    w("")
    w("BEGIN;")
    w("")
    for s_ in SCHEMAS:
        w("CREATE SCHEMA IF NOT EXISTS %s;" % s_)
    w("")
    order = [t for s_ in SCHEMAS for t in SCHEMAS[s_]]
    missing = set(FIN) - set(order)
    assert not missing, missing
    for rel in order:
        attrs = FIN[rel]
        w("-- %s" % ("-" * 69))
        w("CREATE TABLE %s (" % q(rel))
        lines = []
        for a in attrs:
            key = "%s.%s" % (rel, a["name"])
            t = col_type(rel, a)
            if t == "UUID" and a["pk"] and not a["fk"] and len(pk(rel)) == 1:
                t += " DEFAULT gen_random_uuid()"
            null = a["null"] or key in NULLABLE
            d = DEFAULTS.get(a["name"]) if not a["pk"] else None
            line = "    %-27s %s" % (a["name"], t)
            if d and "IDENTITY" not in t:
                line += " DEFAULT " + d
            if not null and not a["pk"]:
                line += " NOT NULL"
            if key in ENUMS:
                line += "\n        CHECK (%s IN (%s))" % (a["name"], ", ".join(sql_str(v) for v in ENUMS[key]))
            lines.append(line)
        lines.append("    CONSTRAINT pk_%s PRIMARY KEY (%s)" % (rel.lower(), ", ".join(pk(rel))))
        for i, u in enumerate(uniques(rel), 1):
            lines.append("    CONSTRAINT uk_%s_%d UNIQUE (%s)" % (rel.lower(), i, ", ".join(u)))
        for i, c in enumerate(CHECKS.get(rel, []), 1):
            lines.append("    CONSTRAINT ck_%s_%d CHECK (%s)" % (rel.lower(), i, c))
        w(",\n".join(lines))
        w(");")
        w("COMMENT ON TABLE %s IS %s;" % (q(rel), sql_str(comment_text(rel))))
        w("")
    # foreign keys
    w("-- %s" % ("=" * 69))
    w("-- Claves foráneas")
    w("-- %s" % ("=" * 69))
    idx = []
    for rel in order:
        for i, (cols, tgt) in enumerate(fks(rel), 1):
            w("ALTER TABLE %s ADD CONSTRAINT fk_%s_%d FOREIGN KEY (%s)\n    REFERENCES %s (%s);"
              % (q(rel), rel.lower(), i, ", ".join(cols), q(tgt), ", ".join(pk(tgt))))
            pkc = pk(rel)
            covered = tuple(pkc[:len(cols)]) == cols or any(tuple(u[:len(cols)]) == cols for u in uniques(rel))
            if not covered:
                idx.append((rel, cols))
    for rel, cols, tgt, why in EXTRA_FK:
        w("-- DECISIÓN: %s." % why)
        w("ALTER TABLE %s ADD CONSTRAINT fk_%s_vinculo FOREIGN KEY (%s)\n    REFERENCES %s (%s);"
          % (q(rel), rel.lower(), ", ".join(cols), q(tgt), ", ".join(pk(tgt))))
    w("")
    w("-- %s" % ("=" * 69))
    w("-- Índices")
    w("-- %s" % ("=" * 69))
    w("-- DECISIÓN: PostgreSQL no indexa las claves foráneas; se crea un índice por")
    w("--   cada una que no esté cubierta por la clave primaria o una única.")
    for rel, cols in idx:
        w("CREATE INDEX ix_%s_%s ON %s (%s);" % (rel.lower(), "_".join(cols), q(rel), ", ".join(cols)))
    for name, rel, cols, where, why in PARTIAL:
        w("-- DECISIÓN: %s." % why)
        w("CREATE UNIQUE INDEX %s ON %s (%s) WHERE %s;" % (name, q(rel), cols, where))
    w("")
    w("-- %s" % ("=" * 69))
    w("-- Reglas que requieren datos de otras tablas (se implementan con triggers)")
    w("-- %s" % ("=" * 69))
    for t in TRIGGER_RULES:
        w("--   * " + t)
    w("")
    w("-- %s" % ("=" * 69))
    w("-- Datos iniciales: parámetros documentados por las fuentes")
    w("-- %s" % ("=" * 69))
    w("-- DECISIÓN: solo se cargan valores que figuran en los documentos de los")
    w("--   módulos; los números de módulo sin asignar se agregan después.")
    for rel, cols, rows in SEEDS:
        w("INSERT INTO %s (%s) VALUES" % (q(rel), ", ".join(cols)))
        w(",\n".join("    (%s)" % ", ".join(sql_str(v) for v in r) for r in rows) + ";")
    w("")
    w("COMMIT;")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    return len(order)


# ---------------------------------------------------------------------------
# Final verification table (report): candidate keys and the reasoning that
# each relation of the final schema is in 1FN, 2FN and 3FN.
# ---------------------------------------------------------------------------
NOTES = {
    "AGENCIA": "`distrito` no determina `ciudad`: hay distritos homónimos en distintas ciudades (Miraflores en Lima y en Arequipa).",
    "CUENTA_CONTABLE": "Se retiró `nivel` en 3FN; `naturaleza` no depende de `codigo_padre`, porque existen cuentas correctoras de naturaleza opuesta a la de su cuenta padre.",
    "ASIENTO_CONTABLE": "`numero_asiento` es clave candidata; `id_asiento_revertido` es única pero admite nulos, por lo que no es clave y no determina nada. `estado_asiento` se retiró por derivarse de otra fila.",
    "CLIENTE": "Cuatro claves candidatas más (documento, correo, celular y verificación); todo determinante es superclave.",
    "CODIGO_VERIFICACION": "`estado_codigo` no se deriva de `intentos_fallidos` ni de `fecha_expiracion`: VALIDADO, PENDIENTE y EXPIRADO dependen del momento y de la respuesta del cliente.",
    "CUENTA_AHORRO": "`cci` es clave candidata; aunque codifica la oficina y el número de cuenta, todo lo que determina lo determina como superclave.",
    "MOVIMIENTO": "`id_asiento` es clave candidata (relación 1:1 con el asiento).",
    "TARJETA": "Tras retirar `tipo_tarjeta` y `vencimiento_mm_aa`, ningún atributo no primo determina a otro.",
    "INTENTO_AUTENTICACION": "`id_canal` solo tiene valor cuando no hay terminal (restricción de arco exclusivo), de modo que no depende de `id_terminal`.",
    "AUTORIZACION": "Igual que el intento respecto de terminal y canal; `codigo_respuesta` no determina el estado (00 corresponde a AUTORIZADA y a DISPENSADA). `uuid_transaccion` es única pero admite nulos (las consultas no generan movimiento).",
    "CALENDARIO_PAGO": "(`id_solicitud`, `version`) es clave candidata.",
    "CUOTA": "`estado_cuota` depende de la fecha de consulta además de los saldos (VENCIDA), por lo que no hay dependencia funcional entre atributos.",
    "EVALUACION": "(`id_solicitud`, `ronda`) es clave candidata. `score_calculado` y `limite_aprobado` se registran como resultado del motor en esa ronda: el modelo de score es externo y versionado, así que `id_consulta` no los determina.",
    "REGLA_EVALUACION": "`codigo_rn` es clave candidata; el tramo (`ratio_min`, `ratio_max`) es único, pero un extremo puede ser nulo (tramos abiertos), por lo que no es clave. `accion` depende de la regla, no del tramo por separado.",
    "DECISION_ANALISTA": "`id_evaluacion` es clave candidata (relación 1:1).",
    "SOLICITUD_REVERSION": "`idempotency_key` es clave candidata; `uuid_transaccion_extorno` es única pero admite nulos (solo la reversión confirmada genera extorno).",
    "ORDEN_DESEMBOLSO": "`codigo_orden` e `idempotency_key` son claves candidatas; `request_hash` depende de la petición, identificada por la clave de idempotencia. `uuid_transaccion_abono` es única pero admite nulos (solo la orden confirmada abona).",
    "EVENTO_ENTREGA": "`version_esquema` no depende de `tipo_evento`: los eventos antiguos conservan la versión del contrato con la que se enviaron.",
    "CREDITO": "`id_orden` e `id_calendario` son claves candidatas (relaciones 1:1).",
    "MORA": "(`id_calendario`, `numero_cuota`, `fecha_calculo`) es clave candidata; `dias_atraso` se retiró en 3FN.",
    "EVENTO_AUDITORIA": "El tipo del registro auditado se obtiene de ENTIDAD_AUDITADA; `numero_cuota` solo tiene valor cuando el registro es una cuota y no depende de `id_entidad`, porque un calendario tiene varias cuotas.",
    "ENTIDAD_AUDITADA": "Un único atributo no primo: el tipo del registro auditado.",
    "TERMINAL": "`id_agencia` no determina `id_canal`: una agencia tiene ventanillas, agentes y cajeros.",
    "REGIMEN_CUENTA": "`firma_conjunta` y `min_titulares` no se determinan entre sí (la indistinta y la conjunta exigen dos titulares).",
    "TITULARIDAD": "Sin atributos no primos dependientes de parte de la clave tras retirar `rol_titular` en 2FN.",
    "LIMITE_CANAL": "Tras trasladar la regla a CANAL, el tope y la habilitación dependen del par canal--moneda.",
    "CREDENCIAL": "Tras extraer `longitud`, los atributos dependen del par tarjeta--tipo.",
}


def verification_rows():
    from modelo_bna import md, relname, ttb, NEW, MR_ORDER
    order = list(MR_ORDER) + [n for n in FIN if n not in MR_ORDER]
    rows = []
    for rel in order:
        nullable = {a["name"] for a in FIN[rel]
                    if a["null"] or "%s.%s" % (rel, a["name"]) in NULLABLE}
        ks = [pk(rel)] + [u for u in uniques(rel) if not set(u) & nullable]
        un = [u for u in uniques(rel) if set(u) & nullable]
        keys = "; ".join(ttb("(" + ", ".join(k) + ")") for k in ks)
        if un:
            keys += r"; \textit{únicas con nulos:} " + "; ".join(ttb("(" + ", ".join(u) + ")") for u in un)
        if rel in NOTES:
            note = md(NOTES[rel])
        elif NEW.get(rel) == "cat":
            note = "Catálogo: código como clave y atributos que describen solo a ese código."
        elif len(pk(rel)) > 1:
            note = "Clave compuesta; los atributos no primos dependen de toda la clave y no entre sí."
        else:
            note = "Clave simple; ningún atributo no primo determina a otro."
        rows.append(r"%s & %s & %s \\" % (relname(rel), keys, note))
    return "\n".join(rows) + "\n"
