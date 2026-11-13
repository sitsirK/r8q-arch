#!/bin/bash
# r8q: keep every CPU out of the idle loop. EXPERIMENTAL -- this is not a fix for the CPU
# wedge and there is no measurement showing that it prevents one. See INSTALLATION.md §11.
#
# BACKGROUND. On this device a core occasionally stops executing while the others carry on:
#
#   rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
#   rcu:   5-...0: (1 GPs behind) idle=2344/1/0x4000000000000000 softirq=59911/59914
#   Sending NMI from CPU 6 to CPUs 5:      <- no backtrace comes back
#
# This script was written for the theory that a core sitting in WFI misses its wake-up, so
# that idle ENTRY is what is unsafe. That theory is wrong:
#   - the one function trace of a dying core ends in the cpuidle governor (menu_select),
#     before WFI is reached, and the dead core does not answer an NMI either -- it has
#     stopped, it is not waiting for an interrupt;
#   - idle-entry rate is not the trigger: ~15 million forced idle entries in 75 s did not
#     wedge the phone;
#   - for the same reason a periodic per-CPU timer "heartbeat" does not help: cores have died
#     with a pinned thread waking each of them every 10 ms.
#
# WHY IT IS STILL HERE. The traced death did happen on the way into idle, and spinners keep
# the cores out of that path. So it remains a cheap experiment -- nothing more. Earlier claims
# in this file that it "carried a 220-crate build to completion" should not be trusted: the
# installed copy was later found corrupt, so it had most likely never run.
#
# WHAT IT DOES. A SCHED_IDLE task is only picked when a CPU would otherwise have nothing to
# run, so one pinned per core means the idle loop is almost never entered, while real work
# keeps 100% of the CPU. Measured: WFI entries across all 8 cores drop from ~300/s to ~4/s.
#
# COST. No core ever sleeps -> constant power draw and heat. Never run it as a boot service.
set -u

ncpu=$(nproc)
pids=()

cleanup() {
	[ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null
	exit 0
}
trap cleanup EXIT INT TERM

for ((c = 0; c < ncpu; c++)); do
	chrt --idle 0 taskset -c "$c" bash -c 'while :; do :; done' &
	pids+=($!)
done

echo "r8q-noidle: $ncpu SCHED_IDLE spinners pinned (cpu0-$((ncpu - 1)))"
wait
