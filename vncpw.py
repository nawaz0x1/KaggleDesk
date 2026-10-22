"""Create a TigerVNC-compatible password file (VNC's DES obfuscation)."""
import sys
from Crypto.Cipher import DES

# VNC's fixed key, with per-byte bit order already reversed for standard DES.
VNC_KEY = bytes.fromhex("e84ad660c4721ae0")


def make(pw: str) -> bytes:
    raw = pw.encode()[:8].ljust(8, b"\x00")
    return DES.new(VNC_KEY, DES.MODE_ECB).encrypt(raw)


if __name__ == "__main__":
    open(sys.argv[2], "wb").write(make(sys.argv[1]))
