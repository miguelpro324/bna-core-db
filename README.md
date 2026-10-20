# bna-core-db — base de datos integrada del CORE del BNA (PostgreSQL)

Base de datos integrada del CORE del Banco Nacional de Arequipa (BNA) para
PostgreSQL 16 o superior, con el modelo del que se genera, las pruebas que la
verifican y la evidencia de las afirmaciones del informe de diseño de la base
de datos (curso Gestión de Sistemas y Tecnologías de la Información, UCSM).

## Relación con Banco_Nacional_Arequipa

Este repositorio es un clon completo de
[SantiagoCusirramos/Banco_Nacional_Arequipa](https://github.com/SantiagoCusirramos/Banco_Nacional_Arequipa)
(remoto `upstream`) que conserva toda su historia.

- `ab6a6ec` es la **línea base MySQL**: la base unificada para MySQL 8
  (`backend/Trabajo_hecho/BD/`), el resto del ERP y el documento de
  tecnologías (`Documents/01-stack-tecnologico.md`).
- El commit siguiente retira ese árbol y lo reemplaza por la versión
  PostgreSQL. El código MySQL no se borra de la historia: se consulta con
  `git show ab6a6ec:<ruta>`, y las fallas encontradas en él se citan como
  `ab6a6ec:<ruta>:<línea>`, de modo que cualquiera puede verificarlas.

## Licencia

El repositorio de origen no declara licencia, por lo que su código pertenece a
sus autores con todos los derechos reservados. Este repositorio tampoco
declara licencia: no concede permisos sobre el código de origen ni sobre el
añadido aquí.

## Contenido

| Ruta | Qué contiene |
|---|---|
| `modelo/` | El modelo integrado (`modelo_bna.py`), el generador del DDL (`ddl_bna.py`), los diagramas (`diagramas_mer.py`) y la capa programable escrita a mano (`programacion_bna.sql`). |
| `sql/bna_core.sql` | El DDL generado, listo para cargar en PostgreSQL 16 o superior. |
| `pruebas/postgres/` | Arnés, datos de prueba, pruebas y el ejecutor para PostgreSQL 16 y 17. |
| `experimentos/sgbd/` | Experimentos E1–E7 de la comparación entre MySQL 8.4 y PostgreSQL. |
| `repro_mysql/` | Reproducción de las fallas de la línea base MySQL (`ab6a6ec`). |
| `trazabilidad/` | Catálogo de fuentes (`catalogo.py`), fallas MySQL con su línea en `ab6a6ec` (`referencias_mysql.csv`) y el generador de la matriz (`matriz.py`). |
| `resultados/` | Salidas en bruto de cada ejecución, con `metadatos.txt` (fecha, commit, versiones, imágenes), y la matriz de trazabilidad. |
| `informe/` | Fragmentos LaTeX generados que el informe incluye desde el submódulo. |
| `imagenes.env` | Imágenes de MySQL 8.4 y PostgreSQL 16 y 17, fijadas por digest. |

## Ejecución

Requisitos: Docker, Python 3.9 o superior y Git con la historia completa del
repositorio. Un solo comando vuelve a ejecutar todo:

```bash
./run_all.sh
```

1. Regenera `sql/bna_core.sql` y los fragmentos del modelo en `informe/`.
2. Ejecuta los experimentos E1–E7 en MySQL 8.4 y PostgreSQL 16 y 17
   (`resultados/experimentos/`).
3. Reproduce las fallas de la línea base MySQL (`resultados/repro_mysql/`).
4. Ejecuta las pruebas en PostgreSQL 16 y 17 (`resultados/postgres/`,
   `informe/pruebas-*.tex`).
5. Ejecuta las mismas pruebas sobre el DDL sin triggers del commit `8aec444`,
   como control (`resultados/control/`).
6. Genera la matriz de trazabilidad (`resultados/trazabilidad.md` y `.csv`),
   las fallas MySQL verificadas (`resultados/referencias_mysql.md`) y los
   fragmentos del informe que dependen de ellas.

Conviene ejecutarlo con el árbol limpio y confirmar después solo `resultados/`
e `informe/`: así `metadatos.txt` registra el commit exacto que se ejecutó.

## Cómo leer la matriz

Cada fila une una afirmación o regla con su fuente (documento del módulo y
página del PDF, documentación oficial, línea del código MySQL en `ab6a6ec` o
decisión del informe), el script que la prueba, el resultado esperado y el
obtenido en cada gestor. Las reglas que ninguna fuente enuncia aparecen como
«Decisión del informe»; los códigos `BNA-*` son mensajes de error definidos
por este proyecto, mientras que `RN-*`, `RF-*`, `INT-*` y `ERR-TAR-*` son los
de los documentos de los módulos.

## Limitaciones conocidas

- **Retenciones sin vencimiento.** Una autorización AUTORIZADA que nunca se
  contabiliza ni se extorna conserva para siempre su parte del tope diario y
  su retención en el saldo disponible. Ningún documento de los módulos ni el
  documento de tecnologías fija un plazo para liberarla, de modo que la base
  no inventa uno; si el banco lo define, se implementa como
  `tarjetas.marcar_tarjetas_vencidas()`: una función que se programa desde
  fuera.
