#! /bin/sh
# Netperfrunner.sh - a shell script that runs several netperf commands simultaneously.
# This mimics the stress test of Flent (www.flent.org - formerly, "netperf-wrapper") 
# from Toke <toke@toke.dk> but doesn't have the nice GUI result. 
# This can live in /usr/lib/OpenWrtScripts
# 
# When you start this script, it concurrently uploads and downloads multiple
# streams (files) to a server on the Internet. This places a heavy load 
# on the bottleneck link of your network (probably your connection to the 
# Internet). It also starts a ping to a well-connected host. It displays:
#
# a) total bandwidth available 
# b) the distribution of ping latency
 
# Usage: sh netperfrunner.sh -Z passphrase [ -4 -6 ] [ -H netperf-server ] [ -t duration ] [ -t host-to-ping ] [ -n simultaneous-streams ]

# Options: If options are present:
#
# -H | --host:   DNS or Address of a netperf server (default - netperf.bufferbloat.net)
#                Alternate servers are netperf-east (east coast US), netperf-west (California), 
#                and netperf-eu (Denmark)
# -4 | -6:       IPv4 or IPv6 
# -t | --time:   Duration for how long each direction's test should run - (default - 60 seconds)
# -p | --ping:   Host to ping to measure latency (default - gstatic.com)
# -n | --number: Number of simultaneous sessions (default - 5 sessions)
# -Z passphrase: Passphrase required for netperf.bufferbloat.net

# Copyright (c) 2014-2024 - Rich Brown rich.brown@blueberryhillsoftware.com
# GPLv2

  # Process the ping times from the passed-in file, and summarize the results
  # grep to keep lines that have "time=", then sed to isolate the time stamps, and sort them
  # Use awk to build an array of those values, and print first & last (which are min, max) 
  # and compute average.
  # If the number of samples is >= 10, also compute median, and 10th and 90th percentile readings

  # Display the values as:
  #   Latency: (in msec, 11 pings, 8.33% packet loss)
  #    Min: 16.556
  #  10pct: 16.561
  # Median: 22.370
  #    Avg: 21.203
  #  90pct: 23.202
  #    Max: 23.394

summarize_pings() {     
  
grep "time" < "$1" | cat | \
sed 's/^.*time=\([^ ]*\) ms/\1/'| \
  # tee >&2 | \
  sort -n | \
  awk 'BEGIN {numdrops=0; numrows=0} \
    { \
      # print ; \
      if ( $0 ~ /timeout/ ) { \
          numdrops += 1; \
      } else { \
        numrows += 1; \
        arr[numrows]=$1; sum+=$1; \
      } \
    } \
    END { \
      pc10="-"; pc90="-"; med="-"; \
      if (numrows == 0) {numrows=1} \
      if (numrows>=10) \
      { # get the 10th pctile - never the first one
        ix=int(numrows/10); if (ix=1) {ix+=1}; pc10=arr[ix]; \
        # get the 90th pctile
        ix=int(numrows*9/10);pc90=arr[ix]; \
        # get the median
        if (numrows%2==1) med=arr[(numrows+1)/2]; else med=(arr[numrows/2]); \
      }; \
      pktloss = numdrops/(numdrops+numrows) * 100; \
      printf("\n  Latency: (in msec, %d pings, %4.2f%% packet loss)\n      Min: %4.3f \n    10pct: %4.3f \n   Median: %4.3f \n      Avg: %4.3f \n    90pct: %4.3f \n      Max: %4.3f\n", numrows, pktloss, arr[1], pc10, med, sum/numrows, pc90, arr[numrows] )\
     }'
}

# Print a line of dots as a progress indicator.
print_dots() {
  while : ; do
    printf "."
    sleep 1
  done
}

# Stop the current print_dots() process
kill_dots() {
  # echo "Pings: $ping_pid Dots: $dots_pid"
  kill -9 "$dots_pid"
  wait "$dots_pid" 2>/dev/null
  dots_pid=0
}

# Stop the current ping process
kill_pings() {
  # echo "Pings: $ping_pid Dots: $dots_pid"
  kill -9 "$ping_pid"
  wait "$ping_pid" 2>/dev/null
  ping_pid=0
}

# Clean up all the debris from the testing
clean_up() {
  kill_pings
  kill_dots
  rm "$PINGFILE"
  rm "$ULFILE"
  rm "$DLFILE"
  rm "$ERRFILE"
}

# Display "no passphrase" message and exit
no_passphrase() {
  echo ""
  echo "Missing passphrase - see https://$TESTHOST" 
  echo ""
  exit 1
}

# ------- Start of the main routine --------

# Usage: sh betterspeedtest.sh [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ]

# “H” and “host” DNS or IP address of the netperf server host (default: netperf.bufferbloat.net)
# “t” and “time” Time to run the test in each direction (default: 60 seconds)
# “p” and “ping” Host to ping for latency measurements (default: gstatic.com)
# "n" and "number" Number of simultaneous upload or download sessions (default: 4 sessions;
#       4 sessions chosen to match default of RRUL test)

# set an initial values for defaults
TESTHOST="netperf.bufferbloat.net"
TESTDUR="60"

PING4=ping
command -v ping4 > /dev/null 2>&1 && PING4=ping4
PING6=ping6

PINGHOST="gstatic.com"
MAXSESSIONS=4
TESTPROTO=-4

# Create temp files for netperf up/download results
ULFILE=`mktemp /tmp/netperfUL.XXXXXX` || exit 1
DLFILE=`mktemp /tmp/netperfDL.XXXXXX` || exit 1
PINGFILE=`mktemp /tmp/measurepings.XXXXXX` || exit 1
ERRFILE=$(mktemp /tmp/netperfErr.XXXXXX) || exit 1

# echo $ULFILE $DLFILE $PINGFILE

# read the options

# extract options and their arguments into variables.
while [ $# -gt 0 ] 
do
    case "$1" in
	    -4|-6) TESTPROTO=$1; shift 1 ;;
        -H|--host)
            case "$2" in
                "") echo "Missing hostname" ; exit 1 ;;
                *) TESTHOST=$2 ; shift 2 ;;
            esac ;;
        -t|--time) 
        	case "$2" in
        		"") echo "Missing duration" ; exit 1 ;;
                *) TESTDUR=$2 ; shift 2 ;;
            esac ;;
        -p|--ping)
            case "$2" in
                "") echo "Missing ping host" ; exit 1 ;;
                *) PINGHOST=$2 ; shift 2 ;;
            esac ;;
        -n|--number)
        	case "$2" in
        		"") echo "Missing number of simultaneous sessions" ; exit 1 ;;
        		*) MAXSESSIONS=$2 ; shift 2 ;;
        	esac ;;
        -Z)
          case "$2" in
              "") no_passphrase ; exit 1 ;;
              *) PASSPHRASEOPTION="-Z $2" ; shift 2 ;;
          esac ;;
        --) shift ; break ;;
        *) echo "Usage: sh Netperfrunner.sh -Z passphrase [ -H netperf-server ] [ -t duration ] [ -p host-to-ping ] [ -n simultaneous-streams ]" ; exit 1 ;;
    esac
done

# Start main test

# Check to see if netperf is installed and exit if not
if ! command -v netperf >/dev/null 2>&1; then
  echo ""
  echo "Error: netperf is not installed or not in PATH" >&2
  exit 1
fi

if [ $TESTPROTO -eq "-4" ]
then
	PROTO="ipv4"
else
	PROTO="ipv6"
fi
DATE=`date "+%Y-%m-%d %H:%M:%S"`
echo "$DATE Testing $TESTHOST ($PROTO) with $MAXSESSIONS streams down and up while pinging $PINGHOST. Takes about $TESTDUR seconds."
# echo "It downloads four files, and concurrently uploads four files for maximum stress."
# echo "It also pings a well-connected host, and prints a summary of the latency results."
# echo "This test is part of the CeroWrt project. To learn more, visit:"
# echo "  http://bufferbloat.net/projects/cerowrt/"

# ------------ start_pings() ----------------
# Start printing dots, then start a ping process, saving the results to a PINGFILE

start_pings() {

  # Create temp file
  PINGFILE=$(mktemp /tmp/measurepings.XXXXXX) || exit 1

  # Start dots
  print_dots &
  dots_pid=$!
  # echo "Dots PID: $dots_pid"

  # Start Ping
  if [ "$TESTPROTO" -eq "-4" ]
  then
    "$PING4"  "$PINGHOST" > "$PINGFILE" &
  else
    "$PING6"  "$PINGHOST" > "$PINGFILE" &
  fi
  ping_pid=$!
  # echo "Ping PID: $ping_pid"

}

start_pings

# Start $MAXSESSIONS upload datastreams from netperf client to the netperf server
# netperf writes the sole output value (in Mbps) to stdout when completed
for i in $( seq $MAXSESSIONS )
do
	netperf $TESTPROTO -H $TESTHOST -t TCP_STREAM -l $TESTDUR -v 0 -P 0 $PASSPHRASEOPTION >> $ULFILE 2>> $ERRFILE&
	# echo "Starting upload #$i $!"
done

# Start $MAXSESSIONS download datastreams from netperf server to the client
for i in $( seq $MAXSESSIONS )
do
	netperf $TESTPROTO -H $TESTHOST -t TCP_MAERTS -l $TESTDUR -v 0 -P 0 $PASSPHRASEOPTION >> $DLFILE 2>> $ERRFILE&
	# echo "Starting download #$i $!"
done

# Wait until each of the background netperf processes completes 
# echo "Process is $$"
# echo `pgrep -P $$ netperf `

for i in `pgrep -P $$ netperf`		# get a list of PIDs for child processes named 'netperf'
do
	# echo "Waiting for $i"
	wait $i
done

# Check the length of the error file. If it's > 0, then there were errors
  file_size=$(wc -c < "$ERRFILE")
  if [ $file_size -gt 0 ]; then
    clean_up                    # stop the machinery
    no_passphrase               # print the error and exit
  fi 

# # Stop the pings after the netperf's are all done
# kill -9 $ping_pid
# wait $ping_pid 2>/dev/null

# sum up all the values (one line per netperf test) from $DLFILE and $ULFILE
# then summarize the ping stat's
echo ""
echo " Download: " `awk '{s+=$1} END {print s}' $DLFILE` Mbps
echo "   Upload: " `awk '{s+=$1} END {print s}' $ULFILE` Mbps
summarize_pings $PINGFILE

clean_up
