#!/bin/bash
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

# URL : https://wiki.linaro.org/WorkingGroups/PowerManagement/Doc/QA/Scripts#thermal_03

source ../include/functions.sh
source ../include/thermal_functions.sh

CPU_HEAT_BIN=../utils/heat_cpu
GPU_HEAT_BIN=glmark2

check_temperature_change() {
    local dirpath=$THERMAL_PATH/$1
    local zone_name=$1
    shift 1

    local cpu_pid=0
    local gpu_pid=0
    local init_temp=$(cat $dirpath/temp)
    $CPU_HEAT_BIN &
    cpu_pid=$(ps | grep heat_cpu| awk '{print $1}')
    check "start cpu heat binary" "test $cpu_pid -ne 0"

    $GPU_HEAT_BIN &
    gpu_pid=$(ps | grep $GPU_HEAT_BIN| awk '{print $1}')
    check "start gpu heat binary" "test $gpu_pid -ne 0"
    sleep 5
    local final_temp=$(cat $dirpath/temp)
    if [ $cpu_pid -ne 0 ]; then
	kill -9 $cpu_pid
    fi
    if [ $gpu_pid -ne 0 ]; then
	kill -9 $gpu_pid
    fi
    check "temperature variation with load" "test $final_temp -gt $init_temp"
}

for_each_thermal_zone check_temperature_change