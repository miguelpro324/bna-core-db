# Funciones comunes de los ejecutores. Se carga con:
#   . "$ROOT/lib/comun.sh"   (con ROOT = raíz del repositorio)
# shellcheck shell=bash

# shellcheck source=../imagenes.env
. "$ROOT/imagenes.env"

# Commit sobre el que corre la ejecución. "sucio" indica cambios sin
# confirmar fuera de resultados/ e informe/, que son salidas.
commit_actual() {
  local c estado=limpio
  c="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
  [ -n "$(git -C "$ROOT" status --porcelain -- . ':!resultados' ':!informe')" ] && estado=sucio
  echo "$c ($estado)"
}

# metadatos ARCHIVO [CLAVE=VALOR]...
# Escribe la fecha de la ejecución, el commit, Docker y los pares recibidos
# (versiones de los gestores, imágenes, etc.).
metadatos() {
  local f="$1"; shift
  {
    echo "fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: $(commit_actual)"
    echo "docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo desconocido)"
    for kv in "$@"; do echo "${kv%%=*}: ${kv#*=}"; done
  } > "$f"
}
