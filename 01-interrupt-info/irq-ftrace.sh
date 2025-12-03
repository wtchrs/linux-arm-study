#!/usr/bin/env sh
set -eu

TRACE=/sys/kernel/debug/tracing
CAT=/bin/cat

OUT=ftrace.log

echo "Mount debugfs..."
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "USAGE: $0 <FUNCTION-TO-TRACE>"
    exit 1
fi

FUNCTION_NAME="$1"

if ! grep -q -E "^${FUNCTION_NAME}$" "$TRACE/available_filter_functions"; then
    echo "Can't find $FUNCTION_NAME function in $TRACE/available_filter_functions"
    exit 1
fi

echo "Trace $FUNCTION_NAME function..."

echo "Reset ftrace state..."
echo nop >"$TRACE/current_tracer"
echo >"$TRACE/set_ftrace_filter"
echo >"$TRACE/trace"
echo 0 >"$TRACE/events/enable"
echo 0 >"$TRACE/tracing_on"

echo "Configure ftrace..."
echo function >"$TRACE/current_tracer"
echo -e "secondary_start_kernel" >"$TRACE/set_ftrace_filter" || true
sleep 1
echo -e "$FUNCTION_NAME" >"$TRACE/set_ftrace_filter"

# Enable events
#echo 1 >"$TRACE/events/irq/irq_handler_entry/enable"
#echo 1 >"$TRACE/events/irq/irq_handler_exit/enable"

# Options
echo 1 >"$TRACE/options/func_stack_trace"
echo 1 >"$TRACE/options/sym-offset"

echo "Tracing start..."
echo 1 >"$TRACE/tracing_on"

echo "Run target command..."
cat /proc/interrupts

echo "Tracing stop..."
echo 0 >"$TRACE/tracing_on"

echo "Export trace..."
cat "$TRACE/trace" >"$OUT"
echo "Saved: $OUT"
