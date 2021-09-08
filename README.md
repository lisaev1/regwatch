# Regwatch

## Table of contents
1. Description
1. Requirements
2. License

## Description

This is a simple script which notifies an admin of situations when registration
with a SIP proxy has expired.

In more detail: some SIP trunks require clients to periodically send REGISTER
packets using appropriate credentials. The proxy confirms successful
registration by a `200 OK` packet which contains an expiration interval (in
seconds). Ideally, the client re-registers right before this interval ends, to
be able to receive inbound calls without interruptions.

The present tool is supposed to sound an alarm when this renewal does not
happen. We capture inbound `200 OK` packets with `tcpdump`, parse them for the
expiration interval, and start a timer which counts down this timeout.

If the next `200 OK` is received before expiration, the current timer is
killed, a new one is armed, and the above process is repeated. Otherwise, the
timer expires and triggers an action by sending a request to a tcp port.

There are two versions: bash and python3. The former is there only for
reference and historical reasons -- in production please use the python script.

There are currently no config files or cmdline options: configuration is inside
the program. Specifically, one needs to provide: a BPF filter for `tcpdump`,
network interface to sniff on (e.g. `ens4` or `any`), and a tuple `(hostname,
port)` where to send the request once the timer expires.

The tcp listening socket is maintained by `systemd`. Once the latter receives a
request, it executes an action script `scripts/regwatch-action.sh`.

## Requirements

`tcpdump`, `bash`, `python3`, `systemd`

## License

GPLv3
