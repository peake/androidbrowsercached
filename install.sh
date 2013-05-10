#!/system/bin/sh
# Copyright (C) 2013  Cal Peake <cp@absolutedigital.net>
#
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For more details
# see the full license text at either:
#
# <http://www.absolutedigital.net/lic/gplv2.txt> or
# <http://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
#
# install.sh - Command-line installer script for Android Browser Cache Daemon
# created 20 Apr 2013
# revision 2013050300

PATH="/system/bin:/system/xbin"

DEFAULT_CACHE_SIZE=50 # from the C source
SED_BIN="/system/xbin/sed" # from busybox
SH_BIN="/system/bin/sh" # mksh by default
INIT_D_DIR="/system/etc/init.d"

SELECT_CHANGE_CACHE_SIZE=false

ABCD_SOURCE="androidbrowsercached"
ABCD_DEST="/system/xbin/$ABCD_SOURCE"
ABCD_PERM=0700
ABCD_PERM_NOEXEC=0600
ABCD_INITRC="/system/etc/install-recovery.sh"
ABCD_INITRC_FILE="90androidbrowsercached"
ABCD_INITRC_PERM=0744
ABCD_UPGRADE=false
ABCD_CHANGE_CACHE_SIZE=false
ABCD_CACHE_SIZE=""
ABCD_CACHE_SIZE_VAR=""
# from the C source
ABCD_SAVED_STATE="/data/data/com.android.browser/.browser_state.parcel"
ABCD_MOUNT_POINT="/data/data/com.android.browser/cache"

# First attempt at a JB 4.2 workaround
OWA_CHECKSUM="1ffe44db148632732c52adeb09af2226  /system/etc/install-recovery.sh"
OWA_UPGRADE=false

function exit_cleanup()
{
  mount -o remount,ro /system 2>/dev/null
  exit 1
}

##
# void read_yn_resp(string prompt)
#
function read_yn_resp()
{
  while true; do
    echo -n "$1"
    read -n 1
    echo
    if [ "$REPLY" == "y" ] || [ "$REPLY" == "n" ]; then
      return
    fi
  done
}

##
# void get_cache_size(void)
#
function get_cache_size()
{
  echo "The default size of the cache is $DEFAULT_CACHE_SIZE megabytes. If you would like to change"
  echo "this, please enter a new size, in megabytes, from 1 to 999. If you don't"
  echo "understand what this means, it is safe to just press ENTER at the prompt."
  echo
  while true; do
    echo -n "Browser cache size (1-999): "
    read
    echo
    if [ "$REPLY" == "" ] || [ "$REPLY" == "$DEFAULT_CACHE_SIZE" ]; then
      read_yn_resp "Please confirm: Use the default cache size of $DEFAULT_CACHE_SIZE megabytes (y/n)? "
      echo
      if [ "$REPLY" == "y" ]; then
        return
      else
        continue
      fi
    fi
    if (( $REPLY < 1 )) || (( $REPLY > 999 )); then
      echo "Invalid size entered."
      echo
      continue
    fi
    ABCD_CACHE_SIZE=$REPLY
    read_yn_resp "Please confirm: Use cache size of $ABCD_CACHE_SIZE megabytes (y/n)? "
    echo
    if [ "$REPLY" == "y" ]; then
      return
    else
      unset ABCD_CACHE_SIZE
    fi
  done
}

##
# void do_install_upgrade(void)
#
function do_install_upgrade()
{
  if [ ! -f $ABCD_SOURCE ]; then
    echo -n "${0}: ERROR: Program binary \`${ABCD_SOURCE}' not found, " >&2
    echo "please run me from the archive extraction directory." >&2
    exit_cleanup
  fi

  if [ -e $ABCD_INITRC ]; then
    if [ "$(md5 $ABCD_INITRC)" == "$OWA_CHECKSUM" ]; then
      echo "Existing becomingx Browser2Ram workaround found, will upgrade."
      echo
      OWA_UPGRADE=true
      sleep 2
    fi
  fi

  if [ -f $ABCD_DEST ]; then
    read_yn_resp "Please confirm: Upgrade (y/n)? "
    echo
    if [ "$REPLY" != "y" ]; then
      return
    fi
    ABCD_UPGRADE=true
  fi

  if $ABCD_UPGRADE; then
    killall $ABCD_SOURCE 2>/dev/null
  fi

  if ! cat $ABCD_SOURCE > $ABCD_DEST; then
    echo "${0}: ERROR: Could not install program binary to \`${ABCD_DEST}'" >&2
    exit_cleanup
  fi

  if $ABCD_UPGRADE; then
    echo "ABCD has been successfully upgraded -- please restart your device to finish."
    echo
    return
  fi

  if ! chmod $ABCD_PERM $ABCD_DEST; then
    echo "${0}: ERROR: Could not set permissions on \`${ABCD_DEST}'" >&2
    exit_cleanup
  fi

  get_cache_size

  if [ ! -z "$ABCD_CACHE_SIZE" ]; then
    ABCD_CACHE_SIZE_VAR="BROWSER_CACHE_SIZE=$ABCD_CACHE_SIZE "
  fi

  if [ ! -e $ABCD_INITRC ] || [ ! -s $ABCD_INITRC ] || $OWA_UPGRADE; then
    echo -e "#!${SH_BIN}\n\
\n\
if [ -x $ABCD_DEST ]; then\n\
  ${ABCD_CACHE_SIZE_VAR}${ABCD_DEST}\n\
fi" > $ABCD_INITRC
    if (( $? != 0 )); then
      echo "${0}: ERROR: Could not write new initrc file \`${ABCD_INITRC}'" >&2
      exit_cleanup
    fi
  elif ! grep -q "^[^#]*${ABCD_DEST}\$" $ABCD_INITRC; then
    echo -e "\n\
if [ -x $ABCD_DEST ]; then\n\
  ${ABCD_CACHE_SIZE_VAR}${ABCD_DEST}\n\
fi" >> $ABCD_INITRC
    if (( $? != 0 )); then
      echo "${0}: ERROR: Could not write changes to initrc file \`${ABCD_INITRC}'" >&2
      exit_cleanup
    fi
  else
    __change_cache_size
  fi

  if ! chmod $ABCD_INITRC_PERM $ABCD_INITRC; then
    echo "${0}: Could not set permissions on initrc file \`$ABCD_INITRC'" >&2
    exit_cleanup
  fi

  echo "ABCD has been successfully installed -- please restart your device to finish."
  echo
}

##
# void do_uninstall(void)
#
function do_uninstall()
{
  read_yn_resp "Please confirm: Uninstall (y/n)? "
  echo
  if [ "$REPLY" != "y" ]; then
    return
  fi

  if [ -f $ABCD_DEST ]; then
    killall $ABCD_SOURCE 2>/dev/null
    if ! rm -f $ABCD_DEST; then
      echo "${0}: ERROR: Could not remove program binary \`${ABCD_DEST}'" >&2
      exit_cleanup
    fi
  fi

  if grep -q "$ABCD_MOUNT_POINT" /proc/mounts 2>/dev/null; then
    umount $ABCD_MOUNT_POINT 2>/dev/null
  fi

  if [ -d $INIT_D_DIR ]; then
    if [ -f $ABCD_INITRC ]; then
      rm -f $ABCD_INITRC 2>/dev/null
    fi
  fi

  if [ -f $ABCD_SAVED_STATE ]; then
    rm -f $ABCD_SAVED_STATE 2>/dev/null
  fi

  echo "ABCD has been successfully uninstalled."
  echo
}

##
# void do_enable_disable(void)
#
function do_enable_disable()
{
  if [ -x $ABCD_DEST ]; then
    read_yn_resp "Please confirm: Disable (y/n)? "
    echo
    if [ "$REPLY" != "y" ]; then
      return
    fi
    if ! chmod $ABCD_PERM_NOEXEC $ABCD_DEST; then
      echo "${0}: ERROR: Could not set permissions \`${ABCD_PERM_NOEXEC}' on \`${ABCD_DEST}'" >&2
      exit_cleanup
    else
      echo "ABCD has been disabled -- restart your device to make the change effective."
      echo
    fi
  elif [ -f $ABCD_DEST ]; then
    read_yn_resp "Please confirm: Enable (y/n)? "
    echo
    if [ "$REPLY" != "y" ]; then
      return
    fi
    if ! chmod $ABCD_PERM $ABCD_DEST; then
      echo "${0}: ERROR: Could not set permissions \`${ABCD_PERM}' on \`${ABCD_DEST}'" >&2
      exit_cleanup
    else
      echo "ABCD has been enabled -- restart your device to make the change effective."
      echo
    fi
  fi
}

##
# void __change_cache_size(void)
#
function __change_cache_size()
{
  if [ ! -x $SED_BIN ]; then
    return
  fi

  if [ -z "$ABCD_CACHE_SIZE" ] || [ "$ABCD_CACHE_SIZE" == "$DEFAULT_CACHE_SIZE" ]; then
    SED_CMD="s!^([[:space:]]*)BROWSER_CACHE_SIZE=[0-9]+[[:space:]]+!\\1!"
  else
    SED_CMD="s!^([[:space:]]*)(BROWSER_CACHE_SIZE=[0-9]+[[:space:]]+)?(${ABCD_DEST})[[:space:]]*\$!\\1BROWSER_CACHE_SIZE=${ABCD_CACHE_SIZE} \\3!"
  fi

  if ! $SED_BIN -i -r -e "$SED_CMD" $ABCD_INITRC; then
    echo "${0}: ERROR: Could not change cache size in initrc file \`${ABCD_INITRC}'" >&2
    exit_cleanup
  fi
}

##
# void do_change_cache_size(void)
#
function do_change_cache_size()
{
  get_cache_size

  __change_cache_size

  echo "Cache size has been changed -- restart your device to make change effective."
  echo
}

if [ -d $INIT_D_DIR ]; then
  ABCD_INITRC="${INIT_D_DIR}/$ABCD_INITRC_FILE"
fi

VALID_SELECTS="Q1"

if [ -f $ABCD_DEST ]; then
  VALID_SELECTS="${VALID_SELECTS}23"
  if [ -f $ABCD_INITRC ] && grep -q "$ABCD_DEST" $ABCD_INITRC && [ -x $SED_BIN ]; then
    VALID_SELECTS="${VALID_SELECTS}4"
    SELECT_CHANGE_CACHE_SIZE=true
  fi
fi

while true; do
  echo
  echo "Android Browser Cache Daemon (ABCD) Installer"
  echo
  if [ -f $ABCD_DEST ]; then
    echo "  1) Upgrade"
  else
    echo "  1) Install"
  fi
  if [ -x $ABCD_DEST ]; then
    echo "  2) Disable"
  elif [ -f $ABCD_DEST ]; then
    echo "  2) Enable"
  fi
  if [ -f $ABCD_DEST ]; then
    echo "  3) Uninstall"
  fi
  if $SELECT_CHANGE_CACHE_SIZE; then
    echo "  4) Change Cache Size"
  fi
  echo "  Q) Quit"
  echo
  echo -n "Selection: "
  read -n 1
  echo
  if echo -n "$REPLY" | grep -qi "^[${VALID_SELECTS}]\$"; then
    break
  else
    echo
    echo "Invalid selection \`${REPLY}'"
    sleep 1
  fi
done

if [ "$REPLY" == "Q" ] || [ "$REPLY" == "q" ]; then
  exit 0
fi

echo

if id | grep -q '^uid=0\(root\) '; then
  echo "${0}: ERROR: This program requires superuser (root) privileges." >&2
  exit 1
fi

if ! mount -o remount,rw /system; then
  echo "${0}: ERROR: Could not remount \`/system' as writable." >&2
  exit 1
fi

trap exit_cleanup 1 2 3 15

case "$REPLY" in
  1 )
    do_install_upgrade
    ;;
  2 )
    do_enable_disable
    ;;
  3 )
    do_uninstall
    ;;
  4 )
    do_change_cache_size
    ;;
esac

mount -o remount,ro /system 2>/dev/null
