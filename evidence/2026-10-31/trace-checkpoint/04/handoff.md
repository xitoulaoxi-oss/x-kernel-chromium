# trace-followup/04 handoff: timer and wakeup events

- Real boot produced 4092 retained events: idle_enter/timer_irq/timer_arm
  chains on all CPUs and 6 IPI-receive events on CPU3.
- CPU0 seq 29096 idle_enter -> 29097 timer_irq -> timer_arm repeats; see
  `event-chain.json` for ticks and args.
- All four rings wrapped (dropped 29095/22038/432/400); each stopped image had
  exactly one in-progress slot rejected by the decoder.
- Trace-on vs closed boot-to-shell wall was 9.2/9.1 s vs 9.2/9.3 s at 0.1 s
  resolution; no measurable overhead at that resolution.
- Status **PASS**. Next: 05 frozen/stall-safe exporter.
