#!/usr/bin/env bash
###
# Map Wine's logical CPUs onto the CPUs this container may use.
#
# Wine/Proton pass Windows thread-affinity masks straight through as host CPU
# numbers. With a restricted cpuset (e.g. `cpuset: 8-15,24-31` in the compose),
# a mask such as "CPU 1" names a CPU the container can't use, and
# SetThreadAffinityMask fails. Launchers that start a worker pinned that way
# and wait for it never get past the start - DOAXVV's launcher stays a grey
# window forever. WINE_CPU_TOPOLOGY makes Wine present exactly the allowed CPUs
# as logical CPUs 0..n-1.
#
# Computed at every container start, so it follows cpuset changes. Nothing is
# set when all CPUs are allowed, or when WINE_CPU_TOPOLOGY is already set (a
# value from the compose or a per-game launch option wins).
#
# Exported here because entrypoint.sh sources the cont-init scripts and then
# execs supervisord: every program - desktop session, Steam, Sunshine -
# inherits it. cont-init scripts are sourced - never `exit` here.
###

wine_cpu_topology() {
    local allowed part first last cpu list="" count=0
    allowed="$(awk '$1 == "Cpus_allowed_list:" { print $2 }' /proc/self/status)"
    [ -n "${allowed}" ] || return 0
    for part in ${allowed//,/ }; do
        first="${part%-*}"
        last="${part#*-}"
        for ((cpu = first; cpu <= last; cpu++)); do
            list="${list:+${list},}${cpu}"
            count=$((count + 1))
        done
    done
    [ "${count}" -gt 0 ] && [ "${count}" -lt "$(nproc --all)" ] || return 0
    echo "${count}:${list}"
}

print_header "Configure Wine CPU topology"

if [ -n "${WINE_CPU_TOPOLOGY:-}" ]; then
    print_step_header "WINE_CPU_TOPOLOGY already set: ${WINE_CPU_TOPOLOGY}"
else
    wine_topology="$(wine_cpu_topology)"
    if [ -n "${wine_topology}" ]; then
        export WINE_CPU_TOPOLOGY="${wine_topology}"
        print_step_header "Container is limited to ${wine_topology%%:*} of $(nproc --all) CPUs - WINE_CPU_TOPOLOGY=${WINE_CPU_TOPOLOGY}"
    else
        print_step_header "All CPUs available - WINE_CPU_TOPOLOGY not needed"
    fi
    unset wine_topology
fi
unset -f wine_cpu_topology
