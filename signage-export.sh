#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exportador de la instalación SIGNAGE actual.
# Ejecutar como root dentro del contenedor/servidor signage.
# Incluye aplicación, contenido, configuración Apache e inventario.
# El paquete contiene datos sensibles: protege el archivo resultante.

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: ejecuta este script como root." >&2
    exit 1
fi

for required in /var/www/signage /srv/signage-content /etc/apache2; do
    if [[ ! -d "$required" ]]; then
        echo "ERROR: no existe $required; se cancela la exportación." >&2
        exit 1
    fi
done

STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUTDIR="/root/signage-backup"
WORKDIR="$(mktemp -d "/tmp/signage-export.XXXXXX")"
ARCHIVE="${OUTDIR}/signage-backup-${STAMP}.tar.gz"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$OUTDIR" "$WORKDIR/payload" "$WORKDIR/inventory"

echo "Preparando inventario de SIGNAGE..."

{
    echo "SIGNAGE - INVENTARIO DE EXPORTACIÓN"
    echo "Fecha de exportación: $(date --iso-8601=seconds)"
    echo
    echo "===== SISTEMA OPERATIVO ====="
    cat /etc/os-release 2>/dev/null || true
    echo
    echo "===== KERNEL ====="
    uname -a 2>&1 || true
    echo
    echo "===== VERSIONES DE PAQUETES ====="
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
        apache2 php libapache2-mod-php apache2-utils 2>/dev/null || true
    echo
    echo "===== APACHE ====="
    apache2 -v 2>&1 || true
    echo
    echo "===== PHP ====="
    php -v 2>&1 || true
    echo
    echo "===== CONFIGURACIÓN DE VIRTUAL HOSTS ====="
    apache2ctl -S 2>&1 || true
    echo
    echo "===== MÓDULOS APACHE ====="
    apache2ctl -M 2>&1 || true
    echo
    echo "===== SITIOS HABILITADOS ====="
    find /etc/apache2/sites-enabled -maxdepth 1 -type l \
        -printf '%f -> %l\n' 2>/dev/null || true
    echo
    echo "===== MÓDULOS HABILITADOS ====="
    find /etc/apache2/mods-enabled -maxdepth 1 -type l \
        -printf '%f -> %l\n' 2>/dev/null || true
    echo
    echo "===== PUERTOS EN ESCUCHA ====="
    ss -lntp 2>&1 || true
    echo
    echo "===== CONFIGURACIÓN APACHE SIGNAGE ====="
    cat /etc/apache2/sites-available/signage.conf 2>&1 || true
    echo
    echo "===== ESTADO DEL VISOR GENÉRICO ====="
    if [[ -s /var/www/signage/visor/index.html ]]; then
        echo "Visor genérico presente: /var/www/signage/visor/index.html"
        grep -n -E 'setInterval|pdf\.js|pdf\.worker\.js|carpeta|selectedFile|const file' \
            /var/www/signage/visor/index.html 2>/dev/null || true
    else
        echo "AVISO: no se encuentra /var/www/signage/visor/index.html"
    fi
    echo
    echo "===== CATÁLOGO CENTRAL ====="
    ls -l /var/www/signage/index.html 2>&1 || true
    grep -n -A 6 'function getViewerUrl' /var/www/signage/index.html 2>/dev/null || true
    echo
    echo "===== API ====="
    ls -l /var/www/signage/api/contenido.php 2>&1 || true
    echo
    echo "===== PDF.JS ====="
    ls -lh /var/www/signage/build/pdf.js \
           /var/www/signage/build/pdf.worker.js 2>&1 || true
    sha256sum /var/www/signage/build/pdf.js \
              /var/www/signage/build/pdf.worker.js 2>/dev/null || true
    echo
    echo "===== INVENTARIO DE CONTENIDO ====="
    find /srv/signage-content -maxdepth 5 \
        -printf '%M %u:%g %s bytes %p\n' 2>&1 || true
    echo
    echo "===== ESPACIO UTILIZADO ====="
    du -sh /var/www/signage /srv/signage-content /etc/apache2 2>&1 || true
} > "$WORKDIR/inventory/inventario.txt"

cat > "$WORKDIR/README-RESTAURACION.txt" <<'EOF'
SIGNAGE - Paquete de exportación
================================

Contiene:
- payload/var/www/signage: catálogo, API, visor genérico, PDF.js y recursos web.
- payload/srv/signage-content: documentos, imágenes y vídeos publicados.
- payload/etc/apache2: configuración de Apache y usuarios WebDAV si el fichero
  de contraseñas está ubicado dentro de /etc/apache2.
- inventory/inventario.txt: versiones, módulos, puertos, configuración e inventario.

Arquitectura esperada:
- Puerto 8080: catálogo y visor público.
- Puerto 8081: WebDAV autenticado.
- Visor genérico: /var/www/signage/visor/index.html.
- Contenido: /srv/signage-content.
- Refresco previsto del visor: 5 minutos (verificado en inventario; revisar el
  archivo del visor si se ha cambiado desde la última actualización).

SEGURIDAD:
El archivo puede contener contenido interno y hashes de contraseñas WebDAV.
Guárdalo en un almacenamiento privado. No lo publiques ni lo compartas sin
protección. El archivo no contiene la definición del contenedor Proxmox/LXC,
las VLAN ni las reglas de firewall externas.

RESTAURACIÓN:
No extraer directamente encima de una instalación existente sin revisar.
Inspeccionar primero:
  tar -tzf signage-backup-AAAA-MM-DD_HHMMSS.tar.gz

Para una VM nueva, instalar primero los paquetes necesarios, extraer a un
directorio temporal, revisar los archivos y restaurar selectivamente.
Validar con:
  apache2ctl configtest
  apache2ctl -S
  systemctl status apache2 --no-pager
y probar catálogo, PDF, imagen, vídeo y WebDAV.
EOF

echo "Copiando archivos de la instalación..."
mkdir -p "$WORKDIR/payload/var/www" "$WORKDIR/payload/srv" "$WORKDIR/payload/etc"
cp -a /var/www/signage "$WORKDIR/payload/var/www/"
cp -a /srv/signage-content "$WORKDIR/payload/srv/"
cp -a /etc/apache2 "$WORKDIR/payload/etc/"

echo "Creando archivo comprimido..."
tar -czpf "$ARCHIVE" -C "$WORKDIR" \
    payload inventory README-RESTAURACION.txt
chmod 600 "$ARCHIVE"

echo
echo "Comprobando integridad del archivo..."
tar -tzf "$ARCHIVE" >/dev/null

echo
echo "EXPORTACIÓN COMPLETADA"
echo "Archivo: $ARCHIVE"
du -h "$ARCHIVE"
echo
echo "Incluye la versión actual de /var/www/signage y /srv/signage-content."
echo "ATENCIÓN: contiene configuración y hashes de contraseñas WebDAV."
