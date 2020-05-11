#!/bin/bash

set -o errexit
set -o nounset

trap "trap - SIGTERM && cleanup" SIGTERM

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

	#-- send the current date/time to a socket
	/usr/bin/date -u | /usr/bin/ncat "${REMOTE[@]}" 2>&1 | "${LOGGER[@]}"
}

cleanup() {
        echo -E "Quitting"
        kill -- -$$
}

# -----------------------------------------------------------------------------
# Parameters
# -----------------------------------------------------------------------------

declare -r FILTER="udp and (dst host 10.0.1.80) and (dst port 5060)" \
	DBG="yes"
declare -ra LOGGER=("/usr/bin/logger" "-t" "${0##*/}" "--")

# -----------------------------------------------------------------------------
# Main program
# -----------------------------------------------------------------------------

declare s l t t_pid
declare -a REMOTE a

#-- check input
if (( $# != 1 )); then
        echo -E "Wrong # of arguments, expecting only one of the form IP:PORT"
        exit 1
fi

IFS=":" read -ra REMOTE <<< "$1"
if (( REMOTE[1] == 0 )); then
        echo -E "Bad port number (${REMOTE[1]:-<empty>})"
        exit 1
fi

IFS="." read -ra a <<< "${REMOTE[0]}"
if (( ${#a[@]} < 4 )); then
        echo -E "Bad IP address (${REMOTE[0]:-<empty>})"
        exit 1
fi
for (( s = 0; s < ${#a[@]}; ++s )); do
        if (( a[s] == 0 )); then
                echo -E "Bad IP address (${REMOTE[0]:-<empty>})"
                exit 1
        fi
done

#-- start the watcher
s=""
t_pid=""
while read -r l; do
	#-- collect headers for each "200 OK" packet
	[[ "$l" =~ ^IP\ .*200\ OK$ ]] && s="|"
	[[ -n "$s" ]] && s="${s}|$l"

	#-- end of packet reached - parse collected headers
	if [[ -z "$l" && -n "$s" ]]; then
		[[ "$DBG" == "yes" ]] && "${LOGGER[@]}" "Got packet: $s"

		t=""
		if [[ "$s" =~ \|CSeq:.*REGISTER\| ]]; then
			if [[ "$s" =~ \;expires=([0-9]{1,})\; ]]; then
				t="${BASH_REMATCH[1]}"

				#-- disable the timer if armed
				if [[ -n "$t_pid" && -d "/proc/$t_pid" ]]; then
					[[ "$DBG" == "yes" ]] && \
						"${LOGGER[@]}" "Stop timer $!"

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

			[[ "$DBG" == "yes" ]] && \
				"${LOGGER[@]}" "Start timer $!"
		fi
	fi
done < <(tcpdump -Annlti eth0 --immediate-mode -s 768 "$FILTER" 2> /dev/null)
