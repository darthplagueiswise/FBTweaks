#!/usr/bin/env python3
"""Attach the names observer and write its structured events; never spawn the app."""
import argparse
import json
import os
from pathlib import Path
import sys
import threading


def event_record(message):
    if message.get("type") != "send":
        return {"event": "agent_script_error", "message": "Agent error; capture is incomplete"}
    payload = message.get("payload")
    if not isinstance(payload, dict) or not isinstance(payload.get("event"), str):
        return None
    return payload


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--process", default="Facebook", help="Running process name (default: Facebook)")
    target.add_argument("--pid", type=int, help="Running process ID")
    parser.add_argument("--device", help="Frida device ID; default is USB")
    parser.add_argument("--output", type=Path, default=Path("diagnostics/names_diagnostic.jsonl"))
    args = parser.parse_args(argv)
    try:
        import frida
    except ImportError:
        parser.exit(2, "Install the host dependency: python3 -m pip install frida-tools\n")
    script_path = Path(__file__).with_name("trace_names_transport.js")
    stopped = threading.Event()
    failed = threading.Event()
    session = None
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        # Exclusive creation prevents accidental replacement or following a file symlink.
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        parser.exit(2, "Output exists. Choose a new --output path.\n")
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        lock = threading.Lock()

        def on_message(message, _data):
            record = event_record(message)
            if record is None:
                return
            with lock:
                output.write(json.dumps(record, ensure_ascii=False) + "\n")
                output.flush()
            print(record["event"], flush=True)
            if record["event"] in {"observer_start_failed", "agent_script_error"}:
                failed.set()
                stopped.set()

        def on_detached(*_args):
            stopped.set()

        try:
            device = frida.get_device(args.device, timeout=5) if args.device else frida.get_usb_device(timeout=5)
            session = device.attach(args.pid if args.pid is not None else args.process)
            session.on("detached", on_detached)
            script = session.create_script(script_path.read_text(encoding="utf-8"))
            script.on("message", on_message)
            script.load()
            print("Wait for observer_ready. Attempt Force name download once, then Ctrl+C.", flush=True)
            stopped.wait()
        except KeyboardInterrupt:
            pass
        except Exception as exc:
            print(f"Capture failed ({type(exc).__name__}); check the device/app attachment.", file=sys.stderr)
            failed.set()
        finally:
            if session is not None:
                try:
                    session.detach()
                except Exception:
                    pass
    print(f"Events saved: {args.output}")
    return 1 if failed.is_set() else 0


if __name__ == "__main__":
    raise SystemExit(main())
