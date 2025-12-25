#!/usr/bin/env bash
set -euo pipefail

# Keep output/text as close as possible to your .bat

# =========================
# Paths (relative to script)
# =========================
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/"
LISTS="${ROOT}remove_list"
SERVERPACK="${ROOT}serverpacks"
CLIENT_PACK="${ROOT}client_pack"
MAP_FILE="${ROOT}config/modpack_map.txt"

echo
echo "================================"
echo "  Serverpack Builder - Beyond"
echo "================================"
echo "  by Catversal "
echo
echo "Press ENTER to start."
echo
read -r _
echo
echo "Loading ..."
echo

# =========================
# Check client_pack content
# =========================
if [[ -d "${CLIENT_PACK}/mods" ]]; then
  :
else
  echo
  echo "===================================================="
  echo " Your client pack folder is empty."
  echo "===================================================="
  echo
  echo "Please copy the CONTENT of the Beyond modpack into this folder:"
  echo
  echo "  ${CLIENT_PACK}"
  echo
  echo "Instructions:"
  echo
  echo "1. Open CurseForge"
  echo "2. Select the downloaded modpack"
  echo "3. Click the three dots next to the Play button"
  echo "4. Click \"Open Folder\""
  echo "5. Copy the CONTENT of this folder into the client_pack directory"
  echo
  echo "IMPORTANT:"
  echo "- Copy ONLY the contents mods, config, kubejs, ..."
  echo "- Do NOT copy the parent folder itself"
  echo
  echo "Press ENTER once you have finished copying the files."
  echo
  read -r _
fi

# =========================
# Read name from manifest.json
# =========================
MANIFEST_JSON="${CLIENT_PACK}/manifest.json"
if [[ ! -f "$MANIFEST_JSON" ]]; then
  echo
  echo "[ERROR] manifest.json not found:"
  echo "  $MANIFEST_JSON"
  exit 1
fi



if command -v jq >/dev/null 2>&1; then
  MANIFEST_NAME="$(jq -r '.name // empty' "$MANIFEST_JSON")"
else
  # python fallback
  MANIFEST_NAME="$(python3 - <<'PY'
import json,sys
p=sys.argv[1]
with open(p,'r',encoding='utf-8') as f:
    m=json.load(f)
print(m.get("name",""))
PY
"$MANIFEST_JSON")"
fi

echo
echo "[INFO] Modpack name from manifest.json:"
echo "  \"${MANIFEST_NAME}\""
echo




# =========================
# Read version from manifest.json
# =========================

if command -v jq >/dev/null 2>&1; then
  MANIFEST_VERSION="$(jq -r '.version // empty' "$MANIFEST_JSON")"
else
  # python fallback
  MANIFEST_VERSION="$(python3 - <<'PY'
import json,sys
p=sys.argv[1]
with open(p,'r',encoding='utf-8') as f:
    m=json.load(f)
print(m.get("version",""))
PY
"$MANIFEST_JSON")"
fi

echo
echo "[INFO] Modpack version from manifest.json:"
echo "  \"${MANIFEST_VERSION}\""
echo



MODPACK="0"
MODPACK_NAME=""
MCVER=""
FORGEVER=""
COPY_TACZ="0"

# =========================
# Map detection (ID|DISPLAY|MATCH|MC|FORGE|CT)
# =========================
if [[ ! -f "$MAP_FILE" ]]; then
  echo
  echo "[ERROR] Map file not found:"
  echo "  $MAP_FILE"
  exit 1
fi

# Similar behavior to your batch: last match wins
while IFS='|' read -r ID DISPLAY MATCH MC FORGE CT; do
  # skip empty/comment lines
  [[ -z "${ID// }" ]] && continue
  [[ "${ID:0:1}" == "#" ]] && continue

  # Case-insensitive substring match
  shopt -s nocasematch
  if [[ "$MANIFEST_NAME" == *"$MATCH"* ]]; then
    MODPACK="$ID"
    MODPACK_NAME="$DISPLAY"
    MCVER="$MC"
    FORGEVER="$FORGE"
    COPY_TACZ="$CT"
  fi
  shopt -u nocasematch
done < "$MAP_FILE"

echo "[INFO] Detected: \"${MODPACK_NAME}\" (ID=${MODPACK})"
echo "[INFO] mc=${MCVER} forge=${FORGEVER} copy_tacz=${COPY_TACZ}"

# =========================
# Prepare target folder
# =========================
mkdir -p "$SERVERPACK"

echo "Deleteing Files From: $SERVERPACK"
rm -rf "${SERVERPACK:?}/"*

# =========================
# Copy (XCOPY equivalent)
# =========================
copy_dir_if_exists() {
  local src="$1" dst="$2"
  if [[ -d "$src" ]]; then
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  fi
}

copy_dir_if_exists "${CLIENT_PACK}/config"          "${SERVERPACK}/config"
copy_dir_if_exists "${CLIENT_PACK}/kubejs"          "${SERVERPACK}/kubejs"
copy_dir_if_exists "${CLIENT_PACK}/defaultconfigs"  "${SERVERPACK}/defaultconfigs"
copy_dir_if_exists "${CLIENT_PACK}/mods"            "${SERVERPACK}/mods"

if [[ "$COPY_TACZ" == "1" ]]; then
  copy_dir_if_exists "${CLIENT_PACK}/tacz"         "${SERVERPACK}/tacz"
  copy_dir_if_exists "${CLIENT_PACK}/tacz_backup"  "${SERVERPACK}/tacz_backup"
fi

if [[ "$MODPACK" == "1" ]]; then
  if [[ -f "${SERVERPACK}/mods/Indestructible Server Fix-1.0.jar.disabled" ]]; then
    mv -f \
      "${SERVERPACK}/mods/Indestructible Server Fix-1.0.jar.disabled" \
      "${SERVERPACK}/mods/Indestructible Server Fix-1.0.jar"
  fi
fi

echo "[OK] Copy step finished."

# =========================
# Remove client-only mods
# =========================
REMOVE_LIST=""

if [[ "$MODPACK" == "1" ]]; then REMOVE_LIST="${LISTS}/beyond_ascension_remove.txt"; fi
if [[ "$MODPACK" == "2" ]]; then REMOVE_LIST="${LISTS}/beyond_cosmos_remove.txt"; fi
if [[ "$MODPACK" == "3" ]]; then REMOVE_LIST="${LISTS}/beyond_depth_remove.txt"; fi

if [[ ! -f "$REMOVE_LIST" ]]; then
  echo
  echo "[WARN] Remove list not found:"
  echo "  $REMOVE_LIST"
else
  if [[ ! -d "${SERVERPACK}/mods" ]]; then
    echo
    echo "[WARN] Server mods folder not found:"
    echo "  ${SERVERPACK}/mods"
  else
    echo
    echo "[INFO] Removing client-only mods using list:"
    echo "  $REMOVE_LIST"
    echo

    shopt -s nullglob
    while IFS= read -r PREFIX || [[ -n "$PREFIX" ]]; do
      PREFIX="${PREFIX%$'\r'}"
      [[ -z "${PREFIX// }" ]] && continue
      [[ "${PREFIX:0:1}" == "#" ]] && continue

      for f in "${SERVERPACK}/mods/${PREFIX}"*.jar; do
        if [[ -f "$f" ]]; then
          echo "[DEL] $(basename -- "$f")"
          rm -f -- "$f"
        fi
      done
    done < "$REMOVE_LIST"
    shopt -u nullglob
  fi
fi

echo
echo "[OK] Mod removal step finished."
echo
echo "=================================================="
echo " [INFO] Java is required to run this server"
echo "--------------------------------------------------"
echo " Please make sure you have Java 17, 18 or 21 installed."
echo
echo " Recommended for this server: Java 21"
echo
echo " You can download Java (Eclipse Temurin) here:"
echo " https://adoptium.net/de/temurin/releases"
echo "=================================================="
echo
echo "Press ENTER to continue"
echo
read -r _

# =========================
# Forge server install
# =========================
FORGE_INSTALLER="${SERVERPACK}/forge-${MCVER}-${FORGEVER}-installer.jar"
FORGE_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${MCVER}-${FORGEVER}/forge-${MCVER}-${FORGEVER}-installer.jar"

if [[ ! -f "$FORGE_INSTALLER" ]]; then
  echo
  echo "[INFO] Downloading Forge installer: ${MCVER}-${FORGEVER}"
  if command -v curl >/dev/null 2>&1; then
    curl -L --silent --show-error --fail -o "$FORGE_INSTALLER" "$FORGE_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$FORGE_INSTALLER" "$FORGE_URL"
  else
    echo "[ERROR] Neither curl nor wget found. Please install one."
    exit 1
  fi
fi

echo
echo "[INFO] Running Forge installer --installServer..."

(
  cd "$SERVERPACK"
  java -jar "$FORGE_INSTALLER" --installServer
)

echo
echo "[INFO] Writing server.properties..."

cat > "${SERVERPACK}/server.properties" <<EOF
#Minecraft server properties
#Generated by setup script
allow-flight=true
allow-nether=true
broadcast-console-to-ops=true
broadcast-rcon-to-ops=true
difficulty=normal
enable-command-block=true
enable-jmx-monitoring=false
enable-query=false
enable-rcon=false
enable-status=true
enforce-secure-profile=true
enforce-whitelist=false
entity-broadcast-range-percentage=100
force-gamemode=false
function-permission-level=2
gamemode=survival
generate-structures=true
generator-settings={}
hardcore=false
hide-online-players=false
initial-disabled-packs=
initial-enabled-packs=vanilla
level-name=world
level-seed=
level-type=minecraft\:normal
max-chained-neighbor-updates=1000000
max-players=200
max-tick-time=-1
max-world-size=29999984
motd=\u00A74\u00A7lBeyond Modpack \u00A76 | \u00A71${MODPACK_NAME}\u00A7r\n\u00A74by Blueversal  \u00A76      |\u00A71 ${MANIFEST_VERSION}
network-compression-threshold=1024
online-mode=true
op-permission-level=4
player-idle-timeout=0
prevent-proxy-connections=false
pvp=true
query.port=25565
rate-limit=0
rcon.password=
rcon.port=25575
require-resource-pack=false
resource-pack=
resource-pack-prompt=
resource-pack-sha1=
server-ip=
server-port=25565
simulation-distance=10
spawn-animals=true
spawn-monsters=true
spawn-npcs=true
spawn-protection=0
sync-chunk-writes=true
text-filtering-config=
use-native-transport=true
view-distance=20
white-list=false
EOF

echo
echo "[INFO] Patching run.sh by adding nogui"

# =========================
# Recreate run.sh with nogui
# =========================
rm -f "${SERVERPACK}/run.sh"

cat > "${SERVERPACK}/run.sh" <<EOF
#!/usr/bin/env bash
# Forge requires a configured set of both JVM and program arguments.
# Add custom JVM arguments to the user_jvm_args.txt
# Add custom program arguments (such as nogui) to this file in the next line before the "\$@" or
# pass them to this script directly
java @user_jvm_args.txt @libraries/net/minecraftforge/forge/${MCVER}-${FORGEVER}/unix_args.txt nogui "\$@"
read -r -p "Press ENTER to close..." _
EOF

chmod +x "${SERVERPACK}/run.sh"

# =========================
# RAM ALLOCATION
# =========================
echo
echo "=================================================="
echo " Dedicated Server RAM Allocation - Helper"
echo " Recomanded Ram for Pack"
echo "--------------------------------------------------"
if [[ "$MODPACK" == "1" ]]; then echo " Beyond Ascension : 8GB base + 1GB per player"; fi
if [[ "$MODPACK" == "2" ]]; then echo " Beyond Cosmo     : 8GB base + 1GB per player"; fi
if [[ "$MODPACK" == "3" ]]; then echo " Beyond Depth     : 6GB base + 1GB per player"; fi
echo "=================================================="
echo

# Detect system RAM (GB) on Linux
TOTAL_RAM_GB="?"
if command -v awk >/dev/null 2>&1 && [[ -r /proc/meminfo ]]; then
  TOTAL_RAM_GB="$(awk '/MemTotal/ {printf "%.0f\n", $2/1024/1024}' /proc/meminfo)"
fi

echo "[INFO] Detected system RAM: ${TOTAL_RAM_GB} GB"
echo

RAM_GB=""
read -r -p "How many GB of RAM should be allocated to the server? [default 6]: " RAM_GB
RAM_GB="${RAM_GB:-6}"

# digits only
if [[ ! "$RAM_GB" =~ ^[0-9]+$ ]]; then
  echo
  echo "[WARN] Invalid RAM input detected. Using default: 6 GB."
  RAM_GB="6"
fi

echo "[INFO] Changing Xms ..."
# Xms = half Xmx (min 2G)
XMS_GB=$(( RAM_GB / 2 ))
if (( XMS_GB < 2 )); then XMS_GB=2; fi

ADD_JVM_ARGS=""
read -r -p "Add recommended JVM arguments? (Y/N) [default Y]: " ADD_JVM_ARGS
ADD_JVM_ARGS="${ADD_JVM_ARGS:-Y}"

JVM_ARGS_FILE="${SERVERPACK}/user_jvm_args.txt"

echo
echo "[INFO] Writing JVM arguments (existing file will be replaced):"
echo "       ${JVM_ARGS_FILE}"
echo

{
  echo "# Xmx and Xms set the maximum and minimum RAM usage, respectively."
  echo "# They can take any number, followed by an M or a G."
  echo "# M means Megabyte, G means Gigabyte."
  echo "# For example, to set the maximum to 3GB: -Xmx3G"
  echo "# To set the minimum to 2.5GB: -Xms2500M"
  echo
  echo "# A good default for a modded server is 4GB."
  echo "# Uncomment the next line to set it."
  echo "# -Xmx4G"
  echo
  echo "-Xmx${RAM_GB}G"
  echo "-Xms${XMS_GB}G"

  if [[ "${ADD_JVM_ARGS^^}" == "Y" ]]; then
    echo "-Dterminal.jline=false"
    echo "-Dterminal.ansi=true"
    echo "-XX:+UseG1GC"
    echo "-XX:+DisableExplicitGC"
    echo "-XX:+AlwaysPreTouch"
    echo "-XX:MaxGCPauseMillis=100"
    echo "-XX:InitiatingHeapOccupancyPercent=25"
    echo "-XX:G1ReservePercent=20"
    echo "-XX:+PerfDisableSharedMem"
  fi
} > "$JVM_ARGS_FILE"

echo
echo "[OK] user_jvm_args.txt updated successfully."
echo "[INFO] Memory: -Xmx${RAM_GB}G  -Xms${XMS_GB}G"
echo

# =========================
# Accept EULA
# =========================
echo
echo "=================================================="
echo " Minecraft EULA"
echo "--------------------------------------------------"
echo " By running a Minecraft server you must accept"
echo " the Minecraft End User License Agreement."
echo
echo " https://aka.ms/MinecraftEULA"
echo "=================================================="
echo
read -r -p "Do you accept the Minecraft EULA? (Y/N): " ACCEPT_EULA

if [[ "${ACCEPT_EULA^^}" == "Y" ]]; then
  echo "[INFO] EULA accepted. Writing eula.txt..."
  echo "eula=true" > "${SERVERPACK}/eula.txt"
else
  echo
  echo "[WARN] You did NOT accept the Minecraft EULA."
  echo "       The server will NOT start until eula=true"
  echo "       is set in eula.txt."
  echo
  echo "       You can accept it later by editing:"
  echo "       ${SERVERPACK}/eula.txt"
  echo
fi

#!/bin/bash







echo
echo "============================================"
echo " [OK] Serverpack created successfully!"
echo "============================================"
echo "Pack: ${MODPACK_NAME}  MODPACK=${MODPACK}"
echo "Path: ${SERVERPACK}"
echo "Java: ${SERVERPACK}/java"
echo "Forge: ${MCVER}-${FORGEVER}"
echo "============================================"
echo "Open Serverpack and Use the Run.sh to start the Server."
echo
echo "Press Enter to Close"
read -r _
