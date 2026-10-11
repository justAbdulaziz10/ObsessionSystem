# agent-overnight regression tests

Run `~/.agent-os/evals/overnight/regression.sh`. Uses fake codex-ha/claude on PATH; no network, no quota. Each case maps to a finding from the 2026-10-08 independent review (F1 interrupted work, F2 agent self-commit, F3 deny at run time, F4 push blocked, F5 failover timeout, F6 queue lock, F7 interruption cap, F8 unique ids). All 8 fail on the pre-fix version.
