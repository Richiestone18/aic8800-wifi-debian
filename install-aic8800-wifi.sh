#!/usr/bin/env bash
#
# install-aic8800-wifi.sh
# Instala el driver del dongle USB WiFi AIC8800DC / AIC8800DW en Debian 13 (trixie).
#
# Dongles compatibles (entre otros): Tenda U2 (2604:0014), Tenda W311MI v6,
# Mercusys MA14N, UGREEN AX300, TP-Link Archer TX1U Nano, Hikvision.
# Todos llegan en "modo USB de almacenamiento" (a69c:5721 y familia) y no
# tienen driver en el kernel de Debian: este script hace las dos cosas.
#
# Uso:
#   sudo ./install-aic8800-wifi.sh            # instalar
#   sudo ./install-aic8800-wifi.sh --check    # solo diagnosticar
#   sudo ./install-aic8800-wifi.sh --uninstall
#   sudo ./install-aic8800-wifi.sh --yes      # sin preguntas
#
# Autor: Richiestone Computer  ·  Licencia: MIT
#
set -euo pipefail

VERSION="1.0.0"
DRIVER_REPO="https://github.com/Kiborgik/aic8800dc-linux-patched.git"
DRIVER_NAME="aic8800dc"

MSC_IDS='a69c:(5720|5721|5722|5723|5724|5725|5726|5727|572a|572c|572f)'
WIFI_IDS='(2604:0013|2604:0014|a69c:88dc|a69c:88dd|a69c:88de|368b:88de|368b:88df|368b:88e0|368b:88e1|368b:88e2|368b:88e3|368b:88e5|2357:0147|2c4e:0114|2c4e:0126|3625:0110|a69c:8801)'

ASSUME_YES=0
MODE="install"

# ---------- utilidades ----------
c_ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

need_root() {
    [ "$(id -u)" -eq 0 ] || die "Ejecuta este script como root:  sudo $0 $*"
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local r
    read -r -p "$1 [s/N] " r
    case "$r" in s|S|si|SI|sí|Sí) return 0 ;; *) return 1 ;; esac
}

# Interfaz inalámbrica creada por el driver (udev la renombra a wlx<MAC>)
wifi_iface() {
    local i
    for i in /sys/class/net/*; do
        i=$(basename "$i")
        case "$i" in
            wl*|wlan*) printf '%s\n' "$i"; return 0 ;;
        esac
    done
    return 1
}

# Estado del dongle: msc | wifi | ausente
dongle_state() {
    if lsusb 2>/dev/null | grep -Eqi "$MSC_IDS"; then echo msc
    elif lsusb 2>/dev/null | grep -Eqi "$WIFI_IDS"; then echo wifi
    else echo ausente
    fi
}

# ---------- diagnóstico ----------
do_check() {
    c_info "Diagnóstico AIC8800 — $(date '+%Y-%m-%d %H:%M')"
    echo
    printf '  Kernel:          %s\n' "$(uname -r)"

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '  Distribución:    %s %s\n' "${NAME:-?}" "${VERSION_ID:-?}"
    fi

    local st
    st=$(dongle_state)
    case "$st" in
        msc)  printf '  Dongle USB:      presente en MODO ALMACENAMIENTO (a69c:57xx)\n' ;;
        wifi) printf '  Dongle USB:      presente en modo WiFi\n' ;;
        *)    printf '  Dongle USB:      NO detectado (¿está enchufado?)\n' ;;
    esac

    if find /lib/modules/"$(uname -r)" -iname '*aic8800*' -print -quit 2>/dev/null | grep -q .; then
        printf '  Driver:          instalado\n'
    else
        printf '  Driver:          no instalado\n'
    fi

    if [ -d /lib/firmware/aic8800DC ]; then
        printf '  Firmware:        instalado\n'
    else
        printf '  Firmware:        no instalado\n'
    fi

    if command -v dkms >/dev/null 2>&1 || [ -x /usr/sbin/dkms ]; then
        local ds
        ds=$(/usr/sbin/dkms status -m "$DRIVER_NAME" 2>/dev/null || true)
        printf '  DKMS:            %s\n' "${ds:-sin registro}"
    else
        printf '  DKMS:            no instalado\n'
    fi

    local ifc
    if ifc=$(wifi_iface); then
        printf '  Interfaz:        %s\n' "$ifc"
        if command -v nmcli >/dev/null 2>&1; then
            printf '  NetworkManager:  %s\n' "$(nmcli -t -f GENERAL.STATE device show "$ifc" 2>/dev/null | cut -d: -f2-)"
            printf '  Conexión:        %s\n' "$(nmcli -t -f GENERAL.CONNECTION device show "$ifc" 2>/dev/null | cut -d: -f2-)"
        fi
    else
        printf '  Interfaz:        ninguna wlan/wlx\n'
    fi
    echo

    if [ "$st" = "ausente" ]; then
        c_err "No hay dongle AIC8800 conectado. Enchúfalo y repite."
        return 1
    fi
    if [ "$st" = "wifi" ] && wifi_iface >/dev/null; then
        c_ok "El adaptador WiFi funciona. Conéctate con:  sudo nmtui"
        return 0
    fi
    c_warn "Falta instalar el driver o pasar el dongle a modo WiFi."
    return 1
}

# ---------- dependencias ----------
ensure_deps() {
    c_info "Comprobando dependencias del sistema..."
    local pkgs=(dkms build-essential eject usb-modeswitch curl)
    local missing=()
    local p

    for p in "${pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done

    # Cabeceras del kernel en ejecución
    if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        if apt-cache show "linux-headers-$(uname -r)" >/dev/null 2>&1; then
            missing+=("linux-headers-$(uname -r)")
        else
            missing+=(linux-headers-amd64)
        fi
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        c_ok "Dependencias completas."
        return 0
    fi

    c_info "Instalando: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    c_ok "Dependencias instaladas."
}

# ---------- descarga del driver ----------
# Descarga el código del driver sin necesidad de git (curl o wget + tar).
# Imprime en stdout la ruta del directorio descargado.
download_driver() {
    local dest="$1"
    local url="https://api.github.com/repos/Kiborgik/aic8800dc-linux-patched/tarball/HEAD"
    local dir

    mkdir -p "$dest"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 20 -o "$dest/driver.tar.gz" "$url" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 -O "$dest/driver.tar.gz" "$url" || return 1
    else
        return 1
    fi

    tar -xzf "$dest/driver.tar.gz" -C "$dest" >/dev/null 2>&1 || return 1
    dir=$(find "$dest" -maxdepth 1 -mindepth 1 -type d | head -1)
    [ -n "$dir" ] || return 1
    printf '%s\n' "$dir"
}

# ---------- driver ----------
build_driver() {
    local workdir src
    workdir=$(mktemp -d /tmp/aic8800-build.XXXXXX)

    c_info "Descargando driver..."
    if ! src=$(download_driver "$workdir"); then
        if command -v git >/dev/null 2>&1; then
            c_warn "La descarga directa falló; lo intento con git..."
            git clone --depth 1 "$DRIVER_REPO" "$workdir/aic8800" >/dev/null 2>&1 \
                || die "No pude descargar el driver. ¿Hay conexión a internet?"
            src="$workdir/aic8800"
        else
            die "No pude descargar el driver. Revisa la conexión a internet (o instala curl o git)."
        fi
    fi

    c_info "Compilando e instalando módulos con DKMS (tarda 1-3 minutos)..."
    ( cd "$src" && bash ./install.sh ) || die "Falló la compilación del driver. Revisa el log de arriba."
    rm -rf "$workdir"

    c_ok "Driver, firmware y reglas udev instalados."
}

# ---------- pasar el dongle a modo WiFi ----------
flip_dongle() {
    if [ "$(dongle_state)" != "msc" ]; then
        return 0
    fi
    c_info "El dongle está en modo almacenamiento; lo paso a modo WiFi..."
    local ids vid pid
    ids=$(lsusb | grep -Ei "$MSC_IDS" | head -1)
    vid=$(printf '%s' "$ids" | sed -E 's/.*ID ([0-9a-f]{4}):([0-9a-f]{4}).*/\1/')
    pid=$(printf '%s' "$ids" | sed -E 's/.*ID ([0-9a-f]{4}):([0-9a-f]{4}).*/\2/')
    [ -n "${vid:-}" ] && [ -n "${pid:-}" ] || die "No pude leer el ID USB del dongle."

    usb_modeswitch -v "$vid" -p "$pid" -K >/dev/null 2>&1 || true
    sleep 4

    if [ "$(dongle_state)" = "wifi" ]; then
        c_ok "Dongle en modo WiFi."
    else
        # Algunos dongles aparecen como CD-ROM: eject también sirve
        local node
        for node in /dev/aicudisk* /dev/sr0; do
            [ -e "$node" ] && eject "$node" >/dev/null 2>&1 || true
        done
        sleep 3
        [ "$(dongle_state)" = "wifi" ] || die "No logré cambiar el dongle a modo WiFi. Desenchúfalo, vuelve a enchufarlo y repite."
        c_ok "Dongle en modo WiFi."
    fi
}

load_modules() {
    modprobe aic_load_fw 2>/dev/null || true
    modprobe aic8800_fdrv 2>/dev/null || true
    sleep 3
}

wait_iface() {
    local i ifc=""
    for i in $(seq 1 20); do
        ifc=$(wifi_iface || true)
        [ -n "$ifc" ] && break
        sleep 1
    done
    [ -n "$ifc" ] || return 1
    printf '%s\n' "$ifc"
}

# ---------- principal ----------
do_install() {
    need_root "$@"

    c_info "Instalador WiFi AIC8800 para Debian 13 — v${VERSION}"
    echo

    # Distro
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [ "${ID:-}" != "debian" ]; then
            c_warn "Esto está pensado para Debian 13; detecté '${NAME:-desconocido}'. Continúo igual."
        fi
    fi

    case "$(dongle_state)" in
        ausente)
            die "No detecto ningún dongle AIC8800. Enchúfalo en un puerto USB directo (sin hub) y vuelve a ejecutar."
            ;;
        msc)
            c_info "Dongle detectado en modo almacenamiento (a69c:57xx)."
            ;;
        wifi)
            c_info "Dongle detectado en modo WiFi."
            ;;
    esac

    ensure_deps
    build_driver
    flip_dongle
    load_modules

    local ifc
    if ! ifc=$(wait_iface); then
        c_err "El driver se instaló pero no apareció interfaz inalámbrica."
        c_err "Prueba: desenchufar el dongle, volver a enchufarlo y correr: sudo $0 --check"
        exit 1
    fi
    c_ok "Interfaz WiFi lista: ${ifc}"

    if command -v nmcli >/dev/null 2>&1; then
        c_info "Redes visibles:"
        nmcli device wifi rescan >/dev/null 2>&1 || true
        sleep 5
        nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | head -10 || true
        echo
        c_info "Para conectarte:   sudo nmtui"
        c_info "o bien:            sudo nmcli device wifi connect \"TU_RED\" --ask"
    fi

    echo
    c_ok "Instalación terminada. El driver se reconstruye solo en cada actualización de kernel (DKMS)."
    if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        c_warn "Secure Boot está ACTIVO: si el módulo no carga, enrola la clave MOK que se generó en /var/lib/dkms/mok.pub o desactiva Secure Boot."
    fi
}

do_uninstall() {
    need_root "$@"
    c_info "Desinstalando driver AIC8800..."
    local workdir src=""
    workdir=$(mktemp -d /tmp/aic8800-uninstall.XXXXXX)

    if src=$(download_driver "$workdir"); then
        ( cd "$src" && bash ./uninstall.sh ) || c_warn "El script del repositorio terminó con errores; limpio a mano."
    elif command -v git >/dev/null 2>&1 && git clone --depth 1 "$DRIVER_REPO" "$workdir/aic8800" >/dev/null 2>&1; then
        ( cd "$workdir/aic8800" && bash ./uninstall.sh ) || c_warn "El script del repositorio terminó con errores; limpio a mano."
    else
        c_warn "No pude descargar el desinstalador del repositorio; limpio a mano."
    fi

    /usr/sbin/dkms remove -m "$DRIVER_NAME" --all >/dev/null 2>&1 || true
    rm -f /etc/modules-load.d/aic8800.conf
    rm -f /etc/udev/rules.d/aic.rules
    rm -rf /lib/firmware/aic8800DC
    udevadm control --reload >/dev/null 2>&1 || true
    rm -rf "$workdir"

    c_ok "Driver desinstalado. Desenchufa y vuelve a enchufar el dongle si quieres usarlo como almacenamiento otra vez."
}

usage() {
    cat <<EOF
Instalador WiFi AIC8800 (Tenda U2, Mercusys, UGREEN AX300, TP-Link TX1U...) — Debian 13

Uso: sudo $0 [opción]

  (sin opción)   Instala el driver y deja el dongle listo
  --check        Solo diagnostica (dongle, driver, firmware, interfaz)
  --uninstall    Quita el driver, firmware y reglas udev
  --yes, -y      No pregunta nada
  -h, --help     Esta ayuda

Después de instalar:  sudo nmtui
EOF
}

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --check)     MODE="check" ;;
            --uninstall) MODE="uninstall" ;;
            --yes|-y)    ASSUME_YES=1 ;;
            -h|--help)   usage; exit 0 ;;
            *)           die "Opción desconocida: $1  (usa --help)" ;;
        esac
        shift
    done

    case "$MODE" in
        check)     do_check ;;
        uninstall) do_uninstall ;;
        install)   do_install ;;
    esac
}

main "$@"
