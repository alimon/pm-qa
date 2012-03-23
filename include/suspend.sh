#!/bin/bash
#
# Script to automate suspend / resume
#
# Copyright (C) 2008-2009 Canonical Ltd.
#
# Authors:
#  Michael Frey <michael.frey@canonical.com>
#  Andy Whitcroft <apw@canonical.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#
# Script to automate suspend / resume
#
# We set a RTC alarm that wakes the system back up and then sleep
# for  seconds before we go back to sleep.
#
# Changelog:
#
# Version for Linaro PM-QA:
#  - this script is edited and integrated into Linaro PM-QA
#  - hongbo.zhang@linaro.org, March, 2012
#
# V8:
#  - add a new suspend battery drain test
#  - track batteries disabling tests which require them automatically
#  - disable dbus tests when we have no primary user
#  - include the new power drain test in --full
#  - handle AC transitions better
#  - use minutes in messages where appropriate
#  - report AC transition failures
#  - only mention AC when we have batteries
#  - report results at the bottom for easy posting
#
# V7:
#  - add a --dry-run mode to simplify developement
#  - add a automation mode for checkbox integration
#  - add a new pm-suspend test
#  - record and restore timer_delay around the variable time test.
#
# V6:
#  - move an --enable/--disable interface for tests
#  - add --set to allow setting of approved parameters
#  - fix up prompting for interactive and non-interactive tests
#  - supply a sensible default for testing on servers (apw, kirkland)
#
# V5:
#  - send dbus messages as the original user
#  - stop clearing the dmesg as we go
#  - stop using trace generally as this affects the wakeups
#  - do a single dbus test then move to pm-suspend to avoid screensaver
#  - timeout waiting for a suspend to complete catching failure to go down
#
# V4:
#  - update the help output
#  - add --comprehensive to do AC related tests
#  - add --extensive to do a range of time related tests
#  - add --full to enable all harder tests
#  - add fallback to pm-suspend for Kbuntu
#  - collect dmesg output
#  - remove hwclock update
#
# V3:
#  - fix typo in fallback acpi interface
#  - when recording the RTC clock do not go direct
#  - pmi is now deprecated suspend using dbus
#
# V2:
#  - support newer rtc sysfs wakealarm interface
#  - move to using pmi action suspend
#  - allow the user to specify the number of iterations
#  - ensure we are running as root
#  - report the iterations to the user
#  - clean up the output and put it in a standard logfile
#  - add a descriptive warning and allow user cancel
#  - add tracing enable/disable
#  - fix logfile location
#  - add a failure cleanup mode
#  - make time sleep time and delay time configurable
#  - ensure the log directory exists
#  - clock will be fixed automatically on network connect
#  - default sleep before wakeup to 20s
#  - do not use dates after we have corrupted the clock
#  - sort out the copyright information
#  - we do not have any failure cleanup currently
#
# V1:
#  - add the suspend test scripts
#
P="test-suspend"

LOGDIR='/var/lib/pm-utils'
LOGFILE="$LOGDIR/stress.log"

setup_wakeup_timer ()
{
	timeout="$1"

	#
	# Request wakeup from the RTC or ACPI alarm timers.  Set the timeout
	# at 'now' + $timeout seconds.
	#
	ctl='/sys/class/rtc/rtc0/wakealarm'
	if [ -f "$ctl" ]; then
		# Cancel any outstanding timers.
		echo "0" >"$ctl"
		# rtcN/wakealarm can use relative time in seconds
		echo "+$timeout" >"$ctl"
		return 0
	fi
	ctl='/proc/acpi/alarm'
	if [ -f "$ctl" ]; then
		echo `date '+%F %H:%M:%S' -d '+ '$timeout' seconds'` >"$ctl"
		return 0
	fi

	echo "no method to awaken machine automatically" 1>&2
	exit 1
}

suspend_system ()
{
	if [ "$dry" -eq 1 ]; then
		echo "DRY-RUN: suspend machine for $timer_sleep"
		sleep 1
		return
	fi

	setup_wakeup_timer "$timer_sleep"

	dmesg >"$LOGFILE.dmesg.A"

	# Send a dbus message to initiate Suspend.
	if [ "$suspend_dbus" -eq 1 ]; then
		sudo -u $SUDO_USER dbus-send --session --type=method_call \
			--dest=org.freedesktop.PowerManagement \
			/org/freedesktop/PowerManagement \
			org.freedesktop.PowerManagement.Suspend \
			>> "$LOGFILE" || {
				ECHO "$P FAILED: dbus suspend failed" 1>&2
				return 1
			}
	else
		pm-suspend >> "$LOGFILE"
	fi

	# Wait on the machine coming back up -- pulling the dmesg over.
	echo "v---" >>"$LOGFILE"
	retry=30
	while [ "$retry" -gt 0 ]; do
		let "retry=$retry-1"

		# Accumulate the dmesg delta.
		dmesg >"$LOGFILE.dmesg.B"
		diff "$LOGFILE.dmesg.A" "$LOGFILE.dmesg.B" | \
			grep '^>' >"$LOGFILE.dmesg"
		mv "$LOGFILE.dmesg.B" "$LOGFILE.dmesg.A"

		echo "Waiting for suspend to complete $retry to go ..." \
							>> "$LOGFILE"
		cat "$LOGFILE.dmesg" >> "$LOGFILE"

		if [ "`grep -c 'Back to C!' $LOGFILE.dmesg`" -ne 0 ]; then
			break;
		fi
		sleep 1
	done
	echo "^---" >>"$LOGFILE"
	rm -f "$LOGFILE.dmesg"*
	if [ "$retry" -eq 0 ]; then
		ECHO "$P SUSPEND FAILED, did not go to sleep" 1>&2
		return 1
	fi
}

delay_system ()
{
	if [ "$dry" -eq 1 ]; then
		echo "DRY-RUN: stay awake for $timer_delay"
		sleep 1
		return
	fi

	#
	# wait for $timer_delay seconds after system resume from S3
	#
	ECHO "wait for $timer_delay seconds..."
	sleep $timer_delay
}

ECHO ()
{
	echo "$@" | tee -a "$LOGFILE"
}


enable_trace()
{
    echo 1 > '/sys/power/pm_trace'
}

disable_trace()
{
    echo 0 > '/sys/power/pm_trace'
}

# Battery
battery_count()
{
	cat /proc/acpi/battery/*/state 2>/dev/null | \
	awk '
		BEGIN			{ total = 0 }
		/present:.*yes/		{ total += 1 }
		END			{ print total }
	'
}
battery_capacity()
{
	cat /proc/acpi/battery/*/state 2>/dev/null | \
	awk '
		BEGIN			{ total = 0 }
		/remaining capacity:/	{ total += $3 }
		END			{ print total }
	'
}


# Options helpers.
chk_test ()
{
	if ! declare -p "test_$1" 2>/dev/null 1>&2; then
		echo "$P: $1: test unknown" 1>&2
		exit 1
	fi
}
handle_set ()
{
	stmt=`echo "$1" | sed -e 's/\./_/g'`

	test="${stmt%%_*}"
	var="${stmt%%=*}"

	chk_test "$test"
	if ! declare -p "args_$var" 2>/dev/null 1>&2; then
		echo "$P: $var: test variable unknown" 1>&2
		exit 1
	fi
	
	RET="args_$stmt"
}
chk_number() {
	eval "val=\"\$$1\""
	let num="0+$val"
	if [ "$val" != "$num" ]; then
		name=`echo "$1" | sed -e 's/args_//' -e 's/_/./'`
		echo "$P: $name: $val: non-numeric value" 1>&2
		exit 1
	fi
}

# Options handling.
dry=0
auto=0
timer_sleep=20
timer_delay=10

test_dbus=0
test_pmsuspend=0
test_ac=0
test_timed=0
test_repeat=0
args_repeat_iterations=10
test_power=0
args_power_sleep=600

chk_number "args_repeat_iterations"
chk_number "args_power_sleep"

battery_count=`battery_count`

suspend_dbus=0

# Check we are running as root as we are going to fiddle with the clock
# and use the rtc wakeups.
id=`id -u`
if [ "$id" -ne 0 ]; then
	echo "ERROR: must be run as root to perform this test, use sudo:" 1>&2
	echo "       sudo $0 $@" 1>&2
	exit 1
fi

ac_needed=-1
ac_is=-1
ac_becomes=-1
ac_required()
{
	ac_check

	ac_needed="$1"
	ac_becomes="$1"
}
ac_transitions()
{
	ac_check

	ac_needed="$1"
	ac_becomes="$2"
}
ac_online()
{
	cat /proc/acpi/ac_adapter/*/state 2>/dev/null | \
	awk '
		BEGIN			{ online = 0; offline = 0 }
		/on-line/		{ online = 1 }
		/off-line/		{ offline = 1 }
		END			{
						if (online) {
							print "1"
						} else if (offline) {
							print "0"
						} else {
							print "-1"
						}
					}
	'
}
ac_check()
{
	typeset ac_current=`ac_online`

	if [ "$ac_becomes" -ne -1 -a "$ac_current" -ne -1 -a \
			"$ac_current" -ne "$ac_becomes" ]; then
		ECHO "*** WARNING: AC power not in expected state" \
			"($ac_becomes) after test"
	fi
	ac_is="$ac_becomes"
}

phase=0
phase_first=1
phase_interactive=1
phase()
{
	typeset sleep

	let phase="$phase+1"

	if [ "$battery_count" -ne 0 -a "$ac_needed" -ne "$ac_is" ]; then
		case "$ac_needed" in
		0) echo "*** please ensure your AC cord is detached" ;;
		1) echo "*** please ensure your AC cord is attached" ;;
		esac
		ac_is="$ac_needed"
	fi
	
	if [ "$timer_sleep" -gt 60 ]; then
		let sleep="$timer_sleep / 60"
		sleep="$sleep minutes"
	else
		sleep="$timer_sleep seconds"
	fi
	echo "*** machine will suspend for $sleep"

	if [ "$auto" -eq 1 ]; then
		:

	elif [ "$phase_interactive" -eq 1 ]; then
		echo "*** press return when ready"
		read x

	elif [ "$phase_first" -eq 1 ]; then
		echo "*** NOTE: there will be no further user interaction from this point"
		echo "*** press return when ready"
		phase_first=0
		read x
	fi
}

# Ensure the log directory exists.
mkdir -p "$LOGDIR"

