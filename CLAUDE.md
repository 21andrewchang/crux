# CLAUDE.md

## Reinstall after every change

After ANY code change in this project, rebuild and reinstall the app on Andrew's iPhone ("andrew", device id `B912DCD3-C247-58B4-98AA-A014D4C521B4`) without being asked:

```sh
scripts/reinstall.sh
```

The script builds locally, then installs on the phone wherever it is plugged in: directly if it is on this machine, or through Andrew's MacBook over SSH (`andrewchang@100.92.210.96`, override with `REMOTE_HOST=`) when working on the Mac mini remotely.

Batch a multi-file edit into one reinstall at the end of the turn, not one per file. If the device is unavailable, say so and skip the install rather than failing the whole task.
