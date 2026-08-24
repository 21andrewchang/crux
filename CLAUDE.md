# CLAUDE.md

## Reinstall after every change

After ANY code change in this project, rebuild and reinstall the app on Andrew's iPhone ("andrew", device id `B912DCD3-C247-58B4-98AA-A014D4C521B4`) without being asked:

```sh
scripts/reinstall.sh
```

The script builds locally, then installs on the phone wherever it is plugged in: directly if it is on this machine, or through Andrew's MacBook over SSH (`andrewchang@100.92.210.96`, override with `REMOTE_HOST=`) when working on the Mac mini remotely.

Batch a multi-file edit into one reinstall at the end of the turn, not one per file. If the device is unavailable, say so and skip the install rather than failing the whole task.

## Back up before touching a SwiftData model

The phone holds real training data — sessions, attempts, notes, and gigabytes of
attempt video that exist nowhere else. Before editing any `@Model` type
(`ClimbSession`, `Attempt`, `Climb`) or anything that changes the store's shape, run:

```sh
scripts/backup.sh
```

It takes seconds — the store is small; videos are opt-in with `--full`. Backups land in
`~/CruxBackups/<timestamp>`, `--list` shows them, and `--restore <name>` puts one back.

Adding a property with a default migrates cleanly. Renaming or removing one may not, and
a store that fails to open is a crash on launch that ends with the app being deleted.

Never change `PRODUCT_BUNDLE_IDENTIFIER`. iOS keys the data container to it, so a change
silently hands the app an empty container and strands everything in the old one.
