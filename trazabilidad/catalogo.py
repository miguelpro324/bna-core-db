# Fuentes de las afirmaciones que prueban las pruebas y los experimentos.
# Es la única parte de la trazabilidad escrita a mano: matriz.py la cruza con
# las salidas de las ejecuciones (resultados/) y genera la matriz, el cuadro
# de objetos programados del informe y sus estadísticas. Una prueba o un
# experimento sin fuente aquí detiene la generación.
#
# Una fuente es (clave, localizador):
#   - clave de bibliography.bib del informe (documentos de los módulos y
#     documentación oficial) y su página o sección, p. ej.
#     ("BNA2026Tarjetas", "p.~34");
#   - las fallas de la línea base MySQL no van aquí: salen de
#     referencias_mysql.csv (commit:archivo:línea, verificadas al generar);
#   - las decisiones del informe (códigos BNA-*) se toman del resultado
#     esperado de cada prueba.

# --- Objetos programados (cuadro «Triggers, funciones, vistas e índices de
# consulta» del informe). Cada objeto lista las pruebas que lo ejercitan.
OBJETOS = [
    dict(grupo="CORE y Cuentas"),
    dict(objeto=r"\nm{fn\_asiento\_cuadra} (trigger de restricción diferido)",
         regla=r"Un asiento tiene al menos una línea en el debe y otra en el haber, y sus sumas coinciden; se verifica al confirmar la transacción.",
         etiqueta="CORE", fuentes=[("BNA2026Core", "")], origen="Nuevo",
         pruebas=["M20a", "M20b", "F24"]),
    dict(objeto=r"\nm{fn\_solo\_insercion} (triggers por fila y por sentencia)",
         regla=r"Asientos, historiales, intentos, auditoría y aplicaciones de pago no admiten \texttt{UPDATE}, \texttt{DELETE} ni \texttt{TRUNCATE}; las autorizaciones no se borran.",
         etiqueta="CORE, Tarjetas (RN-SEG-002, RN-ATM-003), Desembolso y Cobranza",
         fuentes=[("BNA2026Core", ""), ("BNA2026Tarjetas", ""), ("BNA2026Desembolso", ""), ("BNA2026Cobranza", "")],
         origen="Modelo", pruebas=["F11a", "F11b", "F11c", "F11d", "F11e", "F11f", "F13", "F20"]),
    dict(objeto=r"\nm{fn\_fecha\_negocio}",
         regla=r"El día de negocio se corta a las 00:00 de Arequipa.",
         etiqueta="Tarjetas, RN-TOP-001", fuentes=[("BNA2026Tarjetas", "")], origen="Nuevo",
         pruebas=["F12l", "F12m", "F12n"]),
    dict(objeto=r"\nm{fn\_movimiento\_validar}, \nm{fn\_movimiento\_aplicar}, \nm{fn\_consumo\_sumar}",
         regla=r"La cuenta admite débitos o créditos según su estado; el asiento está en la moneda de la cuenta; un débito sin autorización no supera el saldo ni el tope del canal. Bloquea la cuenta, actualiza los saldos y el consumo del día, y vincula el movimiento a su autorización; el extorno devuelve el consumo al día en que se comprometió.",
         etiqueta="Cuentas, CORE y Tarjetas (RN-TOP-001, RN-BD-002, C07)",
         fuentes=[("BNA2026Cuentas", ""), ("BNA2026Core", ""), ("BNA2026Tarjetas", "")], origen="Modelo",
         pruebas=["M04", "M10a", "M10b", "M22", "M24a", "F21a", "F21b", "F22", "F12m", "C01", "C02"]),
    dict(objeto=r"\nm{fn\_movimiento\_inmutable}",
         regla=r"Un movimiento solo cambia de APROBADO a EXTORNADO.",
         etiqueta="CORE", fuentes=[("BNA2026Core", "")], origen="Nuevo", pruebas=["F23"]),
    dict(grupo="Tarjetas"),
    dict(objeto=r"\nm{fn\_tarjeta\_emitir}",
         regla=r"Solo se emite tarjeta a un cliente ACTIVO (RF-TAR-005).",
         etiqueta=r"Tarjetas, \nm{trg\_tarjeta\_bi}", fuentes=[("BNA2026Tarjetas", "")], origen="Portado",
         pruebas=["F01"]),
    dict(objeto=r"\nm{fn\_tarjeta\_emitida}",
         regla=r"La emisión queda en el historial y en la bandeja hacia Seguridad (RN-SEG-002).",
         etiqueta=r"Tarjetas, \nm{trg\_tarjeta\_ai}", fuentes=[("BNA2026Tarjetas", "")], origen="Portado",
         pruebas=["F02"]),
    dict(objeto=r"\nm{fn\_historial\_validar}, \nm{fn\_historial\_aplicar}, \nm{fn\_tarjeta\_estado\_via\_historial}",
         regla=r"La cancelada no cambia y la vencida solo se cancela (RN-TAR-003); solo un operador o Seguridad desbloquean, y al desbloquear los intentos vuelven a cero (RN-TAR-004). El estado de la tarjeta sigue a su historial y cada cambio se avisa a Seguridad.",
         etiqueta=r"Tarjetas, \nm{trg\_tarjeta\_bu} y \nm{trg\_tarjeta\_au}", fuentes=[("BNA2026Tarjetas", "")],
         origen="Portado", pruebas=["F03", "F04", "F05", "F06", "F07"]),
    dict(objeto=r"\nm{fn\_intento\_contar}",
         regla=r"El tercer intento fallido de la credencial o de la matriz bloquea la tarjeta; un intento exitoso reinicia el contador (RN-TAR-004).",
         etiqueta=r"Tarjetas, \nm{trg\_intento\_ai}", fuentes=[("BNA2026Tarjetas", "")], origen="Portado",
         pruebas=["F08", "F09", "F10"]),
    dict(objeto=r"\nm{fn\_autorizacion\_validar}, \nm{fn\_validar\_reglas\_autorizacion}, \nm{fn\_autorizacion\_aplicar}",
         regla=r"Para autorizar, la tarjeta está operativa y vigente, la terminal y el canal están activos, el cajero no opera cuentas mancomunadas conjuntas (RN-ATM-005), el canal opera en la moneda (RN-BD-002) y el débito no supera el tope (RN-TOP-001) ni el saldo, con la cuenta bloqueada. Al autorizar, compromete el tope y retiene el saldo; al extornar sin movimiento, los libera. Controla la secuencia de estados (RN-ATM-007).",
         etiqueta=r"Tarjetas, \nm{trg\_autorizacion\_bi/bu} y \nm{sp\_validar\_reglas\_autorizacion}",
         fuentes=[("BNA2026Tarjetas", "")], origen="Portado",
         pruebas=["M23", "M24b", "M24c", "F12a", "F12b", "F12c", "F12d", "F12e", "F12f", "F12g", "F12h",
                  "F12i", "F12j", "F12k", "F12l", "F12n", "C03"]),
    dict(objeto=r"\nm{fn\_cliente\_estado\_tarjetas}",
         regla=r"Si Clientes bloquea o suspende al cliente, se bloquean sus tarjetas; si lo da de baja, se cancelan (INT-T07).",
         etiqueta=r"Tarjetas, \nm{trg\_cliente\_ref\_au}", fuentes=[("BNA2026Tarjetas", "")], origen="Portado",
         pruebas=["F14a", "F14b"]),
    dict(objeto=r"\nm{bloquear\_tarjeta()}",
         regla=r"Bloquea la tarjeta registrando su motivo y su origen en el historial.",
         etiqueta="Tarjetas, RN-SEG-002", fuentes=[("BNA2026Tarjetas", "")], origen="Portado", pruebas=["M26"]),
    dict(objeto=r"\nm{marcar\_tarjetas\_vencidas()}",
         regla=r"Marca como VENCIDA cada tarjeta cuya fecha ya pasó (RN-TAR-003).",
         etiqueta=r"Tarjetas, \nm{ev\_marcar\_tarjetas\_vencidas}", fuentes=[("BNA2026Tarjetas", "")],
         origen="Portado", pruebas=["F15"]),
    dict(objeto=r"\nm{v\_tarjeta\_resumen}, \nm{v\_consumo\_diario}, \nm{v\_tope\_restante\_hoy}, \nm{v\_credenciales\_en\_riesgo}",
         regla=r"Número enmascarado y vencimiento MM/AA (PCI-DSS); consumo por tarjeta, canal, moneda y día; tope disponible por tarjeta y canal (RN-TOP-001); intentos acumulados y restantes (RN-TAR-004).",
         etiqueta="Tarjetas, objetos programados y consultas C05 y C08", fuentes=[("BNA2026Tarjetas", "")],
         origen="Portado", pruebas=["M25", "F25", "F26", "F27"]),
    dict(grupo="Solicitud, Evaluación, Desembolso y Cobranza"),
    dict(objeto=r"\nm{fn\_orden\_validar}",
         regla=r"La cuenta destino pertenece al cliente de la solicitud y tiene su moneda; el importe no supera el límite aprobado (decisión de este informe); hay una sola orden CONFIRMADA por solicitud, en todas sus rondas.",
         etiqueta="Desembolso y Evaluación", fuentes=[("BNA2026Desembolso", ""), ("BNA2026Evaluacion", "")],
         origen="Modelo", pruebas=["M09a", "M09b", "M09c", "M14b"]),
    dict(objeto=r"\nm{v\_ordenes\_inciertas}, \nm{v\_entregas\_pendientes}, \nm{v\_conciliacion\_diaria}",
         regla=r"Órdenes con resultado incierto en el CORE; entregas a Cobranza que superan dos reintentos; importes ordenados frente a abonados, por fecha y moneda.",
         etiqueta="Desembolso, vistas de apoyo operativo; reintentos, documento de tecnologías",
         fuentes=[("BNA2026Desembolso", ""), ("BNA2026Stack", "")], origen="Portado",
         pruebas=["F28", "F29", "F30"]),
    dict(objeto=r"\nm{fn\_credito\_validar}",
         regla=r"El crédito nace de una orden CONFIRMADA (decisión I15) y su calendario pertenece a la solicitud de la orden y es OFICIAL (decisión de este informe).",
         etiqueta="Cobranza y Solicitud", fuentes=[("BNA2026Cobranza", ""), ("BNA2026Solicitud", "")],
         origen="Modelo", pruebas=["M14a", "F16a", "F16b", "F16c"]),
    dict(objeto=r"\nm{fn\_aplicacion\_validar}, \nm{fn\_aplicacion\_aplicar}",
         regla=r"Solo se aplica un pago CONFIRMADO, a cuotas de su crédito, sin superar el saldo de la cuota ni el monto del pago. Actualiza el saldo y el estado de la cuota y cancela el crédito cuando todas sus cuotas quedan pagadas.",
         etiqueta="Cobranza", fuentes=[("BNA2026Cobranza", "")], origen="Modelo",
         pruebas=["M05", "M13a", "M13b", "F17a", "F17b", "F19"]),
    dict(objeto=r"\nm{aplicar\_pago()}",
         regla=r"Reparte el saldo libre de un pago de la cuota más antigua a la siguiente.",
         etiqueta="Cobranza", fuentes=[("BNA2026Cobranza", "")], origen="Portado", pruebas=["F18"]),
    dict(grupo="Índices"),
    dict(objeto=r"\stat{consultas} índices de consulta",
         regla=r"Movimientos, autorizaciones, intentos e historial por fecha; órdenes por estado y fecha; eventos por enviar; auditoría por \nm{correlation\_id}.",
         etiqueta="Tarjetas y Desembolso", fuentes=[("BNA2026Tarjetas", ""), ("BNA2026Desembolso", "")],
         origen="Portado", pruebas=["F31"]),
]

# --- Pruebas cuya fuente no es un objeto programado (restricciones
# declarativas del modelo, carga y concurrencia). Las pruebas M toman además
# la falla de la línea base MySQL de referencias_mysql.csv.
PRUEBAS = {
    "L01": dict(fuentes=[], nota="El script DDL generado del modelo integrado"),
    "M08": dict(fuentes=[("BNA2026Core", "")]),
    "M11": dict(fuentes=[("BNA2026Cuentas", "")]),
    "M15a": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "M15b": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "M16": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "M17": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "M18": dict(fuentes=[("BNA2026Solicitud", "")]),
    "M19": dict(fuentes=[("BNA2026Core", "")]),
    "M01": dict(fuentes=[]), "M06": dict(fuentes=[]), "M07": dict(fuentes=[]),
    "M12": dict(fuentes=[("BNA2026Cobranza", "")]), "M21": dict(fuentes=[]), "M28": dict(fuentes=[]),
    "R1": dict(fuentes=[("BNA2026Core", "")]),
    "R2": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "R3": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "R4": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "R5": dict(fuentes=[("BNA2026Tarjetas", "")]),
    "R6": dict(fuentes=[("BNA2026Clientes", "")]),
    "R7": dict(fuentes=[("BNA2026Desembolso", "")]),
    "R8": dict(fuentes=[], nota="Decisión del informe: catálogos con borrado restringido"),
    "C01": dict(fuentes=[("BNA2026Core", "")], nota="Requisito 3 del CORE; experimento E7"),
}

# --- Experimentos de la comparación de gestores. «esperado» es lo que
# afirma el informe (cuadro de experimentos) para cada gestor, como
# expresión regular sobre lo observado; «fuentes», la documentación oficial
# que respalda la afirmación cuando existe (si no, la evidencia es el propio
# experimento).
EXPERIMENTOS = [
    dict(id="E1", caso="", afirmacion="El DDL dentro de una transacción: MySQL lo confirma implícitamente; PostgreSQL lo deshace con ROLLBACK.",
         fuentes=[("MySQL2024Manual", "sec.~15.3.3")],
         esperado={"MySQL": "commit implícito", "PG": "se deshizo"}),
    dict(id="E2", caso="Clave foránea diferible", afirmacion="MySQL no admite claves foráneas diferibles; PostgreSQL sí.",
         fuentes=[("MySQL2024Manual", "sec.~15.1.20.5"), ("PostgreSQL2023Docs", "CREATE TABLE")],
         esperado={"MySQL": "error in your SQL syntax", "PG": "^aceptado$"}),
    dict(id="E2", caso="Índice único parcial", afirmacion="MySQL no admite índices únicos parciales; PostgreSQL sí.",
         fuentes=[("PostgreSQL2023Docs", "sec.~11.8")],
         esperado={"MySQL": "error in your SQL syntax", "PG": "^aceptado$"}),
    dict(id="E2", caso="Dominio", afirmacion="MySQL no admite dominios; PostgreSQL sí.",
         fuentes=[("PostgreSQL2023Docs", "sec.~8.18")],
         esperado={"MySQL": "error in your SQL syntax", "PG": "^aceptado$"}),
    dict(id="E3", caso="", afirmacion="MySQL no puede declarar un trigger diferido hasta la confirmación; en PostgreSQL, un trigger de restricción diferido rechaza al confirmar el asiento descuadrado y guarda el que cuadra.",
         fuentes=[("PostgreSQL2023Docs", "CREATE TRIGGER")],
         esperado={"MySQL": "CREATE CONSTRAINT TRIGGER: .*error in your SQL syntax", "PG": "asiento 2 descuadrado.*asientos guardados: 1$"}),
    dict(id="E4", caso="", afirmacion="Con sql_mode = '', MySQL guarda valores inválidos ajustados, solo con advertencias; PostgreSQL los rechaza siempre.",
         fuentes=[("MySQL2024Manual", "sec.~7.1.11")],
         esperado={"MySQL": r"guardado sin error: e='', d=999\.99, f=0000-00-00; advertencias: [1-9]",
                   "PG": "numeric field overflow.*out of range.*filas guardadas: 0"}),
    dict(id="E5", caso="Marca de tiempo de 2039", afirmacion="El TIMESTAMP de MySQL no llega a 2039; el TIMESTAMPTZ de PostgreSQL sí.",
         fuentes=[("MySQL2024Manual", "sec.~13.2.2"), ("PostgreSQL2023Docs", "sec.~8.5")],
         esperado={"MySQL": "Incorrect datetime value", "PG": "TIMESTAMPTZ guarda 2039"}),
    dict(id="E5", caso="BOOLEAN = 5", afirmacion="El BOOLEAN de MySQL es un TINYINT(1) y acepta 5; el de PostgreSQL lo rechaza.",
         fuentes=[("MySQL2024Manual", "sec.~13.1.1"), ("PostgreSQL2023Docs", "sec.~8.6")],
         esperado={"MySQL": "BOOLEAN guarda 5", "PG": "type boolean"}),
    dict(id="E5", caso="UUID 'c2'", afirmacion="MySQL no tiene tipo UUID y CHAR(36) acepta 'c2'; el UUID de PostgreSQL lo rechaza.",
         fuentes=[("PostgreSQL2023Docs", "sec.~8.12")],
         esperado={"MySQL": "CHAR\\(36\\) guarda 'c2'", "PG": "invalid input syntax for type uuid"}),
    dict(id="E6", caso="", afirmacion="Un borrado en cascada no dispara el trigger de auditoría en MySQL y sí en PostgreSQL.",
         fuentes=[("MySQL2024Manual", "sec.~15.1.20.5"), ("PostgreSQL2023Docs", "CREATE TRIGGER")],
         esperado={"MySQL": "bitácora: 0$", "PG": "bitácora: 1$"}),
    dict(id="E7", caso="READ COMMITTED", afirmacion="Con el aislamiento por omisión de PostgreSQL se pierde la actualización (saldo final 50).",
         fuentes=[("PostgreSQL2023Docs", "cap.~13")],
         esperado={"PG": "A confirma; saldo final 50"}),
    dict(id="E7", caso="REPEATABLE READ", afirmacion="Con el aislamiento por omisión de MySQL se pierde la actualización; en PostgreSQL, REPEATABLE READ aborta la segunda transacción, que debe reintentarse.",
         fuentes=[("MySQL2024Manual", "sec.~17.7.2.1"), ("PostgreSQL2023Docs", "cap.~13")],
         esperado={"MySQL": "A confirma; saldo final 50", "PG": "could not serialize"}),
    dict(id="E7", caso="SERIALIZABLE", afirmacion="Con SERIALIZABLE, MySQL hace esperar a la segunda transacción (saldo final 20) y PostgreSQL la aborta para que se reintente.",
         fuentes=[("MySQL2024Manual", "sec.~17.7.2.1"), ("PostgreSQL2023Docs", "cap.~13")],
         esperado={"MySQL": "A confirma; saldo final 20", "PG": "could not serialize"}),
]

# Commit del DDL sin triggers contra el que se mide el control.
CONTROL_COMMIT = "8aec444"
