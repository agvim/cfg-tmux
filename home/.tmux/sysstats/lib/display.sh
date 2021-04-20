#!/bin/bash

function percentage {
    #given a value and the total returns the percentage
    if [[ $2 == 0 ]]; then PERCENTAGE=0; else PERCENTAGE=$((100 * $1 / $2)); fi
    #correct the percentage so it never gets 100%
    #this way will be more readable and we save term space
    if [[ $PERCENTAGE == 100 ]]; then PERCENTAGE=99; fi
}

# source display.sh; SLEEPTIME=0.1; TOTAL=100; for ((W=0; W<=$TOTAL; W++)){ percentage_bar_v $W $TOTAL; printf "%3i '%s'\r"  "$W" "$PERCENTAGE_BAR"; sleep $SLEEPTIME; }

#characters used for the bar
# vertical bars TODO change code
VBARS=(" " "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
VBARSTOTAL=${#VBARS[*]} # to avoid counting bars every time
function percentage_bar_v {
    #given a value and the total, returns the percentage bar
    local LIMIT_IDX=0
    if [[ $2 -ne 0 ]]
    then
        LIMIT_IDX=$(($1 * VBARSTOTAL / $2))
        if [[ $LIMIT_IDX -ge $VBARSTOTAL ]]
        then
            LIMIT_IDX=$(( VBARSTOTAL - 1 ))
        fi
    fi
    PERCENTAGE_BAR=${VBARS[$LIMIT_IDX]}
}

# source display.sh; SLEEPTIME=0.1; TOTAL=100; for ((W=0; W<=$TOTAL; W++)){ percentage_bar_h $W $TOTAL 3 5; printf "%3i '%s'\r"  "$W" "$PERCENTAGE_BAR"; sleep $SLEEPTIME; }

# horizontal bars
HBARS=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")
HBARSTOTAL=${#HBARS[*]} # to avoid counting bars every time
HBAR_EMPTY_C=${HBARS[0]}
HBAR_FULL_C=${HBARS[$((HBARSTOTAL - 1))]}
function percentage_bar_h {
    #given a value, the total and the horizontal size of the bar, returns the
    #percentage bar
    local UPDATED_TOTAL
    local AMOUNT_HBARS=0
    local HBAR_SIZE=0
    local LIMIT_IDX=0
    if [[ $2 -ne 0 ]]
    then
        # correct the total so it is a multiple of the number of bars as there
        # is truncation of decimals
        UPDATED_TOTAL=$(( $2 - ($2 % $3) ))
        AMOUNT_HBARS=$(( $3 * $1 / UPDATED_TOTAL )) # $((3 * 99 / 100))
        HBAR_SIZE=$(( UPDATED_TOTAL / $3 ))
        LIMIT_IDX=$(( (($1) % HBAR_SIZE) * HBARSTOTAL / HBAR_SIZE ))
    fi
    local I
    PERCENTAGE_BAR=""
    for (( I=1; I<=$3; I++ )){
        if [[ $I -le $AMOUNT_HBARS ]]
        then
            PERCENTAGE_BAR+="$HBAR_FULL_C"
        elif [[ $I -eq $((AMOUNT_HBARS + 1)) ]]
        then
            PERCENTAGE_BAR+="${HBARS[$LIMIT_IDX]}"
        else
            PERCENTAGE_BAR+="$HBAR_EMPTY_C"
        fi
    }
}

function pretty_gb {
    #converts a $1 integer that represents MB into GB with $2 decimals
    local DECIMALS=$(($1 % 1024 / (1024 / 10 ** $2)))
    PRETTY_GB=$(printf "%i.%0$2i\n" $(($1 / 1024)) $DECIMALS)
}

