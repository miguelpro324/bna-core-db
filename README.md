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
