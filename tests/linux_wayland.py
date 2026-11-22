"""Exercise Brain's native Wayland process against a fragmented protocol peer."""
import array
import mmap
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time

def u32(*values):
    return struct.pack("<" + "I" * len(values), *values)

def string(value):
    raw = value.encode() + b"\0"
    return u32(len(raw)) + raw + b"\0" * (-len(raw) % 4)

def message(obj, opcode, body=b""):
    return struct.pack("<IHH", obj, opcode, len(body) + 8) + body

def run(executable, with_seat):
    with tempfile.TemporaryDirectory(prefix="brain-wayland-") as temporary:
        root = Path(temporary)
        fixture = root / "document's.txt"
        fixture.write_text("12345🦋\n")
        server = socket.socket(socket.AF_UNIX)
        server.bind(str(root / "wayland-test"))
        server.listen()
        server.settimeout(90)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root), WAYLAND_DISPLAY="wayland-test")
        arguments = [executable, str(fixture)] if with_seat else [executable, "--window-smoke"]
        app = subprocess.Popen(arguments, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        descriptors = []
        shared = None
        try:
            peer, _ = server.accept()
            peer.settimeout(90)
            packet = bytearray()
            received_fds = []
            types = {1: "wl_display"}
            buffers = {}
            registry = surface = top = keyboard = text_input = None
            attached = 0
            frames = 0
            pools = {}
            mappings = []
            stage = 0
            maximum_size = 0
            input_commits = 0
            def send(obj, opcode, body=b""):
                # Split even the eight-byte header to exercise stream assembly.
                raw = message(obj, opcode, body)
                for part in (raw[:3], raw[3:7], raw[7:]):
                    peer.sendall(part)
                    time.sleep(.002)
            def key(code, ctrl=0):
                send(keyboard, 4, u32(1, ctrl, 0, 0, 0))
                send(keyboard, 3, u32(1, 0, code, 1))
            while True:
                while len(packet) < 8 or len(packet) < struct.unpack_from("<H", packet, 6)[0]:
                    data, ancillary, flags, address = peer.recvmsg(65536, socket.CMSG_SPACE(64))
                    if not data:
                        break
                    packet.extend(data)
                    for level, kind, value in ancillary:
                        if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                            values = array.array("i")
                            values.frombytes(value[:len(value) - len(value) % values.itemsize])
                            received_fds.extend(values)
                            descriptors.extend(values)
                if len(packet) < 8:
                    break
                obj, opcode, size = struct.unpack_from("<IHH", packet)
                maximum_size = max(maximum_size, size)
                assert size >= 8 and size % 4 == 0, (obj, opcode, size)
                body = bytes(packet[8:size])
                del packet[:size]
                values = struct.unpack("<" + "I" * (len(body) // 4), body)
                kind = types[obj]
                if kind == "wl_display":
                    if opcode == 1:
                        registry = values[0]
                        types[registry] = "wl_registry"
                    elif opcode == 0:
                        callback = values[0]
                        globals_ = [(10,"wl_compositor",4),(11,"wl_shm",1),(12,"xdg_wm_base",1)]
                        if with_seat:
                            globals_ += [(13,"wl_seat",5),(14,"zwp_text_input_manager_v3",1)]
                        for name, interface, version in globals_:
                            send(registry, 0, u32(name) + string(interface) + u32(version))
                        send(callback, 0, u32(0))
                        send(1, 1, u32(callback))
                elif kind == "wl_registry":
                    length = values[1]
                    interface = body[8:8 + length - 1].decode()
                    new_id = struct.unpack_from("<I", body, 8 + (length + 3) // 4 * 4 + 4)[0]
                    types[new_id] = interface
                    if interface == "wl_seat":
                        send(new_id, 0, u32(2))
                elif kind == "wl_compositor" and opcode == 0:
                    surface = values[0]
                    types[surface] = "wl_surface"
                elif kind == "xdg_wm_base" and opcode == 2:
                    types[values[0]] = "xdg_surface"
                elif kind == "xdg_surface" and opcode == 1:
                    top = values[0]
                    types[top] = "xdg_toplevel"
                elif kind == "wl_seat" and opcode == 1:
                    keyboard = values[0]
                    types[keyboard] = "wl_keyboard"
                elif kind == "zwp_text_input_manager_v3" and opcode == 1:
                    text_input = values[0]
                    types[text_input] = "zwp_text_input_v3"
                elif kind == "wl_shm" and opcode == 0:
                    assert len(pools) < 2, "repainting leaked shared-memory pools"
                    pool_fd = received_fds.pop(0)
                    types[values[0]] = "wl_shm_pool"
                    mapped = mmap.mmap(pool_fd, values[1], access=mmap.ACCESS_READ)
                    pools[values[0]] = mapped
                    mappings.append(mapped)
                elif kind == "wl_shm_pool" and opcode == 0:
                    identifier, offset, width, height, stride, fmt = values
                    assert stride == width * 4 and width <= 4096 and height <= 2160
                    types[identifier] = "wl_buffer"
                    buffers[identifier] = (width, height, stride, pools[obj])
                elif kind == "wl_surface":
                    if opcode == 1:
                        attached = values[0]
                    elif opcode == 6 and not attached:
                        send(top, 0, u32(480, 240, 0))
                        shell_surface = next(k for k,v in types.items() if v == "xdg_surface")
                        send(shell_surface, 0, u32(1))
                    elif opcode == 6 and attached:
                        frames += 1
                        width,height,stride,shared = buffers[attached]
                        assert shared[0:4] == bytes([43,27,33,0]), "Orbit bar color"
                        assert shared[80*stride:80*stride+4] == bytes([31,16,22,0]), "canvas color"
                        if not with_seat:
                            break
                        assert keyboard and text_input
                        if frames == 1:
                            send(text_input, 0, u32(surface))
                        elif stage == 1:
                            for attempt in range(300):
                                if fixture.read_text() == "é12345🦋\n":
                                    break
                                time.sleep(.01)
                            assert fixture.read_text() == "é12345🦋\n", fixture.read_bytes()
                            stage = 2
                            # Resize after releasing the compositor's reference.
                            send(attached, 0)
                            send(top, 0, u32(320, 160, 0))
                            send(shell_surface, 0, u32(2))
                            continue
                        elif stage == 2:
                            if (width,height) != (320,160):
                                send(attached, 0)
                                continue
                            stage = 3
                            send(text_input, 3, string("x"))
                            send(text_input, 5, u32(input_commits))
                            # First quit is vetoed because the new edit is unsaved.
                            key(16,4)
                        elif stage == 3:
                            assert app.poll() is None
                            key(16,4)
                            break
                        if frames > 1:
                            send(attached, 0)
                elif kind == "zwp_text_input_v3":
                    if opcode == 7:
                        input_commits += 1
                        if stage == 0:
                            stage = 1
                            # Commit is buffered until done, with two messages in one write.
                            peer.sendall(message(text_input,3,string("é")) + message(text_input,5,u32(input_commits)))
                            key(31,4)
                    elif opcode == 3:
                        assert len(body) <= 4020
            for mapped in mappings:
                mapped.close()
            mappings.clear()
            shared = None
            peer.close()
            output = app.communicate(timeout=30)[0].decode(errors="replace")
            assert app.returncode == 0, (app.returncode, output)
            if with_seat:
                assert frames >= 4
                assert fixture.read_text() == "é12345🦋\n"
            else:
                assert "mapped and drew" in output
            print("PASS:", "fragmented Wayland input, UTF-8 edit/save, resize, buffer reuse, unsaved quit" if with_seat else "seatless compositor smoke")
        finally:
            if app.poll() is None:
                app.kill()
                app.wait()
            for mapped in mappings:
                mapped.close()
            for descriptor in descriptors:
                os.close(descriptor)
            server.close()

if __name__ == "__main__":
    run(str(Path(sys.argv[1]).resolve()), True)
    run(str(Path(sys.argv[1]).resolve()), False)
