#!/bin/sh
# chrome-mem.sh - per-process memory of Chromium processes, for x-kernel guest.
#
# Design rules (task 14):
#  - No hard-coded page size: getconf first, env override for tests, explicit
#    "assumed" fallback only when the guest has no way to ask.
#  - /proc/<pid>/stat is parsed after stripping through the LAST ')' because
#    comm may contain spaces and parentheses.
#  - The PID set comes from /proc/<pid>/comm and cmdline, not from `ps w`
#    column truncation.
#  - Missing interfaces produce "unavailable", never a silent 0.
#  - RSS sum double-counts shared pages; the output says so. PSS is not
#    available on this kernel (no smaps), so it is not faked.
#  - Guest "used" and host QEMU working set are NOT produced here; they are
#    separate measurements and must not be added together.
#
# XK_PROC and XK_PAGE_SIZE exist for fixture tests on the host.
set -u
PROC=${XK_PROC:-/proc}
PAGE=${XK_PAGE_SIZE:-}
SRC=env

if [ -z "$PAGE" ] && command -v getconf >/dev/null 2>&1; then
    PAGE=$(getconf PAGESIZE 2>/dev/null || true)
    SRC=getconf
fi
case "$PAGE" in
    ''|*[!0-9]*)
        PAGE=4096
        SRC=assumed
        ;;
esac

pids=""
for d in "$PROC"/[0-9]*; do
    [ -d "$d" ] || continue
    p=${d##*/}
    comm=$(cat "$d/comm" 2>/dev/null) || comm=""
    if [ -r "$d/cmdline" ]; then
        cmd=$(tr '\0' ' ' <"$d/cmdline" 2>/dev/null) || cmd=""
    else
        cmd=""
    fi
    case "$comm $cmd" in
        *chromium*|*chrome*) pids="$pids $p" ;;
    esac
done

tot=0
n=0
ok=0
missing=0
json_pids=""
echo "CM page_size=$PAGE source=$SRC proc=$PROC"

for p in $pids; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    kb=""
    from=""
    d="$PROC/$p"

    # 1) statm: field 2 is resident pages.  Field 1 is virtual size pages.
    if [ -r "$d/statm" ]; then
        set -- $(cat "$d/statm" 2>/dev/null)
        if [ $# -ge 2 ] && [ "${2:-0}" -gt 0 ] 2>/dev/null; then
            kb=$(( $2 * PAGE / 1024 ))
            from=statm
        fi
    fi

    # 2) stat: strip through the last ')', then take field 22 of the remainder
    #    (original field 24 = rss in pages).  This survives "comm (x) y".
    if [ -z "$kb" ] && [ -r "$d/stat" ]; then
        line=$(cat "$d/stat" 2>/dev/null) || line=""
        rest=${line##*) }
        if [ -n "$rest" ] && [ "$rest" != "$line" ]; then
            rssp=$(printf '%s\n' "$rest" | awk '{print $22}')
            case "$rssp" in
                ''|*[!0-9]*) rssp=0 ;;
            esac
            if [ "$rssp" -gt 0 ]; then
                kb=$((rssp * PAGE / 1024))
                from=stat
            fi
        fi
    fi

    # 3) status: VmRSS in kB.  This kernel currently omits VmRSS, hence the
    #    explicit unavailable path below.
    if [ -z "$kb" ] && [ -r "$d/status" ]; then
        v=$(awk '/^VmRSS:/{print $2; exit}' "$d/status" 2>/dev/null)
        case "$v" in
            ''|*[!0-9]*) v=0 ;;
        esac
        if [ "$v" -gt 0 ]; then
            kb=$v
            from=status
        fi
    fi

    if [ -z "$kb" ]; then
        missing=$((missing + 1))
        echo "CM pid=$p rss=unavailable"
        json_pids="$json_pids${json_pids:+,}{\"pid\":$p,\"rss_kb\":null,\"source\":\"unavailable\"}"
        continue
    fi

    ok=$((ok + 1))
    tot=$((tot + kb))
    echo "CM pid=$p rss_kb=$kb source=$from"
    json_pids="$json_pids${json_pids:+,}{\"pid\":$p,\"rss_kb\":$kb,\"source\":\"$from\"}"
done

if [ "$ok" -eq 0 ] && [ "$n" -gt 0 ]; then
    state=unavailable
    tot_json=null
    mb_json=null
elif [ "$n" -eq 0 ]; then
    state=no_processes
    tot_json=null
    mb_json=null
else
    state=$([ "$missing" -gt 0 ] && echo partial || echo measured)
    tot_json=$tot
    mb_json=$((tot / 1024))
fi

echo "CMEM procs=$n measured=$ok unavailable=$missing total_kb=${tot_json:-null} total_mb=${mb_json:-null} state=$state shared_double_count=true"
echo "CMJSON {\"page_size\":$PAGE,\"page_size_source\":\"$SRC\",\"proc_count\":$n,\"measured\":$ok,\"unavailable\":$missing,\"rss_kb_sum\":$tot_json,\"rss_mb_sum\":$mb_json,\"state\":\"$state\",\"shared_double_count\":true,\"processes\":[$json_pids]}"
