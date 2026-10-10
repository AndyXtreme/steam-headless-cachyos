#!/usr/bin/env bash
###
# Replaces upstream 11-setup_sysctl_values.sh: report kernel parameters, never
# write them.
#
# vm.max_map_count is not namespaced - writing it from this privileged
# container changes it for the whole host. Upstream's check was also inverted:
# it wrote 524288 whenever the host value was already >= 524288, so it could
# only ever lower the host's setting. If a game needs more, set it on the host
# (TrueNAS: System > Advanced Settings > Sysctl).
###

print_header "Check kernel parameters (read-only)"

max_map_count="$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)"
if [ "${max_map_count}" -ge 524288 ]; then
    print_step_header "vm.max_map_count is ${max_map_count}"
else
    print_warning "vm.max_map_count is ${max_map_count} - some games need at least 524288. Set it on the host; the container leaves it alone"
fi

echo -e "\e[34mDONE\e[0m"
