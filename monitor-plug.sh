#!/bin/ksh

#
# Author: Hegel3DReloaded, Licence: GPLv3
#

# Uncomment for debugging
# exec >> /tmp/monitor-scr.$$ 2>&1

export LC_ALL=C

function usage
{
   echo "${0##*/} [ -s <name> ] [ -c ] [ -h ]"
}

if (($# < 1)); then
   usage
fi

BaseName="${0##*/}"
Tty=$(tty)
function Log
{
   SyslogPrio="$1"
   SyslogMsg="$2"

   if [[ "$Tty" == "not a tty" ]]; then
      logger -p local0.${SyslogPrio} -t "${BaseName}[$$]" "${SyslogMsg}"
   else
      echo -ne "LOG: local0.${SyslogPrio} ${BaseName}: ${SyslogMsg}\n" 1>&2
   fi
}

IFS=" "
OS=$(uname -s)

if [ "$OS" != "Linux" ]; then
   Log err "This script uses Linux sysfs and will not work on $OS. Exiting."
   exit 1
fi

if [ -f "/dev/shm/${BaseName%.sh}.lock" ]; then
   MyPid=$(</dev/shm/${BaseName%.sh}.lock)
   kill -0 "$MyPid" >/dev/null 2>&1
   if (($? == 0)); then
      Log notice "Already running."
      exit 0
   else
      Log warning "Lock file /dev/shm/${BaseName%.sh}.lock exists but there is no pid from it. Breaking lock and running ..."
      rm -f /dev/shm/${BaseName%.sh}.lock
   fi
fi

function collect_runtime
{
   card=$1

   if [ ! -d "/sys/class/drm/${card:=card0}" ]; then
      Log err "No /sys/class/drm/${card:=card0}"
      exit 1
   fi

   CardState=$(egrep -H '' /sys/class/drm/${card:=card0}/*/status)
   if (($? != 0)); then
      Log err "Cannot read device statuses"
      exit 1
   fi
   if [ "x$CardState" == "x" ]; then
      Log err "No connected monitors on card ${card:=card0}"
      exit 0
   fi

   idx=0
   echo $CardState | while IFS=":" read path state
   do
      if [ "$state" == "connected" ]; then
         Log info "Monitor ${path%/*} is connected, taking it into calculation."
         portname[$idx]=$(echo $path | awk -F/ '{ print $6 }' | sed "s/${card:=card0}-//g")
         runedid[$idx]="${path%/*}/edid"
         typeset -bZ checkedid
         read -r -n 8192 checkedid < ${runedid[$idx]}
         edidx=3
         while [ "x$checkedid" == "x" ]
         do
            if (($edidx == 0)); then
               Log notice "Notice: EDID for ${path%/*} is empty, using modes list for hashing" >&2
               break 1
            else
               Log notice "Notice: Waiting for EDID of ${path%/*} to become available ..." >&2
               sleep 1
               checkedid=$(base64 ${runedid[$idx]})
               (( edidx = edidx - 1 ))
            fi
         done
         if (($edidx == 0)); then
            runedid[$idx]="${path%/*}/modes"
            checkmodes=$(<${runedid[$idx]})
            modidx=3
            while [ "x$checkmodes" == "x" ]
            do
               if (($modidx == 0)); then
                  Log err "Error: Cannot get either EDID or modes list of the monitor from ${path%/*}"
                  exit 1
               else
                  sleep 1
                  checkmodes=$(<${runedid[$idx]})
                  (( modidx = modidx - 1 ))
               fi
            done
         fi
         (( idx = idx + 1 ))
      fi
   done

   ConnectedCount=$(echo "$CardState" | egrep "^\/sys\/class\/drm\/${card:=card0}\/.*\/status:connected$" | wc -l)
   PortNames=${portname[*]}
   RunEdidHash=$(cat ${runedid[*]} | sha256sum -)
}

function configure_monitors
{
   if [ "x$XAUTHORITY" == "x" ]; then
      xuser=$(who | egrep '.*tty.*(:0)' | cut -d" " -f 1)
      xuserhome=$(getent passwd $xuser | awk -F: '{ print $6 }')
      if [ -f "${xuserhome}/.Xauthority" ]; then
         export XAUTHORITY="${xuserhome}/.Xauthority"
      fi
   fi

   if [ "x$DISPLAY" == "x" ]; then
      export DISPLAY=":0"
   fi

   Log info "DISPLAY set to ${DISPLAY}, XAUTHORITY set to ${XAUTHORITY}"

   Log info "Collecting runtime information ..."
   collect_runtime

   echo $$ > /dev/shm/${BaseName%.sh}.lock

   if [ ! -f "/etc/opt/monitor-plug/monitordb.txt" ]; then
      Log err "No /etc/opt/monitor-plug/monitordb.txt"
      rm -f /dev/shm/${BaseName%.sh}.lock
      exit 1
   fi

   while read confname devlist edidhash flag
   do
      devidx=0
      for dev in ${devlist/,/ }
      do
         (( devidx = devidx + 1 ))
      done

      if [ "$edidhash" == "${RunEdidHash%% *}" ] && [ "$flag" == "Builtin" ]; then
         if [ -x "/etc/opt/monitor-plug/scripts/${confname}.sh" ]; then
            Log info "Executing ${confname}.sh (Configuration: $flag)."
            rm -f /dev/shm/${BaseName%.sh}.lock
            exec /etc/opt/monitor-plug/scripts/${confname}.sh
         else
            Log warning "Cannot find /etc/opt/monitor-plug/scripts/${confname}.sh"
         fi
      elif [ "$edidhash" == "${RunEdidHash%% *}" ]; then
         if [ "${devlist/,/ }" == "$PortNames" ] && (($devidx == $ConnectedCount)); then
            if [ -x "/etc/opt/monitor-plug/scripts/${confname}.sh" ]; then
               Log info "Executing ${confname}.sh (Configuration: $flag)."
               rm -f /dev/shm/${BaseName%.sh}.lock
               exec /etc/opt/monitor-plug/scripts/${confname}.sh
            else
               Log warning "Cannot find /etc/opt/monitor-plug/scripts/${confname}.sh"
            fi
         fi
      fi
   done < /etc/opt/monitor-plug/monitordb.txt

   rm -f /dev/shm/${BaseName%.sh}.lock
}

function monitordb_savestate
{
   CONFNAME=$1

   collect_runtime

   if (($ConnectedCount == 1)); then
      echo ""
      echo "Configuration line for current layout to be written in /etc/opt/monitor-plug/monitordb.txt:" >&2
      echo "$CONFNAME ${PortNames/ /,} ${RunEdidHash%% *} Builtin"
   else
      echo ""
      echo "Configuration line for current layout to be written in /etc/opt/monitor-plug/monitordb.txt:" >&2
      echo -ne "\n$CONFNAME ${PortNames/ /,} ${RunEdidHash%% *} External\n"
   fi
}

while getopts 's:c:h' opt
do
   case "$opt" in
   c)
      if [ "x$OPTARG" == "default" ]; then
         OPTARG="card0"
      fi
      configure_monitors $OPTARG
   ;;
   s)
      monitordb_savestate $OPTARG
   ;;
   h)
      usage
   ;;
   *)
      usage
   ;;
   esac
done

