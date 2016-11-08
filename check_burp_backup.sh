#! /bin/bash
# WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                   Version 2, December 2004
# 
#Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
#              2016 Roland Hopferwieser
#
#Everyone is permitted to copy and distribute verbatim or modified
#copies of this license document, and changing it is allowed as long
#as the name is changed.
# 
#           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#  TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
# 
# 0. You just DO WHAT THE FUCK YOU WANT TO.

# BURP check backup nagios plugin
# Read the last log file from a BURP backup and check age and warning of backup.
#
# TODO
# * Statistics gathering and state of backup depending of BURP version (use backup_stats if it exists, and fall back to log.gz)

VERSION=1.3
BURP_SERVER_CONF=/etc/burp/burp-server.conf

## Variables
#set -xv
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
PERFDATA=
WARNING=36
CRITICAL=72
WARNERRS=0
CRITERRS=10

usage() {
	cat <<-EOF
$(basename $0) $VERSION

This plugin checks the burp backup age for a given client.

Usage: -H <hostname> [-d <dir>] [-w <hours>] [-c <hours>] [ -W <warnings> ] [-C <warnings>]

Options:
  -H Name of backuped host (see clientconfdir)
  -d Override burp directory (default: read from $BURP_SERVER_CONF)
  -w WARNING number of hours since last backup (default: $WARNING)
  -c CRITICAL number of hours since last backup (default: $CRITICAL)
  -W WARNING number of warnings (default: $WARNERRS)
  -C CRITICAL number of warnings (default: $CRITERRS)
EOF
}

unknown() {
	echo "UNKNOWN : $1"
	exit $STATE_UNKNOWN
}

function convertToSecond() {
	local S=$1
	((h=S/3600))
	((m=S%3600/60))
	((s=S%60))
	printf "%dh%dm%ds\n" $h $m $s
}

burpDir() {
	if [[ ! -r "$BURP_SERVER_CONF" ]]; then
		unknown "Can't read '$BURP_SERVER_CONF'!"
	fi
	local dir=$(awk '/^\s*directory/ { print $3; }' "$BURP_SERVER_CONF")
	if [[ -z "$dir" || ! -r "$dir" ]]; then
		unknown "Invalid burp directory '$dir'!"
	fi
	echo "$dir"
}

## Start
DIR=
HOST=

# Manage arguments
while getopts hH:d:pw:c:W:C: OPT; do
	case $OPT in
		h)	
			usage
 			exit $STATE_UNKNOWN
			;;	
		d)
			DIR=$OPTARG
			;;
		H)
			HOST=$OPTARG
			;;
		w)
			WARNING=$OPTARG
			;;
		c)
			CRITICAL=$OPTARG
			;;
		W)
			WARNERRS=$OPTARG
			;;
		C)
			CRITERRS=$OPTARG
			;;
		*)
			usage
 			exit $STATE_UNKNOWN
			;;	
	esac
done

if [[ -z "$DIR" ]]; then
	DIR=$(burpDir)
fi
DIR="$DIR/$HOST"
LOG="$DIR/current/log.gz"

[[ -n "$HOST" ]] || unknown "Empty host"
[[ $CRITICAL -gt $WARNING ]] || unknown "Warning level is greater than critical level"
[[ -r "$LOG" ]] || unknown "Can't read file '$LOG'"

WARNING=$(( WARNING * 3600 ))
CRITICAL=$(( CRITICAL * 3600 ))

# Unzip log file before read it.
TMP=$(mktemp /tmp/check_burp_backup-XXXXXX)
zcat "$LOG" > $TMP

# Statistics gathering
WARNINGS=$(awk '/Warnings/ {print $NF}' $TMP)
read NEW CHANGED UNCHANGED DELETED TOTAL <<<$( awk '/Grand total:/ { print $3 " " $4 " " $5 " " $6 " " $7; }' $TMP)
TIME=$( awk '/End time:/ { print $3 " " $4; }' $TMP)

ENDSTAMP=$(date -d "$TIME" +%s)
NOW=$(date +%s)

LAST=$(($NOW-$ENDSTAMP))
LASTDIFF=$(convertToSecond $LAST)

PERFDATA=$(echo "| warnings=$WARNINGS; new=$NEW; changed=$CHANGED; unchanged=$UNCHANGED; deleted=$DELETED; total=$TOTAL")

# Cleanup
rm $TMP

STATE=0
[[ $LAST -gt $WARNING || $WARNINGS -gt $WARNERRS ]] && STATE=1
[[ $LAST -gt $CRITICAL || $WARNINGS -gt $CRITERRS ]] && STATE=2

if [[ $STATE -eq 2 ]]; then
	echo "CRITICAL : Last backup $LASTDIFF ago with $WARNINGS errors $PERFDATA"
	exit $STATE_CRITICAL
elif [[ $STATE -eq 1 ]]; then
	echo "WARNING : Last backup $LASTDIFF ago with $WARNINGS errors $PERFDATA"
	exit $STATE_WARNING
else
	echo "OK : Backup without error $LASTDIFF ago $PERFDATA"
	exit $STATE_OK
fi

