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

# Copyright 2022 Oliver "RealLarry" Jaksch

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
SERVER_TIMEOUT="60"

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

# Are we running as root?

function as_root() {
  if [ `whoami` != "root" ]; then
    echo "This script must be run as root. Exiting."
    exit 1
  fi
}

# Run only once

function run_once() {
  if [ -f /tmp/nfs_mount.lock ]; then
    echo "This script may run only once per session. Please reboot your MiSTer first."
    exit 1
  fi
  touch /tmp/nfs_mount.lock
}


# Load script configuration from an INI file.
# ..which isn't really an INI file but just a list of Bash vars
function load_ini() {
 local SCRIPT_PATH="$(realpath "$0")"
 local INI_FILE=${SCRIPT_PATH%.*}.ini
 if [ -e "$INI_FILE" ]; then
   eval "$(cat $INI_FILE | tr -d '\r')"
 fi
}

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
  if [ "${VIABLE}" == "false" ]; then
    echo "You must set the SERVER and SERVER_PATH variables before proceeding. Exiting."
    exit 1
  fi
}

# Wake-up the NFS server using WOL

function wake_up_nfs() {
  if [ "${WOL}" == "yes" ]; then
    for REP in {1..16}; do
      MAC+=$(echo ${SERVER_MAC})
    done
    echo -n "${MAC}" | xxd -r -u -p | socat - UDP-DATAGRAM:255.255.255.255:9,broadcast
  fi
}

# Wait for the NFS server to be up
# We exit hard on timeout

function wait_for_nfs() {
    if [ "${WAIT_FOR_SERVER}" == "true" ]; then
      local PORTS=(2049 111)
      local START=$(date +%s)

      while true; do
          for PORT in "${PORTS[@]}"; do
              nc -z "$SERVER" "$PORT" >/dev/null 2>&1
              if [ $? -eq 0 ]; then
                  echo "NFS-server $SERVER is alive."
                  return 0
              fi
          done

          sleep 1

          local NOW=$(date +%s)
          local ELAPSED=$((NOW - START))
          if [ $ELAPSED -ge $SERVER_TIMEOUT ]; then
              echo "Timeout while waiting $SERVER_TIMEOUT seconds for NFS-server $SERVER.}"
              exit 1
          fi
      done
    fi
    return 0
}

# Install the mount-at-boot scripts

function install_mount_at_boot() {
  if [ "${MOUNT_AT_BOOT}" == "yes" ]; then

    # We need to write to the root filesystem so remount it
    # read-write if it's currently read-only.
    mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="yes"
    [ "${RO_ROOT}" == "yes" ] && mount / -o remount,rw

    local ORIGINAL_SCRIPT_PATH="$0"
    local NET_UP_SCRIPT="/etc/network/if-up.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"
    local NET_DOWN_SCRIPT="/etc/network/if-down.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"

    # Make sure we have a sane working environment
    [ ! -d /etc/network/if-up.d ]
    mkdir -p /etc/network/if-up.d

    [ ! -d /etc/network/if-down.d ]
    mkdir -p /etc/network/if-down.d

    # Permissions should be in a known-good state
    chmod 755 /etc/network/if-up.d
    chmod 755 /etc/network/if-down.d
    chmod 775 /etc/network
    chmod 775 /etc

    # We always recreate this script because we have no way to track changes to it
    [ -f ${NET_UP_SCRIPT} ]
    rm ${NET_UP_SCRIPT}

    touch "${NET_UP_SCRIPT}"
    touch "${NET_DOWN_SCRIPT}"

    # Ensure the NET_UP script is *NOT* executable before it's finished
    chmod 600 "${NET_UP_SCRIPT}"
    echo '#!/bin/env bash' >> "${NET_UP_SCRIPT}"
    echo "$(realpath "$ORIGINAL_SCRIPT_PATH") &" >> "${NET_UP_SCRIPT}"

    # NET_UP_SCRIPT is finished so we make it executable
    chmod 755 "${NET_UP_SCRIPT}"

    echo -e "#!/bin/bash"$'\n'"umount -a -t nfs4" > "${NET_DOWN_SCRIPT}"
    chmod 755 "${NET_DOWN_SCRIPT}"
    sync

    # If we remounted the rootfs because it was read-only, we now
    # undo our remount action and revert the mount to how we found it.
    [ "${RO_ROOT}" == "yes" ] && mount / -o remount,ro
    return 0
  fi
}

# Remove the mount-at-boot script

function remove_mount_at_boot() {
  if [ "${MOUNT_AT_BOOT}" != "yes" ]; then
    local ORIGINAL_SCRIPT_PATH="$0"
    local NET_UP_SCRIPT="/etc/network/if-up.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"
    local NET_DOWN_SCRIPT="/etc/network/if-down.d/$(basename ${ORIGINAL_SCRIPT_PATH%.*})"

    # We need to write to the root filesystem so remount it
    # read-write if it's currently read-only.
    mount | grep "on / .*[(,]ro[,$]" -q && RO_ROOT="yes"
    [ "${RO_ROOT}" == "yes" ] && mount / -o remount,rw

    [ -f ${NET_UP_SCRIPT} ]
    rm ${NET_UP_SCRIPT}

    [ -f ${NET_DOWN_SCRIPT} ]
    rm ${NET_DOWN_SCRIPT}
    sync

    # If we remounted the rootfs because it was read-only, we now
    # undo our remount action and revert the mount to how we found it.
    [ "${RO_ROOT}" == "yes" ] && mount / -o remount,ro
    return 0
  fi
}

#=========BUSINESS LOGIC================================
#
# This part just calls the functions we define above
# in a sequence. To keep things excruciatingly easy
# to follow, any and all config checks are done *inside*
# the functions themselves.
#
# Each of these steps will exit if things are not OK.
#
#=======================================================

# Ensure we are the root user
as_root

# ..and that the script shall run only once per session.
run_once

# Load configuration from the .ini file if we have one.
load_ini

# Only cause changes if the configuration is viable.
viable_config

# We wake up the NFS-server if needed
wake_up_nfs

# ..and give it time to actually get dressed.
wait_for_nfs

# Install/update the scripts to run at every reboot
install_mount_at_boot

# ..or remove them if that's what the user wants.
remove_mount_at_boot

exit 0

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
