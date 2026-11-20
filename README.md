# Grain Rot — Enemy Pattern Drops

UE4SS/Lua mod for Grain Rot (Helden) to unlock one randomly selected, not-yet-owned cosmetic pattern upon an enemy kill, with a test probability of 100%.

- Target: Story Mode and Expedition Mode, host-authoritative.
- No physical world drop, direct native persistent unlock.
- Do not reward the same dead enemy twice.
- Exclude already owned patterns; do nothing if all are owned.
- Status: implementation must be validated against the real game API; mock tests do not prove gameplay behavior.

Sources of engine reflection: https://github.com/SirRosa/Grain-Rot-Mod-Data-Base
