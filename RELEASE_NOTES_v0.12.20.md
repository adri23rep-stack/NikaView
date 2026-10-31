# Takopi Explorer v0.12.20 — Build 57

## Minimal Vault UI
- The Vault action bar remains fixed at the bottom of the unlocked Vault screen using Liquid Glass on supported iOS versions.
- Redesigned the Home Vault card with a smaller icon, readable adaptive text, and a subtle two-tone surface in light and dark mode.
- Removed the saturated full-width purple gradient, animated glow and distracting decorations.
- Preserved Vault encryption, Face ID/password, importing, backups, and all six action-bar controls.
- Added CI checks to prevent the toolbar returning to the header or the overly bright Vault card returning.

## Build
Unsigned arm64 IPA intended for LiveContainer testing. Automated compilation is not a substitute for testing the visual layout on a real iPhone.
