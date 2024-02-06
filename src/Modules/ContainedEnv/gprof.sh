function callgrind {
    local _exe=$(basename $1)
    local _args=$@
    # Generate callgrind file
    valgrind --tool=callgrind --callgrind-out-file=${_exe}.callgrind.out --dump-line=yes --collect-systime=nsec ${_args}
}

function __gprof2dot {
    local _exe=$(basename $1)
    local _args=$@
    python3 /opt/gprof2dot.py --format=callgrind ${_exe}.callgrind.out | dot -Tpng -o ${_exe}.png
}

function profile {
    local _exe=$(basename $1)
    local _args=$@
    # Generate callgrind file
    callgrind ${_args}
    __gprof2dot ${_args}
}