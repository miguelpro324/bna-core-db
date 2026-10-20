# Genera la matriz de trazabilidad a partir del catálogo de fuentes
# (catalogo.py), de las fallas de la línea base MySQL
# (referencias_mysql.csv) y de las salidas de las ejecuciones (resultados/).
#   resultados/trazabilidad.csv y .md   matriz completa
#   resultados/referencias_mysql.md     cada falla con su línea en ab6a6ec
#   informe/trazabilidad.tex            filas del anexo del informe
#   informe/programacion.tex            filas del cuadro de objetos programados
#   informe/trazabilidad-stats.tex      cifras del control, de las corridas y
#                                       de la matriz, para el texto del informe
# Se detiene si una prueba o un experimento no tiene fuente, si una línea
# citada de ab6a6ec no contiene el fragmento registrado o si lo observado en
# un experimento no coincide con lo que afirma el informe en ninguna versión.
# Uso: python3 trazabilidad/matriz.py
import csv
import datetime
import os
import re
import subprocess
import sys
import zoneinfo

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import catalogo  # noqa: E402

RES = os.path.join(ROOT, "resultados")
INF = os.path.join(ROOT, "informe")
BASE = "ab6a6ec"
PREFIJO = "backend/Trabajo_hecho/"

DOCS = {"BNA2026Clientes": "Clientes", "BNA2026Cuentas": "Cuentas", "BNA2026Tarjetas": "Tarjetas",
        "BNA2026Solicitud": "Solicitud", "BNA2026Evaluacion": "Evaluación",
        "BNA2026Desembolso": "Desembolso", "BNA2026Cobranza": "Cobranza", "BNA2026Core": "CORE",
        "BNA2026Stack": "Tecnologías", "MySQL2024Manual": "Manual de MySQL 8.4",
        "PostgreSQL2023Docs": "Documentación de PostgreSQL 16"}
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
         "octubre", "noviembre", "diciembre"]


def falla(msg):
    sys.exit("matriz.py: " + msg)


def leer_csv(*partes):
    with open(os.path.join(RES, *partes), newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


def metadatos(carpeta):
    d = {}
    with open(os.path.join(RES, carpeta, "metadatos.txt"), encoding="utf-8") as f:
        for linea in f:
            k, _, v = linea.partition(": ")
            d[k] = v.strip()
    return d


def fecha_larga(iso):
    t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(zoneinfo.ZoneInfo("America/Lima"))
    return "%d de %s de %d" % (t.day, MESES[t.month - 1], t.year)


def version(v):
    return v.split(" ")[0]


# --- LaTeX -------------------------------------------------------------------
TEX = {"\\": r"\textbackslash{}", "_": r"\_", "%": r"\%", "&": r"\&", "#": r"\#",
       "$": r"\$", "{": r"\{", "}": r"\}", "~": r"\textasciitilde{}", "^": r"\textasciicircum{}"}


def tex(s):
    s = "".join(TEX.get(c, c) for c in s)
    return re.sub(r"(?<![\w\\/.])([\w/.]*\w(?:\\_\w+)+(?:\.\w+)?(?:\(\))?)", r"\\nm{\1}", s)


def nm(s):
    return r"\nm{%s}" % s.replace("_", r"\_")


def cita(fuentes):
    """\\parencite de una lista de (clave, localizador)."""
    if not fuentes:
        return ""
    if len(fuentes) == 1:
        k, loc = fuentes[0]
        return r"\parencite[%s]{%s}" % (loc, k) if loc else r"\parencite{%s}" % k
    return r"\parencites" + "".join(("[%s]{%s}" % (loc, k)) if loc else "{%s}" % k for k, loc in fuentes)


def texto_fuente(fuentes):
    return "; ".join(DOCS.get(k, k) + (" " + loc.replace("~", " ") if loc else "") for k, loc in fuentes)


def unir_fuentes(listas):
    """Une fuentes de varios objetos: una entrada por documento."""
    orden, locs = [], {}
    for k, loc in (f for lista in listas for f in lista):
        if k not in locs:
            orden.append(k)
            locs[k] = []
        if loc and loc not in locs[k]:
            locs[k].append(loc)
    return [(k, "; ".join(locs[k])) for k in orden]


# --- Fallas de la línea base MySQL, verificadas contra ab6a6ec ---------------
def referencias():
    refs, cache = {}, {}
    with open(os.path.join(HERE, "referencias_mysql.csv"), newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["path"] not in cache:
                cache[r["path"]] = subprocess.run(
                    ["git", "-C", ROOT, "show", "%s:%s" % (BASE, r["path"])],
                    capture_output=True, text=True, check=True).stdout.split("\n")
            linea = cache[r["path"]][int(r["line"]) - 1]
            if r["snippet"] not in linea:
                falla("%s:%s:%s no contiene «%s»" % (BASE, r["path"], r["line"], r["snippet"]))
            refs.setdefault(int(r["check"]), []).append(r)
    return refs


def ref_corta(r):
    ruta = r["path"][len(PREFIJO):] if r["path"].startswith(PREFIJO) else r["path"]
    return "%s:%s" % (ruta, r["line"])


# --- Líneas de los scripts ---------------------------------------------------
def buscar(ruta, patron):
    with open(os.path.join(ROOT, ruta), encoding="utf-8") as f:
        for i, linea in enumerate(f, 1):
            if patron in linea:
                return "%s:%d" % (ruta, i)
    return None


def script_prueba(tid):
    return (buscar("pruebas/postgres/pruebas.sql", "('%s'," % tid)
            or buscar("pruebas/postgres/run_tests.sh", "concurrente %s " % tid)
            or buscar("pruebas/postgres/run_tests.sh", "VALUES ('%s'," % tid)
            or falla("no se encontró el script de la prueba %s" % tid))


def main():
    refs = referencias()
    versiones = ["16", "17"]

    # Pruebas
    res = {v: {r[0]: r for r in leer_csv("postgres", "resultado-pg%s.csv" % v)} for v in versiones}
    ctl = {v: {r[0]: r for r in leer_csv("control", "resultado-pg%s.csv" % v)} for v in versiones}
    ids = list(res["16"])
    por_objeto = {}
    for o in catalogo.OBJETOS:
        for t in o.get("pruebas", []):
            por_objeto.setdefault(t, []).append(o)
    for o in catalogo.OBJETOS:
        for t in o.get("pruebas", []):
            if t not in res["16"]:
                falla("el objeto %s cita la prueba %s, que no existe" % (o["objeto"], t))

    filas = []
    for t in ids:
        _, grupo, ref, desc, esperado, _, _ = res["16"][t]
        objs = por_objeto.get(t, [])
        fuentes = unir_fuentes([o["fuentes"] for o in objs] + [catalogo.PRUEBAS.get(t, {}).get("fuentes", [])])
        m = re.match(r"Comprobación (\d+)", ref)
        mysql = refs.get(int(m.group(1)), []) if m else []
        decisiones = sorted(set(re.findall(r"BNA-[A-Z-]+[A-Z]", esperado)))
        decision = catalogo.DECISIONES.get(t)
        if not (fuentes or mysql or decisiones or decision):
            falla("la prueba %s no tiene fuente en el catálogo" % t)
        obt = {v: res[v][t][5] for v in versiones}
        filas.append(dict(
            tipo="prueba", id=t, afirmacion=desc, regla=ref, fuentes=fuentes, mysql=mysql,
            decisiones=decisiones, decision=decision, script=script_prueba(t),
            esperado=esperado, obtenido=obt,
            resultado={v: res[v][t][6] for v in versiones}, mysql_res=None,
            objetos=[re.sub(r"\\[a-z]+\{|\}|\\", "", o["objeto"]) for o in objs]))

    # Experimentos
    exp = {}
    for e, caso, gestor, obtenido in leer_csv("experimentos", "experimentos.csv")[1:]:
        exp.setdefault((e, caso), {})[gestor] = obtenido
    gestores = {"MySQL": ["MySQL 8.4"], "PG": ["PG 16", "PG 17"]}
    vistos = set()
    for x in catalogo.EXPERIMENTOS:
        clave = (x["id"], x["caso"])
        vistos.add(clave)
        obs = exp.get(clave) or falla("el experimento %s %s no tiene salida" % clave)
        resultado = {}
        for fam, patron in x["esperado"].items():
            for g in gestores[fam]:
                if g not in obs:
                    falla("el experimento %s %s no tiene salida para %s" % (clave + (g,)))
                resultado[g] = "pasa" if re.search(patron, obs[g]) else "falla"
        if "falla" in resultado.values():
            falla("el experimento %s %s no coincide con lo que afirma el informe: %s" % (clave + (obs,)))
        filas.append(dict(
            tipo="experimento", id=x["id"] + (" (%s)" % x["caso"] if x["caso"] else ""),
            afirmacion=x["afirmacion"], regla="", fuentes=x["fuentes"], mysql=[], decisiones=[],
            decision=None, script=buscar("experimentos/sgbd/experimentos.sh", "linea %s " % x["id"]),
            esperado="; ".join("%s: %s" % (f, p) for f, p in x["esperado"].items()),
            obtenido={g: obs[g] for g in resultado},
            resultado={"16": resultado.get("PG 16", "—"), "17": resultado.get("PG 17", "—")},
            mysql_res=resultado.get("MySQL 8.4", "—"), objetos=[]))
    sobran = set(exp) - vistos
    if sobran:
        falla("experimentos sin entrada en el catálogo: %s" % sorted(sobran))

    # Reproducción en la línea base MySQL
    repro = leer_csv("repro_mysql", "resultado.csv")[1:]
    for n, ok, bug, titulo, esperado, obtenido in repro:
        script = (buscar("repro_mysql/run.sh", '"%s"' % titulo)
                  or next((s for s in (buscar("repro_mysql/sql/%s" % f, "'%s'" % titulo)
                                       for f in sorted(os.listdir(os.path.join(ROOT, "repro_mysql", "sql"))))
                           if s), None)
                  or falla("no se encontró la comprobación %s" % n))
        if not refs.get(int(n)):
            falla("la comprobación %s no tiene línea en %s" % (n, BASE))
        filas.append(dict(
            tipo="mysql", id="MY%02d" % int(n), afirmacion=titulo,
            regla="Comprobación %s" % n + (" (bug %s)" % bug if bug != "-" else ""),
            fuentes=[], mysql=refs[int(n)], decisiones=[], decision=None, script=script,
            esperado=esperado, obtenido={"MySQL 8.4": obtenido},
            resultado={"16": "—", "17": "—"}, mysql_res="OK" if ok == "1" else "falla", objetos=[]))

    # Control: pruebas actuales sobre el DDL sin triggers
    cmeta = metadatos("control")
    m = re.search(r"en (\w+)", cmeta["ddl"])
    control_commit = m.group(1)[:7] if m else "?"
    if not catalogo.CONTROL_COMMIT.startswith(control_commit[:7]) and not control_commit.startswith(catalogo.CONTROL_COMMIT):
        falla("el control corrió sobre %s, no sobre %s" % (control_commit, catalogo.CONTROL_COMMIT))
    cvals = {v: [ctl[v][t][6] for t in ctl[v]] for v in versiones}
    if cvals["16"] != cvals["17"]:
        falla("el control da resultados distintos en PostgreSQL 16 y 17")
    cpasan = [t for t in ctl["16"] if ctl["16"][t][6] == "pasa"]

    escribir(filas, refs)
    pmeta, emeta, rmeta = metadatos("postgres"), metadatos("experimentos"), metadatos("repro_mysql")
    stats = dict(
        controlpasan=len(cpasan), controlfallan=cvals["16"].count("falla"), controlna=cvals["16"].count("N/A"),
        controlcommit=catalogo.CONTROL_COMMIT, controlpasanids=", ".join(cpasan),
        controlmismasversiones="sí",
        pruebasfecha=fecha_larga(pmeta["fecha"]), pruebascommit=pmeta["commit"].split()[0][:7],
        expfecha=fecha_larga(emeta["fecha"]), expmysql=emeta["mysql"],
        exppgdieciseis=version(emeta["postgresql16"]), exppgdiecisiete=version(emeta["postgresql17"]),
        reprofecha=fecha_larga(rmeta["fecha"]), repromysql=rmeta["mysql"],
        reprototal=len(repro), reprook=sum(1 for r in repro if r[1] == "1"),
        reprofallan=sum(1 for r in repro if r[1] == "0"),
        matrizfilas=len(filas), referenciasmysql=sum(len(v) for v in refs.values()),
    )
    with open(os.path.join(INF, "trazabilidad-stats.tex"), "w", encoding="utf-8") as f:
        f.write("% Generated by trazabilidad/matriz.py\n")
        for k, v in stats.items():
            f.write("\\expandafter\\def\\csname stat:%s\\endcsname{%s}\n" % (k, v))
    escribir_programacion()
    print("Matriz: %d filas; %d referencias a %s verificadas; control %s: %d pasan, %d fallan, %d N/A" % (
        len(filas), stats["referenciasmysql"], BASE, catalogo.CONTROL_COMMIT,
        stats["controlpasan"], stats["controlfallan"], stats["controlna"]))


# --- Salidas ------------------------------------------------------------------
def fuente_texto(f):
    partes = []
    if f["fuentes"]:
        partes.append(texto_fuente(f["fuentes"]))
    if f["mysql"]:
        partes.append("MySQL %s: %s" % (BASE, ", ".join(ref_corta(r) for r in f["mysql"])))
    if f["decisiones"]:
        partes.append("Decisión del informe: " + ", ".join(f["decisiones"]))
    if f["decision"]:
        partes.append("Decisión del informe: " + f["decision"])
    return "; ".join(partes)


def obtenido_texto(f):
    vals = list(dict.fromkeys(f["obtenido"].values()))
    if f["tipo"] == "prueba" and len(vals) == 1:
        return vals[0]
    if f["tipo"] == "experimento":
        pg = [f["obtenido"][g] for g in ("PG 16", "PG 17") if g in f["obtenido"]]
        out = []
        if "MySQL 8.4" in f["obtenido"]:
            out.append("MySQL 8.4: " + f["obtenido"]["MySQL 8.4"])
        if pg and len(set(pg)) == 1:
            out.append("PG 16 y 17: " + pg[0])
        elif pg:
            out += ["PG 16: " + pg[0], "PG 17: " + pg[1]]
        return "; ".join(out)
    return "; ".join("%s: %s" % kv for kv in f["obtenido"].items())


def escribir(filas, refs):
    cols = ["id", "tipo", "afirmacion", "regla", "fuente", "script", "esperado", "obtenido",
            "pg16", "pg17", "mysql84"]
    with open(os.path.join(RES, "trazabilidad.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(cols)
        for f in filas:
            w.writerow([f["id"], f["tipo"], f["afirmacion"], f["regla"], fuente_texto(f), f["script"],
                        f["esperado"], obtenido_texto(f), f["resultado"]["16"], f["resultado"]["17"],
                        f["mysql_res"] or "—"])

    def celda(s):
        return s.replace("|", "\\|").replace("\n", " ")
    md = ["# Matriz de trazabilidad", "",
          "Generada por `trazabilidad/matriz.py` a partir de `trazabilidad/catalogo.py`,",
          "`trazabilidad/referencias_mysql.csv` y las salidas de `resultados/`. Las páginas son las",
          "del archivo PDF de cada documento; las fallas MySQL se citan como `%s:<ruta>:<línea>`," % BASE,
          "con la ruta relativa a `%s`." % PREFIJO, "",
          "| ID | Afirmación o regla | Fuente | Script | Esperado | Obtenido | PG 16 | PG 17 | MySQL 8.4 |",
          "|---|---|---|---|---|---|---|---|---|"]
    for f in filas:
        md.append("| %s |" % " | ".join(celda(x) for x in [
            f["id"], f["afirmacion"] + (" (%s)" % f["regla"] if f["regla"] else ""), fuente_texto(f),
            "`%s`" % f["script"], f["esperado"], obtenido_texto(f), f["resultado"]["16"],
            f["resultado"]["17"], f["mysql_res"] or "—"]))
    with open(os.path.join(RES, "trazabilidad.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(md) + "\n")

    # Anexo del informe
    abrev = {"pasa": "P", "falla": "F", "N/A": "N/A", "—": "—", "OK": "OK"}
    grupos = {"prueba": "Pruebas de la base integrada", "experimento": "Experimentos de comparación de los gestores",
              "mysql": "Comprobaciones sobre la línea base MySQL (commit %s)" % BASE}
    lineas, actual = ["% Generated by trazabilidad/matriz.py"], None
    for f in filas:
        if f["tipo"] != actual:
            actual = f["tipo"]
            if len(lineas) > 1:
                lineas.append(r"\addlinespace")
            lineas.append(r"\multicolumn{7}{@{}l}{\textit{%s}} \\" % grupos[actual])
        fuente = []
        if f["fuentes"]:
            fuente.append(cita(f["fuentes"]))
        if f["mysql"]:
            fuente.append("MySQL: " + ", ".join(nm(ref_corta(r).replace("BD/99_bna_unificado.sql", "99"))
                                               for r in f["mysql"]))
        if f["decisiones"]:
            fuente.append("Decisión: " + ", ".join(f["decisiones"]))
        if f["decision"]:
            fuente.append("Decisión: " + tex(f["decision"]))
        afirm = tex(f["afirmacion"]) + (r" \textit{(%s)}" % tex(f["regla"]) if f["regla"] else "")
        eo = r"\textit{E:} %s \newline \textit{O:} %s" % (tex(f["esperado"]), tex(obtenido_texto(f)))
        script = nm(f["script"])
        lineas.append(r"%s & %s & %s & %s & %s & %s & %s \\" % (
            tex(f["id"]), afirm, "; ".join(fuente), script, eo,
            "%s/%s" % (abrev[f["resultado"]["16"]], abrev[f["resultado"]["17"]]),
            abrev[f["mysql_res"] or "—"]))
    with open(os.path.join(INF, "trazabilidad.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lineas) + "\n")

    # Fallas MySQL con su línea
    md = ["# Fallas de la línea base MySQL", "",
          "Cada línea se comprobó con `git show %s:<ruta>` al generar la matriz." % BASE, "",
          "| Comprobación | Bug | Ruta:línea | Fragmento | Explicación |", "|---|---|---|---|---|"]
    for n in sorted(refs):
        for r in refs[n]:
            md.append("| %s | %s | `%s` | `%s` | %s |" % (n, r["bug"], ref_corta(r), celda(r["snippet"]),
                                                          celda(r["explanation"])))
    with open(os.path.join(RES, "referencias_mysql.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(md) + "\n")


def escribir_programacion():
    lineas = ["% Generated by trazabilidad/matriz.py"]
    for o in catalogo.OBJETOS:
        if "grupo" in o:
            if len(lineas) > 1:
                lineas.append(r"\addlinespace")
            lineas.append(r"\multicolumn{4}{@{}l}{\textit{%s}} \\" % o["grupo"])
            continue
        pruebas = ", ".join(o["pruebas"])
        lineas.append(r"%s & %s \textit{Pruebas: %s.} & %s %s & %s \\" % (
            o["objeto"], o["regla"], pruebas, o["etiqueta"], cita(o["fuentes"]), o["origen"]))
    with open(os.path.join(INF, "programacion.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lineas) + "\n")


if __name__ == "__main__":
    main()
