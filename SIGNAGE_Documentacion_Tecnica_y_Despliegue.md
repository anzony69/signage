# SIGNAGE — Guía de construcción, exportación y migración

**Estado documentado:** 10 de octubre de 2026  
**Entorno actual:** Debian GNU/Linux 13 (trixie), contenedor LXC `signage`, IP actual `192.168.0.48`.

## 1. Objetivo

Esta guía documenta tanto cómo se construyó SIGNAGE como la forma de exportar la instalación actual y restaurarla en una futura máquina virtual.

Hay dos vías complementarias:

1. **Reconstrucción desde cero:** seguir los pasos de instalación y configuración descritos aquí.
2. **Migración del estado actual:** generar un paquete con los archivos y configuración actuales y restaurarlo, revisándolo antes de aplicarlo.

La exportación no sustituye a la guía; conserva los archivos que ya funcionan y reduce el trabajo de migración.

## 2. Arquitectura actual

- **Apache HTTP Server** sirve el catálogo y los visores.
- **Puerto 8080:** catálogo y visor público, sin autenticación para la visualización.
- **Puerto 8081:** WebDAV autenticado para subir y organizar contenido.
- **`/var/www/signage/`:** aplicación web, catálogo central, API, visor genérico y archivos de PDF.js.
- **`/srv/signage-content/`:** contenido publicado, organizado en carpetas que pueden crearse mediante WebDAV.
- **`/etc/apache2/signage.htpasswd`:** usuarios y hashes de contraseñas de WebDAV.
- **`/var/www/signage/api/contenido.php`:** API PHP que detecta carpetas y archivos automáticamente.
- **`/var/www/signage/visor/index.html`:** visor genérico compartido para todas las carpetas.
- **PDF.js:** biblioteca JavaScript usada para renderizar PDF en el navegador.

La IP `192.168.0.48` corresponde al entorno actual y puede cambiar al migrar.

## 3. Estructura de directorios

```text
/var/www/signage/
├── index.html                 # Catálogo central
├── api/
│   └── contenido.php          # Descubrimiento dinámico del contenido
├── visor/
│   └── index.html             # Único visor genérico
├── build/
│   ├── pdf.js
│   └── pdf.worker.js
└── web/                       # Recursos de PDF.js

/srv/signage-content/
├── TRIM01/
│   └── contenido_01.pdf
├── LOG01/
│   └── contenido.jpg
└── NUEVA_PANTALLA/
    └── contenido.mp4
```

Los nombres de ejemplo son ilustrativos. Las carpetas de contenido pueden ser otras y se descubren dinámicamente si contienen archivos admitidos.

Las antiguas carpetas de visores, como `/var/www/signage/TRIM01/`, `/var/www/signage/LOG01/` y otras, ya no son necesarias para el nuevo catálogo cuando este apunta al visor genérico. No eliminarlas hasta verificar que no contienen otros archivos que deban conservarse. Si se apartan, guardarlas fuera de `/var/www/signage/`.

## 4. Cómo se construyó, paso a paso

### Paso 1. Preparar Debian e instalar paquetes

En una instalación Debian nueva:

```bash
apt update
apt install -y apache2 php libapache2-mod-php apache2-utils
```

Comprobar:

```bash
apache2 -v
php -v
systemctl status apache2 --no-pager
```

### Paso 2. Separar aplicación y contenido

La aplicación se encuentra en `/var/www/signage`; los documentos, imágenes y vídeos que se muestran se guardan en `/srv/signage-content`.

```bash
mkdir -p /var/www/signage
mkdir -p /srv/signage-content
```

Esta separación evita mezclar el código web con el contenido administrado por WebDAV.

### Paso 3. Instalar e integrar PDF.js

PDF.js permite visualizar PDF dentro del navegador. El visor importa la biblioteca y configura su worker así:

```js
import * as pdfjsLib from "/build/pdf.js";
pdfjsLib.GlobalWorkerOptions.workerSrc = "/build/pdf.worker.js";
```

Archivos utilizados:

- `/var/www/signage/build/pdf.js`
- `/var/www/signage/build/pdf.worker.js`
- `/var/www/signage/web/`

La inspección realizada en el archivo `pdf.js` encontró un aviso de licencia Apache 2.0, pero no permitió confirmar la versión exacta. Para migrar la instalación actual, conserva juntos los archivos existentes. No actualices `pdf.js` y `pdf.worker.js` por separado: deben ser de la misma versión.

Comprobación:

```bash
test -s /var/www/signage/build/pdf.js && echo 'pdf.js OK'
test -s /var/www/signage/build/pdf.worker.js && echo 'worker OK'
test -d /var/www/signage/web && echo 'recursos web OK'
```

### Paso 4. Crear el visor genérico

El visor común está en:

```text
/var/www/signage/visor/index.html
```

Recibe dos parámetros en la URL:

- `carpeta`: nombre de la carpeta dentro de `/srv/signage-content`.
- `file`: nombre del archivo que se mostrará.

Ejemplo:

```text
http://192.168.0.48:8080/visor/?carpeta=TRIM01&file=contenido_01.pdf
```

El visor presenta PDF con PDF.js, imágenes mediante `img` y vídeos mediante `video`. Para vídeo, se configuran reproducción automática, silencio y repetición en bucle.

El visor contiene una actualización periódica del contenido cada **5 minutos**:

```js
setInterval(loadContent, 5 * 60 * 1000);
```

Este intervalo vuelve a consultar y cargar el archivo seleccionado. Por tanto, un vídeo que dure más de cinco minutos podría interrumpirse. El intervalo de cinco minutos es una decisión operativa actual, no una garantía de que los vídeos terminen antes de refrescar.

### Paso 5. Configurar Apache en el puerto 8080

Apache sirve la aplicación desde `/var/www/signage` y los archivos de contenido desde `/srv/signage-content`. La regla `AliasMatch` se configuró para no enumerar exclusivamente las nueve carpetas antiguas, permitiendo servir archivos de carpetas nuevas.

El catálogo y el visor deben seguir siendo accesibles mediante sus rutas propias, como `/`, `/api/`, `/build/`, `/web/` y `/visor/`; la regla de contenido debe excluir esas rutas y no mapear `index.html` de la aplicación como un archivo de contenido.

Comprobaciones:

```bash
apache2ctl configtest
apache2ctl -S
ss -lntp | grep -E ':(8080|8081)\b'
```

La configuración real que se migre debe revisarse en `/etc/apache2/sites-available/signage.conf` y compararse con los sitios habilitados.

### Paso 6. Configurar WebDAV en el puerto 8081

WebDAV permite administrar el contenido desde un cliente compatible, por ejemplo el Explorador de archivos de Windows. El directorio de contenido es `/srv/signage-content`.

Módulos usados:

```bash
a2enmod dav dav_fs auth_basic
```

El fichero de usuarios es `/etc/apache2/signage.htpasswd`.

Cambiar la contraseña de un usuario existente:

```bash
htpasswd -B /etc/apache2/signage.htpasswd signageadmin
```

No usar `-c` al cambiar una contraseña: esa opción crea/sobrescribe el fichero y puede borrar otros usuarios. Después de un cambio:

```bash
apache2ctl configtest && systemctl reload apache2
```

WebDAV con autenticación Basic sobre HTTP no cifra las credenciales durante el transporte. En un entorno productivo debe valorarse HTTPS o limitar el acceso a una red de confianza.

### Paso 7. Crear la API dinámica

El endpoint `/var/www/signage/api/contenido.php` examina `/srv/signage-content` y devuelve JSON con carpetas y archivos admitidos. Las extensiones contempladas incluyen `pdf`, `jpg`, `jpeg`, `png`, `webp`, `mp4` y `webm`.

La página principal `/var/www/signage/index.html` consume el JSON y genera las tarjetas, listas de archivos, enlaces de apertura y función de copiar URL. Por eso no es necesario editar el HTML central al crear una carpeta nueva.

### Paso 8. Crear una nueva pantalla

1. Crear una carpeta en WebDAV dentro de `/srv/signage-content`, por ejemplo `NUEVA_PANTALLA`.
2. Subir un archivo compatible.
3. Abrir el catálogo central en `http://192.168.0.48:8080/`.
4. Seleccionar el archivo en la tarjeta correspondiente y pulsar **Abrir pantalla**.

El enlace generado tendrá este patrón:

```text
http://192.168.0.48:8080/visor/?carpeta=NUEVA_PANTALLA&file=contenido.pdf
```

No hace falta crear un directorio nuevo bajo `/var/www/signage/` ni añadir un `index.html` por pantalla.

### Paso 9. Permisos y comprobaciones

Antes de cambiar permisos, inspeccionar el estado actual:

```bash
stat -c '%A %U:%G %n' /srv/signage-content
find /srv/signage-content -maxdepth 2 -printf '%M %u:%g %p\n' | head -80
```

No aplicar `chown` recursivo a ciegas en una restauración: comprobar primero los permisos requeridos por Apache y WebDAV.

Pruebas funcionales:

1. Abrir el catálogo en el puerto 8080.
2. Comprobar una carpeta antigua y una recién creada.
3. Mostrar un PDF, una imagen y un vídeo.
4. Comprobar WebDAV en el puerto 8081 y probar una subida.
5. Revisar los registros si algo falla:

```bash
tail -n 100 /var/log/apache2/error.log
tail -n 100 /var/log/apache2/access.log
```

## 5. Exportar el estado actual

Ejecuta como `root` los comandos siguientes para crear una copia comprimida. El paquete incluye los archivos de aplicación, contenido, configuración de Apache e inventario.

```bash
mkdir -p /root/signage-backup
chmod 700 /root/signage-backup

FECHA=$(date +%Y-%m-%d_%H%M%S)
ARCHIVO="/root/signage-backup/signage-backup-${FECHA}.tar.gz"

{
    echo "=== FECHA ==="
    date
    echo
    echo "=== SISTEMA ==="
    cat /etc/os-release
    echo
    echo "=== APACHE ==="
    apache2 -v
    echo
    echo "=== PHP ==="
    php -v
    echo
    echo "=== MODULOS APACHE ==="
    apache2ctl -M
    echo
    echo "=== VIRTUAL HOSTS ==="
    apache2ctl -S
    echo
    echo "=== SITIOS HABILITADOS ==="
    ls -l /etc/apache2/sites-enabled/
    echo
    echo "=== PUERTOS ==="
    ss -lntp
    echo
    echo "=== PAQUETES ==="
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
        apache2 php libapache2-mod-php apache2-utils 2>/dev/null
    echo
    echo "=== PDF.JS ==="
    ls -lh /var/www/signage/build/pdf.js \
           /var/www/signage/build/pdf.worker.js
    sha256sum /var/www/signage/build/pdf.js \
              /var/www/signage/build/pdf.worker.js
    echo
    echo "=== CONTENIDO ==="
    find /srv/signage-content -maxdepth 4 \
        -printf '%M %u:%g %s %p\n'
} > /root/signage-backup/inventario.txt 2>&1

tar -czpf "$ARCHIVO" \
    /var/www/signage \
    /srv/signage-content \
    /etc/apache2 \
    /root/signage-backup/inventario.txt

chmod 600 "$ARCHIVO"
echo "Copia creada: $ARCHIVO"
ls -lh "$ARCHIVO"
```

El paquete contiene el fichero de usuarios de WebDAV y posiblemente documentos internos. Debe guardarse de forma privada y transferirse a otro almacenamiento para que no dependa exclusivamente del contenedor.

La copia no incluye la definición de LXC en Proxmox, VLAN, reglas externas de firewall ni configuración del host.

## 6. Restaurar en una VM nueva

1. Instalar Debian y los paquetes necesarios:

```bash
apt update
apt install -y apache2 php libapache2-mod-php apache2-utils
```

2. Copiar el archivo `.tar.gz` a la VM.
3. Inspeccionar su contenido:

```bash
tar -tzf signage-backup-AAAA-MM-DD_HHMMSS.tar.gz | less
```

4. Extraer primero a una ubicación temporal para revisar los archivos:

```bash
mkdir -p /root/signage-restore
tar -xzf signage-backup-AAAA-MM-DD_HHMMSS.tar.gz -C /root/signage-restore
```

El archivo creado por los comandos de exportación anteriores guarda las rutas bajo `var/www/signage`, `srv/signage-content` y `etc/apache2` directamente desde `/`. Revisa el listado y restaura con cuidado. En una VM vacía, después de revisar el contenido y realizar cualquier copia previa necesaria, se pueden restaurar las rutas preservadas con:

```bash
cp -a /root/signage-restore/var/www/signage /var/www/
cp -a /root/signage-restore/srv/signage-content /srv/
cp -a /root/signage-restore/etc/apache2/. /etc/apache2/
```

Si los directorios ya existen, no sobrescribirlos sin compararlos y hacer una copia previa.

5. Comprobar módulos, configuración y puertos:

```bash
a2enmod dav dav_fs auth_basic
apache2ctl configtest
apache2ctl -S
systemctl enable --now apache2
ss -lntp | grep -E ':(8080|8081)\b'
```

6. Adaptar IP, DNS y firewall a la nueva VM. La dirección antigua no tiene por qué conservarse.
7. Probar catálogo, visor PDF, imagen, vídeo y una subida por WebDAV.

La exportación conserva archivos y configuración, pero no instala paquetes sin conexión ni recrea la configuración externa de Proxmox. La migración debe validarse antes de sustituir el servicio actual.

## 7. Diagnóstico rápido

```bash
apache2ctl configtest
systemctl status apache2 --no-pager
tail -n 100 /var/log/apache2/error.log
curl -s -o /dev/null -w 'Catálogo: HTTP %{http_code}\n' http://127.0.0.1:8080/
curl -s -o /dev/null -w 'Visor: HTTP %{http_code}\n' http://127.0.0.1:8080/visor/
```

## 8. Datos pendientes de confirmar

- La versión exacta y procedencia original de PDF.js no se han identificado; la exportación conserva los archivos actuales.
- Antes de una migración definitiva, revisar los archivos reales de Apache y probar la restauración en una VM aislada.
- El refresco actual es de cinco minutos. Si se incorporan vídeos más largos, conviene modificar la lógica para que el visor no interrumpa su reproducción.
