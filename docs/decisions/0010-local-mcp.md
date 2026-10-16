# Opt-in local MCP bridge

Use a Python standard-library stdio server and a bounded filesystem mailbox inside the LÖVE
save directory. This avoids a socket dependency in the drop-in Lua folder and lets requests
continue while the simulation clock is paused. Session identifiers and request expiry reject
stale writes; same-account local software is trusted. Scalar live edits use the existing
history and override machinery. Project source edits are separately scoped to a configured
project and backed up. The native bridge does not run in browser exports.
