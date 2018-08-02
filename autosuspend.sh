#!/bin/bash

set -e

# https://wiki.ubuntuusers.de/Skripte/AutoSuspend/

. /etc/autosuspend.conf

logit()
{
	logger -p local0.notice -s -- AutoSuspend: $*
	return 0
}

IsOnline()
{
	for i in $*; do
		if [ "$(ping $i -c1 | grep rtt)" ] ; then
		  logit "PC $i is still active, auto suspend terminated"
                  return 1
		fi
	done
	return 0
}

IsRunning()
{
	for i in $*; do
		if [ `pgrep -c $i` -gt 0 ] ; then
			logit "$i still active, auto suspend terminated"
			return 1
                fi
	done
	return 0
}

IsDaemonActive()
{
	for i in $*; do
		if [ `pgrep -c $i` -gt 1 ] ; then
			logit "$i still active, auto suspend terminated"
			return 1
		fi
	done
	return 0
}

IsBusy()
{
        # system usage
        UPTIME="$(uptime)"
        LOAD_AVERAGE="${UPTIME: -4}"
        LOAD_AVERAGE="${LOAD_AVERAGE/,/.}"  # , --> .
        RET=0
        if (( $(bc <<< "$LOAD_AVERAGE > ${SYSTEM_IDLE_LOAD}") ))
        then
            logit "load average high, dont suspend"
            RET=1
        fi

	# Samba
	if [ "x$SAMBANETWORK" != "x" ]; then
		if [ `/usr/bin/smbstatus -b | grep $SAMBANETWORK | wc -l ` != "0" ]; then
		  logit "samba connected, auto suspend terminated"
		  RET=1
		fi
	fi

	#daemons that always have one process running
	IsDaemonActive $DAEMONS
	if [ "$?" == "1" ]; then
	    RET=1
	fi

	#backuppc, wget, wsus, ....
	IsRunning $APPLICATIONS
	if [ "$?" == "1" ]; then
	    RET=1
	fi

	# Read logged users
	USERCOUNT=`who | wc -l`;
	# No Suspend if there are any users logged in
	test $USERCOUNT -gt 0 && { logit "$USERCOUNT users still connected, auto suspend terminated"; RET=1; }

	IsOnline $CLIENTS
	if [ "$?" == "1" ]; then
            RET=1
	fi

	return $RET
}

Suspend()
{
	iw phy0 wowlan enable magic-packet disconnect  # wake up on WLAN
	( test ! -x "/usr/bin/pm-is-supported" && ( logit "cannot check the system's suspend ability. aborting" || /bin/true ) ) || \
	( /usr/bin/pm-is-supported --suspend-hybrid && /usr/sbin/pm-suspend-hybrid ) || \
	( /usr/bin/pm-is-supported --suspend && /usr/sbin/pm-suspend ) || \
	( /usr/bin/pm-is-supported --hibernate && /usr/sbin/pm-hibernate ) || \
	logit "NEITHER SUSPEND NOR RESUME ARE NOT SUPPORTED BY THIS SYSTEM!!! aborting"
}

COUNTFILE="/var/spool/suspend_counter"
OFFFILE="/var/spool/suspend_off"

# turns off the auto suspend
if [ -e $OFFFILE ]; then
	logit "auto suspend is turned off by existents of $OFFFILE"
	exit 0
fi

if [ "$AUTO_SUSPEND" = "true" ] || [ "$AUTO_SUSPEND" = "yes" ] ; then
	IsBusy
	if [ "$?" == "0" ]; then
		# was it not busy already last time? Then suspend.
		if [ -e $COUNTFILE ]; then
			# only auto-suspend at night
			if [ \( "$DONT_SUSPEND_BY_DAY" != "true" -a "$DONT_SUSPEND_BY_DAY" != "yes" \) -o \( "`date +%H`" -ge "3" -a "`date +%H`" -lt "8" \) ]; then
				# notice resume-plan
				NEXTWAKE="0"
				while read line; do
					if [ "`date +%s -d \"$line\"`" -gt "`date +%s`" -a  \( "`date +%s -d \"$line\"`" -lt "$NEXTWAKE" -o "$NEXTWAKE" = "0" \) ]; then
						NEXTWAKE="`date +%s -d \"$line\"`"
					fi
				done < /etc/autosuspend_resumeplan
				if [ "$NEXTWAKE" -gt "`date +%s`" ]; then
					if [ "$NEXTWAKE" -gt "`expr \"\`date +%s\`\" + 1800`" ]; then
						echo "0" > /sys/class/rtc/rtc0/wakealarm
						echo "$NEXTWAKE" > /sys/class/rtc/rtc0/wakealarm
						logit "will resume at $NEXTWAKE"
					else
						logit "do not suspend because would have been awaken within next 30 minutes"
						exit 0
					fi
				fi
				# and suspend or reboot:
				rm -f $COUNTFILE
				if [ \( "$REBOOT_ONCE_PER_WEEK" = "true" -o "$REBOOT_ONCE_PER_WEEK" = "yes" \) -a "`echo \"scale=2; ( \`cat /proc/uptime | cut -d' ' -f1-1\` / 3600 / 24 ) >= 7\" | bc`" -gt 0 ]; then
					logit "REBOOTING THE MACHINE BECAUSE IT HAS BEEN RUNNING FOR MORE THAN A WEEK"
					shutdown -r now
				else
					logit "AUTO SUSPEND CAUSED"
					if [ "$POWER_OFF" = "true" ] || [ "$POWER_OFF" = "yes" ] ; then
						poweroff
					else
						Suspend
					fi
				fi
			else
				logit "did not auto suspend because it is broad day"
			fi
			exit 0
		else
			# shut down next time
			touch $COUNTFILE
			logit "marked for suspend in next try"
			exit 0
		fi
	else
		rm -f $COUNTFILE
		logit "aborted"
		exit 0
	fi
else
	logit "Autosuspend disabled"
	exit 0
fi

logit "malfunction"
exit 1
