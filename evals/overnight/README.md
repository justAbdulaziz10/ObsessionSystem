# agent-overnight regression tests

Run `bash evals/overnight/regression.sh` from the repository root. It puts fake `codex-ha` and `claude` commands on PATH, so it needs no network and spends no quota.

The eight cases cover: interrupted work, an agent committing by itself, a permission denied at run time, a blocked push, failover timeout, the queue lock, the interruption cap and unique task ids.
