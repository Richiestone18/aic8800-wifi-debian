# WiFi AIC8800 en Debian 13 — instalador automático

Script que deja funcionando los dongles USB WiFi con chip **AIC8800DC / AIC8800DW**
en **Debian 13 (trixie)**. Un solo comando: instala el driver, el firmware, las reglas
udev y deja la tarjeta lista para conectarse.

Probado en Debian 13 con kernel 7.2.12 (liquorix-amd64) y dongle **Tenda U2 (2604:0014)**.

## ¿Por qué hace falta un script?

Estos dongles (son baratos y muy comunes: Tenda, Mercusys, UGREEN, TP-Link, Hikvision)
tienen dos problemas clásicos en Linux:

1. **Llegan en "modo USB de almacenamiento".** Se presentan como un pendrive de ~3.7 MB
   con un `Setup.exe` para Windows (`lsusb` los muestra como `a69c:5721 aicsemi Aic MSC`).
   Hay que pasar la tarjeta a modo WiFi.
2. **No tienen driver en el kernel de Debian.** No existe en el kernel hasta la versión 7.x,
   así que hay que compilar el driver con DKMS.

Mientras eso no está resuelto, `nmcli radio` dice `WIFI-HW missing` y no aparece
ninguna interfaz `wlan`.

## Dongles compatibles

| ID USB (modo WiFi) | Equipo | Chip |
| --- | --- | --- |
| `2604:0014` | Tenda U2 | 8800DC |
| `2604:0013` | Tenda W311MI v6.0 | 8800DC |
| `2c4e:0114` / `2c4e:0126` | Mercusys MA14N | 8800DC |
| `2357:0147` | TP-Link Archer TX1U Nano | 8800DW |
| `3625:0110` | TP-Link AX300 | 8800DC |
| `a69c:88dc` / `a69c:88dd` / `a69c:88de` | Referencia AIC | 8800DC / DW |
| `368b:88e0`–`368b:88e5` | Hikvision / H3C / UGREEN AX300 | 8800DC |

Si tu dongle aparece con otro ID, abre un issue con la salida de `lsusb`.

## Requisitos

- Debian 13 (trixie), arquitectura x86_64 o arm64.
- Conexión a internet (por cable o desde otra máquina) para descargar el driver.
- Permisos de `sudo`.
- **Secure Boot desactivado.** Si lo tienes activo, el módulo del kernel no cargará
  (ver *Problemas*).

## Instalación

```bash
git clone https://github.com/Richiestone18/aic8800-wifi-debian.git
cd aic8800-wifi-debian
sudo ./install-aic8800-wifi.sh
```

El script hace todo esto:

1. Revisa que el dongle esté conectado y detecta en qué modo está.
2. Instala dependencias: `dkms`, `build-essential`, `eject`, `usb-modeswitch`,
   `git` y las cabeceras (`linux-headers`) de tu kernel.
3. Descarga y compila el driver con DKMS (tarda 1–3 minutos).
4. Pasa el dongle de modo almacenamiento a modo WiFi si hace falta.
5. Carga los módulos, espera la interfaz y te muestra las redes disponibles.

Al terminar aparecerá la interfaz como `wlx<MAC>` (por ejemplo `wlx500ff582688c`).

## Conectarse a tu red

```bash
sudo nmtui
```

o directamente:

```bash
sudo nmcli device wifi connect "NOMBRE_DE_TU_RED" --ask
```

El icono de red del escritorio (MATE, GNOME, XFCE) también lista la interfaz nueva,
a veces hay que reiniciar el applet o volver a entrar a la sesión.

## Opciones

```bash
sudo ./install-aic8800-wifi.sh --check       # solo diagnóstico, no cambia nada
sudo ./install-aic8800-wifi.sh --uninstall   # quita driver, firmware y reglas udev
sudo ./install-aic8800-wifi.sh --yes         # instalar sin preguntar
sudo ./install-aic8800-wifi.sh --help
```

Ejemplo de `--check` en un equipo ya funcionando:

```
  Kernel:          7.2.12-1-liquorix-amd64
  Distribución:    Debian GNU/Linux 13
  Dongle USB:      presente en modo WiFi
  Driver:          instalado
  Firmware:        instalado
  DKMS:            aic8800dc/6.4.3.0-patched.17, 7.2.12-1-liquorix-amd64, x86_64: installed
  Interfaz:        wlx500ff582688c
  NetworkManager:  100 (connected)
  Conexión:        Richiestone Wireless
```

## Actualizaciones de kernel

DKMS reconstruye el módulo automáticamente cada vez que se actualiza el kernel.
Si alguna vez no compila tras una actualización, entra al repo del driver y ejecuta:

```bash
cd /usr/src/aic8800dc-*/ && sudo make clean && sudo dkms build -m aic8800dc -v 6.4.3.0-patched.17 -k $(uname -r)
```

o vuelve a correr este instalador.

## Problemas frecuentes

**No aparece la interfaz / `lsusb` sigue mostrando `a69c:5721`.**
El dongle quedó en modo almacenamiento. Vuelve a correr el instalador o hazlo a mano:

```bash
sudo usb_modeswitch -v a69c -p 5721 -K
```

Si tras enchufarlo vuelve a modo almacenamiento, es que la regla udev no se aplicó:
`sudo udevadm control --reload && sudo udevadm trigger`.

**Secure Boot activo.**
El módulo va firmado con una clave MOK autogenerada. Si Secure Boot está activo hay que
enrolarla (`sudo mokutil --import /var/lib/dkms/mok.pub` y confirmar en el reinicio) o
desactivar Secure Boot en la BIOS.

**El driver no compila.**
Casi siempre es que faltan las cabeceras del kernel en uso. Comprueba que exista
`/lib/modules/$(uname -r)/build`; si no, instala `linux-headers-amd64` o
`linux-headers-$(uname -r)`.

**Funciona el WiFi pero no hay internet.**
Revisa rutas y DNS: `ip route`, `nmcli device show wlx...`. Un perfil guardado de un
dongle anterior puede estar amarrado al nombre de la interfaz vieja; se arregla con:

```bash
sudo nmcli connection modify "TU_RED" connection.interface-name ""
```

**Aviso `USING PERMISSIVE CUSTOM REGULATORY RULES` en dmesg.**
Es normal en este driver (no aplica restricciones regulatorias por país).

## Créditos y licencia

- Script de instalación: **Richiestone Computer** — licencia MIT (ver `LICENSE`).
- Driver y firmware: [Kiborgik/aic8800dc-linux-patched](https://github.com/Kiborgik/aic8800dc-linux-patched),
  basado en el driver upstream 6.4.3.0 de AICSemi. Este repositorio **no** incluye el
  driver; el script lo descarga desde su fuente original y respeta su licencia.
