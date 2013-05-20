#!/bin/bash
#gets the tmux environment variables, calculates the display stuff and prints it

function percentage {
    #given a value and the total returns the percentage
    PERCENTAGE=$((100 * $1 / $2))
    #correct the percentage so it never gets 100% 
    #this way will be more readable and we save term space
    if [[ $PERCENTAGE == 100 ]]; then PERCENTAGE=99; fi
}

#characters used for the bar
BAR_CHAR="|"
LIMIT_CHAR="|"
EMPTY_CHAR=" "
function percentage_bar {
    #given a value, the total and the horizontal size of the bar, returns the
    #percentage bar
    local AMOUNT_BARS=$(($3 * $1 / $2))
    #TODO XXX FIXME: there must be a better way to do this
    PERCENTAGE_BAR=""
    for ((I=$3; I>0; I--)){
        if [[ $I > $AMOUNT_BARS ]]
        then
            PERCENTAGE_BAR+=$EMPTY_CHAR
        elif [[ $I == $AMOUNT_BARS ]]
        then
            PERCENTAGE_BAR+=$LIMIT_CHAR
        else
            PERCENTAGE_BAR+=$BAR_CHAR
        fi
    }
}

function reset_counters {
    #note that the interface is preserved
    #tmux setenv -g NETDATAIFACE "$IFACE"
    #reset counter variables (especially usefull to reset network reference
    #maximums after perverting it with LAN measurements)
    tmux setenv -g CPUDATA "0 0"
    tmux setenv -g MEMSWAPDATA "0 0 0"
    tmux setenv -g NETDATA "0 1 1 0 0"
}

#THE TMUX CODE IS BASED ON THE FOLLOWING OUTPUT SHAPE:
# $ tmux setenv HI "miu"
# $ tmux showenv HI
#HI=miu
# $ tmux setenv -u HI
# $ tmux showenv HI
#unknown variable: HI
function get_tmux {
    #$1 is the variable name
    IFS='='
    local SHOWENV=($(tmux showenv -g "$1" 2>&1))
    if [[ ${SHOWENV[0]} == "$1" ]]
    then
        local VALUE=${SHOWENV[1]}
        unset IFS
        #unpack and create an array
        TMV=($VALUE)
        #echo "${#TMV[@]} ${TMV[@]}"
        return 0
    else
        unset IFS
        return 1
    fi
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

function print_help {
    echo "usage:"
    echo "$0 reset: resets the counters and historic data"
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


