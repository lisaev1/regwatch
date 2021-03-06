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

	trap 'exec {f}<&-; return 1' TERM

	exec {f}<> <(:)
	"${LOGGER[@]}" "snore(): using fd $f"

	read -t "$t" -u "$f" || :
	exec {f}<&-
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
		snore "$(( e + e / 10 ))" || return 0
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
declare -ra LOGGER=("/usr/bin/logger" "-t" "${0##*/}($$)" "--")

# -----------------------------------------------------------------------------
# Main program
# -----------------------------------------------------------------------------

declare s l t t_pid
declare -a REMOTE a

#-- check input
if (( $# != 1 )); then
        "${LOGGER[@]}" \
		"Wrong # of arguments, expecting only one of the form IP:PORT"
        exit 1
fi

IFS=":" read -ra REMOTE <<< "$1"
if [[ ! "${REMOTE[1]:-}" =~ ^[0-9]{2,5}$ ]]; then
        "${LOGGER[@]}" "Bad port number (${REMOTE[1]:-<empty>})"
        exit 1
fi

IFS="." read -ra a <<< "${REMOTE[0]}"
if (( ${#a[@]} != 4 )); then
        "${LOGGER[@]}" "Bad IP address (${REMOTE[0]:-<empty>})"
        exit 1
fi
for s in "${a[@]}"; do
	if [[ "$s" =~ ^[0-9]{1,3}$ ]] && (( s < 255 )); then
		continue
	fi
	"${LOGGER[@]}" "Bad IP address (${REMOTE[0]:-<empty>})"
	exit 1
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
			"${LOGGER[@]}" "REGISTER packet: $s"

			if [[ "$s" =~ \;expires=([0-9]{1,})\; ]]; then
				t="${BASH_REMATCH[1]}"

				#-- disable the timer if armed
				if [[ -n "$t_pid" ]]; then
					"${LOGGER[@]}" "Stopping timer $t_pid"

					kill -- %arm_timer 2>&1 | \
						"${LOGGER[@]}"
					(( ${PIPESTATUS[0]} == 0 )) && \
						"${LOGGER[@]}" "... killed"
					t_pid=""
				fi
			fi
		fi
		s=""

		if [[ -n "$t" ]]; then
			#-- arm the timer for 1.1 * t sec
			arm_timer "$t" &
			t_pid="$!"

			"${LOGGER[@]}" "Started timer $t_pid"
		fi
	fi
done < <(tcpdump -Annlti eth0 --immediate-mode -s 768 "$FILTER" 2> /dev/null)
