#!/bin/bash

#System stats in "pure bash".
#Attempts to spawn as less external processes as possible
#WARNING: reads data from various system files so it is linux distro dependant

. "$(dirname $0)/lib/display.sh"
. "$(dirname $0)/lib/tmux.sh"

#protecting them for tmux rewrite
function init_cpu {
    CPUDATA=(0 0 0 0)
}
function cpu {
#$ grep '^cpu ' /proc/stat
#cpu  1135143 2962258 1385972 13764304 29072 11 5709 0 0 0
    local CPU=($(grep '^cpu ' /proc/stat))  # Get the total CPU statistics.
    local IDLE=${CPU[4]}                    # Get the idle CPU time.
    unset CPU[0]                            # Discard the "cpu" prefix.

    # Calculate the total CPU time.
    local TOTAL=0
    for VALUE in ${CPU[@]}
    do
        TOTAL=$(($TOTAL + $VALUE))
    done

    # Calculate the CPU usage since we last checked.
    local DIFF_IDLE=$(($IDLE - ${CPUDATA[0]}))
    local DIFF_TOTAL=$(($TOTAL - ${CPUDATA[1]}))
    local DIFF_USED=$(($DIFF_TOTAL - $DIFF_IDLE))

    # Remember the total and idle CPU times for the next check.
    CPUDATA[0]="$IDLE"
    CPUDATA[1]="$TOTAL"

    #Data for display
    CPUDATA[2]=$DIFF_USED
    CPUDATA[3]=$DIFF_TOTAL
}

function mem-swap {
# $ grep -E '^(Mem|Swap)' /proc/meminfo
# MemTotal:       16385132 kB
# MemFree:        10585440 kB
# MemAvailable:   14531416 kB
# SwapCached:            0 kB
# SwapTotal:             0 kB
# SwapFree:              0 kB
    local MEMINFO=($(grep -E '^(Mem|Swap)' /proc/meminfo))
    MEMSWAPDATA=(${MEMINFO[1]} ${MEMINFO[7]} ${MEMINFO[13]} ${MEMINFO[16]})
}

function calculate_bw {
    #calculates BW in bits/second
    #$1 = prev_date ms
    #$2 = curr_date ms
    #$3 = prevrx/tx bytes
    #$4 = currx/tx bytes
    #echo "prev_date $1"
    #echo "curr_date $2"
    #echo "prev bytes $3"
    #echo "curr bytes $4"
    if [[ $1 == 0 ]]
    then
        BW=0
    else
        #BASHBITS=$((($4 - $3) * 8))
        #echo "bc b $BCBITS, bash b $BASHBITS"

        #SECS=$((($2 - $1) / 1000))
        #echo $SECS

        #BASHBW=$(($BASHBITS / $SECS))
        #BASHBW=$((($4 - $3) * 8  * 1000 / ($2 - $1)))
        #BASHBW=$((($4 - $3) * 8000 / ($2 - $1)))
        BW=$((($4 - $3) * 8000 / ($2 - $1)))
    fi
}

#NETDATA array is used for tracking the network data:
function init_netstats {
    IFACE=$1
    #prev_miliseconds, max TX_BW, max RX_BW, prev_tx, prev_rx, tx_bw, rx_bw
    NETDATA=(0 1 1 0 0 0 0)
}
function netstats {
    #$1 = interface

    #DATE IN MILLISECONDS (NANOSECONDS / 1000000)
    local CURDATE=$(($(date +%s%N) / 1000000))
    #get raw data, the time it takes to get it pollutes the CURDATE precision
    local TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)
    local RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
    #calculate the bandwidths
    calculate_bw ${NETDATA[0]} $CURDATE ${NETDATA[3]} $TX
    local TX_BW=$BW
    calculate_bw ${NETDATA[0]} $CURDATE ${NETDATA[4]} $RX
    local RX_BW=$BW
    #update netdata
    NETDATA[0]=$CURDATE
    if [[ $(($TX_BW > ${NETDATA[1]})) == 1 ]]; then NETDATA[1]=$TX_BW; fi
    if [[ $(($RX_BW > ${NETDATA[2]})) == 1 ]]; then NETDATA[2]=$RX_BW; fi
    NETDATA[3]=$TX
    NETDATA[4]=$RX
    NETDATA[5]=$TX_BW
    NETDATA[6]=$RX_BW
}

function tmux_cpu {
    ##global inter-call variables
    #Data for next calculus
    #CPUDATA[0]="$IDLE"
    #CPUDATA[1]="$TOTAL"
    ##Data for display
    #CPUDATA[2]=$DIFF_USED
    #CPUDATA[3]=$DIFF_TOTAL

    get_tmux "CPUDATA"
    if [[ $? -eq 1 ]]
    then
        init_cpu
    else
        CPUDATA=(${TMV[@]})
    fi

    #do the work
    cpu

    #output variable
    local TMUXCPUDATA=${CPUDATA[@]}
    tmux setenv -g CPUDATA "$TMUXCPUDATA"
}

function tmux_mem-swap {
    #do the work
    mem-swap

    ##output variables
    local TMUXMEMSWAPDATA=${MEMSWAPDATA[@]}
    tmux setenv -g MEMSWAPDATA "$TMUXMEMSWAPDATA"
}

function tmux_netstats {
    ##global inter-call variables
    #NETDATA[0]=$CURDATE
    #NETDATA[1]=$TX_BW max
    #NETDATA[2]=$RX_BW max
    #NETDATA[3]=$TX
    #NETDATA[4]=$RX
    #NETDATA[5]=$TX_BW
    #NETDATA[6]=$RX_BW

    #iface picked from .tmux.conf
    get_tmux "NETDATAIFACE"
    if [[ $? -eq 1 ]]
    then
        #attempt to run anyway with eth0 if not defined
        IFACE="eth0"
    else
        IFACE=$TMV
    fi

    #tmux showenv -g NETDATAIFACE

    get_tmux "NETDATA"
    if [[ $? -eq 1 ]]
    then
        #iface picked up from .tmux.conf
        init_netstats $IFACE
    else
        NETDATA=(${TMV[@]})
    fi

    #do the work
    netstats

    TMUXNETDATA=${NETDATA[@]}
    tmux setenv -g NETDATA "$TMUXNETDATA"
}

function tmux_update_stats {
    #tmux mode
    tmux_cpu
    tmux_mem-swap
    tmux_netstats
    #save the timestamp
    tmux setenv -g DATATIME "$DATATIME"
}

function tmux_stats {
    #get the stats at the specified frequency
    #(this way we can have multiple tmux sessions that share the same stats)
    #the price to pay is that the data in some sessions can be up to 
    #DATAFREQUENCY seconds old
    get_tmux "DATAFREQUENCY"
    if [[ $? -eq 0 ]]
    then
        DATAFREQUENCY=$TMV
    else
        #set allowed data frequency to 1 second if not configured
        DATAFREQUENCY=1
    fi
    get_tmux "DATATIME"
    if [[ $? -eq 0 ]]
    then
        local OLDDATATIME=$TMV
    else
        local OLDDATATIME=0
    fi
    #update if enough time has passed.
    local DATATIME="$(date +%s)"
    local TIMEDIFF=$(($DATATIME - $OLDDATATIME))
    if [[ $(($TIMEDIFF < $DATAFREQUENCY)) == 0 ]]
    then
        tmux_update_stats
    fi
}

function update_stats {
    cpu
    mem-swap
    netstats
}

function print_help {
    echo "usage:"
    echo "$0 continuous <iface> <refresh>: displays a line that refreshes every refresh seconds with the network device iface"
    echo "$0 tmux: sets global variables in tmux."
}

if [[ $# == 0 ]]; then print_help $0; exit 1; fi
case $1 in
    "tmux")
        if [[ $# != 1 ]]; then print_help $0; exit 1; fi
        tmux_stats
        ;;
    "continuous")
        if [[ $# != 3 ]]; then print_help $0; exit 1; fi
        #init is needed for both single run and continuous
        init_cpu
        init_netstats $2
        #continuous mode
        while true
        do
            update_stats
            # echo percentage ${CPUDATA[2]} ${CPUDATA[3]}
            percentage ${CPUDATA[2]} ${CPUDATA[3]}
            LOAD=$PERCENTAGE
            # echo percentage ${MEMSWAPDATA[0]} ${MEMSWAPDATA[1]}
            percentage ${MEMSWAPDATA[0]} ${MEMSWAPDATA[1]}
            RAM_PERCENTAGE=$PERCENTAGE
            # echo percentage ${MEMSWAPDATA[2]} ${MEMSWAPDATA[3]}
            percentage ${MEMSWAPDATA[2]} ${MEMSWAPDATA[3]}
            SWAP_PERCENTAGE=$PERCENTAGE
            # echo percentage ${NETDATA[6]} ${NETDATA[2]}
            percentage ${NETDATA[6]} ${NETDATA[2]}
            RX_PER=$PERCENTAGE
            # echo percentage ${NETDATA[5]} ${NETDATA[1]}
            percentage ${NETDATA[5]} ${NETDATA[1]}
            TX_PER=$PERCENTAGE
            printf "\rl:%2s m:%2s s:%2s ni:%2s no:%2s" $LOAD $RAM_PERCENTAGE $SWAP_PERCENTAGE $RX_PER $TX_PER
            sleep $3
        done
        ;;
    "*")
        print_help $0
        exit 1
esac

