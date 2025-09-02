#!/bin/zsh
# Zorg dat het script met sudo/root draait
if [[ $EUID -ne 0 ]]; then
  echo "Dit script moet met sudo of als root uitgevoerd worden." >&2
  exit 1
fi

# Genereer on-demand Munki nopkg voor een Installomator label
# Gebruikt JOUW preinstall script 1:1 (alleen label vervangen)

set -euo pipefail

# ------------------ Defaults ------------------
MUNKI_REPO="/Users/Shared/munki_repo"     # munki repo root
PKGSINFO_DIR="${MUNKI_REPO}/pkgsinfo"
ICONS_DIR="${MUNKI_REPO}/icons"
CATALOGS=("testing")                       # b.v. ("testing")
MANIFEST="site_default"                    # manifest voor optional_installs
CATEGORY="Self-Service"
LANG_NL=1

# Tools
MAKECAT="/usr/local/munki/makecatalogs"
MANUTIL="/usr/local/munki/manifestutil"

log(){ print -r -- "$(date '+%Y%m%d-%H%M%S')  $*"; }
die(){ log "ERROR: $*"; exit 1; }
need_bin(){ [[ -x "$1" ]] || die "Vereiste tool niet gevonden of niet uitvoerbaar: $1"; }
cap_first(){ local s="$1"; print -r -- "${s[1]:u}${s[2,-1]}"; }



# ------------------ Installomator Icon functie (ingebed) ------------------
installomator_icon() {
  (
# Installomator → Munki icon grabber (v1.1)
# Haalt het icoon uit een app-bundle via Installomator label en zet het als 128x128 PNG in <repo>/icons/<label>.png

set -euo pipefail

# ---------- Defaults ----------
MUNKI_REPO="/Users/Shared/munki_repo"
ICONS_DIR="icons"
OUTPUT_NAME=""          # default: <label>.png
OVERWRITE=""            # ask interactively if empty
INSTALLOMATOR="/usr/local/Installomator/Installomator.sh"
LOG_FILE="/var/log/installomator-icons.log"

# ---------- Helpers ----------
ts(){ date '+%Y%m%d-%H%M%S'; }
log(){ printf "%s  %s\n" "$(ts)" "$*" | tee -a "$LOG_FILE" >&2; }
fail(){ log "ERROR: $*"; exit 1; }

usage(){
  cat <<USAGE
Gebruik:
  $0 --label <installomator_label> [--repo /pad/naar/munki_repo] [--name naam.png] [--overwrite yes|no]

Opties:
  --label        Vereist. Installomator label (zoals in Labels.txt).
  --repo         Pad naar je Munki repo (default: $MUNKI_REPO).
  --name         Bestandsnaam in icons/ (default: <label>.png).
  --overwrite    yes/no. Als niet gezet, vraagt het script bij conflict.

Voorbeeld:
  $0 --label microsoftedge --repo /Users/Shared/munki_repo
USAGE
}

# ---------- Parse args ----------
LABEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)      LABEL="${2:-}"; shift 2 ;;
    --repo)       MUNKI_REPO="${2:-}"; shift 2 ;;
    --name)       OUTPUT_NAME="${2:-}"; shift 2 ;;
    --overwrite)  OVERWRITE="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) fail "Onbekende optie: $1 (gebruik --help)" ;;
  esac
done

[[ -z "$LABEL" ]] && { usage; exit 1; }
[[ -x "$INSTALLOMATOR" ]] || fail "Installomator niet gevonden op $INSTALLOMATOR"
[[ -d "$MUNKI_REPO" ]] || fail "Munki repo niet gevonden: $MUNKI_REPO"

ICON_DIR_FULL="$MUNKI_REPO/$ICONS_DIR"
mkdir -p "$ICON_DIR_FULL"
[[ -n "$OUTPUT_NAME" ]] || OUTPUT_NAME="${LABEL}.png"
OUT_PATH="$ICON_DIR_FULL/$OUTPUT_NAME"

log "Start icoonextractie voor label: $LABEL"
log "Munki repo: $MUNKI_REPO"
log "Icons map: $ICON_DIR_FULL"
log "Doelbestand: $OUT_PATH"

# overwrite check
if [[ -f "$OUT_PATH" ]]; then
  case "$OVERWRITE" in
    yes|YES|true|1) log "Overwrite geforceerd: bestaand bestand wordt overschreven." ;;
    no|NO|false|0)  fail "Bestaat al: $OUT_PATH (gebruik --overwrite yes om te overschrijven)" ;;
    *)
      echo -n "Bestand bestaat: $OUT_PATH. Overschrijven? [y/N]: " >&2
      read -r ans
      [[ "$ans" == "y" || "$ans" == "Y" ]] || fail "Gestopt: niet overschreven."
      ;;
  esac
fi

WORKDIR="$(mktemp -d "/tmp/insticon.XXXXXX")"
cleanup(){ [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# ---------- Stap 1: Probeer download-only & cap output ----------
log "Probeer download-only met Installomator (INSTALL=0)…"
set +e
INSTALL=0 BLOCKING_PROCESS_ACTION=ignore NOTIFY=silent LOGGING=REQ REOPEN=no \
  "$INSTALLOMATOR" "$LABEL" 2>&1 | tee "$WORKDIR/inst.out"
rc=$?
set -e
[[ $rc -ne 0 ]] && log "Installomator exitcode $rc (kan prima zijn bij 'geen update')."

# ---------- NIEUW: Stap 1b – Parseer lokaal geïnstalleerde app uit output ----------
APP_PATH=""
if [[ -f "$WORKDIR/inst.out" ]]; then
  # 1) Probeer "found app at /path/App.app"
  APP_PATH="$(grep -Eo 'found app at /[^"]+\.app' "$WORKDIR/inst.out" | sed -E 's/^found app at //;q' || true)"
  # 2) Zo niet: "App(s) found: /path/App.app"
  [[ -z "$APP_PATH" ]] && APP_PATH="$(grep -Eo 'App\(s\) found: /[^"]+\.app' "$WORKDIR/inst.out" | sed -E 's/^App\(s\) found: //;q' || true)"
  # 3) Sommige labels tonen meerdere paden met komma’s — pak de eerste
  [[ -n "$APP_PATH" ]] && APP_PATH="${APP_PATH%%,*}"
fi
if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
  log "Lokale geïnstalleerde app gevonden via Installomator output: $APP_PATH"
fi

# ---------- Stap 2: Als nog geen app, zoek in /Volumes of Cache (download result) ----------
if [[ -z "$APP_PATH" ]]; then
  log "Geen lokale app uit output kunnen bepalen; zoek naar gedownloade bundles (/Volumes & Cache)…"
  APP_CANDIDATES=()
  while IFS= read -r p; do APP_CANDIDATES+=("$p"); done < <(find /Volumes -maxdepth 2 -type d -name "*.app" -prune -print 2>/dev/null | xargs -I{} stat -f "%m %N" {} 2>/dev/null | sort -rn | awk '{ $1=""; sub(/^ /,""); print }' | head -n 5)

  if [[ -d "/Library/Installomator/Cache" ]]; then
    while IFS= read -r p; do APP_CANDIDATES+=("$p"); done < <(find "/Library/Installomator/Cache" -type d -name "*.app" -print 2>/dev/null | head -n 5)
  fi

  if [[ ${#APP_CANDIDATES[@]} -gt 0 ]]; then
    log "Gevonden kandidaat .app bundles:"
    for a in "${APP_CANDIDATES[@]}"; do log "  - $a"; done
    APP_PATH="${APP_CANDIDATES[1]}"
    log "Gekozen app: $APP_PATH"
  fi
fi

# ---------- NIEUW: Stap 3 – Laatste fallback: zoek geïnstalleerde apps systemwide ----------
if [[ -z "$APP_PATH" ]]; then
  log "Zoek geïnstalleerde apps in standaard locaties (/Applications, /Applications/Utilities)…"
  FOUND_LOCAL="$(/usr/bin/mdfind -onlyin /Applications -onlyin /Applications/Utilities 'kMDItemKind == "Application"' 2>/dev/null | grep -Ei "/$(echo "$LABEL" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/./g')|/$(echo "$LABEL" | sed 's/[^a-z0-9]/./gI')" | head -n 1 || true)"
  if [[ -n "$FOUND_LOCAL" && -d "$FOUND_LOCAL" ]]; then
    APP_PATH="$FOUND_LOCAL"
    log "Heuristisch geïnstalleerde app gevonden: $APP_PATH"
  fi
fi

[[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "Geen app-bundle gevonden (noch lokaal, noch uit download/cache) voor label ‘$LABEL’."

# ---------- Extract .icns ----------
RES="$APP_PATH/Contents/Resources"
[[ -d "$RES" ]] || fail "Resources map niet gevonden: $RES"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
ICNS_CANDIDATE=""
if [[ -f "$INFO_PLIST" ]]; then
  ICON_BASENAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ -n "${ICON_BASENAME:-}" ]]; then
    [[ "$ICON_BASENAME" == *.icns ]] || ICON_BASENAME="${ICON_BASENAME}.icns"
    [[ -f "$RES/$ICON_BASENAME" ]] && ICNS_CANDIDATE="$RES/$ICON_BASENAME" && log "CFBundleIconFile gevonden: $ICNS_CANDIDATE"
  fi
fi
if [[ -z "$ICNS_CANDIDATE" ]]; then
  ICNS_CANDIDATE="$(find "$RES" -maxdepth 1 -type f -name "*.icns" -print0 2>/dev/null | xargs -0 stat -f "%z %N" 2>/dev/null | sort -rn | head -n1 | awk '{ $1=""; sub(/^ /,""); print }')"
  [[ -n "$ICNS_CANDIDATE" ]] || fail "Geen .icns gevonden in $RES"
  log "Grootste .icns gekozen: $ICNS_CANDIDATE"
fi

# ---------- Convert & write ----------
TMP_PNG="$WORKDIR/icon.png"
/usr/bin/sips -s format png "$ICNS_CANDIDATE" --out "$TMP_PNG" >/dev/null 2>&1 || fail "Conversie naar PNG mislukt."
/usr/bin/sips --resampleHeightWidthMax 128 "$TMP_PNG" --out "$TMP_PNG" >/dev/null 2>&1 || fail "Resample naar 128px mislukt."
/bin/mv -f "$TMP_PNG" "$OUT_PATH" || fail "Kon $OUT_PATH niet schrijven."
log "Icoon geplaatst: $OUT_PATH"
log "Klaar. Voeg indien gewenst 'icon_name: $(basename "$OUT_PATH")' toe aan je pkginfo."
exit 0
  )
  return $?
}
# -------------------------------------------------------------------------


# ------------------ Checks ------------------
[[ -d "$MUNKI_REPO" ]] || die "Munki repo niet gevonden: $MUNKI_REPO"
mkdir -p "$PKGSINFO_DIR" "$ICONS_DIR"
need_bin "$MAKECAT"
need_bin "$MANUTIL"

# Repo owner/group (voor correcte rechten achteraf)
DIR_OWNER="$(/usr/bin/stat -f '%Su' "$PKGSINFO_DIR")"
DIR_GROUP="$(/usr/bin/stat -f '%Sg' "$PKGSINFO_DIR")"

# ------------------ Input ------------------
read -r "?Welk Installomator label wil je on-demand maken? " LABEL
[[ -n "$LABEL" ]] || die "Geen label opgegeven."
DEFAULT_DISPLAY="$(cap_first "$LABEL")"
read -r "?Display name (enter = '${DEFAULT_DISPLAY}'): " DISPLAY_NAME
DISPLAY_NAME="${DISPLAY_NAME:-$DEFAULT_DISPLAY}"
log "Catalogs: ${(j:, :)CATALOGS}"

# Bestands-/itemnamen
FILE_BASENAME="${LABEL}-installomator"    # bv. asana-installomator
ITEM_NAME="${FILE_BASENAME}"               # name in pkginfo
PKGINFO_PATH="${PKGSINFO_DIR}/${FILE_BASENAME}.plist"
ICON_NAME="${LABEL}.png"
ICON_PATH="${ICONS_DIR}/${ICON_NAME}"
VERSION_STR="$("/bin/date" '+%Y.%m.%d.%H%M')"

# ------------------ JOUW preinstall (1:1, enkel label) ------------------
# Let op: GEEN leading/trailing whitespace. Trailing newline wordt weggesneden.
PREINSTALL="$(cat <<'EOS'
#!/bin/zsh
set -euo pipefail
log(){ print -r -- "$(date '+%Y%m%d-%H%M%S')  $*"; }

INSTALLPATH="/usr/local/Installomator/Installomator.sh"
PKG_URL="https://github.com/Installomator/Installomator/releases/latest/download/Installomator.pkg"
PKG_TMP="/tmp/Installomator.pkg"

# Check if Installomator is installed
if [[ ! -x "$INSTALLPATH" ]]; then
  log "Installomator niet gevonden. Download & installatie starten..."
  /usr/bin/curl -L -o "$PKG_TMP" "$PKG_URL" || { log "Download mislukt"; exit 1; }
  /usr/sbin/installer -pkg "$PKG_TMP" -target / || { log "Installatie mislukt"; exit 1; }
  /bin/rm -f "$PKG_TMP"
  log "Installomator geïnstalleerd."
else
  log "Installomator aanwezig."
fi

# Run Installomator
"$INSTALLPATH" __LABEL__ BLOCKING_PROCESS_ACTION=quit NOTIFY=silent LOGGING=REQ REOPEN=no
exit $?
EOS
)"
# Label invullen
PREINSTALL="${PREINSTALL//__LABEL__/$LABEL}"
# Trailing newline verwijderen indien aanwezig (belangrijk voor exact einde)
PREINSTALL="${PREINSTALL%$'\n'}"

# ------------------ Plist bouwen (zonder preinstall_script) ------------------
TMP_PLIST="$(/usr/bin/mktemp /tmp/${FILE_BASENAME}.XXXXXX.plist)"

if [[ "$LANG_NL" -eq 1 ]]; then
  DESCRIPTION="Voert Installomator-label '${LABEL}' uit wanneer je op Installeren klikt. On-demand zonder extra detectie."
else
  DESCRIPTION="Runs Installomator label '${LABEL}' when you click Install. On-demand without extra detection."
fi

CATALOGS_XML=""
for c in "${CATALOGS[@]}"; do
  CATALOGS_XML="${CATALOGS_XML}<string>${c}</string>"
done

# Belangrijk: GEEN unattended_* keys, en preinstall_script pas hierna met plutil zetten.
cat > "$TMP_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key><string>${ITEM_NAME}</string>
  <key>display_name</key><string>${DISPLAY_NAME}</string>
  <key>description</key><string>${DESCRIPTION}</string>
  <key>installer_type</key><string>nopkg</string>
  <key>OnDemand</key><true/>
  <key>version</key><string>${VERSION_STR}</string>
  <key>category</key><string>${CATEGORY}</string>
  <key>catalogs</key>
  <array>${CATALOGS_XML}</array>
</dict>
</plist>
EOF

# Nu de preinstall_script exact, zonder leading/trailing spaces/newlines via plutil:
# Dit zorgt ervoor dat de string letterlijk met '#!/bin/zsh' begint.
#/usr/bin/plutil -replace preinstall_script -string "$PREINSTALL" "$TMP_PLIST"
# Gebruik -replace (bestaat al of niet), en dan verplaatsen naar eindpad met correcte perms
/usr/bin/plutil -replace preinstall_script -string "$PREINSTALL" "$TMP_PLIST" >/dev/null

/usr/bin/plutil -lint "$TMP_PLIST" >/dev/null
/bin/mv -f "$TMP_PLIST" "$PKGINFO_PATH"
/usr/sbin/chown "$DIR_OWNER:$DIR_GROUP" "$PKGINFO_PATH"
/bin/chmod 0644 "$PKGINFO_PATH"
log "Pkginfo geschreven: $PKGINFO_PATH"

# ------------------ Icoon genereren ------------------
# Gebruik de ingebedde functie i.p.v. extern script
log "Probeer icoon te extraheren via ingebedde functie…"
if installomator_icon --label "$LABEL" --repo "$MUNKI_REPO"; then
  log "Icoon OK: ${ICON_PATH}"
  /usr/sbin/chown "$DIR_OWNER:$DIR_GROUP" "$ICON_PATH" 2>/dev/null || true
  /bin/chmod 0644 "$ICON_PATH" 2>/dev/null || true
  /usr/bin/plutil -insert icon_name -string "${ICON_NAME}" "$PKGINFO_PATH" 2>/dev/null || \
    /usr/usr/bin/plutil -replace icon_name -string "${ICON_NAME}" "$PKGINFO_PATH"
else
  log "Kon icoon niet genereren (ga verder zonder)."
fi

# ------------------ Manifest aanpassen ------------------

log "Voeg toe aan manifest '${MANIFEST}' als optional_install…"
if ! "$MANUTIL" add-pkg "$ITEM_NAME" --manifest "$MANIFEST" --section optional_installs; then
  log "Kon niet toevoegen aan manifest (bestaat manifest wel?). Ga verder."
fi

# ------------------ Catalogs bouwen ------------------
log "Run makecatalogs…"
"$MAKECAT" "$MUNKI_REPO"

log "KLAAR 🎉  Item: $ITEM_NAME"
[[ -f "$ICON_PATH" ]] && log "Icon : $ICON_PATH"
