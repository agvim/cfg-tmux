# cfg-tmux:

This is a homeshick configuration repository. See
https://github.com/agvim/homeshick

It depends on https://github.com/agvim/cfg-bash for the aliases (besides it
integrates colors nicely)

It enables useful tmux features and provides solarized colors and a fancy
statusline that uses a system load monitor that has no external
dependences except bash and some standard linux programs.

For the network monitor to work, an environment variable needs to be exported:

  export NETDATAIFACE="enp0s31f6"
