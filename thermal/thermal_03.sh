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

# URL : https://wiki.linaro.org/WorkingGroups/PowerManagement/Resources/TestSuite/PmQaSpecification#thermal_03

. ../include/functions.sh

CPU_HEAT_BIN=../utils/heat_cpu
cpu_pid=""

heater_kill() {
    if [ "$cpu_pid" ]; then
	kill -9 $cpu_pid
    fi
    kill_glmark2
}

check_temperature_change() {
    dirpath=$THERMAL_PATH/$1
    zone_name=$1
    shift 1

    init_temp=$(cat $dirpath/temp)
    $CPU_HEAT_BIN &

    get_os
    if [ $? -eq 1 ]; then
        cpu_pid=$(ps | grep heat_cpu| awk '{print $1}')
    else
        cpu_pid=$(ps | grep heat_cpu| awk '{print $2}')
    fi
    if [ -z "$cpu_pid" ]; then
        echo "failed to start cpu heat binary"
        return
    fi
    echo "start cpu heat binary"

    start_glmark2

    sleep 5
    final_temp=$(cat $dirpath/temp)
    heater_kill
    check "temperature variation with load" "test $final_temp -gt $init_temp"
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
       for_each_thermal_zone check_temperature_change
    fi
fi
test_status_show
