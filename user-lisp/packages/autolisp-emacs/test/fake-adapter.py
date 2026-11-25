"""A stand-in for AutoLispDebugAdapter.exe, for tests.

Speaks just enough of the Debug Adapter Protocol, answers initialize the way
the AutoCAD 2027 adapter does, and logs every request to argv[1].
"""
import json
import sys

log = open(sys.argv[1], "a", encoding="utf-8")
seq = 0
program = ""


def send(message):
    global seq
    seq += 1
    message["seq"] = seq
    data = json.dumps(message).encode()
    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
    sys.stdout.buffer.flush()


def event(name, body):
    send({"type": "event", "event": name, "body": body})


CAPS = {"supportsConfigurationDoneRequest": True, "supportsEvaluateForHovers": True}

while True:
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        line = line.strip()
        if not line:
            break
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":")[1])
    request = json.loads(sys.stdin.buffer.read(length))
    command, args = request["command"], request.get("arguments")
    log.write(json.dumps({"command": command, "arguments": args}) + "\n")
    log.flush()

    body = {}
    if command == "initialize":
        body = CAPS
    elif command == "attach":
        program = args["program"]
    elif command == "setBreakpoints":
        body = {"breakpoints": [{"verified": True, "line": b["line"]}
                                for b in args.get("breakpoints", [])]}
    elif command == "threads":
        body = {"threads": [{"id": 1, "name": "main"}]}
    elif command == "stackTrace":
        # As AutoCAD 2027 does: frames of its own around the user's.
        body = {"stackFrames": [
            {"id": 0, "line": 0, "column": 0, "name": ":BREAK-POINT"},
            {"id": 147, "line": 2, "column": 3, "name": "FOO",
             "source": {"name": "err.lsp", "path": program}},
            {"id": 0, "line": 0, "column": 0, "name": ":TOP-COMMAND"}],
            "totalFrames": 3}
    elif command == "evaluate":
        body = {"result": "3", "variablesReference": 0}
    send({"type": "response", "request_seq": request["seq"], "success": True,
          "command": command, "body": body})
    if command == "initialize":
        event("initialized", CAPS)
    elif command == "continue":
        event("continued", {"threadId": 1})
    elif command == "configurationDone":
        event("stopped", {"reason": "breakpoint", "threadId": 1})
    elif command == "customLoad":
        event("runtimeerror", {"file": args, "startline": 2, "startcol": 2,
                               "endline": 2, "endcol": 7,
                               "message": "bad argument type"})
