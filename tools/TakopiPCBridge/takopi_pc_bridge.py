"""Takopi PC Bridge: direct encrypted Vault backup, restore and inspection.

Windows: Python 3.10+. Optional: py -m pip install cryptography
Passwords are used locally only for inspecting the encrypted index.
"""
from __future__ import annotations
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import queue
import re
import secrets
import shutil
import socket
import struct
import threading
import time
import uuid

PORT = 48933
MAGIC = b"TKPC0001"
BUFFER = 256 * 1024
MAX_MANIFEST = 32 * 1024 * 1024
MAX_FILES = 100_000
MAX_TOTAL = 500 * 1024**3
CONFIGS = {"vault.json", "vault.backup.json", "index.ssv", "index.previous.ssv"}
BLOB_NAME = re.compile(r"^blobs/([a-fA-F0-9-]{36})\.ssvb$")
THUMB_NAME = re.compile(r"^thumbnails/([a-fA-F0-9-]{36})\.nkt$")
SHA256_NAME = re.compile(r"^[0-9a-f]{64}$")


class TransferError(Exception):
    pass


def allowed(path: str) -> bool:
    if path in CONFIGS:
        return True
    for rule in (BLOB_NAME, THUMB_NAME):
        match = rule.fullmatch(path)
        if match:
            try:
                return str(uuid.UUID(match[1])).lower() == match[1].lower()
            except ValueError:
                return False
    return False


def validate_manifest(manifest: dict) -> int:
    if not isinstance(manifest, dict) or manifest.get("format") != "takopi-encrypted-vault" or manifest.get("version") != 1:
        raise TransferError("Formato de bóveda incompatible")
    files = manifest.get("files")
    if not isinstance(files, list) or not 4 <= len(files) <= MAX_FILES:
        raise TransferError("Lista de archivos inválida")
    paths = set()
    total = 0
    for record in files:
        if not isinstance(record, dict):
            raise TransferError("Registro inválido")
        path, size, digest = record.get("path"), record.get("size"), record.get("sha256")
        if not isinstance(path, str) or not allowed(path) or path in paths:
            raise TransferError("Ruta inválida o duplicada")
        if type(size) is not int or size < 0 or not isinstance(digest, str) or not SHA256_NAME.fullmatch(digest):
            raise TransferError("Tamaño o SHA-256 inválido")
        paths.add(path)
        total += size
        if total > MAX_TOTAL:
            raise TransferError("Respaldo demasiado grande")
    if not CONFIGS.issubset(paths):
        raise TransferError("Falta metadata necesaria de Takopi Vault")
    return total


def read_exact(sock: socket.socket, size: int) -> bytes:
    if size < 0:
        raise TransferError("Tamaño negativo")
    chunks = bytearray()
    while len(chunks) < size:
        chunk = sock.recv(min(BUFFER, size - len(chunks)))
        if not chunk:
            raise TransferError("Conexión interrumpida")
        chunks.extend(chunk)
    return bytes(chunks)


def receive_frame(sock: socket.socket) -> dict:
    (size,) = struct.unpack(">I", read_exact(sock, 4))
    if not 0 < size <= MAX_MANIFEST:
        raise TransferError("Mensaje inválido")
    obj = json.loads(read_exact(sock, size))
    if not isinstance(obj, dict):
        raise TransferError("Respuesta inválida")
    return obj


def send_frame(sock: socket.socket, value: dict) -> None:
    data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if not 0 < len(data) <= MAX_MANIFEST:
        raise TransferError("Mensaje demasiado grande")
    sock.sendall(struct.pack(">I", len(data)) + data)


def ack(sock: socket.socket, ok: bool = True, error: str | None = None) -> None:
    send_frame(sock, {"ok": ok, "error": error})


def require_ack(sock: socket.socket) -> None:
    response = receive_frame(sock)
    if response.get("ok") is not True:
        raise TransferError(str(response.get("error") or "El iPhone rechazó el archivo"))


def safe_file(root: Path, relative: str) -> Path:
    if not allowed(relative):
        raise TransferError("Ruta prohibida")
    result = root.joinpath(*relative.split("/"))
    if root.is_symlink() or result.is_symlink() or result.parent.is_symlink():
        raise TransferError("Enlace simbólico prohibido")
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while part := source.read(BUFFER):
            digest.update(part)
    return digest.hexdigest()


def verify_backup(folder: Path, status=lambda text: None) -> dict:
    manifest_file = folder / "manifest.json"
    if folder.is_symlink() or manifest_file.is_symlink():
        raise TransferError("Carpeta enlazada no permitida")
    if manifest_file.stat().st_size > MAX_MANIFEST:
        raise TransferError("Manifest demasiado grande")
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    total = validate_manifest(manifest)
    for i, record in enumerate(manifest["files"], 1):
        file = safe_file(folder, record["path"])
        if not file.is_file() or file.stat().st_size != record["size"]:
            raise TransferError("Archivo perdido o de tamaño incorrecto: " + record["path"])
        if sha256(file) != record["sha256"]:
            raise TransferError("SHA-256 incorrecto: " + record["path"])
        if i % 5 == 0 or i == len(manifest["files"]):
            status(f"Verificados {i}/{len(manifest['files'])} archivos")
    status(f"Respaldo íntegro: {len(manifest['files'])} archivos, {total:,} bytes")
    return manifest


def receive_backup(conn: socket.socket, base: Path, status=lambda text: None) -> Path:
    manifest = receive_frame(conn)
    total = validate_manifest(manifest)
    if shutil.disk_usage(base).free < total + 16 * 1024**2:
        raise TransferError("No hay espacio suficiente en la PC")
    now = time.strftime("%Y%m%d-%H%M%S")
    destination = base / f"Takopi-Vault-{now}-{uuid.uuid4().hex[:6]}"
    temp = base / (".takopi-incomplete-" + uuid.uuid4().hex)
    temp.mkdir(mode=0o700)
    success = False
    try:
        ack(conn)
        for index, record in enumerate(manifest["files"], 1):
            output = safe_file(temp, record["path"])
            output.parent.mkdir(parents=True, exist_ok=True)
            remaining = record["size"]
            digest = hashlib.sha256()
            with output.open("xb") as target:
                while remaining:
                    block = read_exact(conn, min(BUFFER, remaining))
                    target.write(block)
                    digest.update(block)
                    remaining -= len(block)
                target.flush()
                os.fsync(target.fileno())
            if digest.hexdigest() != record["sha256"]:
                raise TransferError("SHA-256 incorrecto: " + record["path"])
            ack(conn)
            status(f"Recibidos {index}/{len(manifest['files'])}: {record['path']}")
        if receive_frame(conn) != {"done": True}:
            raise TransferError("No se recibió la confirmación final")
        for name in ("index.ssv", "vault.json"):
            record = next(item for item in manifest["files"] if item["path"] == name)
            if sha256(safe_file(temp, name)) != record["sha256"]:
                raise TransferError("Metadata incompleta")
        (temp / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        temp.rename(destination)
        success = True
        ack(conn)
        status("RESPALDO COMPLETO Y VERIFICADO: " + str(destination))
        return destination
    finally:
        if not success:
            shutil.rmtree(temp, ignore_errors=True)


def serve_restore(conn: socket.socket, folder: Path, status=lambda text: None) -> None:
    manifest = verify_backup(folder, status)
    send_frame(conn, manifest)
    require_ack(conn)
    for i, record in enumerate(manifest["files"], 1):
        file = safe_file(folder, record["path"])
        with file.open("rb") as source:
            while chunk := source.read(BUFFER):
                conn.sendall(chunk)
        require_ack(conn)
        status(f"Enviados {i}/{len(manifest['files'])}: {record['path']}")
    ack(conn)
    status("Archivos cifrados enviados. El iPhone debe validar la contraseña y restaurar.")


def serve_one(listener: socket.socket, mode: bytes, token: bytes,
              folder: Path, status=lambda text: None) -> None:
    conn, address = listener.accept()
    with conn:
        conn.settimeout(120)
        try:
            address_ip = ipaddress.ip_address(address[0])
            if not (address_ip.is_private or address_ip.is_loopback):
                raise TransferError("Conexión fuera de red privada rechazada")
            hello = read_exact(conn, 25)
            if hello[:8] != MAGIC or not hmac.compare_digest(hello[8:24], token) or hello[24:25] != mode:
                raise TransferError("Código incorrecto o modo incompatible")
            ack(conn)
            if mode == b"B":
                receive_backup(conn, folder, status)
            else:
                serve_restore(conn, folder, status)
        except Exception as exc:
            try:
                ack(conn, False, str(exc))
            except OSError:
                pass
            raise


def virtual_entries(folder: Path, password: str) -> list[str]:
    """Show virtual filenames in RAM only; ciphertext files never decrypted on disk."""
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError as exc:
        raise TransferError("Instala el lector con: py -m pip install cryptography") from exc
    verify_backup(folder)
    config = json.loads((folder / "vault.json").read_text("utf-8"))
    import base64
    salt, verifier = base64.b64decode(config["salt"]), base64.b64decode(config["verifier"])
    if len(salt) != 16:
        raise TransferError("Salt inválida")
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 310_001, dklen=32)

    def decrypt(data: bytes) -> bytes:
        if len(data) < 28:
            raise TransferError("Índice cifrado inválido")
        return AESGCM(key).decrypt(data[:12], data[12:], None)

    try:
        if decrypt(verifier) != b"SolidSecPrivateVault-v1":
            raise TransferError("Contraseña incorrecta")
        entries = json.loads(decrypt((folder / "index.ssv").read_bytes()))
    except Exception as exc:
        raise TransferError("Contraseña incorrecta o índice cifrado dañado") from exc
    if not isinstance(entries, list) or len(entries) > MAX_FILES:
        raise TransferError("Índice inválido")
    mapped = {str(item["id"]): item for item in entries}
    if len(mapped) != len(entries):
        raise TransferError("Hay IDs duplicados en el índice")
    physical = {record["path"] for record in json.loads(
        (folder / "manifest.json").read_text(encoding="utf-8"))["files"]}
    paths = []
    for item in entries:
        if item.get("kind") == "file":
            blob_name = item.get("blobName")
            if (not isinstance(blob_name, str)
                    or not allowed("blobs/" + blob_name)
                    or "blobs/" + blob_name not in physical):
                raise TransferError("Falta el archivo cifrado de: " + str(item.get("name")))
        seen = set()
        parts = [str(item.get("name", ""))]
        parent = item.get("parentID")
        while parent:
            if parent in seen or parent not in mapped or len(seen) > len(entries):
                raise TransferError("Jerarquía inválida")
            seen.add(parent)
            item_parent = mapped[parent]
            parts.insert(0, str(item_parent.get("name", "")))
            parent = item_parent.get("parentID")
        paths.append(("📁 " if item.get("kind") == "folder" else "📄 ") + "/".join(parts))
    return sorted(paths, key=str.casefold)


def local_ipv4() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("192.0.2.1", 80))
            return sock.getsockname()[0]
    except OSError:
        return "IP de Windows (consulta ipconfig)"


def pairing_uri(host: str, code: str, mode: bytes) -> str:
    """A one-use LAN pairing QR; never contains a Vault password or files."""
    try:
        address = ipaddress.IPv4Address(host)
    except ipaddress.AddressValueError as exc:
        raise TransferError("No hay IPv4 local válida para el QR; usa ipconfig.") from exc
    if not (address.is_private or address.is_link_local):
        raise TransferError("El QR solo se permite en redes privadas.")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", code):
        raise TransferError("Código de conexión inválido.")
    if mode not in (b"B", b"R"):
        raise TransferError("Modo inválido.")
    return f"takopi-pc://pair?v=1&host={address}&port={PORT}&code={code.lower()}&mode={mode.decode('ascii')}"


def start_gui() -> None:
    import tkinter as tk
    from tkinter import filedialog, messagebox, scrolledtext, simpledialog, ttk

    app = tk.Tk()
    app.title("Takopi PC Bridge · Vault")
    app.geometry("850x760")
    app.minsize(680, 610)
    messages: queue.Queue[object] = queue.Queue()
    status_text = tk.StringVar(value="Selecciona dónde guardar o cuál respaldo restaurar.")
    connection_text = tk.StringVar(value="")
    root = ttk.Frame(app, padding=18)
    root.pack(fill="both", expand=True)
    ttk.Label(root, text="Takopi PC Bridge", font=("Segoe UI", 20, "bold")).pack(anchor="w")
    ttk.Label(root, text="Vault cifrado · transferencia directa · verificación SHA-256").pack(anchor="w", pady=(0, 12))
    ttk.Label(root, textvariable=status_text, wraplength=740).pack(anchor="w", pady=4)
    ttk.Label(root, textvariable=connection_text, font=("Consolas", 11), wraplength=740).pack(anchor="w", pady=4)
    qr_frame = ttk.Frame(root)
    qr_frame.pack(fill="x", pady=(5, 2))
    qr_label = ttk.Label(qr_frame, text="El código QR aparecerá al iniciar una sesión.")
    qr_label.pack(side="left", padx=(8, 18))
    qr_note = ttk.Label(qr_frame, text="QR temporal de una sola conexión.\nNo contiene tu contraseña.", wraplength=360)
    qr_note.pack(side="left")
    qr_image_state = {"image": None}

    def hide_pairing_qr() -> None:
        qr_label.configure(image="", text="El código QR aparecerá al iniciar una sesión.")
        qr_image_state["image"] = None

    def show_pairing_qr(host: str, token: bytes, mode: bytes) -> None:
        try:
            import qrcode
            from PIL import ImageTk
            payload = pairing_uri(host, token.hex(), mode)
            qr = qrcode.QRCode(border=2, box_size=7, error_correction=qrcode.constants.ERROR_CORRECT_M)
            qr.add_data(payload)
            qr.make(fit=True)
            rendered = qr.make_image(fill_color="black", back_color="white").convert("RGB")
            rendered.thumbnail((230, 230))
            photo = ImageTk.PhotoImage(rendered, master=app)
            qr_image_state["image"] = photo
            qr_label.configure(image=photo, text="")
            qr_note.configure(text="Escanea desde Takopi en el iPhone.\nLa IP y el código se llenan solos.")
        except (ImportError, TransferError) as exc:
            hide_pairing_qr()
            qr_note.configure(text="QR no disponible: " + str(exc) + "\nPuedes introducir la IP y el código manualmente.")

    log = scrolledtext.ScrolledText(root, state="disabled", height=16)
    log.pack(side="bottom", fill="both", expand=True, pady=(14, 0))
    buttons = ttk.Frame(root)
    buttons.pack(fill="x", pady=12)
    current_server = {"socket": None}

    def write_line(text: str) -> None:
        log.configure(state="normal")
        log.insert("end", text + "\n")
        log.see("end")
        log.configure(state="disabled")
        status_text.set(text)

    def poll() -> None:
        try:
            while True:
                message = messages.get_nowait()
                if isinstance(message, tuple) and message == ("session_end",):
                    current_server["socket"] = None
                    connection_text.set("")
                    hide_pairing_qr()
                else:
                    write_line(str(message))
        except queue.Empty:
            pass
        app.after(120, poll)

    def start(mode: bytes, folder: Path) -> None:
        if current_server["socket"] is not None:
            messagebox.showinfo("Sesión activa", "Termina o cancela la conexión actual primero.")
            return
        token = secrets.token_bytes(16)
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("0.0.0.0", PORT))
            listener.listen(1)
            listener.settimeout(240)
        except OSError as exc:
            listener.close()
            messagebox.showerror("No se pudo abrir el puerto", str(exc))
            return
        current_server["socket"] = listener
        network_ip = local_ipv4()
        connection_text.set(f"IP de PC: {network_ip}   Puerto: {PORT}   Código: {token.hex()}")
        show_pairing_qr(network_ip, token, mode)
        write_line("En el iPhone: Takopi Vault → Respaldo a PC. Introduce IP y código."
                   if mode == b"B" else "En el iPhone: Takopi Vault → Restaurar desde PC. Introduce IP, código y contraseña de Vault.")

        def task():
            try:
                serve_one(listener, mode, token, folder, messages.put)
            except Exception as exc:
                messages.put("Sesión terminada: " + str(exc))
            finally:
                listener.close()
                # Tkinter UI must only be touched by its main thread.
                messages.put(("session_end",))
        threading.Thread(target=task, daemon=True).start()

    def receive() -> None:
        location = filedialog.askdirectory(title="Elige carpeta de destino EN LA PC")
        if location:
            start(b"B", Path(location))

    def restore() -> None:
        location = filedialog.askdirectory(title="Elige una carpeta Takopi-Vault respaldada")
        if location:
            start(b"R", Path(location))

    def verify() -> None:
        location = filedialog.askdirectory(title="Selecciona respaldo para verificar")
        if not location:
            return
        def task():
            try:
                verify_backup(Path(location), messages.put)
            except Exception as exc:
                messages.put("ERROR DE VERIFICACIÓN: " + str(exc))
        threading.Thread(target=task, daemon=True).start()

    def inspect() -> None:
        location = filedialog.askdirectory(title="Elige el respaldo cifrado")
        if not location:
            return
        password = simpledialog.askstring("Ver contenido", "Contraseña de Takopi Vault (solo en esta PC):", show="*", parent=app)
        if password is None:
            return
        def task():
            try:
                entries = virtual_entries(Path(location), password)
                messages.put(f"Contenido: {len(entries)} archivos/carpetas")
                messages.put("\n".join(entries) if entries else "La bóveda está vacía")
            except Exception as exc:
                messages.put("No se pudo ver el contenido: " + str(exc))
        threading.Thread(target=task, daemon=True).start()

    ttk.Button(buttons, text="Recibir respaldo del iPhone", command=receive).pack(side="left", padx=(0, 8))
    ttk.Button(buttons, text="Restaurar al iPhone", command=restore).pack(side="left", padx=8)
    ttk.Button(buttons, text="Verificar copia", command=verify).pack(side="left", padx=8)
    ttk.Button(buttons, text="Ver archivos", command=inspect).pack(side="left", padx=8)
    def close():
        if current_server["socket"] is not None:
            current_server["socket"].close()
        app.destroy()
    app.protocol("WM_DELETE_WINDOW", close)
    app.after(120, poll)
    app.mainloop()


if __name__ == "__main__":
    start_gui()
