#!/bin/bash

function percentage {
    #given a value and the total returns the percentage
    if [[ $2 == 0 ]]; then PERCENTAGE=0; else PERCENTAGE=$((100 * $1 / $2)); fi
    #correct the percentage so it never gets 100%
    #this way will be more readable and we save term space
    if [[ $PERCENTAGE == 100 ]]; then PERCENTAGE=99; fi
}

#characters used for the bar
BAR_CHAR="■"
LIMIT_CHAR="■"
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

function pretty_gb {
    #converts a $1 integer that represents MB into GB with $2 decimals
    local DECIMALS=$(($1 % 1024 / (1024 / 10 ** $2)))
    PRETTY_GB=$(printf "%i.%0$2i\n" $(($1 / 1024)) $DECIMALS)
}

