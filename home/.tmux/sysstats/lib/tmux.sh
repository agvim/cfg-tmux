#!/bin/bash

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
        VALUE=${SHOWENV[1]}
        unset IFS
        TMV=($VALUE)
        return 0
    else
        #error case
        unset IFS
        return 1
    fi
}
