# Takopi PC Bridge (Windows)

Back up the **encrypted original Takopi Vault files directly to Windows** without creating a full ZIP backup on the iPhone. This is a separate option from the existing Files/iCloud ZIP export.

## Features

- Receive: iPhone to Windows, encrypted files transferred in 256 KiB chunks.
- Verify: check every file size and SHA-256 against manifest.json.
- View: type the Vault password locally in Windows to list actual filenames and folder structure from the encrypted index. Files remain encrypted.
- Restore: PC to iPhone, verify ciphertext checksums and Vault password/index before replacing any live data.

## Windows app

Download the **Takopi-PC-Bridge-Windows** ZIP from the Windows GitHub Actions build, extract it and run Takopi-PC-Bridge.exe.

Or run with Windows Python 3.10 or newer:

    py tools\TakopiPCBridge\takopi_pc_bridge.py

To enable viewing decrypted filenames when running the Python script:

    py -m pip install cryptography

The EXE build includes this library.

## Backup (iPhone -> PC)

1. Connect iPhone and PC to the same trusted private Wi-Fi/LAN.
2. In the Windows tool, choose **Recibir respaldo del iPhone** and a PC destination folder.
3. The PC shows a **one-time QR code** with its private IP and a 32-character code (port 48933). Allow Windows Firewall on **Private networks only**.
4. Unlock Takopi Vault on iPhone, open the Vault menu, tap **Respaldo directo a Windows (sin ZIP)**.
5. Tap **Escanear QR de Windows**, scan the QR on the PC and confirm **Iniciar respaldo a PC**. The IP and code can still be entered manually. Keep Takopi open and iPhone awake.
6. On PC, use **Verificar copia** with the new Takopi-Vault-... directory. Optionally choose **Ver archivos** and type your Vault password locally to view the original filenames.

Do **not** reinstall Takopi, delete the Vault, or clear the phone until the PC backup verifies and your expected content is listed.

## Restore (PC -> iPhone)

1. PC: choose **Restaurar al iPhone** and select the previously verified Takopi-Vault-... backup folder.
2. iPhone: from the locked Vault screen choose **Restaurar Vault desde Windows**, or open Restore from the unlocked Vault menu.
3. Scan the PC QR with **Escanear QR de Windows**, or enter its IP and fresh pairing code manually. Enter the original Vault password on the iPhone.
4. Takopi streams ciphertext into a protected staging folder, verifies checksums, authenticates the Vault password and encrypted index, then swaps the complete Vault.
5. Unlock with your original password. Face ID needs to be set up again.

Restore needs free iPhone space for the encrypted files; it does not make a second large ZIP.

## Security and limits

- Encrypted contents are never decrypted for transfer, and the Vault password is never sent through the connection.
- This is **ordinary local TCP, not TLS**. The pairing code and metadata can be exposed to anyone sniffing the LAN. Use **trusted private networks only**, and NEVER forward port 48933 to the internet.
- Pairing codes are random 128-bit tokens valid for one connection. The QR contains only the PC's private IP, port, mode and pairing code; **no Vault password**. Anyone who can scan the QR can attempt to connect during that session; do not show it publicly.
- The QR scanner requires a camera-capable host app with an iOS camera-usage declaration; manual pairing remains available (some LiveContainer hosts may not expose camera access). Scanning the QR never automatically begins a transfer.
- If iOS terminates unexpectedly during backup, Takopi shows the last saved non-sensitive transfer stage when reopened to help identify the crash; it does not independently prove the root cause.
- Hash/size mismatch aborts a backup. Incomplete PC folders are removed. Restores cannot replace the Vault until its password and index are validated.
- PC backups are directories containing encrypted files and manifest.json, NOT regular .tkvault ZIP archives. Use this companion for restoring them.
- Keep Takopi in the foreground; one operation at a time.
- Windows can display filenames after local password entry, not previews or plaintext file exports.
- This backs up **Takopi Vault, not BloomBox or its installed apps**.

## Tests

    py -m unittest discover -s tools\TakopiPCBridge -p "test_*.py" -v

GitHub Actions builds the portable Windows EXE and the existing IPA workflow checks iOS integration when opening a pull request.
