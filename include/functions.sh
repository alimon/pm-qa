#!/bin/sh
#
# PM-QA validation test suite for the power management on Linux
#
# Copyright (C) 2008-2009 Canonical Ltd.
# Copyright (C) 2011-2016, Linaro Limited.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Contributors:
#     Daniel Lezcano <daniel.lezcano@linaro.org> (IBM Corporation)
#       - initial API and implementation
#     Michael Frey <michael.frey@canonical.com>
#       - initial suspend/resume functions
#     Andy Whitcroft <apw@canonical.com>
#       - initial suspend/resume functions
#     Hongbo Zhang <hongbo.zhang@linaro.org>
#       - updated suspend/resume functions
#

. ../Switches/Switches.sh

LOGDIR='/var/lib/pm-utils'
LOGFILE="$LOGDIR/stress.log"
CPU_PATH="/sys/devices/system/cpu"
TEST_NAME=$(basename ${0%.sh})
PREFIX=$TEST_NAME
INC=0
cpus=$(ls $CPU_PATH | grep "cpu[0-9].*")
pass_count=0
fail_count=0
skip_count=0
test_script_status="pass"
NANOSLEEP="../utils/nanosleep"
gov_array="governors_backup"
freq_array="frequencies_backup"
THERMAL_PATH="/sys/devices/virtual/thermal"
MAX_ZONE=0-12
MAX_CDEV=0-50
scaling_freq_array="scaling_freq"
mode_array="mode_list"
thermal_gov_array="thermal_governor_backup"

# config options for suspend/resume
dry=0
auto=1
pm_trace=1
timer_sleep=20

test_status_show() {
    if [ $fail_count -ne 0 ]; then
        test_script_status="fail"
    else
        if [ $skip_count -ne 0 ]; then
            if [ $pass_count -ne 0 ]; then
                test_script_status="pass"
            else
                test_script_status="skip"
            fi
        fi
    fi

    echo " "
    if [ "$test_script_status" = "fail" ]; then
        echo "$TEST_NAME: fail"
    elif [ "$test_script_status" = "skip" ]; then
        echo "$TEST_NAME: skip"
    else
        echo "$TEST_NAME: pass"
    fi
    echo " "
}

skip_tests() {
    dir=$1

    test_script_list=$(ls ../$1/*.sh | grep -v 'sanity.sh$' | grep -v '00.sh$')

    for test_script in $test_script_list; do
        test_case=$(basename $test_script .sh)
        echo "$test_case: skip"
    done
}

log_begin() {
    printf "%-76s" "$TEST_NAME.$INC$CPU: $@... "
    INC=$(($INC+1))
}

log_end() {
    printf "$*\n"

    if [ "$*" = "Err" ]; then
        fail_count=$((fail_count + 1))
    elif [ "$*" = "skip" ]; then
        skip_count=$((skip_count + 1))
    else
        pass_count=$((pass_count + 1))
    fi
}

log_skip() {
    log_begin "$@"
    log_end "skip"
}

for_each_cpu() {
    cpu_func=$1
    shift 1

    for cpu in $cpus; do
        INC=0
        CPU=/$cpu
        $cpu_func $cpu $@
    done

    return 0
}

for_each_governor() {
    gov_cpu=$1
    gov_func=$2
    cpufreq_dirpath=$CPU_PATH/$gov_cpu/cpufreq
    governors=$(cat $cpufreq_dirpath/scaling_available_governors)
    shift 2

    for governor in $governors; do
        $gov_func $gov_cpu $governor $@
    done

    return 0
}

for_each_frequency() {
    freq_cpu=$1
    freq_func=$2
    cpufreq_dirpath=$CPU_PATH/$freq_cpu/cpufreq
    frequencies=$(cat $cpufreq_dirpath/scaling_available_frequencies)
    shift 2

    for frequency in $frequencies; do
        $freq_func $freq_cpu $frequency $@
    done

    return 0
}

set_governor() {
    gov_cpu=$1
    scaling_gov_dirpath=$CPU_PATH/$gov_cpu/cpufreq/scaling_governor
    newgov=$2

    echo $newgov > $scaling_gov_dirpath
}

get_governor() {
    gov_cpu=$1
    scaling_gov_dirpath=$CPU_PATH/$gov_cpu/cpufreq/scaling_governor

    cat $scaling_gov_dirpath
}

wait_latency() {
    wait_latency_cpu=$1
    cpufreq_dirpath=$CPU_PATH/$wait_latency_cpu/cpufreq
    gov=$(cat $cpufreq_dirpath/scaling_governor)

    # consider per-policy governor case
    if [ -e $CPU_PATH/$wait_latency_cpu/cpufreq/$gov ]; then
        #try one path to see if the sampling_rate can be found
        if [ -e $CPU_PATH/$wait_latency_cpu/cpufreq/$gov/sampling_rate ]; then
            sampling_rate=$(cat $CPU_PATH/$wait_latency_cpu/cpufreq/$gov/sampling_rate)
        else
            # try another path to get the sampling_rate
            if [ -e $CPU_PATH/cpufreq/$gov/sampling_rate ]; then
                sampling_rate=$(cat $CPU_PATH/cpufreq/$gov/sampling_rate)
            else
                return 1
            fi
        fi
    else
        return 1
    fi
    sampling_rate=$((sampling_rate * 1000)) # unit nsec

    latency=$(cat $cpufreq_dirpath/cpuinfo_transition_latency)
    if [ $? -ne 0 ]; then
        return 1
    fi

    nrfreq=$(cat $cpufreq_dirpath/scaling_available_frequencies | wc -w)
    if [ $? -ne 0 ]; then
        return 1
    fi

    nrfreq=$((nrfreq + 1))

    sleep_time=$(($latency + $sampling_rate))

    $NANOSLEEP $(($nrfreq * $sleep_time))
}

frequnit() {
    freq=$1
    ghz=$(echo $freq | awk '{printf "%.1f", ($1 / 1000000)}')
    mhz=$(echo $freq | awk '{printf "%.1f", ($1 / 1000)}')

    ghz_value=$(echo $ghz | awk '{printf "%f", ($1 > 1.0)}')
    if [ "$ghz_value" = "1" ]; then
        echo $ghz GHz
        return 0
    fi

    mhz_value=$(echo $mhz | awk '{printf "%f", ($1 > 1.0)}')
    if [ "$mhz_value" = "1" ];then
        echo $mhz MHz
        return 0
    fi

    echo $freq KHz
}

set_frequency() {
    freq_cpu=$1
    cpufreq_dirpath=$CPU_PATH/$freq_cpu/cpufreq
    newfreq=$2
    setfreqpath=$cpufreq_dirpath/scaling_setspeed

    echo $newfreq > $setfreqpath
    wait_latency $freq_cpu
}

get_frequency() {
    freq_cpu=$1
    scaling_cur_freq=$CPU_PATH/$freq_cpu/cpufreq/scaling_cur_freq
    cat $scaling_cur_freq
}

get_max_frequency() {
    freq_cpu=$1
    scaling_max_freq=$CPU_PATH/$freq_cpu/cpufreq/scaling_max_freq
    cat $scaling_max_freq
}

get_min_frequency() {
    freq_cpu=$1
    scaling_min_freq=$CPU_PATH/$freq_cpu/cpufreq/scaling_min_freq
    cat $scaling_min_freq
}

set_online() {
    current_cpu=$1
    current_cpu_path=$CPU_PATH/$current_cpu

    if [ "$current_cpu" = "cpu0" ]; then
        return 0
    fi

    echo 1 > $current_cpu_path/online
}

set_offline() {
    current_cpu=$1
    current_cpu_path=$CPU_PATH/$current_cpu

    if [ "$current_cpu" = "cpu0" ]; then
        return 0
    fi

    echo 0 > $current_cpu_path/online
}

get_online() {
    current_cpu=$1
    current_cpu_path=$CPU_PATH/$current_cpu

    cat $current_cpu_path/online
}

check() {
    check_descr=$1
    check_func=$2
    shift 2;

    log_begin "checking $check_descr"

    $check_func $@
    if [ $? -ne 0 ]; then
        log_end "Err"
        return 1
    fi

    log_end "Ok"

    return 0
}

check_file() {
    file=$1
    dir=$2

    check "'$file' exists in '$dir'" "test -f" $dir/$file
}

check_cpufreq_files() {
    cpu_id=$1
    cpufreq_files_dir=$CPU_PATH/$cpu_id/cpufreq
    shift 1

    for i in $@; do
        check_file $i $cpufreq_files_dir || return 1
    done

    return 0
}

check_sched_mc_files() {

    for i in $@; do
        check_file $i $CPU_PATH || return 1
    done

    return 0
}

check_topology_files() {
    cpu=$1
    topology_files_dir=$CPU_PATH/$cpu/topology
    shift 1

    for i in $@; do
        check_file $i $topology_files_dir || return 1
    done

    return 0
}

check_cpuhotplug_files() {
    cpuhotplug_files_dir=$CPU_PATH/$1
    shift 1

    for i in $@; do
        if [ `echo $cpuhotplug_files_dir | grep -c "cpu0"` -eq 1 ]; then
            if [ $hotplug_allow_cpu0 -eq 0 ]; then
                continue
            fi
        fi

        check_file $i $cpuhotplug_files_dir || return 1
    done

    return 0
}

save_governors() {
    index=0

    for cpu in $cpus; do
        scaling_gov_value=$(cat $CPU_PATH/$cpu/cpufreq/scaling_governor)
        eval $gov_array$index=$scaling_gov_value
        eval export $gov_array$index
        index=$((index + 1))
    done
}

restore_governors() {
    index=0

    for cpu in $cpus; do
        oldgov=$(eval echo \$$gov_array$index)
        echo $oldgov > $CPU_PATH/$cpu/cpufreq/scaling_governor
        index=$((index + 1))
    done
}

save_frequencies() {
    index=0

    for cpu in $cpus; do
        freq_value=$(cat $CPU_PATH/$cpu/cpufreq/scaling_cur_freq)
        eval $freq_array$index=$freq_value
        eval export $freq_array$index
        index=$((index + 1))
    done
}

restore_frequencies() {
    index=0

    for cpu in $cpus; do
        set_governor $cpu userspace
        oldfreq=$(eval echo \$$freq_array$index)
        echo $oldfreq > $CPU_PATH/$cpu/cpufreq/scaling_setspeed
        index=$((index + 1))
    done
}

sigtrap() {
    exit 255
}

# currently we support ubuntu and android
get_os() {
     build_prop_file="\system\build.prop"

     if [ ! -e "$build_prop_file" ]; then
        # for ubuntu
        return 1
     else
        # for android
        return 2
     fi
}

is_root() {
    get_os
    if [ $? -eq 1 ]; then
        # for ubuntu
        ret=$(id -u)
    else
        # for android
        ret=$(id | awk '{if ($1) print $1}' | sed 's/[^0-9]*//g')
    fi
    return $ret
}

is_cpu0_hotplug_allowed() {
    status=$1

    if [ $status -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

check_valid_temp() {
    file=$1
    zone_name=$2
    dir=$THERMAL_PATH/$zone_name

    temp_file=$dir/$file
    shift 2;

    temp_val=$(cat $temp_file)
    descr="'$zone_name'/'$file' ='$temp_val'"
    log_begin "checking $descr"

    if [ $temp_val -gt 0 ]; then
        log_end "Ok"
        return 0
    fi

    log_end "Err"

    return 1
}

for_each_thermal_zone() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    thermal_func=$1
    shift 1

    for thermal_zone in $thermal_zones; do
        INC=0
        $thermal_func $thermal_zone $@
    done

    return 0
}

get_total_trip_point_of_zone() {
    zone=$1
    zone_path=$THERMAL_PATH/$zone
    count=0
    shift 1
    trips=$(ls $zone_path | grep "trip_point_['$MAX_ZONE']_temp")
    for trip in $trips; do
        count=$((count + 1))
    done

    return $count
}

for_each_trip_point_of_zone() {
    zone_path=$THERMAL_PATH/$1
    count=0
    func=$2
    zone_name=$1
    shift 2
    trips=$(ls $zone_path | grep "trip_point_['$MAX_ZONE']_temp")
    for trip in $trips; do
        $func $zone_name $count
        count=$((count + 1))
    done

    return 0
}

for_each_binding_of_zone() {
    zone_path=$THERMAL_PATH/$1
    count=0
    func=$2
    zone_name=$1
    shift 2
    trips=$(ls $zone_path | grep "cdev['$MAX_CDEV']_trip_point")
    for trip in $trips; do
        $func $zone_name $count
        count=$((count + 1))
    done

    return 0

}

check_valid_binding() {
    trip_point=$1
    zone_name=$2
    dirpath=$THERMAL_PATH/$zone_name
    temp_file=$zone_name/$trip_point
    trip_point_val=$(cat $dirpath/$trip_point)
    get_total_trip_point_of_zone $zone_name
    trip_point_max=$?
    descr="'$temp_file' valid binding"
    shift 2

    log_begin "checking $descr"
    if [ $trip_point_val -ge $trip_point_max ]; then
        log_end "Err"
        return 1
    fi

    log_end "Ok"
    return 0
}

validate_trip_bindings() {
    zone_name=$1
    bind_no=$2
    dirpath=$THERMAL_PATH/$zone_name
    trip_point=cdev"$bind_no"_trip_point
    shift 2

    check_file $trip_point $dirpath || return 1
    check_valid_binding $trip_point $zone_name || return 1
}

validate_trip_level() {
    zone_name=$1
    trip_no=$2
    dirpath=$THERMAL_PATH/$zone_name
    trip_temp=trip_point_"$trip_no"_temp
    trip_type=trip_point_"$trip_no"_type
    shift 2

    check_file $trip_temp $dirpath || return 1
    check_file $trip_type $dirpath || return 1
    check_valid_temp $trip_temp $zone_name || return 1
}

for_each_cooling_device() {
    cdev_func=$1
    shift 1

    cooling_devices=$(ls $THERMAL_PATH | grep "cooling_device['$MAX_CDEV']")
    if [ "$cooling_devices" = "" ]; then
        log_skip "no cooling devices"
        return 0
    fi

    for cooling_device in $cooling_devices; do
        INC=0
        $cdev_func $cooling_device $@
    done

    return 0
}
check_scaling_freq() {
    before_freq_list=$1
    after_freq_list=$2
    shift 2
    index=0

    flag=0
    for cpu in $cpus; do
        after_freq=$(eval echo \$$after_freq_list$index)
        before_freq=$(eval echo \$$before_freq_list$index)

        if [ $after_freq -ne $before_freq ]; then
            flag=1
        fi

        index=$((index + 1))
    done

    return $flag
}

store_scaling_maxfreq() {
    index=0

    for cpu in $cpus; do
        scaling_freq_max_value=$(cat $CPU_PATH/$cpu/cpufreq/scaling_max_freq)
        eval $scaling_freq_array$index=$scaling_freq_max_value
        eval export $scaling_freq_array$index

        index=$((index + 1))
    done

    return 0
}

get_trip_id() {
    trip_name=$1
    shift 1

    id1=$(echo $trip_name|cut -c12)
    id2=$(echo $trip_name|cut -c13)
    if [ $id2 != "_" ]; then
        id1=$(($id2 + 10*$id1))
    fi

    return $id1
}

disable_all_thermal_zones() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    index=0

    for thermal_zone in $thermal_zones; do
        mode=$(cat $THERMAL_PATH/$thermal_zone/mode)
        eval $mode_array$index=$mode
        eval export $mode_array$index
        index=$((index + 1))
        echo -n "disabled" > $THERMAL_PATH/$thermal_zone/mode
    done

    return 0
}

enable_all_thermal_zones() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    index=0

    for thermal_zone in $thermal_zones; do
        mode=$(eval echo \$$mode_array$index)
        echo $mode > $THERMAL_PATH/$thermal_zone/mode
        index=$((index + 1))
    done

    return 0
}

GPU_HEAT_BIN=/usr/bin/glmark2
gpu_pid=0

check_for_glmark2() {
    glmark2_found=$(which glmark2)

    if [ $? -ne 0 ]; then
        return 1
    else
        return 0
    fi
}

start_glmark2() {
    if [ -n "$ANDROID" ]; then
        am start org.linaro.glmark2/.Glmark2Activity
        return
    fi

    if [ -x $GPU_HEAT_BIN ]; then
        $GPU_HEAT_BIN &
        gpu_pid=$(pidof $GPU_HEAT_BIN)
        # Starting X application from serial console needs this
        if [ -z "$gpu_pid" ] && [ -f "/etc/lightdm/lightdm.conf" ]; then
            cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.bk
            echo "autologin-user=root" >> /etc/lightdm/lightdm.conf
            export DISPLAY=localhost:0.0
            restart lightdm
            sleep 5
            mv /etc/lightdm/lightdm.conf.bk /etc/lightdm/lightdm.conf
            $GPU_HEAT_BIN &
            gpu_pid=$(pidof $GPU_HEAT_BIN)
        fi

        if [ -z "$gpu_pid" ]; then
            gpu_pid=0
            echo "failed to start gpu heat binary"
        else
            echo "start gpu heat binary $gpu_pid"
        fi
    else
        echo "glmark2 not found." 1>&2
    fi
}

kill_glmark2() {
    if [ -n "$ANDROID" ]; then
        am kill org.linaro.glmark2
        return
    fi

    if [ "$gpu_pid" -ne 0 ]; then
        kill -9 $gpu_pid
    fi
}

set_thermal_governors() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    gov=$1
    index=0

    for thermal_zone in $thermal_zones; do
        policy=$(cat $THERMAL_PATH/$thermal_zone/policy)
        eval $thermal_gov_array$index=$policy
        eval export $thermal_gov_array$index
        index=$((index + 1))
        echo $gov > $THERMAL_PATH/$thermal_zone/policy
    done

    return 0
}

restore_thermal_governors() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']")
    index=0

    for thermal_zone in $thermal_zones; do
        old_policy=$(eval echo \$$thermal_gov_array$index)
        echo $old_policy > $THERMAL_PATH/$thermal_zone/policy
        index=$((index + 1))
    done

    return 0
}

check_for_thermal_zones() {
    thermal_zones=$(ls $THERMAL_PATH | grep "thermal_zone['$MAX_ZONE']" 2>/dev/null)
    if [ ! -z "$thermal_zones" ]; then
        return 0
    else
        return 1
    fi
}

check_logdir() {
    if [ ! -f $LOGDIR ]; then
        mkdir -p $LOGDIR
    fi
}

setup_wakeup_timer() {
        timeout="$1"

        # Request wakeup from the RTC or ACPI alarm timers.  Set the timeout
        # at 'now' + $timeout seconds.
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

suspend_system() {
        if [ "$dry" -eq 1 ]; then
                echo "DRY-RUN: suspend machine for $timer_sleep"
                sleep 1
                return
        fi

        setup_wakeup_timer "$timer_sleep"

        dmesg >"$LOGFILE.dmesg.A"

        # Initiate suspend in different ways.
        case "$1" in
                dbus)
                        dbus-send --session --type=method_call \
                        --dest=org.freedesktop.PowerManagement \
                        /org/freedesktop/PowerManagement \
                        org.freedesktop.PowerManagement.Suspend \
                        >> "$LOGFILE" || {
                                ECHO "FAILED: dbus suspend failed" 1>&2
                                return 1
                        }
                ;;
                pmsuspend)
                        pm-suspend >> "$LOGFILE"
                ;;
                mem)
                        `echo "mem" > /sys/power/state` >> "$LOGFILE"
                ;;
        esac

        # Wait on the machine coming back up -- pulling the dmesg over.
        echo "v---" >>"$LOGFILE"
        retry=30
        while [ "$retry" -gt 0 ]; do
                retry=$((retry - 1))

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
                ECHO "SUSPEND FAILED, did not go to sleep" 1>&2
                return 1
        fi
}

ECHO() {
        echo "$@" | tee -a "$LOGFILE"
}

enable_trace() {
        if [ -w /sys/power/pm_trace ]; then
                echo 1 > '/sys/power/pm_trace'
        fi
}

disable_trace() {
        if [ -w /sys/power/pm_trace ]; then
                echo 0 > '/sys/power/pm_trace'
        fi
}

trace_state=-1

save_trace() {
        if [ -r /sys/power/pm_trace ]; then
                trace_state=`cat /sys/power/pm_trace`
        fi
}

restore_trace() {
        if [ "$trace_state" -ne -1 -a -w /sys/power/pm_trace ]; then
                echo "$trace_state" > '/sys/power/pm_trace'
        fi
}

battery_count() {
        cat /proc/acpi/battery/*/state 2>/dev/null | \
        awk '
                BEGIN                   { total = 0 }
                /present:.*yes/         { total += 1 }
                END                     { print total }
        '
}

battery_capacity()
{
        cat /proc/acpi/battery/*/state 2>/dev/null | \
        awk '
                BEGIN                   { total = 0 }
                /remaining capacity:/   { total += $3 }
                END                     { print total }
        '
}

ac_needed=-1
ac_is=-1
ac_becomes=-1

ac_required() {
        ac_check

        ac_needed="$1"
        ac_becomes="$1"
}

ac_transitions() {
        ac_check

        ac_needed="$1"
        ac_becomes="$2"
}

ac_online() {
        cat /proc/acpi/ac_adapter/*/state 2>/dev/null | \
        awk '
                BEGIN                   { online = 0; offline = 0 }
                /on-line/               { online = 1 }
                /off-line/              { offline = 1 }
                END                     {
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

ac_check() {
        ac_current=`ac_online`

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

phase() {
        phase=$((phase + 1))

        if [ "$ac_needed" -ne "$ac_is" ]; then
                case "$ac_needed" in
                0) echo "*** please ensure your AC cord is detached" ;;
                1) echo "*** please ensure your AC cord is attached" ;;
                esac
                ac_is="$ac_needed"
        fi

        if [ "$timer_sleep" -gt 60 ]; then
                sleep="$timer_sleep / 60"
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

save_trace

if [ "$pm_trace" -eq 1 ]; then
        enable_trace
else
        disable_trace
fi
