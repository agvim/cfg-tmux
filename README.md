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

## speeding up tmux statusline refresh
tmux can be patched to refresh faster than 1 second to provide a more
responsive monitor.

the following patch hardcodes half a second refresh time when the
"status-interval" config option is set:
    ```diff
    --- a/status.c
    +++ b/status.c
    @@ -194,7 +194,13 @@ status_timer_callback(__unused int fd, __unused short events, void *arg)
            timerclear(&tv);
            tv.tv_sec = options_get_number(s->options, "status-interval");

    -       if (tv.tv_sec != 0)
    +    // force using a faster half a second refresh time when asking for a second
    +    if (tv.tv_sec == 1){
    +        tv.tv_sec = 0;
    +        tv.tv_usec = 500000;
    +    }
    +
    +       if (tv.tv_sec != 0 || tv.tv_usec != 0)
                    evtimer_add(&c->status.timer, &tv);
            log_debug("client %p, status interval %d", c, (int)tv.tv_sec);
     }
    ```

In that case, patch also the rsysstats variable:

    ```rust
    const WORK_SLEEP_DURATION: Duration = Duration::from_millis(500);
    ```
