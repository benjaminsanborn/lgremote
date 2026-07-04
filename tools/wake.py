#!/usr/bin/env python3
"""Send Wake-on-LAN magic packets from a Mac to confirm the TV wakes on
broadcast WoL. macOS has no broadcast entitlement restriction, so this tests
the mechanism the iOS app will use once Apple grants the multicast entitlement.

Usage: python3 tools/wake.py [MAC] [unicast-ip]
"""
import socket
import sys

mac = (sys.argv[1] if len(sys.argv) > 1 else "34:e6:e6:a4:f5:fc").replace(":", "").replace("-", "")
unicast = sys.argv[2] if len(sys.argv) > 2 else "192.168.1.168"
packet = b"\xff" * 6 + bytes.fromhex(mac) * 16

for target in ("255.255.255.255", "192.168.1.255", unicast):
    for port in (9, 7):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        try:
            s.sendto(packet, (target, port))
            print(f"{target}:{port} ok")
        except OSError as e:
            print(f"{target}:{port} {e}")
        finally:
            s.close()
