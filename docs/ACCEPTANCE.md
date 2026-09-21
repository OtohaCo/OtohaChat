# Local vs hosted verification

Record actual commands here after they run. Do not mark unrun live tests as passing.

## PCC core loop

Status: `BLOCKED_CONFIGURATION`

Required (not run without a granted entitlement and `OTOHACHAT_PCC_LIVE=1`):

PCC → RC3 Agent → Session → Run → Calculator → Core executor → tool result → second PCC turn → terminal → drain

Unsigned clones still ship the ordinary app, other providers, and the OtohaChat-PCC scheme/entitlements file.
