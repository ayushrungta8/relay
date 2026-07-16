# Requirement 3: Context and account capacity

## Outcome

Relay exposes per-task context consumption and account-wide capacity without
requiring `/status`, `/usage`, or account-menu navigation.

## Required behavior

- Read `account/rateLimits/read` on startup and refresh it after relevant
  notifications and at a conservative periodic interval.
- Use backend `windowDurationMins`, `usedPercent`, and `resetsAt`; do not
  hard-code the primary window as five hours or the secondary window as one
  week.
- Display both primary and secondary windows when present.
- Display reset-credit `availableCount`, expiry time, and backend title when
  details are supplied.
- Decode `thread/tokenUsage/updated` and retain the latest total, last-turn
  usage, and `modelContextWindow` for each observed thread.
- Compute context percentage only when the context window is nonzero.
- Distinguish account rate-limit consumption from thread context consumption.
- Use warning presentation at 75 percent and critical presentation at
  90 percent, while retaining the exact percentage and reset time.
- Treat unavailable usage as unavailable, never as zero.

## Acceptance

The user can see both rolling limits and their reset times, the count of usable
reset credits, and the context pressure of active tasks. Missing data results in
a restrained unavailable state rather than a misleading empty meter.
