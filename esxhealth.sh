#!/usr/bin/env bash
set -euo pipefail

DEFAULT_HOST="192.168.3.7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CONFIG_FILE="${ESXHEALTH_CONFIG:-$SCRIPT_DIR/.esxhealth.conf}"
SAVE_CREDS=false
ACTION="snaps"

usage() {
  cat <<EOF
Usage: esxhealth [-h host] [-u user] [-p password] [--save-creds] [--config-file file] [-list] [-snaps] [-ds]

Query an ESXi host using VCF.PowerCLI (or VMware.PowerCLI fallback) and list all current snapshots or VMs.
Query an ESXi host directly over SSH and list all current snapshots or VMs.

Options:
  -h, --host         ESXi host or vCenter server
  -u, --user         ESXi username
  -p, --password     ESXi password (avoid if you want to enter it interactively)
  --save-creds       Save host/user/password to the default config file
  --config-file file Use a custom credential file instead of $SCRIPT_DIR/.esxhealth.conf
  -list              List all VMs and their current power state
  -snaps             List all current snapshots
  -ds                List datastores and their free space
  -uptime            Show the ESXi host uptime
  --help             Show this help message

Environment:
  ESX_HOST            Host to connect to
  ESX_USER            Username for connection
  ESX_PASSWORD        Password for connection
  ESXHEALTH_CONFIG    Path to credential file

Credential file format:
  ESX_HOST=192.168.3.7
  ESX_USER=root
  ESX_PASSWORD=""
EOF
}

HOST="${ESX_HOST:-}"
USER="${ESX_USER:-}"
PASSWORD="${ESX_PASSWORD:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host)
      HOST="$2"
      shift 2
      ;;
    -u|--user)
      USER="$2"
      shift 2
      ;;
    -p|--password)
      PASSWORD="$2"
      shift 2
      ;;
    --save-creds)
      SAVE_CREDS=true
      shift
      ;;
    --config-file)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -list)
      ACTION="list"
      shift
      ;;
    -snaps)
      ACTION="snaps"
      shift
      ;;
    -ds)
      ACTION="datastores"
      shift
      ;;
    -uptime)
      ACTION="uptime"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -f "$CONFIG_FILE" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      ESX_HOST|HOST)
        if [[ -z "$HOST" ]]; then
          value="${value#\"}"
          value="${value%\"}"
          value="${value#\'}"
          value="${value%\'}"
          HOST="$value"
        fi
        ;;
      ESX_USER|USER)
        if [[ -z "$USER" ]]; then
          value="${value#\"}"
          value="${value%\"}"
          value="${value#\'}"
          value="${value%\'}"
          USER="$value"
        fi
        ;;
      ESX_PASSWORD|PASSWORD)
        if [[ -z "$PASSWORD" ]]; then
          value="${value#\"}"
          value="${value%\"}"
          value="${value#\'}"
          value="${value%\'}"
          PASSWORD="$value"
        fi
        ;;
    esac
done < <(grep -E '^(ESX_HOST|ESX_USER|ESX_PASSWORD|HOST|USER|PASSWORD)=' "$CONFIG_FILE" 2>/dev/null || true)
fi

HOST="${HOST:-$DEFAULT_HOST}"

if [[ -z "$USER" ]]; then
  echo -n "Username: "
  read -r USER
fi


if [[ -z "$PASSWORD" ]]; then
  echo -n "Password: "
  read -rs PASSWORD
  echo
fi

if [[ "$SAVE_CREDS" == true ]]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<EOF
ESX_HOST=$HOST
ESX_USER=$USER
ESX_PASSWORD=$PASSWORD
EOF
  chmod 600 "$CONFIG_FILE"
  echo "Saved credentials to $CONFIG_FILE"
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Error: 'sshpass' is not installed or not on PATH." >&2
  echo "Install sshpass (e.g., via yum, dnf, pacman, or brew) to run queries non-interactively." >&2
  exit 1
fi

# Construct the script that will be executed remotely on the ESXi host
REMOTE_SCRIPT=$(cat << 'EOF'
ACTION="ESXHEALTH_ACTION_PLACEHOLDER"
if [ "$ACTION" = "snaps" ]; then
    vim-cmd vmsvc/getallvms | sed -e '1d' | while read -r line; do
        if echo "$line" | grep -q '^\([0-9][0-9]*\) '; then
            vmid=$(echo "$line" | awk '{print $1}')
            # Parse everything up to the first bracket so we don't trip on spaces in VM names
            name=$(echo "$line" | sed 's/^[0-9]*[ \t]*\([^\[]*\).*/\1/' | sed 's/[ \t]*$//')
            vim-cmd vmsvc/snapshot.get "$vmid" 2>/dev/null | awk -v vm="$name" '
                /Snapshot Name/ { snap=$0; sub(/^[[:space:]|-]*Snapshot Name[[:space:]]*:[[:space:]]*/, "", snap) }
                /Snapshot Created On/ { date=$0; sub(/^[[:space:]|-]*Snapshot Created On[[:space:]]*:[[:space:]]*/, "", date); print vm "|" snap "|" date }
            '
        fi
    done
elif [ "$ACTION" = "list" ]; then
    vim-cmd vmsvc/getallvms | sed -e '1d' | while read -r line; do
        if echo "$line" | grep -q '^\([0-9][0-9]*\) '; then
            vmid=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | sed 's/^[0-9]*[ \t]*\([^\[]*\).*/\1/' | sed 's/[ \t]*$//')
            state=$(vim-cmd vmsvc/power.getstate "$vmid" 2>/dev/null | tail -n 1)
            if [ "$state" = "Powered on" ]; then
                echo "$name|PoweredOn"
            else
                echo "$name|PoweredOff"
            fi
        fi
    done
elif [ "$ACTION" = "datastores" ]; then
    # Handles ESXi 6/7/8 filesystem formatting cleanly even if volumes have spaces
    esxcli storage filesystem list | awk '$5~/^(VMFS|NFS|VFFS)/ || $6~/^(VMFS|NFS|VFFS)/ || $7~/^(VMFS|NFS|VFFS)/ {
        type_idx=0
        for(i=1;i<=NF;i++){ if($i~/^(VMFS|NFS|VFFS)/){ type_idx=i; break } }
        if(type_idx>0){
            size = $(type_idx+1) / 1024 / 1024 / 1024
            free = $(type_idx+2) / 1024 / 1024 / 1024
            name = $2
            for(i=3; i<=type_idx-3; i++) name = name " " $i
            pct = (size > 0) ? (free / size) * 100 : 0
            printf "%s|%.2f|%.2f|%.2f\n", name, size, free, pct
        }
    }'
elif [ "$ACTION" = "uptime" ]; then
    uptime
fi
EOF
)

# Inject the chosen action into the remote script variable
REMOTE_SCRIPT="${REMOTE_SCRIPT/ESXHEALTH_ACTION_PLACEHOLDER/$ACTION}"

SSH_CMD=(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -q "$USER@$HOST")

if ! output=$("${SSH_CMD[@]}" "$REMOTE_SCRIPT" 2>/dev/null); then
    echo "Error: Failed to connect to $HOST or execute commands." >&2
    echo "Check your credentials and ensure the SSH service is enabled and running on the ESXi host." >&2
    exit 1
fi

if [ "$ACTION" = "snaps" ]; then
    if [ -z "$output" ]; then
        echo "No snapshots found on $HOST."
    else
        (echo "VM|Snapshot Name|Created Date" && echo "---|---|---" && echo "$output") | column -t -s '|'
    fi
elif [ "$ACTION" = "list" ]; then
    if [ -z "$output" ]; then
        echo "No VMs found on $HOST."
    else
        (echo "Name|PowerState" && echo "----|----------" && echo "$output") | column -t -s '|' | sed -e $'s/PoweredOn/\033[32mPoweredOn\033[0m/g' -e $'s/PoweredOff/\033[31mPoweredOff\033[0m/g'
    fi
elif [ "$ACTION" = "datastores" ]; then
    if [ -z "$output" ]; then
        echo "No datastores found on $HOST."
    else
        (echo "Name|CapacityGB|FreeSpaceGB|FreePercent" && echo "----|----------|-----------|-----------" && echo "$output") | column -t -s '|' | awk 'NR<=2{print;next} $NF+0 < 15 { sub(/[0-9.]+$/, "\033[31m&\033[0m") } 1'
    fi
elif [ "$ACTION" = "uptime" ]; then
    echo -e "Host Uptime:\n$output"
fi
