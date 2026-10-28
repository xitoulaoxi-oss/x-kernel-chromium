#!/bin/sh
# Print the accumulated heartbeat lines for the harness console.
tail -80 /tmp/xk-hb.log 2>/dev/null || echo NO_HB
