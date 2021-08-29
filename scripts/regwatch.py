import re, subprocess, threading, signal, socket

# -----------------------------------------------------------------------------
# Configuration -- don't edit beyond this section
# -----------------------------------------------------------------------------

DBG = True
BPF_FILTER = "udp and (dst host 192.168.122.43) and (dst port 5060)"

#-- tuple (action host, action port)
ACTION_HP = ("localhost", 13000)

# -----------------------------------------------------------------------------
# Parameters
# -----------------------------------------------------------------------------

#-- tcpdump(1) cmdline
TCPDUMP_CMD = ["/usr/sbin/tcpdump", "-Annlti", "ens4", \
	"--immediate-mode", "-s", "768", BPF_FILTER]

#-- regex's to match packets against
RE_200_OK = re.compile(r"^IP .*200 OK$")
RE_REGISTER = re.compile(r"^.*\|CSeq:.*REGISTER\|")
RE_EXP = re.compile(r"\|Contact.*;expires=([0-9]{1,});")

#-- token for the action script
ACTION_TOKEN = "ndT1LkaJP6SgIfj2FdkUo1E7tSXgoU".encode("ascii")

# -----------------------------------------------------------------------------
# Functions and classes
# -----------------------------------------------------------------------------

class CleanUp:
    """
    A generic signal handler that gracefully terminates the program
    """
    killnow = False

    def __init__(self):
        signal.signal(signal.SIGINT, self.cleanup)
        signal.signal(signal.SIGTERM, self.cleanup)

    def cleanup(self, s, f):
        print("Received signal {}, finishing...".format(s))
        self.killnow = True


def timer_action():
    """
    Execute action when the timer expires
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.settimeout(10.0)
            s.connect(ACTION_HP)
            s.sendall(ACTION_TOKEN)
        except socket.error as err:
            print("Couldn't connect to {}: {}".format(ACTION_HP, err))

    print("Timer elapsed")


# -----------------------------------------------------------------------------
# Main program
# -----------------------------------------------------------------------------

#-- establish a SIGTERM handler
killer = CleanUp()

#-- start tcpdump(1)
t_pipe = subprocess.Popen(TCPDUMP_CMD, stdout=subprocess.PIPE,
	stderr=subprocess.PIPE)

#-- main loop
p = timer = ""
while not killer.killnow:
    l = t_pipe.stdout.readline().decode("us-ascii", errors = "ignore")[:-1]

    if RE_200_OK.match(l):
        p = "|"
    if (len(p) > 0):
        p += "|" + l

    if ((len(l) == 0) and (len(p) > 0)):
        t = -1
        if RE_REGISTER.match(p):
            if DBG: print("Got 200 OK REGISTER packet: ", p)

            t = RE_EXP.search(p).group(1)
            if t:
                try:
                    t = int(t)
                except ValueError:
                    t = -1
            else:
                t = -1

            if DBG: print("Timeout: {} sec".format(t))

            if (isinstance(timer, threading.Timer) and
                    timer.isAlive() and (t > 0)):
                timer.cancel()
                if DBG: print("Timer canceled", timer)

        p = ""
        if (t > 0):
            timer = threading.Timer(1.1 * t , timer_action)
            timer.start()
            if DBG: print("Timer armed", timer)


#-- cleanup
if (isinstance(timer, threading.Timer) and timer.isAlive()):
    timer.cancel()
print("Done")
