#!/bin/bash

declare -a sendto=("leonid.isaev@ifax.com")
declare t

t="$(/usr/bin/cat -)"

echo -E "Please check your server..." | /usr/bin/mail -s \
	"SIP registration failed at $t on host \"$(hostname)\"" \
	"${sendto[@]}" 2>&1 | \
	/usr/bin/logger -t "regwatch-action" --
