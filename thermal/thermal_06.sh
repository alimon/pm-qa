#!/bin/sh
#
# PM-QA validation test suite for the power management on Linux
#
# Copyright (C) 2011, Linaro Limited.
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
# Contributors:
#     Amit Daniel <amit.kachhap@linaro.org> (Samsung Electronics)
#       - initial API and implementation
#

# URL : https://wiki.linaro.org/WorkingGroups/PowerManagement/Resources/TestSuite/PmQaSpecification#thermal_06

. ../include/functions.sh

TEST_LOOP=100
CPU_HEAT_BIN=../utils/heat_cpu
cpu_pid=0
trip_cross_array="trip_cross"

heater_kill() {
    if [ $cpu_pid -ne 0 ]; then
	kill -9 $cpu_pid
    fi
    kill_glmark2
}

check_trip_point_change() {
    zone_name=$1
    dirpath=$THERMAL_PATH/$zone_name
    shift 1

    count=0
    cur_temp=0
    trip_temp=0
    trip_type=0
    trip_type_path=0
    $CPU_HEAT_BIN &
    get_os
    if [ $? -eq 1 ]; then
        cpu_pid=$(ps | grep heat_cpu| awk '{print $1}')
    else
        cpu_pid=$(ps | grep heat_cpu| awk '{print $2}')
    fi

    test -z $cpu_pid && cpu_pid=0
    check "start cpu heat binary" "test $cpu_pid -ne 0"
    test $cpu_pid -eq 0 && return

    start_glmark2

    index=0

    trip_point_temps=$(ls $thermal_zone_path | grep "trip_point_['$MAX_ZONE']_temp")

    for trip in $trip_point_temps; do
        trip_value=0
        eval $trip_cross_array$index=$trip_value
        eval export $trip_cross_array$index
        index=$((index + 1))
    done

    while (test $count -lt $TEST_LOOP); do
	    index=0
	    sleep 1

        for trip in $trip_point_temps; do
            cur_temp=$(cat $thermal_zone_path/temp)
            trip_temp=$(cat $thermal_zone_path/$trip)
	    
            if [ $cur_temp -gt $trip_temp ]; then
                value=$(eval echo \$$trip_cross_array$index)
                value=$((value + 1))
                eval $trip_cross_array$index=$value
                eval export $trip_cross_array$index
            fi

            index=$((index + 1))
	    done

	    count=$((count + 1))
    done

    index=0
    for trip in $trip_point_temps; do	
        get_trip_id $trip
	    trip_id=$?
	    trip_type=$(cat $thermal_zone_path/trip_point_"$trip_id"_type)
        trip_temp=$(cat $thermal_zone_path/$trip)

	    if [ $trip_type != "critical" ]; then
	        count=$(eval echo \$$trip_cross_array$index)
	        check "$trip:$trip_temp crossed" "test $count -gt 0"
	    fi
	
        index=$((index + 1))
    done

    heater_kill
}

trap "heater_kill; sigtrap" HUP INT TERM

check_for_thermal_zones
if [ $? -ne 0 ]; then
   log_skip "No thermal zones found"
else
    check_for_glmark2
    if [ $? -ne 0 ]; then
        log_skip "glmark2 not found"
    else
        for_each_thermal_zone check_trip_point_change
    fi
fi
test_status_show
