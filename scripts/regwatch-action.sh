#!/bin/bash

declare -r TOKEN="ndT1LkaJP6SgIfj2FdkUo1E7tSXgoU"
declare -ra LOGGER=("/usr/bin/logger" "-t" "${0##*/}($$)" "--")

declare -a sendto=("leonid.isaev@ifax.com")
declare t

t="$(/usr/bin/cat -)"

if [[ "$t" != "$TOKEN" ]]; then
	"${LOGGER[@]}" \
		"Unauthorized connection attempt with token \"${t}\""
	exit 1
fi

echo -E "Please check your server..." | /usr/bin/mail -s \
    "SIP registration failed on \"$(/usr/bin/date)\" on host \"${HOSTNAME}\"" \
	"${sendto[@]}" 2>&1 | "${LOGGER[@]}"
