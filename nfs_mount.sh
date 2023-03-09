#!/usr/bin/env bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Copyright 20221 Oliver "RealLarry" Jaksch

# You can download the latest version of this script from:
# https://github.com/MiSTer-devel/CIFS_MiSTer

# Version 1.1 - 2022-12-25 - Cosmetics
# Version 1.0 - 2021-12-29 - First commit



#=========   USER OPTIONS   =========
# You can edit these user options or make an ini file with the same
# name as the script, i.e. nfs_mount.ini, containing the same options.

# Your NFS Server, i.e. your NAS name or it's IP address.
SERVER=""

# The path to mount from your NFS server, for example "/storage/games"
SERVER_PATH=""

# The number of seconds to wait before considering the server unreachable
SERVER_TIMEOUT="30"

# Wake up the server from above by using WOL (Wake On LAN)
WOL="no"
MAC="FFFFFFFFFFFF"
SERVER_MAC="00:11:22:33:44:55"

# Optional additional mount options.
MOUNT_OPTIONS="noatime"

# "yes" in order to wait for the CIFS server to be reachable;
# useful when using this script at boot time.
WAIT_FOR_SERVER="yes"

# "yes" for automounting NFS shares at boot time;
# it will create start/kill scripts in /etc/network/if-up.d and /etc/network/if-down.d.
MOUNT_AT_BOOT="yes"

#=========NO USER-SERVICEABLE PARTS BELOW THIS LINE=====

#=========FUNCTION LIBRARY==============================

# Check if we have an IPv4 address on any of the interfaces that is
# not a local loopback (127.0.0.0/8) or link-local (169.254.0.0/16) adddress.

function has_ip_address() {
  ip addr show | grep 'inet ' | grep -vE '127.|169.254.' >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Check if the script's configuration is minimally viable

function viable_config() {
  local VIABLE="false"
  if [ "${SERVER}" != "" ]; then
    VIABLE="true"
  fi
  if [ "${SERVER_PATH}" != "" ]; then
    VIABLE="true"
  fi
  if [ "${VIABLE}" == "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Wait for the NFS server to be up

function wait_for_nfs() {
    local PORTS=(2049 111)
    local START=$(date +%s)

    while true; do
        for PORT in "${PORTS[@]}"; do
            nc -z "$SERVER" "$PORT" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "TCP connection to $SERVER on port $PORT succeeded!"
                return 0
            fi
        done

        sleep 1

        local NOW=$(date +%s)
        local ELAPSED=$((NOW - START))
        if [ $ELAPSED -ge $SERVER_TIMEOUT ]; then
            echo "Timeout waiting for TCP connection to $SERVER on ports ${PORTS[*]}"
            return 1
        fi
    done
}

#=========BUSINESS LOGIC================================

if [ "$(viable_config)" == "false" ]; then
  echo "You need to set both SERVER and SERVER_PATH variables."
  exit 1
else
  echo "Configuration data is complate."
  echo "Server: $SERVER"
  echo "Path  : $SERVER_PATH"
fi

# Run this script only once after getting an IP address
[ -f /tmp/nfs_mount.lock ] && exit 1
touch /tmp/nfs_mount.lock

if [ "${WAIT_FOR_SERVER}" == "yes" ]; then
    echo -n "Waiting IP connectivity."
    while [ "$(has_ip_address)" != "true" ]; do
	sleep 1
	echo -n "."
    done
    echo
fi

if [ "${WOL}" == "yes" ]; then
    for REP in {1..16}; do
	MAC+=$(echo ${SERVER_MAC})
    done
    echo -n "${MAC}" | xxd -r -u -p | socat - UDP-DATAGRAM:255.255.255.255:9,broadcast
fi

echo "Waiting for NFS server to be up."
wait_for_nfs

ORIGINAL_SCRIPT_PATH="$0"
if [ "$ORIGINAL_SCRIPT_PATH" == "bash" ]; then
    ORIGINAL_SCRIPT_PATH=$(ps | grep "^ *$PPID " | grep -o "[^ ]*$")
fi
INI_PATH=${ORIGINAL_SCRIPT_PATH%.*}.ini
if [ -f $INI_PATH ]; then
    eval "$(cat $INI_PATH | tr -d '\r')"
fi

if ! [ "$(zgrep "CONFIG_NFS_FS=" /proc/config.gz)" = "CONFIG_NFS_FS=y" ]; then
    echo "The current Kernel doesn't support NFS."
    echo "Please update your MiSTer Linux system."
    exit 1
fi

NET_UP_SCRIPT="/etc/network/if-up.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"
NET_DOWN_SCRIPT="/etc/network/if-down.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"
if [ "${MOUNT_AT_BOOT}" ==  "yes" ]; then
    WAIT_FOR_SERVER="yes"
    if [ ! -f "${NET_UP_SCRIPT}" ] || [ ! -f "${NET_DOWN_SCRIPT}" ]; then
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="yes"
	[ "${RO_ROOT}" == "yes" ] && mount / -o remount,rw
	echo -e "#!/bin/bash"$'\n\n'"$(realpath "$ORIGINAL_SCRIPT_PATH") &" > "${NET_UP_SCRIPT}"
	chmod +x "${NET_UP_SCRIPT}"
	echo -e "#!/bin/bash"$'\n\n'"umount -a -t nfs4" > "${NET_DOWN_SCRIPT}"
	chmod +x "${NET_DOWN_SCRIPT}"
	sync
	[ "${RO_ROOT}" == "yes" ] && mount / -o remount,ro
    fi
else
    if [ -f "${NET_UP_SCRIPT}" ] || [ -f "${NET_DOWN_SCRIPT}" ]; then
	mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="yes"
	[ "${RO_ROOT}" == "yes" ] && mount / -o remount,rw
	rm "${NET_UP_SCRIPT}" > /dev/null 2>&1
	rm "${NET_DOWN_SCRIPT}" > /dev/null 2>&1
	sync
	[ "${RO_ROOT}" == "yes" ] && mount / -o remount,ro
    fi
fi

if [ "${WAIT_FOR_SERVER}" == "yes" ]; then
    echo -n "Waiting for ${SERVER}."
    until [ "$(ping -4 -c1 ${SERVER} &>/dev/null ; echo $?)" = "0" ]; do
	sleep 1
	echo -n "."
    done
    echo
fi

SCRIPT_NAME=${ORIGINAL_SCRIPT_PATH##*/}
SCRIPT_NAME=${SCRIPT_NAME%.*}
mkdir -p "/tmp/${SCRIPT_NAME}" > /dev/null 2>&1
/bin/busybox mount -t nfs4 ${SERVER}:${SERVER_PATH} /tmp/${SCRIPT_NAME} -o ${MOUNT_OPTIONS}
IFS=$'\n'
for LDIR in $(ls /tmp/${SCRIPT_NAME}); do
    if [ -d "/media/fat/${LDIR}" ] && [ -d "/tmp/${SCRIPT_NAME}/${LDIR}" ] && ! [ $(mount | grep "/media/fat/${LDIR} type nfs4") ]; then
        echo "Mounting ${LDIR}"
        mount -o bind "/tmp/${SCRIPT_NAME}/${LDIR}" "/media/fat/${LDIR}"
    fi
done

echo "Done!"
exit 0

