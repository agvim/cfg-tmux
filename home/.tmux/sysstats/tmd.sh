#!/bin/bash
#gets the tmux environment variables, calculates the display stuff and prints it

. "$(dirname $0)/lib/display.sh"
. "$(dirname $0)/lib/tmux.sh"

function reset_counters {
    #note that the interface is preserved
    #tmux setenv -g NETDATAIFACE "$IFACE"
    #reset counter variables (especially usefull to reset network reference
    #maximums after perverting it with LAN measurements)
    tmux setenv -g CPUDATA "0 0"
    tmux setenv -g MEMSWAPDATA "0 0 0"
    tmux setenv -g NETDATA "0 1 1 0 0"
}

function get_short {
    get_tmux $1
    if [[ $? -eq 1 ]]
    then
        printf "err! \n"
        exit
    fi
}

function print_l {
    #CPUDATA[2]=$DIFF_USED
    #CPUDATA[3]=$DIFF_TOTAL
    get_short "CPUDATA"
    percentage ${TMV[2]} ${TMV[3]}
    printf "l:%2s \n" $PERCENTAGE
}

function print_m {
    #MEMSWAPDATA="$MBCUSED $MTOTAL $SUSED $STOTAL"
    get_short "MEMSWAPDATA"
    percentage ${TMV[0]} ${TMV[1]}
    printf "m:%2s \n" $PERCENTAGE
}

function print_s {
    #MEMSWAPDATA="$MBCUSED $MTOTAL $SUSED $STOTAL"
    get_short "MEMSWAPDATA"
    if [[ ${TMV[3]} != 0 ]]
    then
        percentage ${TMV[2]} ${TMV[3]}
        printf "s:%2s \n" $PERCENTAGE
    fi
}

function print_ni {
    #current date, max TX_BW, max RX_BW, prev_tx, prev_rx, tx_bw, rx_bw
    get_short "NETDATA"
    percentage ${TMV[6]} ${TMV[2]}
    printf "ni:%2s \n" $PERCENTAGE
}

function print_no {
    #current date, max TX_BW, max RX_BW, prev_tx, prev_rx, tx_bw, rx_bw
    get_short "NETDATA"
    percentage ${TMV[5]} ${TMV[1]}
    printf "no:%2s \n" $PERCENTAGE
}

function print_tmuxline {
    #CPUDATA[2]=$DIFF_USED
    #CPUDATA[3]=$DIFF_TOTAL
    get_short "CPUDATA"
    percentage ${TMV[2]} ${TMV[3]}
    L=$PERCENTAGE
    #MEMSWAPDATA="$MBCUSED $MTOTAL $SUSED $STOTAL"
    get_short "MEMSWAPDATA"
    percentage ${TMV[0]} ${TMV[1]}
    M=$PERCENTAGE
    #current date, max TX_BW, max RX_BW, prev_tx, prev_rx, tx_bw, rx_bw
    get_short "NETDATA"
    percentage ${TMV[6]} ${TMV[2]}
    NI=$PERCENTAGE
    #current date, max TX_BW, max RX_BW, prev_tx, prev_rx, tx_bw, rx_bw
    get_short "NETDATA"
    percentage ${TMV[5]} ${TMV[1]}
    NO=$PERCENTAGE
    #MEMSWAPDATA="$MBCUSED $MTOTAL $SUSED $STOTAL"
    get_short "MEMSWAPDATA"
    if [[ ${TMV[3]} != 0 ]]
    then
        percentage ${TMV[2]} ${TMV[3]}
        S=$PERCENTAGE
        printf "#[fg=colour33]l:%2s #[fg=colour64]m:%2s #[fg=colour125]s:%2s #[fg=colour166]ni:%2s #[fg=colour136]no:%2s\n" $L $M $S $NI $NO
    else
        printf "#[fg=colour33]l:%2s #[fg=colour64]m:%2s #[fg=colour166]ni:%2s #[fg=colour136]no:%2s\n" $L $M $NI $NO
    fi
}

function print_help {
    echo "usage:"
    echo "$0 reset: resets the counters and historic data"
    echo "$0 tmuxline: updates and prints all counters"
    echo "$0 <short>: prints the short form (% between 0 and 99) of a counter or 'err!' if there is an error. <short> can be:"
    echo "- l: cpu load"
    echo "- m: memory usage"
    echo "- s: swap usage. Prints nothing if the system does not use swap "
    echo "- ni: monitored network interface incoming usage compared to the daemon sessions maximum"
    echo "- no: monitored network interface outgoing usage compared to the daemon sessions maximum"
}

if [[ $# != 1 ]]; then print_help $0; exit 1; fi
case $1 in
    "reset")
        reset_counters
        ;;
    "tmuxline")
        . "$(dirname $0)/sysstats.sh"
        tmux_stats
        print_tmuxline
        #[fg=colour61]#($tmd l)#[fg=colour64]#($tmd m)#[fg=colour125]#($tmd s)#[fg=colour166]#($tmd ni)#[fg=colour136]#($tmd no)#[fg=colour37]%R'
        ;;
    "l")
        print_l
        ;;
    "m")
        print_m
        ;;
    "s")
        print_s
        ;;
    "ni")
        print_ni
        ;;
    "no")
        print_no
        ;;
    "*")
        print_help
        ;;
esac
unset IFS


