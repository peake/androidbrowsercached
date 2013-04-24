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
# revision 2013042200

PATH="/system/bin:/system/xbin"

DEFAULT_CACHE_SIZE=40 # from the C source
SED_BIN="/system/xbin/sed" # from busybox
SH_BIN="/system/bin/sh" # mksh by default

ABCD_SOURCE="androidbrowsercached"
ABCD_DEST="/system/xbin/$ABCD_SOURCE"
ABCD_PERM=0700
ABCD_INITRC="/system/etc/install-recovery.sh"
ABCD_INITRC_PERM=0750
ABCD_UPGRADE=false
ABCD_CHANGE_CACHE_SIZE=false
ABCD_CACHE_SIZE=""
ABCD_CACHE_SIZE_VAR=""

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
    if [ "$REPLY" == "" ]; then
      read_yn_resp "Please confirm: use the default cache size of $DEFAULT_CACHE_SIZE megabytes (y/n)? "
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
    read_yn_resp "Please confirm: use cache size of $ABCD_CACHE_SIZE megabytes (y/n)? "
    echo
    if [ "$REPLY" == "y" ]; then
      return
    else
      unset ABCD_CACHE_SIZE
    fi
  done
}

echo
read_yn_resp "This will install Android Browser Cache Daemon (ABCD), do you wish to continue (y/n)? "
if [ "$REPLY" == "n" ]; then
  exit 0
fi
echo

if [ ! -f $ABCD_SOURCE ]; then
  echo -n "${0}: ERROR: Program binary \`${ABCD_SOURCE}' not found, " >&2
  echo "please run me from the archive extraction directory." >&2
  exit 1
fi

if [ "$(id)" != "uid=0(root) gid=0(root)" ]; then
  echo "${0}: ERROR: This program requires superuser privileges." >&2
  exit 1
fi

if [ -e /system/etc/install-recovery.sh ]; then
  if [ "$(md5 /system/etc/install-recovery.sh)" == "$OWA_CHECKSUM" ]; then
    echo "Existing becomingx Browser2Ram workaround found, will upgrade."
    echo
    OWA_UPGRADE=true
    sleep 2
  fi
fi

if [ -e $ABCD_DEST ]; then
  read_yn_resp "Existing ABCD installation found, upgrade (y/n)? "
  echo
  if [ "$REPLY" == "n" ]; then
    echo "Will not upgrade, exiting."
    exit 0
  fi
  ABCD_UPGRADE=true
fi

# If we have sed(1) installed, we can offer to change cache size during upgrade.
if $ABCD_UPGRADE; then
  if [ -x $SED_BIN ]; then
    read_yn_resp "Do you wish to change the cache size during the upgrade (y/n)? "
    echo
    if [ "$REPLY" == "y" ]; then
      ABCD_CHANGE_CACHE_SIZE=true
      get_cache_size
    else
      echo "Not changing cache size."
      echo
    fi
  fi
else
  get_cache_size
fi

if [ ! -z "$ABCD_CACHE_SIZE" ]; then
  ABCD_CACHE_SIZE_VAR="BROWSER_CACHE_SIZE=$ABCD_CACHE_SIZE "
fi

if ! mount -o remount,rw /system; then
  echo "${0}: ERROR: Could not remount \`/system' as writable." >&2
  exit 1
fi

trap exit_cleanup 1 2 3 15

if $ABCD_UPGRADE; then
  killall $ABCD_SOURCE 2>/dev/null
fi

if ! cat $ABCD_SOURCE > $ABCD_DEST; then
  echo "${0}: ERROR: Could not install program binary to \`$ABCD_DEST'" >&2
  exit_cleanup
fi

if ! $ABCD_UPGRADE && ! chmod $ABCD_PERM $ABCD_DEST; then
  echo "${0}: ERROR: Could not set permissions on \`$ABCD_DEST'" >&2
  exit_cleanup
fi

if $ABCD_UPGRADE && [ -s $ABCD_INITRC ]; then
  if $ABCD_CHANGE_CACHE_SIZE; then
    if [ -z "$ABCD_CACHE_SIZE" ]; then
      SED_CMD="s/^([[:space:]]*)BROWSER_CACHE_SIZE=[0-9]+[[:space:]]+/\1/"
    else
      SED_CMD="s/^([[:space:]]*)(BROWSER_CACHE_SIZE=[0-9]+[[:space:]]+)?(.*${ABCD_SOURCE})\$/\1BROWSER_CACHE_SIZE=${ABCD_CACHE_SIZE} \3/"
    fi
    if ! $SED_BIN -ire "$SED_CMD" $ABCD_INITRC; then
      echo "${0}: WARNING: Could not change cache size in initrc file \`${ABCD_INITRC}'" >&2
    fi
  fi
else
  if [ ! -e $ABCD_INITRC ] || $OWA_UPGRADE || [ ! -s $ABCD_INITRC ]; then
    echo -e "#!${SH_BIN}\n\
\n\
if [ -x $ABCD_DEST ]; then\n\
  ${ABCD_CACHE_SIZE_VAR}${ABCD_DEST}\n\
fi" > $ABCD_INITRC
    if (( $? != 0 )); then
      echo "${0}: ERROR: Could not write new initrc file \`${ABCD_INITRC}'" >&2
      exit_cleanup
    fi
  else
    echo -e "\n\
if [ -x $ABCD_DEST ]; then\n\
  ${ABCD_CACHE_SIZE_VAR}${ABCD_DEST}\n\
fi" >> $ABCD_INITRC
    if (( $? != 0 )); then
      echo "${0}: ERROR: Could not write changes to initrc file \`${ABCD_INITRC}'" >&2
      exit_cleanup
    fi
  fi
fi

if ! $ABCD_UPGRADE && ! chmod $ABCD_INITRC_PERM $ABCD_INITRC; then
  echo "${0}: Could not set permissions on initrc file \`$ABCD_INITRC'" >&2
  exit_cleanup
fi

mount -o remount,ro /system 2>/dev/null

echo "All done installing -- restart your device to finish, and enjoy!"
echo
