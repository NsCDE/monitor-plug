**Monitor Plug**

This is Linux only (not portable) udev(7) triggered script for configuring
multiple or single monitor setup for X11 based on recognized monitor
names, EDID and resolution modes data from /sys/class/drm/cardX entries
on the Linux sysfs filesystem which is mounted on /sys.


How it works

This script has two modes of operation:
 - collection mode (-s <name>)
 - configuration mode (-c <card>)

In the collection mode it will find all connected monitors on the system,
take their EDID data SHA-256 hash, or resolution mode hash if EDID
information is empty or otherwise not readable. It will join this binary
data, and calculate SHA-256 hash of this concentrated data. Then, it will
try to find device names (in C locale order) in the configuration text
database /etc/opt/monitor-plug/monitordb.txt which itself has this format

- configuration name
- comma separated list of monitors as seen by the Linux kernel, not xrandr
- SHA-256 hash
- flag

For every monitor combination values above are concentrated in one line,
separated by a space. Configuration name is also the name of the script
which runs xrandr and/or whatever is put in it. This script exists as
/etc/opt/monitor-plug/scripts/<configuration-name>.sh. List of monitors
is a list of all connected monitors on the system which are expected.
Their names are similar, but a bit different from the names which
xrandr(1) presents on the output.

When monitor-plug.sh is run by the udev rule (see example udev rule file
96-monitor-hotplug.rules.example), it will collect data about monitor
names hashes of their EDID or resolution modes data, and compare this
with configuration lines in the /etc/opt/monitor-plug/monitordb.txt.
If there is a match, script named by configuration name will be run
from the scripts/ subdirectory of the /etc/opt/monitor-plug. In this
scripts, xrandr command line, created manually or with arandr(1) will
be run to configure monitors in the way user desires for this setup.
This scripts can do any other things, but be careful not to overbloat
them with unnecessary or inappropriate actions.

Presently, there are two types of flags: Builtin and External. For
line with Builting flag, less internal checks and rules will be
applied. This line should have configuration name "Default" usually
and hash of the single (notebook builtin) monitor. All other monitor
combinations (cloned, builtin disconnected, external connected, all
connected ...) should have a flag External.


Who needs this

People who have multiple monitor and projector devices at home, on job,
etc ... and are tired to configure manually or with a place based script
every time they connect some DisplayPort, HDMI, VGA, DVI or other cable
in their laptop.
It is probably not needed for static stable configurations where nothing
gets often reconnected and definitely not for single monitor machines.


How to populate monitordb.txt

Connect all monitors you want and turn on and off to get desirable state.
Run "monitor-plug.sh -s <name>" to generate configuration line which
contains C locale ordered and comma separated Linux monitor names and
EDID or modes hashed data. Put this line into monitordb.txt.

Example:

\# monitor-plug.sh -s HomeOffice\
LOG: local0.info monitor-plug.sh: Monitor /sys/class/drm/card0/card0-HDMI-A-1 is connected, taking it into calculation.
LOG: local0.info monitor-plug.sh: Monitor /sys/class/drm/card0/card0-eDP-1 is connected, taking it into calculation.

Configuration line for current layout to be written in /etc/opt/monitor-plug/monitordb.txt:

Office HDMI-A-1,eDP-1 88bfce976725d8f22d60a460091ef3c022f592cfddcfde5b39fef560df179c3a External


How to install and start

- Put monitor-plug.sh someware in your PATH and make it executable
- Inspect 96-monitor-hotplug.rules.example and put it in
  /etc/udev/rules.d omitting ".example" from the end of file name.
- Optional: uncomment atd(8) based rule if you are not using systemd(1)
  and comment out systemd based rule. Make sure you have atd service
  installed and running
- Copy monitor-plug.service into /etc/systemd/system and edit to suit
  if using systemd instead of atd
- mkdir -p /etc/opt/monitor-plug/scripts
- Unplug all apart from built in or primary monitor
- monitor-plug.sh -s Default > /etc/opt/monitor-plug/monitordb.txt
- Do "systemctl daemon-reload" if using systemd instead of atd
- If you are using atd instead of systemd, make sure atd is enabled
  and running on your system 
- udevadm trigger
- Write xrandr(1) scripts and put them as executables in directory
  /etc/opt/monitor-plug/scripts name them Default.sh and whatever
  other configurations you generated with "-s <name>".
- Play with cables and see if it works


Misc facts

- Script monitor-plug.sh logs into local0 syslog facility if it was not
  run from the terminal. Otherwise, log lines are visible on stderr. In
  collection mode (which is interactive) it will always log on stderr of
  the attached tty device.

- This script depends on the Linux sysfs, EDID data of the monitor or
  resolition modes, combined with device names. If kernel for some
  reason is not providing either EDID or modes in the
  /sys/class/drm/cardX/cardX-DEVNAME-X/{edid,modes}, this will not
  work unfortunately. Luckily, even KVM virtualized displays are
  providing at least modes information.

- All pain with the systemd(1) or atd(8) is due to the fact that
  udev(7) will kill all long running programs run with the RUN argument
  even if backgrounded and disowned - udev will find them and kill

- DISPLAY and XAUTHORITY variables are essential for configuration
  based scripts to work if they are calling X11 based programs.
  Program xrandr(1) is one of them. DISPLAY is assumed to be :0,
  while w(1) is used to inspect who is logged on the DISPLAY :0 and
  to find it's home directory with getent, and then .Xauthority file.
  If this fails, X11 based programs will not work if called from
  configuration based scripts in the /etc/opt/monitor-plug/scripts.
  Both DISPLAY and XAUTHORITY can be set or overriden in the udev rule
  file. For example:

  ENV{DISPLAY}=":0", ENV{XAUTHORITY}="/home/user2/.Xauthority"

  See udev(7) documentation if you want to customize udev rules example
  provided with monitor-plug.

  If called from atd or systemd, DISPLAY and XAUTHORITY must be set in
  the monitor-plug.service unit file, overlayed with "systemctl edit",
  or provided to atd(8) by other means.

- Because kernel can trigger DRM event twice sometimes, or cable can
  quickly go in and out, script implements internal locking mechanism
  to avoid running multiple instances in the same time.

- This operates on the system level and is run under the root privileges,
  so be careful with configuration based scripts.

- What about information about resolution, serial number etc from EDID?
  Unreliable. As EDID existance itself. Hashing that data is opportunistic
  way to get some semi-unique identifiers of user setup states and to act
  upon them.

- Log example while unplugging HDMI cable to the notebook:

`Oct 12 21:12:04 testbox11 monitor-plug.sh[318407]: DISPLAY set to :0, XAUTHORITY set to /home/h3d/.Xauthority`
\
`Oct 12 21:12:04 testbox11 monitor-plug.sh[318408]: Collecting runtime information ...`
\
`Oct 12 21:12:06 testbox11 monitor-plug.sh[318412]: Monitor /sys/class/drm/card0/card0-eDP-1 is connected, taking it into calculation.`
\
`Oct 12 21:12:06 testbox11 monitor-plug.sh[318421]: Executing Default.sh (Configuration: Builtin).`
\
- Log example while plugging HDMI cable to the notebook:

`Oct 12 21:12:16 testbox11 monitor-plug.sh[318440]: DISPLAY set to :0, XAUTHORITY set to /home/h3d/.Xauthority`
\
`Oct 12 21:12:17 testbox11 monitor-plug.sh[318441]: Collecting runtime information ...`
\
`Oct 12 21:12:19 testbox11 monitor-plug.sh[318448]: Monitor /sys/class/drm/card0/card0-HDMI-A-1 is connected, taking it into calculation.`
\
`Oct 12 21:12:19 testbox11 monitor-plug.sh[318452]: Monitor /sys/class/drm/card0/card0-eDP-1 is connected, taking it into calculation.`
\
`Oct 12 21:12:19 testbox11 monitor-plug.sh[318461]: Executing HomeOffice.sh (Configuration: External).`
