#!/bin/bash

#set -x

trap "cleanup" SIGTERM 

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Bash implementation of sleep(1)
# https://blog.dhampir.no/content/sleeping-without-a-subprocess-in-bash-and-how-to-sleep-forever
#
# Input:
#	$1 -- time to sleep
# Returns:
#	None
snore() {
	local f="" t="$1"

	[[ -z "$f" ]] && exec {f}<> <(:)
	read -t "$t" -u "$f" || :
}

# Watchdog timer that executes a command after a timeout
#
# Input:
#	$1 -- registration expiration time
# Returns:
#	None
arm_timer() {
	local -i e="$1"

	if (( e > 0 )); then
		snore "$(( e + e / 10 ))"
	else
		return 1
	fi

        logger -t -- "$(date)"
}

cleanup() {
        echo -E "Quitting"
        kill -- -$$
}

# -----------------------------------------------------------------------------
# Main program
# -----------------------------------------------------------------------------

declare -r filter="udp and (dst host 10.0.1.80) and (dst port 5060)"
declare s l t t_pid

s=""
t_pid=""
echo -E ">>> $$"
while read -r l; do
	#echo -E "$l"

	#-- collect headers for each "200 OK" packet
	[[ "$l" =~ ^IP\ .*200\ OK$ ]] && s="|"
	[[ -n "$s" ]] && s="${s}|$l"

	#-- end of packet reached - parse collected headers
	if [[ -z "$l" && -n "$s" ]]; then
		t=""
		echo -E ">>> $s"
		if [[ "$s" =~ \|CSeq:.*REGISTER\| ]]; then
			if [[ "$s" =~ \;expires=([0-9]{1,})\; ]]; then
				t="${BASH_REMATCH[1]}"

				#-- disable the timer if armed
				if [[ (-n "$t_pid") && (-d "/proc/$t_pid") ]]; then
					echo -E ">>> Stop the timer at $! on $(date)"
					kill -- "$t_pid" 2> /dev/null
					t_pid=""
				fi
			fi
		fi
		s=""

		if [[ -n "$t" ]]; then
			#-- arm the timer for 1.1 * t sec
			arm_timer "$t" &
			t_pid="$!"

			echo -E ">>> Arming timer with pid $! for ~$t sec on $(date)..."
		fi
	fi
done < <(tcpdump -Annti eth0 --immediate-mode -l -s 768 "$filter" 2> /dev/null)
