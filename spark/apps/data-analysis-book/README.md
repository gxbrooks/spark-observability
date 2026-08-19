# Data Analysis Book (Spark client chapters)

Example Spark applications from *Spark: The Definitive Guide*, used as the lab
client-mode workload (logs under `/mnt/spark/client-logs/<instance>/`).

## Organization

| Path | Purpose |
| ---- | ------- |
| `chapters/Chapter_*.py` | Chapter jobs (03–10) |
| `bin/run-chapters.sh` | Run a list of chapters once (one client instance) |
| `bin/run-stress.sh` | Spin `-p` parallel `run-chapters.sh` copies, each `-i` times back to back |
| `bin/wait-chapters.sh` | Wait for driver PIDs (or poll until they exit) |
| `chapter-timings.csv` | Per-chapter elapsed times written by `run-chapters.sh` |

## Entrypoints

```bash
cd spark/apps/data-analysis-book

# One client, selected chapters
./bin/run-chapters.sh 03 04 08
./bin/run-chapters.sh -a

# Stress: 4 parallel clients, 3 full-suite iterations each
./bin/run-stress.sh --parallel 4 --iteration 3

# Same, subset of chapters
./bin/run-stress.sh -p 2 -i 1 08 09
```

`SPARK_DRIVER_INSTANCE` defaults to `par-a`, `par-b`, … for stress threads, or
the wrapper PID for a lone `run-chapters.sh`. Override with
`SPARK_DRIVER_INSTANCE` / `SPARK_LOG_DIR`.

Source `vars/contexts/spark_client_env.sh` (via `run-chapters.sh`) before
running so the driver uses the cluster master and client log4j2 config.
