# Reproducción de la revisión del backend MySQL (BNA)

Pruebas usadas para comprobar los hallazgos sobre
`backend/Trabajo_hecho/BD/99_bna_unificado.sql`. No modifican el repositorio:
todo corre en un contenedor MySQL 8.4 temporal que se elimina al terminar.

## Requisitos

- Docker con la imagen `mysql:8.4` (se descarga sola si falta).
- Este repositorio con su historia completa (el script lee `ab6a6ec` con `git archive`).

## Uso

```bash
./run.sh                                   # usa backend/Trabajo_hecho del commit ab6a6ec
./run.sh /ruta/a/backend/Trabajo_hecho     # otra ubicación
```

La salida de cada paso queda en `resultados/repro_mysql/` (en la raíz del repositorio), junto con `resultado.csv` y `metadatos.txt`.

## Qué hace

| Paso | Archivo | Comprueba |
|---|---|---|
| 1 | `run.sh` | Bug 1: `cargar_bna.ps1` busca `99_bna_unificado.sql` en `Trabajo_hecho\`, pero está en `BD\`. |
| 2 | `run.sh` | Carga el script unificado y lista errores y avisos. |
| 3 | `sql/00_conteos.sql` | Tablas, vistas, triggers, rutinas, eventos, FKs, CHECKs y columnas. |
| 4 | `sql/01_estado_demo.sql` | Bug 2: `fn_uuid_v7()` suma dos veces los milisegundos y rompe el orden. Bug 3: el depósito no cambia el saldo. Bug 4: el pago no reduce `saldo_capital`. |
| 5 | `sql/02_integridad.sql` | Bug 7: datos inconsistentes aceptados. También el pago aplicado a mora que deja la cuota `PAGADA`, la auditoría con referencia libre y la reversión con el mismo empleado. |
| 6 | `sql/03_topes_y_bloqueo.sql` | Bug 5: tope contado dos veces, aprobación posterior no contada y tope no aplicado; la vista suma todas las cuentas. Bug 6: `sp_bloquear_tarjeta` ignora motivo y origen. |
| 7 | `run.sh` | `diccionario_datos.md` contra las columnas reales, y relaciones y tablas que faltan en `mer_bna.mermaid`. |

Los archivos `sql/` dependen del orden: `02` crea la tarjeta `k1` que usa `03`, y
ambos parten de los datos demo que inserta `13_consultas.sql` dentro del
script unificado. Para repetir una prueba suelta, vuelve a correr `run.sh`.

## Cómo leer el resultado

Al final, `run.sh` muestra un informe en lenguaje simple (se guarda también en
`resultados/repro_mysql/informe.txt`). Cada comprobación aparece así:

```
[FALLA]  4. Un deposito actualiza el saldo de la cuenta  (bug 3)
   Que se hizo: El propio script (13_consultas.sql) abre la cuenta 0011000001
                con saldo 0 y le deposita S/500.
   Correcto:    saldo_contable = 500.00
   Obtenido:    saldo_contable = 0.00
   Significa:   El movimiento queda registrado pero el saldo nunca cambia: ...
```

- `[ OK  ]`: el script hace lo correcto.
- `[FALLA]`: el script hace otra cosa. **Correcto** es lo que debería pasar,
  **Obtenido** es lo que pasó y **Significa** explica la consecuencia.
- `(bug N)` es el número del hallazgo en la revisión. Sin número, es una
  comprobación adicional.
- Las pruebas de datos inconsistentes intentan guardar algo que no tiene
  sentido. Lo correcto es que MySQL lo **rechace**; "MySQL lo acepto sin
  error" es la falla.

La última línea resume el total. El resultado esperado con el script actual es
`28 comprobaciones: 3 OK, 25 FALLA`. Las OK confirman que la carga funciona,
que crea los objetos prometidos y que el diccionario coincide con la base.

Para ver las tablas técnicas de cada prueba: `./run.sh --detalle`, o los
archivos `resultados/repro_mysql/*.log`.
