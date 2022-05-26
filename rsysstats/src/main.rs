#![warn(missing_docs)]
#![warn(rustdoc::broken_intra_doc_links)]
//! Implements a Unix socket server that monitors the system and network load
//! and a client that connects to it and prints the load
use std::env;
use std::fs::{self, File};
use std::io::{stdout, BufRead, BufReader, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::process;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime};
use nix::unistd::getuid;

//const WORK_SLEEP_DURATION: Duration = Duration::from_millis(1000);
const WORK_SLEEP_DURATION: Duration = Duration::from_millis(500);
const SOCKET_TIMEOUT: Duration = Duration::from_millis(1000);
const MAX_INACTIVE_TIME: Duration = Duration::from_secs(5);

/// data needed for calculating some of the load percentages
struct MonitorData {
    // the last monitored timestamp
    time: SystemTime,

    // the last monitored idle and total values to load %
    cpu_idle: u32,
    cpu_total: u32,

    // last know tx and rx values to calculate bandwidth with the time
    tx: u64,
    rx: u64,
}

/// maximum tx and rx values to calculate a % relative to the known maximum
struct MaxBW {
    tx: u64,
    rx: u64,
}

/// percentage load values that are sent to the clients
struct LoadData {
    cpu_load: i8,
    mem_load: i8,
    swap_load: i8,
    net_in: i8,
    net_out: i8,
}

/// Send the load data on a 'r' character
/// or resets the max bandwidth reference on an 'm' character
fn handle_client(
    mut stream: UnixStream,
    lastconnection: Arc<Mutex<SystemTime>>,
    ld: Arc<Mutex<LoadData>>,
    maxbw: Arc<Mutex<MaxBW>>,
) {
    // register the last client connection time
    {
        let mut lastconnection = lastconnection.lock().unwrap();
        *lastconnection = SystemTime::now();
    }
    // do the work
    let mut readdata = [0];
    let _ = stream.read(&mut readdata);
    match readdata[0] {
        b'r' => {
            // return the last load measurements
            let ld = ld.lock().unwrap();
            // CPU load, mem load, swap load, rx %, tx %
            let bytes: [u8; 5] = [
                ld.cpu_load as u8,
                ld.mem_load as u8,
                ld.swap_load as u8,
                ld.net_in as u8,
                ld.net_out as u8,
            ];
            let _ = stream.write(&bytes);
        }
        b'm' => {
            // reset the max bandwidth reference
            let mut maxbw = maxbw.lock().unwrap();
            maxbw.rx = 1;
            maxbw.tx = 1;
        }
        _ => {
            println!("unexpected character {}", readdata[0])
        }
    }
}

/// blocks waiting for incoming connections and dispatches them to handler threads
fn server_dispatch(
    listener: UnixListener,
    lastconnection: Arc<Mutex<SystemTime>>,
    ld: Arc<Mutex<LoadData>>,
    maxbw: Arc<Mutex<MaxBW>>,
) {
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let _ = stream.set_read_timeout(Some(SOCKET_TIMEOUT));
                let _ = stream.set_write_timeout(Some(SOCKET_TIMEOUT));
                let clientlastconnection = Arc::clone(&lastconnection);
                let clientld = Arc::clone(&ld);
                let clientmaxbw = Arc::clone(&maxbw);
                thread::spawn(|| {
                    handle_client(stream, clientlastconnection, clientld, clientmaxbw)
                });
            }
            Err(err) => {
                println!("Error: {}", err);
                break;
            }
        }
    }
}

/// updates the cpu load monitor data and load data
fn update_cpu(md: &mut MonitorData, ld: &Arc<Mutex<LoadData>>) -> std::io::Result<()> {
    let file = File::open("/proc/stat")?;
    let mut reader = BufReader::new(file);
    let mut cpuline = String::new();
    reader.read_line(&mut cpuline)?;
    // the line will be similar to:
    // cpu  1135143 2962258 1385972 13764304 29072 11 5709 0 0 0
    let mut iter = cpuline.split_whitespace();
    // discard "cpu" text
    iter.next();
    // get the other values as integers
    // TODO XXX FIXME: assuming the cpuline is correct
    // will crash the server but I have no better idea
    let cpulinevalues: Vec<u32> = iter
        .map(|s| {
            s.parse::<u32>()
                .expect(&format!("/proc/stat value should be a number '{}'", s))
        })
        .collect();
    let cpu_total = cpulinevalues.iter().sum();
    let cpu_idle = cpulinevalues[3];
    // println!("{:?}", cpulinevalues);
    let diff_idle = cpu_idle - md.cpu_idle;
    let diff_total = cpu_total - md.cpu_total;
    let diff_used = diff_total - diff_idle;
    md.cpu_idle = cpu_idle;
    md.cpu_total = cpu_total;

    // update the shared load state
    {
        let mut ld = ld.lock().unwrap();
        ld.cpu_load = (diff_used * 100 / diff_total) as i8;
    }
    Ok(())
}

/// updates the swap and memory load data
fn update_memswap(ld: &Arc<Mutex<LoadData>>) -> std::io::Result<()> {
    let file = File::open("/proc/meminfo")?;
    let reader = BufReader::new(file);
    let mut memswapvalues: Vec<u32> = Vec::new();
    // get the Mem and Swap lines and get their values as integers
    // will be in the shape of (only relevant lines):
    // MemTotal:       16385132 kB
    // MemFree:        10585440 kB
    // MemAvailable:   14531416 kB
    // SwapCached:            0 kB
    // SwapTotal:             0 kB
    // SwapFree:              0 kB
    // TODO XXX FIXME: assuming the lines are correct
    // will crash the server but I have no better idea
    for line in reader.lines() {
        let line = line?;
        if line.starts_with("Mem") || line.starts_with("Swap") {
            //println!("{}", line)
            let s = line
                .split_whitespace()
                .nth(1)
                .expect(&format!("unexpected meminfo line format '{}'", line));
            memswapvalues.push(
                s.parse::<u32>()
                    .expect(&format!("meminfo value should be a number '{}'", s)),
            );
        }
        // ignore remaining lines after have the mem and swap info
        if memswapvalues.len() == 6 {
            break;
        };
    }
    let mem_total = memswapvalues[0];
    let mem_available = memswapvalues[2];
    let swap_total = memswapvalues[4];
    let swap_free = memswapvalues[5];

    // now that we have the values, we can calculate the load percentage
    {
        let mut ld = ld.lock().unwrap();
        ld.mem_load = ((mem_total - mem_available) * 100 / mem_total) as i8;
        if swap_total != 0 {
            ld.swap_load = ((swap_total - swap_free) * 100 / swap_total) as i8;
        } else {
            ld.swap_load = -1;
        }
    }
    Ok(())
}

/// updates the reception and transmission monitor data, load data and the historic max bandwidth
fn update_netstats(
    net_interface: &str,
    md: &mut MonitorData,
    ld: &Arc<Mutex<LoadData>>,
    maxbw: &Arc<Mutex<MaxBW>>,
) -> std::io::Result<()> {
    // each statistics file just contains the number of tx or rx bytes
    // TODO XXX FIXME: assuming the lines are correct
    // will crash the server but I have no better idea
    let mut file = File::open(format!(
        "/sys/class/net/{}/statistics/tx_bytes",
        net_interface
    ))?;
    let mut bytes = String::new();
    file.read_to_string(&mut bytes)?;
    let txbytes = bytes
        .trim()
        .parse::<u64>()
        .expect(&format!("tx_bytes value should be a number '{}'", bytes));

    let mut file = File::open(format!(
        "/sys/class/net/{}/statistics/rx_bytes",
        net_interface
    ))?;
    let mut bytes = String::new();
    file.read_to_string(&mut bytes)?;
    let rxbytes = bytes
        .trim()
        .parse::<u64>()
        .expect(&format!("rx_bytes value should be a number '{}'", bytes));

    //println!("{} {}", txbytes, rxbytes);

    let now = SystemTime::now();
    //calculates BW in bytes/second
    let millisdiff = now.duration_since(md.time).unwrap_or_default().as_millis() as u64;
    // println!("{}", millisdiff);
    if millisdiff != (0) {
        let tx_bw = (txbytes - md.tx) * 1000 / millisdiff;
        let rx_bw = (rxbytes - md.rx) * 1000 / millisdiff;
        // println!("{} {}", tx_bw, rx_bw);
        // now that we have the values, we can update the recorded max bw
        // and calculate the load percentage
        let mut maxbw = maxbw.lock().unwrap();
        if tx_bw > maxbw.tx {
            maxbw.tx = tx_bw;
        }
        if rx_bw > maxbw.rx {
            maxbw.rx = rx_bw;
        }
        {
            let mut ld = ld.lock().unwrap();
            ld.net_out = (tx_bw * 100 / maxbw.tx as u64) as i8;
            ld.net_in = (rx_bw * 100 / maxbw.rx as u64) as i8;
            // println!("{} {}", ld.net_out, ld.net_in);
        }
    }
    md.tx = txbytes;
    md.rx = rxbytes;
    md.time = now;
    Ok(())
}

/// load data calculation loop and server killing on inactivity code
fn server_work(
    socket: &str,
    net_interface: &str,
    lastconnection: Arc<Mutex<SystemTime>>,
    ld: Arc<Mutex<LoadData>>,
    maxbw: Arc<Mutex<MaxBW>>,
) {
    // this code is running in the main thread since is not waiting on client connections
    // so it is the one terminating the server once there has been client inactivity
    let mut md = MonitorData {
        time: SystemTime::now(),

        cpu_idle: 0,
        cpu_total: 0,

        tx: 0,
        rx: 0,
    };
    loop {
        // do the work
        {
            // if there is a problem with any of the updates, just ignore that update
            let _ = update_cpu(&mut md, &ld);
            let _ = update_memswap(&ld);
            let _ = update_netstats(net_interface, &mut md, &ld, &maxbw);
        }

        // decide whether to close the server due to inactivity
        {
            let lastconnection = lastconnection.lock().unwrap();
            if lastconnection.elapsed().unwrap_or_default() > MAX_INACTIVE_TIME {
                // force delete the socket file and exit
                // TODO: nicely close the socket instead
                let _ = std::fs::remove_file(socket);
                process::exit(0x0);
            }
        }

        // sleep until next refresh
        thread::sleep(WORK_SLEEP_DURATION);
    }
}

/// spawn the unix socket server on a thread and call the load calculation loop function
fn main_server(socket: &str, net_interface: &str) -> std::io::Result<()> {
    // force delete the socket file (ignore any potential error result)
    let _ = std::fs::remove_file(socket);

    // establish a new socket and handle clients in a separate thread
    let listener = UnixListener::bind(socket)?;

    let now = SystemTime::now();
    let lastconnection = Arc::new(Mutex::new(now));
    let serverlastconnection = Arc::clone(&lastconnection);

    let ld = LoadData {
        cpu_load: 0,
        mem_load: 0,
        swap_load: 0,
        net_in: 0,
        net_out: 0,
    };
    let ld = Arc::new(Mutex::new(ld));
    let serverld = Arc::clone(&ld);

    let maxbw = MaxBW { tx: 1, rx: 1 };
    let maxbw = Arc::new(Mutex::new(maxbw));
    let servermaxbw = Arc::clone(&maxbw);

    // spawn a thread to handle the connections loop
    thread::spawn(|| server_dispatch(listener, serverlastconnection, serverld, servermaxbw));

    // the main thread will do the computations and stop the server when no requests are received
    // for a period of time
    server_work(socket, net_interface, lastconnection, ld, maxbw);
    Ok(())
}

const VBARS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
/// convert a percentage value to a vertical unicode bar representation
///
/// 0 percent is an empty bar and 100% is a full bar
fn percentage_bar_v(percentage: i8) -> char {
    let percentage = percentage as usize;
    VBARS[(percentage * (VBARS.len() - 1) / 100)]
}

/// print load data bars with tmux color codes
fn print_ld_tmux(ld: &LoadData) {
    const BLUE: &str = "#[fg=colour33]";
    const GREEN: &str = "#[fg=colour64]";
    const MAGENTA: &str = "#[fg=colour125]";
    const RED: &str = "#[fg=colour166]";
    const YELLOW: &str = "#[fg=colour136]";
    print!(
        "\r{}{}{}{}",
        BLUE,
        percentage_bar_v(ld.cpu_load),
        GREEN,
        percentage_bar_v(ld.mem_load)
    );
    if ld.swap_load != -1 {
        print!("{}{}", MAGENTA, percentage_bar_v(ld.swap_load));
    }
    print!(
        " {}{}{}{}",
        RED,
        percentage_bar_v(ld.net_in),
        YELLOW,
        percentage_bar_v(ld.net_out)
    );
    let mut stdout = stdout();
    let _ = stdout.flush();
}

/// print the percentage and bars of each load data item with terminal color codes
fn print_ld_shell(ld: &LoadData) {
    fn max_99(p: i8) -> i8 {
        if p >= 100 {
            99
        } else {
            p
        }
    }
    fn escapecode(parameter:&str, code:&str) -> String {
        format!("\x1b[{};{}m", parameter, code)
    }
    const FG: &str = "38;2";
    const BG: &str = "48;2";
    const BASE02: &str = "7;54;66";
    const BLUE: &str = "38;139;210";
    const GREEN: &str = "133;153;0";
    const MAGENTA: &str = "211;54;130";
    const RED: &str = "220;50;47";
    const YELLOW: &str = "181;137;0";

    print!(
        "\r{}cpu({:2}%):{} {}mem({:2}%):{}",
        escapecode(FG, BLUE),
        max_99(ld.cpu_load),
        percentage_bar_v(ld.cpu_load),
        escapecode(FG, GREEN),
        max_99(ld.mem_load),
        percentage_bar_v(ld.mem_load)
    );
    if ld.swap_load != -1 {
        print!(
            "{}swp({:2}%):{}",
            escapecode(FG, MAGENTA),
            max_99(ld.swap_load),
            percentage_bar_v(ld.swap_load)
        );
    }
    print!(
        " {}ni({:2}%):{} {}no({:2}%):{} ",
        escapecode(FG, RED),
        max_99(ld.net_in),
        percentage_bar_v(ld.net_in),
        escapecode(FG, YELLOW),
        max_99(ld.net_out),
        percentage_bar_v(ld.net_out)
    );
    let mut stdout = stdout();
    let _ = stdout.flush();
}

/// connect to the server and either request the load data
/// or request the max reference bandwidths to be reset
fn main_client(socket: &str, reset_bw_max: bool) -> std::io::Result<()> {
    let mut stream: UnixStream;
    if reset_bw_max {
        match UnixStream::connect(socket) {
            Ok(mut stream) => {
                let _ = stream.write(b"m");
                Ok(())
            }
            Err(e) => {
                println!("{}", e);
                Err(e)
            }
        }
    } else {
        let mut bytes: [u8; 5] = [0; 5];
        let tmux_output: bool = env::var("TERM").unwrap_or_default() == "tmux-256color";
        loop {
            stream = UnixStream::connect(socket)?;
            stream
                .write_all(b"r")
                .expect("error communicating with the server");

            stream
                .read_exact(&mut bytes)
                .expect("error receiving answer from the server");
            let ld = LoadData {
                cpu_load: bytes[0] as i8,
                mem_load: bytes[1] as i8,
                swap_load: bytes[2] as i8,
                net_in: bytes[3] as i8,
                net_out: bytes[4] as i8,
            };
            if tmux_output {
                print_ld_tmux(&ld);
            } else {
                print_ld_shell(&ld);
            }
            // sleep half the duration to sample faster
            thread::sleep(WORK_SLEEP_DURATION / 2);
        }
    }
}

/// get the interface from an environment variable or pick the first one it in /sys/class/net
fn discover_interface() -> Result<String, Box<dyn std::error::Error>> {
    match env::var("NETDATAIFACE") {
        Ok(net_interface) => Ok(net_interface),
        Err(_) => {
            for dir in fs::read_dir("/sys/class/net")? {
                let dirname = dir?
                    .file_name()
                    .to_str()
                    .ok_or("strange filename in /sys/class/net")?
                    .to_string();
                if dirname != "lo" {
                    return Ok(dirname);
                }
            }
            panic!("unable to find an interface to monitor");
        }
    }
}

/// spawn a client to print the loads or the server if the client fails to connect
fn main() {
    let mut args = env::args();
    let program = args.next().unwrap();
    // default mode is client mode
    let mode: &str = &args.next().unwrap_or_else(|| "-c".to_string());
    // println!("{}", mode);

    // println!("{}", getuid());
    let socket: String = format!("/run/user/{}/tmux-rsysstats.socket", getuid());

    match mode {
        "-c" => {
            match main_client(&socket, false) {
                Ok(_client) => {}
                Err(_err) => {
                    // start the server
                    process::Command::new(program).arg("-s").spawn().unwrap();
                    // loop trying to connect to the server
                    loop {
                        main_client(&socket, false)
                            .unwrap_or_else(|_| thread::sleep(WORK_SLEEP_DURATION / 2));
                    }
                }
            }
        }
        "-s" => {
            // choose an interface for the server and run it
            let net_interface =
                discover_interface().expect("unable to discover the network interface");
            println!("{}", net_interface);
            match main_server(&socket, &net_interface) {
                Ok(_server) => {}
                Err(err) => {
                    println!("Error: {}", err);
                }
            }
        }
        "-r" => {
            main_client(&socket, true).unwrap();
        }
        _ => {
            println!("unknown mode");
        }
    }
}
