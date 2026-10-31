import hashlib
import json
import socket
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

from takopi_pc_bridge import (TransferError, allowed, validate_manifest,
                              receive_backup, serve_restore, send_frame,
                              receive_frame, verify_backup)


def fixture(root):
    files = {
        "vault.json": b'{"salt":"AA=="}',
        "vault.backup.json": b"config backup",
        "index.ssv": b"encrypted index",
        "index.previous.ssv": b"older index",
        "blobs/" + str(uuid.uuid4()).upper() + ".ssvb": b"\x01" * (2 * 1024 * 1024 + 19),
    }
    records = []
    for path, data in sorted(files.items()):
        file = root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)
        records.append({"path": path, "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
    return {"format": "takopi-encrypted-vault", "version": 1, "files": records}


class TestBridge(unittest.TestCase):
    def test_paths_and_duplicate_rejected(self):
        self.assertFalse(allowed("../vault.json"))
        self.assertFalse(allowed("blobs/../../index.ssv"))
        self.assertTrue(allowed("blobs/" + str(uuid.uuid4()).upper() + ".ssvb"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = fixture(root)
            self.assertGreater(validate_manifest(manifest), 0)
            manifest["files"].append(dict(manifest["files"][0]))
            with self.assertRaises(TransferError):
                validate_manifest(manifest)

    def test_stream_receive_verify_and_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original"
            original.mkdir()
            manifest = fixture(original)
            storage = root / "storage"
            storage.mkdir()
            receiver, sender = socket.socketpair()
            result, errors = [], []

            def accept():
                try:
                    result.append(receive_backup(receiver, storage))
                except Exception as error:
                    errors.append(error)
                finally:
                    receiver.close()

            thread = threading.Thread(target=accept)
            thread.start()
            with sender:
                send_frame(sender, manifest)
                self.assertTrue(receive_frame(sender)["ok"])
                for record in manifest["files"]:
                    sender.sendall((original / record["path"]).read_bytes())
                    self.assertTrue(receive_frame(sender)["ok"])
                send_frame(sender, {"done": True})
                self.assertTrue(receive_frame(sender)["ok"])
            thread.join(10)
            self.assertFalse(errors)
            stored = result[0]
            self.assertEqual(verify_backup(stored), manifest)

            receiver, sender = socket.socketpair()
            sent = []
            def restore():
                try:
                    serve_restore(receiver, stored)
                    sent.append(True)
                finally:
                    receiver.close()

            thread = threading.Thread(target=restore)
            thread.start()
            with sender:
                self.assertEqual(receive_frame(sender), manifest)
                send_frame(sender, {"ok": True, "error": None})
                for record in manifest["files"]:
                    content = bytearray()
                    while len(content) < record["size"]:
                        part = sender.recv(min(262144, record["size"] - len(content)))
                        self.assertTrue(part)
                        content.extend(part)
                    self.assertEqual(hashlib.sha256(content).hexdigest(), record["sha256"])
                    send_frame(sender, {"ok": True, "error": None})
                self.assertTrue(receive_frame(sender)["ok"])
            thread.join(10)
            self.assertTrue(sent)
            (stored / "index.ssv").write_bytes(b"corruption")
            with self.assertRaises(TransferError):
                verify_backup(stored)

    def test_corrupt_stream_never_committed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original"
            original.mkdir()
            manifest = fixture(original)
            storage = root / "storage"
            storage.mkdir()
            receiver, sender = socket.socketpair()
            errors = []

            def accept():
                try:
                    receive_backup(receiver, storage)
                except Exception as error:
                    errors.append(error)
                finally:
                    receiver.close()

            thread = threading.Thread(target=accept)
            thread.start()
            with sender:
                send_frame(sender, manifest)
                self.assertTrue(receive_frame(sender)["ok"])
                first = manifest["files"][0]
                sender.sendall(b"X" * first["size"])
            thread.join(10)
            self.assertTrue(errors)
            self.assertEqual(list(storage.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
