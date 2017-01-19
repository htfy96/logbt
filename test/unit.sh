#!/usr/bin/env bash

set -u
set -o pipefail

export CODE=0
export failures=0
export passed=0
export RESULT=0
export WORKING_DIR="/tmp/logbt-unit-test-outputs"
export STDOUT_LOGS="./stdout.txt"
export STDERR_LOGS="./stderr.txt"
export CXXFLAGS="-g -O0 -DDEBUG"
export CXX=${CXX:-g++}
export SIGSEGV_CODE="139"
export SIGABRT_CODE="134"
export SIGFPE_CODE="136"
export TIMEOUT_CODE="124"
export SIGTERM_CODE="143"
export SIGILL_CODE="132"


if [[ $(uname -s) == 'Darwin' ]]; then
    export SIGBUS_CODE="138"
    export USR1_CODE="158"
else
    export SIGBUS_CODE="135"
    export USR1_CODE="138"
fi

function teardown() {
    rm -rf ${WORKING_DIR}/
    rm -f ${STDOUT_LOGS}
    rm -f ${STDERR_LOGS}
}

trap "teardown" EXIT

function assertEqual() {
    if [[ "$1" == "$2" ]]; then
        echo -e "\033[1m\033[32mok\033[0m - $1 == $2 ($3)"
        export passed=$((passed+1))
    else
        echo -e "\033[1m\033[31mnot ok\033[0m - $1 != $2 ($3)"
        export CODE=1
        export failures=$((failures+1))
    fi
}

function assertContains() {
    if [[ "$1" =~ "$2" ]]; then
        echo -e "\033[1m\033[32mok\033[0m - Found string $2 in output ($3)"
        export passed=$((passed+1))
    else
        echo -e "\033[1m\033[31mnot ok\033[0m - Did not find string '$2' in '$1' ($3)"
        export CODE=1
        export failures=$((failures+1))
    fi
}

function exit_tests() {
    if [[ ${CODE} == 0 ]]; then
        echo -e "\033[1m\033[32m* Success: ${passed} tests succeeded\033[0m";
    else
        echo -e "\033[1m\033[31m* Error: ${failures} test(s) failed\033[0m";
    fi
    exit ${CODE}
}

function exit_early() {
    if [[ ${CODE} != 0 ]]; then
        echo "bailing tests early"
        echo
        echo "dumping log of stdout"
        cat ${STDOUT_LOGS}
        echo
        echo "dumping log of stderr"
        cat ${STDERR_LOGS}
        echo
        exit_tests
    fi
}

function stdout() {
    #head -n $1 ${STDOUT_LOGS} | tail -n 1
    sed "${1}q;d" ${STDOUT_LOGS}
}

function stderr() {
    sed "${1}q;d" ${STDERR_LOGS}
}

function all_lines() {
    cat ${STDOUT_LOGS}
}

function run_test() {
    export RESULT=0
    ./bin/logbt --watch $@ >${STDOUT_LOGS} 2>${STDERR_LOGS} || export RESULT=$?
    echo -e "\033[1m\033[32mok\033[0m - ran ./bin/logbt --watch $@ >${STDOUT_LOGS} 2>${STDERR_LOGS}"
    export passed=$((passed+1))
}

function main() {
    export EXPECTED_STARTUP_MESSAGE="[logbt] using corefile location: "
    export EXPECTED_STARTUP_MESSAGE2="[logbt] using core_pattern: "

    mkdir -p ${WORKING_DIR}

    # test logbt misusage
    export RESULT=0
    ./bin/logbt --watch >${STDOUT_LOGS} 2>${STDERR_LOGS} || export RESULT=$?
    assertEqual "${RESULT}" "1" "invalid usage (no args) should result in error code of 1"
    # check stderr
    assertContains "$(stderr 1)" "Usage for logbt:" "Emitted expected usage error"
    # check stdout
    assertEqual "$(stdout 1)" "" "no stdout on usage error"

    # test logbt version
    export RESULT=0
    ./bin/logbt --version >${STDOUT_LOGS} 2>${STDERR_LOGS} || export RESULT=$?
    assertEqual "${RESULT}" "0" "Should result in error code of 0"
    # check stdout
    assertContains "$(stdout 1)" "v" "Should contain v for version number"
    # check stderr
    assertEqual "$(stderr 1)" "" "Should be empty"

    # test logbt with non-crashing program
    run_test node -e "console.error('stderr');console.log('stdout')"
    assertEqual "${RESULT}" "0" "emitted expected signal"
    # check stdout
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertEqual "$(stdout 3)" "stdout" "Emitted expected first line of stdout"
    assertEqual "$(stdout 4)" "" "No line 4 present"
    # check stderr
    assertEqual "$(stderr 1)" "stderr" "Emitted expected first line of stderr"
    assertEqual "$(stderr 2)" "" "No line 3 present"

    exit_early

    # run node process that waits to exit for set time
    # And ensure timeout is shorter and everything closes down correctly
    timeout_cmd="timeout 2 ./bin/logbt --watch node test/wait.js 20"
    ${timeout_cmd} >${STDOUT_LOGS} 2>${STDERR_LOGS} || export RESULT=$?
    echo -e "\033[1m\033[32mok\033[0m - ran ${timeout_cmd} >${STDOUT_LOGS} 2>${STDERR_LOGS}"
    assertEqual "${RESULT}" "${TIMEOUT_CODE}" "emitted expected timeout code"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "Process id is" "Emitted expected line of stdout"
    assertEqual "$(stdout 4)" "Running for 20 s" "Emitted expected line of stdout"
    assertEqual "$(stdout 5)" "Running tic # 0" "Emitted expected line of stdout"
    assertEqual "$(stdout 6)" "Running tic # 1" "Emitted expected line of stdout"
    assertEqual "$(stdout 7)" "Running tic # 2" "Emitted expected line of stdout"
    assertEqual "$(stdout 8)" "Running tic # 3" "Emitted expected line of stdout"
    assertEqual "$(stdout 9)" "Running tic # 4" "Emitted expected line of stdout"
    assertEqual "$(stdout 10)" "Running tic # 5" "Emitted expected line of stdout"
    assertEqual "$(stdout 11)" "Running tic # 6" "Emitted expected line of stdout"
    assertEqual "$(stdout 12)" "Running tic # 7" "Emitted expected line of stdout"
    assertContains "$(all_lines)" "[logbt] received signal:${SIGTERM_CODE} (TERM)" "Emitted expected line of stdout"
    assertContains "$(all_lines)" "[logbt] sending SIGTERM to node" "Emitted expected line of stdout"
    assertContains "$(all_lines)" "node received SIGTERM" "Emitted expected line of stdout"

    exit_early

    # test sending custom USR1 signal (158) to logbt
    watcher_command="./bin/logbt --watch node test/wait.js 200"
    # background logbt and grab its PID
    ${watcher_command} >${STDOUT_LOGS} 2>${STDERR_LOGS} & LOGBT_PID=$!
    echo -e "\033[1m\033[32mok\033[0m - ran ${watcher_command} >${STDOUT_LOGS} 2>${STDERR_LOGS}"
    # clean out logs
    echo "" > ${STDOUT_LOGS}
    sleep 1
    # this should trigger a snapshot backtrace
    kill -USR1 ${LOGBT_PID}
    sleep 4
    assertContains "$(all_lines)" "node::Start" "Found expected line number in backtrace output"
    # clean out logs again
    echo "" > ${STDOUT_LOGS}
    sleep 2
    kill -USR1 ${LOGBT_PID}
    sleep 4
    assertContains "$(all_lines)" "node::Start" "Found expected line number in backtrace output"
    kill -TERM ${LOGBT_PID}
    RESULT=0
    wait ${LOGBT_PID} || RESULT=$?
    assertEqual "${RESULT}" "143" "emitted expected signal"
    # should complete cleanly
    assertContains "$(all_lines)" "forcing exit" "Node script finished as expected"
    export CODE=1
    exit_early

    # run node process that segfaults after 1000ms
    run_test test/segfault.js

    assertEqual "${RESULT}" "${SIGSEGV_CODE}" "emitted expected signal"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertEqual "$(stdout 3)" "running custom-node" "Emitted expected line of stdout"
    assertEqual "$(stdout 4)" "[logbt] saw 'test/segfault.js' exit with code:${SIGSEGV_CODE} (SEGV)" "Emitted expected stdout with exit code"
    assertContains "$(stdout 5)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "node::Kill(v8::FunctionCallbackInfo<v8::Value> const&)" "Found expected line number in backtrace output"

    exit_early

    # run node process that runs segfault.js as a child
    run_test node test/children.js

    assertEqual "${RESULT}" "${SIGSEGV_CODE}" "emitted expected signal"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertEqual "$(stdout 3)" "running custom-node" "Emitted expected first line of stdout"
    assertEqual "$(stdout 4)" "[logbt] saw 'node' exit with code:${SIGSEGV_CODE} (SEGV)" "Emitted expected stdout with exit code"
    assertContains "$(stdout 5)" "No corefile found at" "No core for direct child"
    assertContains "$(stdout 6)" "Found corefile (non-tracked) at" "Found corefile by directory search"
    assertContains "$(stdout 7)" "[logbt] Processing cores..." "Processing cores..."
    assertContains "$(all_lines)" "node::Kill(v8::FunctionCallbackInfo<v8::Value> const&)" "Found expected line number in backtrace output"

    exit_early

    # run bash script that runs node, which segfaults
    run_test ./test/wrapper.sh

    assertEqual "${RESULT}" "${SIGSEGV_CODE}" "emitted expected signal"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertEqual "$(stdout 3)" "running custom-script" "Emitted expected first line of stdout"
    assertContains "$(stdout 4)" "exit with code:${SIGSEGV_CODE} (SEGV)" "Emitted expected stdout with exit code"
    assertContains "$(stdout 5)" "No corefile found at" "No core for direct child"
    assertContains "$(stdout 6)" "Found corefile (non-tracked) at" "Found corefile by directory search"
    assertContains "$(stdout 7)" "[logbt] Processing cores..." "Processing cores..."
    assertContains "$(all_lines)" "node::Kill(v8::FunctionCallbackInfo<v8::Value> const&)" "Found expected line number in backtrace output"

    exit_early

    # test logbt with non-crashing program
    run_test false
    assertEqual "${RESULT}" "1" "emitted expected signal"
    # check stdout
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "exit with code:1 (HUP)" "Emitted expected stdout with exit code"

    exit_early

    # abort
    echo "#include <cstdlib>" > ${WORKING_DIR}/abort.cpp
    echo "int main() { abort(); }" >> ${WORKING_DIR}/abort.cpp

    ${CXX} ${CXXFLAGS} -o ${WORKING_DIR}/run-test ${WORKING_DIR}/abort.cpp
    assertEqual "$?" "0" "able to compile program abort.cpp"

    run_test ${WORKING_DIR}/run-test

    assertEqual "${RESULT}" "${SIGABRT_CODE}" "emitted expected signal"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "exit with code:${SIGABRT_CODE} (ABRT)" "Emitted expected line of stdout with error code"
    assertContains "$(stdout 4)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "abort.cpp:2" "Found expected line number in backtrace output"

    exit_early

    # segfault
    echo "#include <signal.h>" > ${WORKING_DIR}/segfault.cpp
    echo "int main() { raise(SIGSEGV); }" >> ${WORKING_DIR}/segfault.cpp

    ${CXX} ${CXXFLAGS} -o ${WORKING_DIR}/run-test ${WORKING_DIR}/segfault.cpp
    assertEqual "$?" "0" "able to compile program segfault.cpp"

    run_test ${WORKING_DIR}/run-test

    assertEqual "${RESULT}" "${SIGSEGV_CODE}" "emitted expected signal from segfault"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "exit with code:${SIGSEGV_CODE} (SEGV)" "Emitted expected line of stdout with error code"
    assertContains "$(stdout 4)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "segfault.cpp:2" "Found expected line number in backtrace output"

    exit_early

    # bus error
    echo "#include <signal.h>" > ${WORKING_DIR}/bus_error.cpp
    echo "int main() { raise(SIGBUS); }" >> ${WORKING_DIR}/bus_error.cpp

    ${CXX} ${CXXFLAGS} -o ${WORKING_DIR}/run-test ${WORKING_DIR}/bus_error.cpp
    assertEqual "$?" "0" "able to compile program bus_error.cpp"

    run_test ${WORKING_DIR}/run-test

    assertEqual "${RESULT}" "${SIGBUS_CODE}" "emitted expected signal from bus error"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "exit with code:${SIGBUS_CODE} (BUS)" "Emitted expected line of stdout with error code"
    assertContains "$(stdout 4)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "bus_error.cpp:2" "Found expected line number in backtrace output"

    exit_early

    # ILL error
    echo "#include <signal.h>" > ${WORKING_DIR}/illegal_instruction_error.cpp
    echo "int main() { raise(SIGILL); }" >> ${WORKING_DIR}/illegal_instruction_error.cpp

    ${CXX} ${CXXFLAGS} -o ${WORKING_DIR}/run-test ${WORKING_DIR}/illegal_instruction_error.cpp
    assertEqual "$?" "0" "able to compile program illegal_instruction_error.cpp"

    run_test ${WORKING_DIR}/run-test

    assertEqual "${RESULT}" "${SIGILL_CODE}" "emitted expected signal from illegal instruction error"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains "$(stdout 3)" "exit with code:${SIGILL_CODE} (ILL)" "Emitted expected line of stdout with error code"
    assertContains "$(stdout 4)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "illegal_instruction_error.cpp:2" "Found expected line number in backtrace output"

    exit_early

    # Floating point exception: 8
    echo "int main() { int zero = 0; float f2 = 1/zero; }" > ${WORKING_DIR}/floating-point-exception.cpp

    ${CXX} ${CXXFLAGS} -o ${WORKING_DIR}/run-test ${WORKING_DIR}/floating-point-exception.cpp
    assertEqual "$?" "0" "able to compile program floating-point-exception.cpp"

    run_test ${WORKING_DIR}/run-test

    assertEqual "${RESULT}" "${SIGFPE_CODE}" "emitted expected signal"
    assertContains "$(stdout 1)" "${EXPECTED_STARTUP_MESSAGE}" "Expected startup message"
    assertContains "$(stdout 2)" "${EXPECTED_STARTUP_MESSAGE2}" "Expected startup message"
    assertContains"$(stdout 3)" "exit with code:${SIGFPE_CODE} (FPE)" "Emitted expected line of stdout with error code"
    assertContains "$(stdout 4)" "Found corefile at" "Found corefile for given PID"
    assertContains "$(all_lines)" "floating-point-exception.cpp:1" "Found expected line number in backtrace output"

    exit_early

    exit_tests
}

main
