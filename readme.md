logbt
-----
Simple wrapper for running a backtrace when a program segfaults. Requires `gdb` on linux and `lldb` on OS X.

[![Build Status](https://travis-ci.org/mapbox/logbt.svg?branch=master)](https://travis-ci.org/mapbox/logbt)

### Install

To /usr/local/bin:

```sh
curl -sSfL https://github.com/mapbox/logbt/archive/v1.4.0.tar.gz | tar --gunzip --extract --strip-components=1 --exclude="*md" --exclude="test*" --directory=/usr/local
which logbt
/usr/local/bin/logbt
```

Locally (perhaps if your user cannot write to /usr/local):

```sh
curl -sSfL https://github.com/mapbox/logbt/archive/v1.4.0.tar.gz | tar --gunzip --extract --strip-components=2 --exclude="*md" --exclude="test*" --directory=.
./logbt sleep 1
Using existing corefile location: /cores/core.%P
sleep exited with code:0
```

### Supports

 - Linux and OS X
 - Running as root or as unprivileged user

When running as root the corefile location will be modified by `logbt` when run.

When running as an unprivileged user logbt will not modify the corefile location and instead will only assert that it looks acceptable.

On OSX this means:

 - The system default is unmodified such that `$(sysctl -n kern.corefile) == '/cores/core.%P'`

On Linux this means:

 - The `/proc/sys/kernel/core_pattern` file has been modified by root like:

 ```
 sudo bash -c "echo '/tmp/logbt-coredumps/core.%p.%E' > /proc/sys/kernel/core_pattern"
 ```

### Our usage

We use this from within Docker containers to get a backtrace and dump it to `stdout`. Requires the `privileged` parameter to be set to `true` within [container definition](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definition_security).


Before (linux):

```sh
$ node segfault.js
running custom-node
going to crash custom-node
Segmentation fault
```

After (linux):

```sh
$ sudo ./bin/logbt node segfault.js
Setting /tmp/logbt-coredumps/core.%p.%E -> /tmp/logbt-coredumps/core.%p.%E
running custom-node
going to crash custom-node
./bin/logbt: line 112: 15425 Segmentation fault      (core dumped) $*
node exited with code:139
Found core at /tmp/logbt-coredumps/core.15425

warning: core file may not match specified executable file.
[New LWP 15425]
[New LWP 15426]
[New LWP 15428]
[New LWP 15427]
[New LWP 15429]

warning: Can't read pathname for load map: Input/output error.
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/lib/x86_64-linux-gnu/libthread_db.so.1".
Core was generated by `custom-node     '.
Program terminated with signal 11, Segmentation fault.
#0  0x00007f51f7452317 in kill () from /lib/x86_64-linux-gnu/libc.so.6

Thread 5 (Thread 0x7f51f5c18700 (LWP 15429)):
#0  0x00007f51f77e7fd0 in sem_wait () from /lib/x86_64-linux-gnu/libpthread.so.0
#1  0x0000000000fa97d8 in v8::base::Semaphore::Wait() ()
#2  0x0000000000e46f99 in v8::platform::TaskQueue::GetNext() ()
#3  0x0000000000e470ec in v8::platform::WorkerThread::Run() ()
#4  0x0000000000faa790 in v8::base::ThreadEntry(void*) ()
#5  0x00007f51f77e1e9a in start_thread () from /lib/x86_64-linux-gnu/libpthread.so.0
#6  0x00007f51f750f36d in clone () from /lib/x86_64-linux-gnu/libc.so.6
#7  0x0000000000000000 in ?? ()

[... snip ...]
```
