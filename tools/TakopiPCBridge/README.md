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
3. Copy the Windows IP and one-time 32-character pairing code (port 48933). Allow Windows Firewall on **Private networks only**.
4. Unlock Takopi Vault on iPhone, open the Vault menu, tap **Respaldo directo a Windows (sin ZIP)**.
5. Enter the IP and pairing code, and keep Takopi open and iPhone awake.
6. On PC, use **Verificar copia** with the new Takopi-Vault-... directory. Optionally choose **Ver archivos** and type your Vault password locally to view the original filenames.

Do **not** reinstall Takopi, delete the Vault, or clear the phone until the PC backup verifies and your expected content is listed.

## Restore (PC -> iPhone)

1. PC: choose **Restaurar al iPhone** and select the previously verified Takopi-Vault-... backup folder.
2. iPhone: from the locked Vault screen choose **Restaurar Vault desde Windows**, or open Restore from the unlocked Vault menu.
3. Enter the PC IP, fresh pairing code, and the original Vault password on the iPhone.
4. Takopi streams ciphertext into a protected staging folder, verifies checksums, authenticates the Vault password and encrypted index, then swaps the complete Vault.
5. Unlock with your original password. Face ID needs to be set up again.

Restore needs free iPhone space for the encrypted files; it does not make a second large ZIP.

## Security and limits

- Encrypted contents are never decrypted for transfer, and the Vault password is never sent through the connection.
- This is **ordinary local TCP, not TLS**. The pairing code and metadata can be exposed to anyone sniffing the LAN. Use **trusted private networks only**, and NEVER forward port 48933 to the internet.
- Pairing codes are random 128-bit tokens valid for one connection.
- Hash/size mismatch aborts a backup. Incomplete PC folders are removed. Restores cannot replace the Vault until its password and index are validated.
- PC backups are directories containing encrypted files and manifest.json, NOT regular .tkvault ZIP archives. Use this companion for restoring them.
- Keep Takopi in the foreground; one operation at a time.
- Windows can display filenames after local password entry, not previews or plaintext file exports.
- This backs up **Takopi Vault, not BloomBox or its installed apps**.

## Tests

    py -m unittest discover -s tools\TakopiPCBridge -p "test_*.py" -v

GitHub Actions builds the portable Windows EXE and the existing IPA workflow checks iOS integration when opening a pull request.
