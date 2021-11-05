# cfg-tmux:

This is a homeshick configuration repository. See
https://github.com/agvim/homeshick

It depends on https://github.com/agvim/cfg-bash for the aliases (besides it
integrates colors nicely)

It enables useful tmux features and provides solarized colors and a fancy
statusline that uses a system load monitor.

The load monitor can either be:
1. one that has no external dependences except bash and some standard linux
   programs.
2. a more optimized version written in rust with no external dependencies (the
   binary is added in the repository also)

For the network monitor, the load monitor will use the first found network
interface, but it can be overriden with an environment variable:

  export NETDATAIFACE="enp0s31f6"
