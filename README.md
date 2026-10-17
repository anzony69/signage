# SIGNAGE — Guía de instalación en Debian 13

**Versión:** 3.0  
**Fecha:** 16/10/2026

<img width="1450" height="605" alt="image" src="https://github.com/user-attachments/assets/2abb7795-d5b7-4458-a093-30f5f3a3f619" />

## 1. Objetivo

Esta guía explica cómo instalar, configurar, probar y respaldar SIGNAGE en un servidor con **Debian 13 (Trixie)**. La instalación se centra en Debian y no depende de una plataforma de virtualización concreta.

La migración a una máquina virtual o la exportación a OVA, si se necesita, son procedimientos alternativos y quedan fuera del procedimiento principal de esta guía.

## 2. Arquitectura y rutas

SIGNAGE es una aplicación interna de señalización digital que ofrece un catálogo web, un visor y una API para localizar los contenidos. Los archivos de las pantallas se guardan en carpetas y se pueden administrar mediante WebDAV.

Rutas utilizadas en el entorno actual:

| Componente | Ruta |
|---|---|
| Catálogo principal unificado | `/var/www/signage/index.html` |
| Visor | `/var/www/signage/visor/index.html` |
| API | `/var/www/signage/api/contenido.php` |
| PDF.js | `/var/www/signage/build/` |
| Recursos auxiliares de PDF.js | `/var/www/signage/web/` |
| Contenido de las pantallas | `/srv/signage-content/` |
| Configuración de Apache | `/etc/apache2/` |
| Archivo de credenciales WebDAV conocido | `/etc/apache2/signage.htpasswd` |

En el entorno de desarrollo se han utilizado los puertos 8080 para la web y 8081 para WebDAV. **Comprueba la configuración real antes de habilitar esos puertos**; no asumas que son obligatorios en una instalación nueva.

## 3. Requisitos previos

- Debian 13 actualizado.
- Acceso de administrador mediante `root` o `sudo`.
- Conectividad de red desde los equipos que mostrarán la señalización.
- Copia de los archivos de SIGNAGE y de los contenidos.
- Nombres de carpetas y estructura de contenidos definidos.
- Un navegador compatible en las pantallas.

Actualizar Debian:

```bash
apt update
apt full-upgrade -y
```

Instalar herramientas útiles:

```bash
apt install -y curl ca-certificates unzip tar rsync nano
```

## 4. Instalar Apache, PHP y WebDAV

Instalar Apache, PHP y las herramientas de autenticación:

```bash
apt install -y apache2 php libapache2-mod-php apache2-utils
```

Habilitar los módulos necesarios para WebDAV y autenticación básica:

```bash
a2enmod dav dav_fs auth_basic
```

Activar Apache al arrancar y comprobar el servicio:

```bash
systemctl enable --now apache2
systemctl status apache2 --no-pager
```

Verificar módulos y virtual hosts:

```bash
apache2ctl -M
apache2ctl -S
```

Los módulos y extensiones PHP adicionales dependen del contenido real de `contenido.php`. Si la API requiere alguna extensión PHP, instálala según los errores observados en los logs.

## 5. Crear las carpetas de SIGNAGE

Crear las rutas base:

```bash
mkdir -p /var/www/signage
mkdir -p /srv/signage-content
```

La estructura de la aplicación debe quedar, como mínimo, así:

```text
/var/www/signage/
├── index.html
├── api/
│   └── contenido.php
├── visor/
│   └── index.html
├── build/
│   ├── pdf.js
│   └── pdf.worker.js
└── web/

/srv/signage-content/
├── TRIM01/
├── LOG01/
└── ...
```

Los nombres de carpetas de ejemplo deben sustituirse por los nombres reales de las pantallas o departamentos.

## 6. Copiar los archivos de la aplicación y los contenidos

Si se dispone de una copia de seguridad generada por el script de exportación, primero inspeccionarla:

```bash
tar -tzf signage-backup-FECHA.tar.gz | less
```

Extraerla en una carpeta temporal, sin sobrescribir directamente la configuración del sistema:

```bash
mkdir -p /root/signage-restore
tar -xzf signage-backup-FECHA.tar.gz -C /root/signage-restore
```

La exportación preparada para el proyecto guarda normalmente los archivos bajo rutas similares a:

```text
payload/var/www/signage/
payload/srv/signage-content/
payload/etc/apache2/
```

Confirma los nombres exactos con `tar -tzf` antes de continuar.

Copiar la aplicación y los contenidos revisados:

```bash
cp -a /root/signage-restore/payload/var/www/signage /var/www/
cp -a /root/signage-restore/payload/srv/signage-content /srv/
```

Si se instala desde archivos sueltos, copia el catálogo, el visor, la API, PDF.js y sus recursos a las rutas indicadas. Asegúrate de que `pdf.js` y `pdf.worker.js` procedan de la misma distribución.

No copies a ciegas todo `/etc/apache2` desde otro sistema. Revisa y adapta los VirtualHost, alias, puertos, módulos y autenticación al Debian de destino.

## 7. Configurar permisos

Apache necesita leer la aplicación y los contenidos. WebDAV necesita permisos de escritura únicamente en las ubicaciones donde se permita administrar archivos.

Como punto de partida para la aplicación estática:

```bash
chown -R root:root /var/www/signage
find /var/www/signage -type d -exec chmod 755 {} \;
find /var/www/signage -type f -exec chmod 644 {} \;
```

Los permisos del contenido dependen de cómo esté configurado WebDAV. No apliques un `chown -R www-data:www-data` a todo el árbol sin revisar primero qué usuario necesita escribir. Mantén separados los permisos de lectura del visor y los permisos de escritura de WebDAV.

Comprueba los permisos:

```bash
namei -l /var/www/signage/index.html
namei -l /srv/signage-content
```

## 8. Configurar Apache

Antes de editar, inspeccionar la configuración:

```bash
grep -RniE 'Listen|VirtualHost|AliasMatch|Dav|AuthType|AuthUserFile' /etc/apache2
ss -lntp
```

Durante el desarrollo se ha utilizado una regla de alias para servir los archivos de contenido. La regla equivalente conocida es:

```apache
AliasMatch "^/(?!api/|build/|web/|visor/|dav/)([^/]+)/([^/]+)$" "/srv/signage-content/$1/$2"
```

Esta regla es solo una referencia del entorno existente. Debe colocarse y probarse dentro de la configuración de Apache apropiada, verificando que no interfiera con el catálogo, la API, PDF.js, el visor ni WebDAV.

Configura los puertos web y WebDAV según el diseño deseado. Si se decide utilizar 8080 y 8081, comprueba que no estén ocupados y añade las directivas `Listen` y los VirtualHost correspondientes.

Después de cualquier cambio:

```bash
apache2ctl configtest
apache2ctl -S
systemctl reload apache2
```

No continúes si `configtest` informa de errores.

## 9. Configurar WebDAV y las credenciales

Crear un archivo de contraseñas nuevo, si no existe:

```bash
htpasswd -cB /etc/apache2/signage.htpasswd signageadmin
```

Si el archivo ya existe y solo quieres cambiar la contraseña del usuario:

```bash
htpasswd -B /etc/apache2/signage.htpasswd signageadmin
```

No uses `-c` al modificar un archivo existente porque lo recrea.

El VirtualHost o directorio WebDAV debe incluir las directivas adecuadas de `Dav On`, autenticación y autorización, y debe limitarse a la ruta prevista. No habilites escritura sobre todo el sitio web.

**Seguridad:** Basic Auth sobre HTTP no cifra las credenciales. En producción, utiliza HTTPS o limita WebDAV a una red confiable/VPN y aplica reglas de firewall. Protege el archivo `signage.htpasswd` y no lo publiques en GitHub.

## 10. Configurar el catálogo unificado

El catálogo principal es:

```text
/var/www/signage/index.html
```

Integra dos modos por carpeta.

### 10.1 Modo selectivo

- Incluye un desplegable con los archivos disponibles.
- Incluye los botones **Abrir URL**, **Copiar URL** y **Chrome Kiosk**.
- Utiliza una URL con carpeta y nombre de archivo, por ejemplo:

```text
http://SERVIDOR:8080/visor/?carpeta=TRIM01&file=presentacion.pdf
```

### 10.2 Modo AUTO

- Busca un único archivo compatible cuyo nombre base sea exactamente `contenido`.
- Extensiones admitidas por el catálogo: `pdf`, `jpg`, `jpeg`, `png`, `webp`, `mp4`, `webm`.
- Si hay exactamente uno, presenta los botones **Abrir URL**, **Copiar URL** y **Chrome Kiosk**.
- Si no hay ninguno o hay varios, muestra una advertencia.

Ejemplos de contenido:

```text
/srv/signage-content/
├── TRIM01/contenido.pdf
├── LOG01/contenido.mp4
└── PAINT01/contenido.jpg
```

URL AUTO:

```text
http://SERVIDOR:8080/visor/?carpeta=TRIM01&auto=1
```

Ambos modos usan `/visor/`; el visor debe admitir los parámetros `carpeta`, `file` y `auto`.

## 11. Configurar la API

La API debe estar disponible en:

```text
/var/www/signage/api/contenido.php
```

El catálogo espera una respuesta JSON en forma de array de grupos. Cada grupo debe incluir `name` y `files`, donde `files` sea una lista de nombres de archivo.

Probarla localmente, adaptando el puerto:

```bash
curl -i http://127.0.0.1:8080/api/contenido.php
```

Si devuelve un error HTTP, HTML en lugar de JSON o un formato distinto, revisar los logs de Apache y PHP. El catálogo y el visor deben utilizar la misma estructura de respuesta.

## 12. Visor PDF.js y otros contenidos

El visor está en `/var/www/signage/visor/index.html`. Según la implementación actual, puede presentar PDF, imágenes y vídeo de los formatos admitidos.

Para PDF.js:

- Mantén `pdf.js` y `pdf.worker.js` de la misma versión/distribución.
- Prueba con los navegadores que se utilizarán en las pantallas.
- Si se conserva el polyfill de `Map.prototype.getOrInsertComputed`, debe estar antes de importar el módulo PDF.js:

```html
<script>
if (!Map.prototype.getOrInsertComputed) {
    Map.prototype.getOrInsertComputed = function(key, callback) {
        if (this.has(key)) return this.get(key);
        const value = callback(key);
        this.set(key, value);
        return value;
    };
}
</script>
```

En pruebas previas se observó un error de compatibilidad relacionado con `getOrInsertComputed`. Mantener el polyfill solo si la versión de PDF.js y los navegadores utilizados lo requieren, y comprobar que el visor funciona después de cualquier actualización.

**Refresco AUTO:** la implementación actual comprueba el contenido periódicamente (se ha utilizado un intervalo de cinco minutos). Si se sustituye un archivo por otro conservando exactamente el mismo nombre y ruta, debe probarse que el visor vuelve a cargarlo. Si no lo hace, habrá que comparar `ETag`, `Last-Modified` o una versión del contenido para forzar la actualización.

## 13. Chrome Kiosk

El catálogo genera un archivo `.bat` para abrir el navegador a pantalla completa. El comando generado usa esta ruta de Chrome:

```bat
@echo off
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk --no-first-run "URL_DE_LA_PANTALLA"
exit
```

La ruta debe coincidir con la instalación de Chrome de cada pantalla. El BAT no configura por sí solo el inicio de sesión automático de Windows ni el arranque automático de la aplicación.

## 14. Comprobaciones finales

Ejecutar:

```bash
apache2ctl configtest
systemctl status apache2 --no-pager
ss -lntp
tail -n 100 /var/log/apache2/error.log
tail -n 100 /var/log/apache2/access.log
```

Probar el catálogo, el visor y la API desde el propio servidor, usando el puerto real:

```bash
curl -I http://127.0.0.1:8080/
curl -I http://127.0.0.1:8080/visor/
curl -i http://127.0.0.1:8080/api/contenido.php
```

Lista de validación:

- [ ] Apache arranca sin errores.
- [ ] El catálogo detecta las carpetas y muestra archivos.
- [ ] El modo selectivo abre el archivo elegido.
- [ ] El modo AUTO detecta un único `contenido.*`.
- [ ] PDF, imágenes y vídeos se visualizan correctamente.
- [ ] Los BAT contienen la URL correcta para cada modo.
- [ ] WebDAV autentica y permite solo las operaciones previstas.
- [ ] Los permisos de lectura y escritura son correctos.
- [ ] Los puertos y el acceso desde la red funcionan según lo previsto.
- [ ] El refresco AUTO se ha probado al sustituir un archivo.

## 15. Copias de seguridad

El script `signage-export-actualizado-v2.sh` realiza una exportación de archivos y configuración de SIGNAGE; no es una imagen completa de disco ni un backup del sistema operativo.

Ejecutarlo en el servidor donde esté instalado el script:

```bash
chmod 700 signage-export-actualizado-v2.sh
./signage-export-actualizado-v2.sh
```

El archivo se guarda bajo una ruta del tipo:

```text
/root/signage-backup/signage-backup-FECHA.tar.gz
```

La exportación incluye la aplicación, los contenidos y la configuración de Apache que contempla el script, además de inventario y checksums. Inspecciona el archivo antes de restaurar y confirma las rutas exactas con `tar -tzf`.

El backup puede contener el archivo de autenticación WebDAV y otros datos internos. Guárdalo con permisos restringidos. No publiques el backup, los hashes de credenciales ni secretos en GitHub.

## 16. Solución de problemas

- **Catálogo vacío:** comprueba el JSON de la API y los permisos de lectura de `/srv/signage-content/`.
- **Error HTTP 403/404:** revisa VirtualHost, alias, permisos y logs de Apache.
- **Error PHP:** revisa `/var/log/apache2/error.log` y las extensiones PHP requeridas.
- **AUTO no aparece:** confirma que existe exactamente un `contenido.*` con extensión admitida.
- **PDF no carga:** comprueba que `pdf.js` y `pdf.worker.js` corresponden a la misma distribución y prueba el polyfill si procede.
- **WebDAV no autentica:** comprueba el módulo, `AuthUserFile`, usuario y permisos.
- **No se puede escribir por WebDAV:** revisa los permisos del directorio de contenido y la autorización del bloque WebDAV.
- **La pantalla no accede al servidor:** comprueba IP, DNS, puerto, firewall y conectividad de red.

## 17. Seguridad y repositorio GitHub

Se puede publicar en el repositorio el código de la aplicación, la documentación y scripts revisados. No publiques:

- `signage.htpasswd` ni hashes de contraseñas.
- Backups `.tar.gz`.
- Contraseñas, tokens, claves privadas o secretos.
- Contenidos internos no autorizados para publicación.

Revisa cualquier configuración o script antes de hacer commit.

## 18. Despliegues alternativos

La instalación descrita en esta guía es la instalación de referencia en **Debian 13**. Si se decide desplegarla dentro de una VM, en VMware Workstation, en Proxmox u otra plataforma, la plataforma de virtualización es una decisión separada.

El procedimiento alternativo de virtualización debe comenzar con una instalación Debian y aplicar esta guía. Si se necesita exportar una VM como OVA, debe documentarse y validarse como un procedimiento adicional, sin sustituir los pasos de instalación de SIGNAGE en Debian.



## 19. Código completo del catálogo y del visor

Esta sección incorpora los códigos HTML facilitados para que puedan recuperarse al reinstalar el servicio. Guárdalos exactamente en las rutas indicadas.

### 19.1 Catálogo unificado: `/var/www/signage/index.html`

El catálogo genera las tarjetas de cada carpeta, el modo selectivo y el modo AUTO. Incluye los botones Abrir URL, Copiar URL y Chrome Kiosk.

```html
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SIGNAGE | Panel de pantallas</title>

<style>
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 22px;
  font-family: "Segoe UI", Arial, sans-serif;
  background: #f1f4f8;
  color: #172033;
}

header {
  max-width: 1400px;
  margin: 0 auto 18px;
}

h1 {
  margin: 0 0 6px;
  font-size: 27px;
}

header p {
  color: #64748b;
  margin: 0;
  font-size: 13px;
}

.toolbar {
  max-width: 1400px;
  margin: 0 auto 14px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  flex-wrap: wrap;
}

.status {
  color: #64748b;
  font-size: 12px;
}

.grid {
  max-width: 1400px;
  margin: auto;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 14px;
}

.card {
  min-width: 0;
  background: white;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 15px;
  box-shadow: 0 3px 10px #0f172a0a;
}

.card h2 {
  font-size: 17px;
  margin: 0 0 6px;
  overflow-wrap: anywhere;
}

.card-description {
  color: #64748b;
  font-size: 12px;
  margin: 0 0 12px;
  overflow-wrap: anywhere;
}

/* Bloques de los modos */

.mode-section {
  padding: 11px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  margin-top: 10px;
  min-width: 0;
}

.selective-mode {
  background: #f8fafc;
  border-top: 3px solid #2563eb;
}

.auto-mode {
  background: #f0fdf4;
  border-top: 3px solid #16a34a;
}

.mode-heading {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0 0 6px;
  font-size: 14px;
}

.selective-mode .mode-heading {
  color: #1d4ed8;
}

.auto-mode .mode-heading {
  color: #166534;
}

.mode-description {
  color: #64748b;
  font-size: 11px;
  line-height: 1.4;
  margin: 0 0 10px;
  overflow-wrap: anywhere;
}

label {
  display: block;
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  margin-bottom: 5px;
}

select {
  display: block;
  width: 100%;
  min-width: 0;
  padding: 8px;
  margin-bottom: 9px;
  border: 1px solid #cbd5e1;
  border-radius: 6px;
  background: white;
  color: #172033;
  font: inherit;
  font-size: 12px;
}

/* Los tres botones permanecen en una fila */

.actions {
  display: flex;
  flex-wrap: nowrap;
  align-items: stretch;
  gap: 5px;
  min-width: 0;
}

a,
button {
  display: inline-block;
  border: 0;
  border-radius: 6px;
  padding: 8px 4px;
  font-size: 11px;
  text-decoration: none;
  cursor: pointer;
  font-family: inherit;
  text-align: center;
}

.actions a,
.actions button {
  flex: 1 1 0;
  min-width: 0;
  white-space: nowrap;
  letter-spacing: -0.25px;
}

.open,
.refresh {
  background: #1d4ed8;
  color: white;
}

.copy {
  background: #e8edf5;
  color: #172033;
}

.kiosk {
  background: #15803d;
  color: white;
}

button:disabled,
a.disabled {
  opacity: .45;
  cursor: not-allowed;
  pointer-events: none;
}

.auto-warning {
  padding: 9px;
  background: #fff7ed;
  border: 1px solid #fed7aa;
  border-radius: 6px;
  color: #9a3412;
  font-size: 11px;
  line-height: 1.4;
  overflow-wrap: anywhere;
}

.empty {
  grid-column: 1 / -1;
  padding: 24px;
  text-align: center;
  background: white;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  color: #64748b;
  overflow-wrap: anywhere;
}

footer {
  max-width: 1400px;
  margin: 22px auto 0;
  color: #64748b;
  font-size: 11px;
}

/* Pantallas pequeñas */

@media (max-width: 600px) {
  body {
    padding: 16px 10px;
  }

  h1 {
    font-size: 24px;
  }

  .card {
    padding: 12px;
  }

  .mode-section {
    padding: 10px;
  }

  .actions {
    gap: 4px;
  }

  .actions a,
  .actions button {
    padding: 8px 3px;
    font-size: 10px;
  }
}
</style>
</head>

<body>

<header>
  <h1>SIGNAGE</h1>
  <p>Panel de acceso a las pantallas de información</p>
</header>

<div class="toolbar">
  <span class="status" id="status">
    Cargando carpetas y archivos...
  </span>

  <button class="refresh" id="refresh" type="button">
    Actualizar listado
  </button>
</div>

<main class="grid" id="screens"></main>

<footer>
  Sistema interno de señalización digital.
</footer>

<script>
const container = document.getElementById("screens");
const statusText = document.getElementById("status");
const refreshButton = document.getElementById("refresh");

const supportedExtensions = [
  "pdf", "jpg", "jpeg", "png", "webp", "mp4", "webm"
];

/* URL del modo selectivo */

function getSelectiveUrl(folder, file) {
  const url = new URL("/visor/", window.location.origin);

  url.searchParams.set("carpeta", folder);
  url.searchParams.set("file", file);
  url.searchParams.set("v", Date.now());

  return url.href;
}

/* URL del modo AUTO */

function getAutoUrl(folder) {
  const url = new URL("/visor/", window.location.origin);

  url.searchParams.set("carpeta", folder);
  url.searchParams.set("auto", "1");

  return url.href;
}

/* Contenido del BAT para Chrome Kiosk */

function makeBatContent(url) {
  return [
    "@echo off",
    'start "" "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" --kiosk --no-first-run "' + url + '"',
    "exit"
  ].join("\r\n");
}

/* Descargar BAT */

function downloadKioskBat(folder, file, url) {
  const blob = new Blob(
    [makeBatContent(url)],
    { type: "application/octet-stream" }
  );

  const downloadUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");

  const baseName = file
    ? file.replace(/\.[^.]+$/, "")
    : "auto";

  const safeName = (folder + "-" + baseName + "-kiosk")
    .replace(/[^a-zA-Z0-9_-]/g, "_");

  link.href = downloadUrl;
  link.download = safeName + ".bat";

  document.body.appendChild(link);
  link.click();
  link.remove();

  setTimeout(() => {
    URL.revokeObjectURL(downloadUrl);
  }, 1000);
}

/* Botón Abrir URL */

function createOpenButton(getUrl) {
  const open = document.createElement("a");

  open.className = "open";
  open.href = getUrl();
  open.target = "_blank";
  open.rel = "noopener";
  open.textContent = "Abrir URL";

  return open;
}

/* Botón Copiar URL */

function createCopyButton(getUrl) {
  const copy = document.createElement("button");

  copy.className = "copy";
  copy.type = "button";
  copy.textContent = "Copiar URL";

  copy.addEventListener("click", async () => {
    const url = getUrl();

    try {
      await navigator.clipboard.writeText(url);
    } catch {
      window.prompt("Copia esta URL:", url);
    }

    copy.textContent = "Copiado";

    setTimeout(() => {
      copy.textContent = "Copiar URL";
    }, 1500);
  });

  return copy;
}

/* Botón Chrome Kiosk */

function createKioskButton(folder, getUrl, getFile) {
  const kiosk = document.createElement("button");

  kiosk.className = "kiosk";
  kiosk.type = "button";
  kiosk.textContent = "Chrome Kiosk";
  kiosk.title = "Descargar el acceso de Chrome a pantalla completa";

  kiosk.addEventListener("click", () => {
    downloadKioskBat(
      folder,
      getFile ? getFile() : null,
      getUrl()
    );

    kiosk.textContent = "BAT descargado";

    setTimeout(() => {
      kiosk.textContent = "Chrome Kiosk";
    }, 1800);
  });

  return kiosk;
}

/* Crear el título de cada bloque */

function createModeSection(className, headingText, descriptionText) {
  const section = document.createElement("section");
  section.className = "mode-section " + className;

  const heading = document.createElement("h3");
  heading.className = "mode-heading";
  heading.textContent = headingText;

  const description = document.createElement("p");
  description.className = "mode-description";
  description.textContent = descriptionText;

  section.append(heading, description);

  return section;
}

/* Construir tarjeta */

function createCard(group) {
  const card = document.createElement("section");
  card.className = "card";

  const title = document.createElement("h2");
  title.textContent = group.name;

  const description = document.createElement("p");
  description.className = "card-description";
  description.textContent =
    group.files.length + " archivo(s) disponible(s)";

  card.append(title, description);

  // MODO SELECTIVO

  const selectiveSection = createModeSection(
    "selective-mode",
    "Modo selectivo",
    "Elige el archivo que quieres mostrar en la pantalla."
  );

  const label = document.createElement("label");
  label.textContent = "Archivo que se mostrará";

  const select = document.createElement("select");
  select.setAttribute(
    "aria-label",
    "Archivo de " + group.name
  );

  group.files.forEach(file => {
    const option = document.createElement("option");
    option.value = file;
    option.textContent = file;
    select.appendChild(option);
  });

  const selectiveActions = document.createElement("div");
  selectiveActions.className = "actions";

  const getSelectedUrl = () =>
    getSelectiveUrl(group.name, select.value);

  const selectiveOpen = createOpenButton(getSelectedUrl);
  const selectiveCopy = createCopyButton(getSelectedUrl);

  const selectiveKiosk = createKioskButton(
    group.name,
    getSelectedUrl,
    () => select.value
  );

  select.addEventListener("change", () => {
    selectiveOpen.href = getSelectedUrl();
  });

  selectiveActions.append(
    selectiveOpen,
    selectiveCopy,
    selectiveKiosk
  );

  selectiveSection.append(
    label,
    select,
    selectiveActions
  );

  card.appendChild(selectiveSection);

  // MODO AUTO

  const autoSection = createModeSection(
    "auto-mode",
    "Modo AUTO",
    "Muestra automáticamente el archivo contenido.* de esta carpeta."
  );

  const matches = group.files.filter(file => {
    const match = /^contenido\.([a-zA-Z0-9]+)$/i.exec(file);

    return match &&
      supportedExtensions.includes(match[1].toLowerCase());
  });

  if (matches.length === 1) {
    const contentFile = matches[0];

    const autoInfo = document.createElement("p");
    autoInfo.className = "mode-description";
    autoInfo.textContent = "Archivo detectado: " + contentFile;

    const autoActions = document.createElement("div");
    autoActions.className = "actions";

    const getAutomaticUrl = () => getAutoUrl(group.name);

    const autoOpen = createOpenButton(getAutomaticUrl);
    const autoCopy = createCopyButton(getAutomaticUrl);

    const autoKiosk = createKioskButton(
      group.name,
      getAutomaticUrl,
      () => contentFile
    );

    autoActions.append(
      autoOpen,
      autoCopy,
      autoKiosk
    );

    autoSection.append(autoInfo, autoActions);

  } else {
    const warning = document.createElement("div");
    warning.className = "auto-warning";

    if (matches.length === 0) {
      warning.textContent =
        "No hay un archivo válido para el modo AUTO. " +
        "Añade un único archivo llamado contenido.pdf, " +
        "contenido.jpg, contenido.mp4, etc.";
    } else {
      warning.textContent =
        "Se han encontrado varios archivos válidos para AUTO. " +
        "Deja solo uno con el nombre contenido y su extensión.";
    }

    autoSection.appendChild(warning);
  }

  card.appendChild(autoSection);

  return card;
}

/* Cargar carpetas y archivos */

async function loadScreens() {
  refreshButton.disabled = true;
  statusText.textContent = "Actualizando listado...";

  try {
    const response = await fetch(
      "/api/contenido.php?t=" + Date.now(),
      { cache: "no-store" }
    );

    if (!response.ok) {
      throw new Error(
        "El servidor respondió con HTTP " + response.status
      );
    }

    const groups = await response.json();

    if (!Array.isArray(groups)) {
      throw new Error(
        groups.error || "Respuesta no válida del servidor"
      );
    }

    container.replaceChildren();

    const validGroups = groups.filter(group =>
      group &&
      typeof group.name === "string" &&
      Array.isArray(group.files)
    );

    if (validGroups.length === 0) {
      const empty = document.createElement("div");
      empty.className = "empty";
      empty.textContent =
        "No hay carpetas con archivos disponibles.";

      container.appendChild(empty);
    } else {
      validGroups.forEach(group => {
        container.appendChild(createCard(group));
      });
    }

    statusText.textContent =
      validGroups.length +
      " pantalla(s) detectada(s) · Listado actualizado";

  } catch (error) {
    console.error("Error cargando el catálogo:", error);

    container.replaceChildren();

    const message = document.createElement("div");
    message.className = "empty";
    message.textContent =
      "No se ha podido cargar el listado. " +
      "Comprueba el endpoint PHP y vuelve a intentarlo.";

    container.appendChild(message);
    statusText.textContent = "Error al cargar las carpetas";

  } finally {
    refreshButton.disabled = false;
  }
}

refreshButton.addEventListener("click", loadScreens);

loadScreens();
</script>

</body>
</html>
```

### 19.2 Visor: `/var/www/signage/visor/index.html`

El visor admite PDF, JPG, JPEG, PNG, WEBP, MP4 y WEBM. En modo AUTO consulta `/api/contenido.php` y busca un único archivo `contenido.*`. Para PDF utiliza PDF.js y contiene la compatibilidad con `Map.prototype.getOrInsertComputed` necesaria para Chrome 130.

```html
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SIGNAGE</title>
<style>
html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: #000;
    overflow: hidden;
}
#viewer {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
}
canvas, img, video {
    display: block;
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
}
#error {
    color: white;
    font: 20px Arial, sans-serif;
    text-align: center;
    padding: 24px;
    overflow-wrap: anywhere;
    max-width: 90%;
}
</style>
</head>
<body>
<div id="viewer"></div>

<!-- Compatibilidad con Chrome 130 -->
<script>
if (!Map.prototype.getOrInsertComputed) {
    Map.prototype.getOrInsertComputed = function(key, callback) {
        if (this.has(key)) {
            return this.get(key);
        }
        const value = callback(key);
        this.set(key, value);
        return value;
    };
}
</script>

<script type="module">
import * as pdfjsLib from "/build/pdf.js";
pdfjsLib.GlobalWorkerOptions.workerSrc = "/build/pdf.worker.js";

const viewer = document.getElementById("viewer");
const params = new URLSearchParams(location.search);
const folder = params.get("carpeta");
let file = params.get("file");
const autoMode = params.get("auto") === "1";

const validName = /^[a-zA-Z0-9 _.-]+$/;
const allowed = ["pdf", "jpg", "jpeg", "png", "webp", "mp4", "webm"];
let refreshTimer = null;
let lastContent = null;

function showError(message) {
    const error = document.createElement("div");
    error.id = "error";
    error.textContent = message;
    viewer.replaceChildren(error);
}

function getContentUrl() {
    return "/" + encodeURIComponent(folder) + "/" +
        encodeURIComponent(file) + "?t=" + Date.now();
}

// Busca el archivo contenido.* en el catálogo del servidor.
async function findAutomaticContent() {
    const response = await fetch(
        "/api/contenido.php?t=" + Date.now(),
        { cache: "no-store" }
    );
    if (!response.ok) {
        throw new Error(
            "No se ha podido consultar el catálogo: HTTP " + response.status
        );
    }
    const groups = await response.json();
    if (!Array.isArray(groups)) {
        throw new Error("La respuesta del catálogo no es válida.");
    }
    const group = groups.find(item => item.name === folder);
    if (!group || !Array.isArray(group.files)) {
        throw new Error("No se encuentra la carpeta " + folder);
    }
    const matches = group.files.filter(name =>
        /^contenido\.(pdf|jpg|jpeg|png|webp|mp4|webm)$/i.test(name)
    );
    if (matches.length === 0) {
        throw new Error(
            "No hay ningún archivo contenido compatible en " + folder
        );
    }
    if (matches.length > 1) {
        throw new Error(
            "La carpeta contiene varios archivos contenido.*. " +
            "Deja solamente uno."
        );
    }
    return matches[0];
}

async function loadPDF(url) {
    const loadingTask = pdfjsLib.getDocument({ url });
    const pdf = await loadingTask.promise;
    const page = await pdf.getPage(1);
    const viewport = page.getViewport({ scale: 1 });
    const scale = Math.min(
        window.innerWidth / viewport.width,
        window.innerHeight / viewport.height
    );
    const scaled = page.getViewport({ scale });
    const canvas = document.createElement("canvas");
    canvas.width = Math.floor(scaled.width);
    canvas.height = Math.floor(scaled.height);
    viewer.replaceChildren(canvas);
    await page.render({
        canvasContext: canvas.getContext("2d"),
        viewport: scaled
    }).promise;
}

function loadImage(url) {
    return new Promise((resolve, reject) => {
        const img = document.createElement("img");
        img.alt = "Contenido SIGNAGE";
        img.onload = () => {
            viewer.replaceChildren(img);
            resolve();
        };
        img.onerror = () => {
            reject(new Error("No se ha podido cargar la imagen."));
        };
        img.src = url;
    });
}

function loadVideo(url) {
    return new Promise((resolve, reject) => {
        const video = document.createElement("video");
        video.src = url;
        video.autoplay = true;
        video.muted = true;
        video.loop = true;
        video.playsInline = true;
        video.oncanplay = () => resolve();
        video.onerror = () => {
            reject(new Error("No se ha podido cargar el vídeo."));
        };
        viewer.replaceChildren(video);
        video.play().catch(() => {});
    });
}

async function loadContent() {
    if (
        !folder ||
        !validName.test(folder) ||
        folder === "." ||
        folder === ".."
    ) {
        showError("La carpeta indicada no es válida.");
        return;
    }
    try {
        // En modo AUTO, descubrir el archivo en cada actualización.
        if (autoMode) {
            file = await findAutomaticContent();
        } else if (
            !file ||
            !validName.test(file) ||
            file === "." ||
            file === ".."
        ) {
            showError("La carpeta o el archivo indicado no es válido.");
            return;
        }
        const extension = file.split(".").pop().toLowerCase();
        if (!allowed.includes(extension)) {
            throw new Error("Tipo de archivo no permitido.");
        }
        // Evita volver a renderizar si el archivo no ha cambiado.
        const contentKey = folder + "/" + file;
        if (contentKey === lastContent) {
            return;
        }
        const url = getContentUrl();
        const response = await fetch(url, {
            method: "HEAD",
            cache: "no-store"
        });
        if (!response.ok) {
            throw new Error("El archivo devuelve HTTP " + response.status);
        }
        if (extension === "pdf") {
            await loadPDF(url);
        } else if (["jpg", "jpeg", "png", "webp"].includes(extension)) {
            await loadImage(url);
        } else {
            await loadVideo(url);
        }
        lastContent = contentKey;
    } catch (error) {
        console.error("Error cargando contenido:", error);
        // Si falla una actualización, conservar el contenido anterior
        // siempre que ya se esté mostrando algo.
        if (lastContent === null || viewer.childElementCount === 0) {
            showError(
                "Error cargando el contenido: " +
                (error.message || String(error))
            );
        }
    }
}

loadContent();

// Comprobar cada cinco minutos si ha cambiado el contenido.
refreshTimer = setInterval(loadContent, 5 * 60 * 1000);
</script>
</body>
</html>
```

### 19.3 Dependencias y observaciones del código

- El catálogo y el visor consultan la API `/api/contenido.php`.
- El visor importa `/build/pdf.js` y utiliza `/build/pdf.worker.js`; conserva también los recursos auxiliares de PDF.js que formen parte de la instalación.
- El contenido se sirve desde las carpetas de `/srv/signage-content/` mediante la configuración de Apache.
- El visor vuelve a comprobar el contenido cada cinco minutos. En el código actual, si el nombre del archivo no cambia, `lastContent` evita volver a renderizarlo. Por tanto, sustituir un archivo por otro con el mismo nombre no garantiza que se vuelva a mostrar durante esa sesión.
- El código PHP de la API no se ha incluido en este anexo porque en esta entrega se han facilitado el catálogo y el visor, pero no el contenido actual de `api/contenido.php`. Para una restauración completa, conserva también ese archivo funcional.

