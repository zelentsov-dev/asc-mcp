#!/usr/bin/env python3

import argparse
import json
import os
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


class SmokeFailure(RuntimeError):
    pass


class JSONRPCClient:
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        if process.stdin is None or process.stdout is None:
            raise SmokeFailure("MCP process pipes are unavailable")
        self.process = process
        self.stdin = process.stdin
        self.stdout = process.stdout
        self.buffer = bytearray()

    def send(self, message: dict[str, Any]) -> None:
        payload = json.dumps(message, separators=(",", ":")).encode("utf-8") + b"\n"
        self.stdin.write(payload)
        self.stdin.flush()

    def receive(self, response_id: int, timeout: float) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            line = self._readline(deadline)
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as error:
                raise SmokeFailure(f"MCP stdout contained invalid JSON: {line[:200]!r}") from error
            if not isinstance(payload, dict):
                raise SmokeFailure("MCP stdout JSON-RPC payload is not an object")
            if payload.get("id") == response_id:
                return payload

    def _readline(self, deadline: float) -> str:
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                raw = bytes(self.buffer[:newline])
                del self.buffer[: newline + 1]
                return raw.rstrip(b"\r").decode("utf-8")

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SmokeFailure("Timed out waiting for an MCP JSON-RPC response")

            ready, _, _ = select.select([self.stdout.fileno()], [], [], remaining)
            if not ready:
                continue
            chunk = os.read(self.stdout.fileno(), 65536)
            if not chunk:
                raise SmokeFailure(
                    f"MCP process closed stdout unexpectedly with exit code {self.process.poll()}"
                )
            self.buffer.extend(chunk)


def non_negative_integer(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an integer") from error
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return parsed


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise an asc-mcp binary over MCP stdio")
    parser.add_argument("--binary", required=True)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--expected-tool-count", required=True, type=non_negative_integer)
    parser.add_argument("--expected-prefix", required=True)
    parser.add_argument("--expected-prefix-count", required=True, type=non_negative_integer)
    parser.add_argument("--error-tool", required=True)
    return parser.parse_args()


def response_result(payload: dict[str, Any], operation: str) -> dict[str, Any]:
    if "error" in payload:
        raise SmokeFailure(f"{operation} returned a JSON-RPC error: {payload['error']!r}")
    result = payload.get("result")
    if not isinstance(result, dict):
        raise SmokeFailure(f"{operation} did not return an object result")
    return result


def validate_initialize(result: dict[str, Any], expected_version: str) -> str:
    server_info = result.get("serverInfo")
    if not isinstance(server_info, dict):
        raise SmokeFailure("initialize result is missing serverInfo")
    version = server_info.get("version")
    if version != expected_version:
        raise SmokeFailure(f"expected server version {expected_version!r}, received {version!r}")
    return version


def validate_tools(
    result: dict[str, Any],
    expected_count: int,
    expected_prefix: str,
    expected_prefix_count: int,
    error_tool: str,
) -> tuple[list[str], int]:
    tools = result.get("tools")
    if not isinstance(tools, list):
        raise SmokeFailure("tools/list result is missing the tools array")
    if result.get("nextCursor") is not None:
        raise SmokeFailure("tools/list unexpectedly returned a pagination cursor")

    names: list[str] = []
    for index, tool in enumerate(tools):
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str):
            raise SmokeFailure(f"tools[{index}] is missing a string name")
        names.append(tool["name"])

    if len(names) != expected_count:
        raise SmokeFailure(f"expected {expected_count} tools, received {len(names)}")

    duplicate_names = sorted({name for name in names if names.count(name) > 1})
    if duplicate_names:
        raise SmokeFailure(f"duplicate tool names: {duplicate_names[:10]!r}")

    prefix_count = sum(name.startswith(expected_prefix) for name in names)
    if prefix_count != expected_prefix_count:
        raise SmokeFailure(
            f"expected {expected_prefix_count} tools with prefix {expected_prefix!r}, "
            f"received {prefix_count}"
        )
    if error_tool not in names:
        raise SmokeFailure(f"error tool {error_tool!r} is absent from tools/list")
    return names, prefix_count


def validate_error_result(result: dict[str, Any], error_tool: str) -> None:
    if result.get("isError") is not True:
        raise SmokeFailure(f"{error_tool} with empty arguments did not return isError=true")

    structured = result.get("structuredContent")
    if not isinstance(structured, dict):
        raise SmokeFailure(f"{error_tool} error is missing structuredContent")
    if structured.get("success") is not False:
        raise SmokeFailure(f"{error_tool} structuredContent.success is not false")
    if not isinstance(structured.get("error"), str) or not structured["error"]:
        raise SmokeFailure(f"{error_tool} structuredContent.error is missing or empty")
    if "details" not in structured:
        raise SmokeFailure(f"{error_tool} structuredContent.details is missing")

    content = result.get("content")
    if not isinstance(content, list):
        raise SmokeFailure(f"{error_tool} error is missing content")
    text_blocks = [
        block.get("text")
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ]
    if not text_blocks or not isinstance(text_blocks[-1], str):
        raise SmokeFailure(f"{error_tool} error has no final text block")
    try:
        mirror = json.loads(text_blocks[-1])
    except json.JSONDecodeError as error:
        raise SmokeFailure(f"{error_tool} final text block is not a JSON mirror") from error
    if mirror != structured:
        raise SmokeFailure(f"{error_tool} structuredContent and final JSON mirror differ")


def close_process(process: subprocess.Popen[bytes]) -> int:
    if process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.close()
        except BrokenPipeError:
            pass
    try:
        exit_code = process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            exit_code = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            exit_code = process.wait(timeout=5)
    if process.stdout is not None and not process.stdout.closed:
        process.stdout.close()
    return exit_code


def run_smoke(arguments: argparse.Namespace) -> dict[str, Any]:
    binary = Path(arguments.binary).expanduser().resolve()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise SmokeFailure(f"binary is not an executable file: {binary}")

    with tempfile.TemporaryDirectory(prefix="asc-mcp-stdio-smoke-") as directory:
        smoke_directory = Path(directory)
        key_path = smoke_directory / "AuthKey.p8"
        config_path = smoke_directory / "companies.json"
        subprocess.run(
            [
                "openssl",
                "genpkey",
                "-algorithm",
                "EC",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
                "-out",
                str(key_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        config_path.write_text(
            json.dumps(
                {
                    "companies": [
                        {
                            "id": "ci-smoke",
                            "name": "CI Smoke",
                            "key_id": "SMOKEKEY",
                            "issuer_id": "00000000-0000-0000-0000-000000000000",
                            "key_path": str(key_path),
                        }
                    ]
                },
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )

        environment = os.environ.copy()
        environment["ASC_MCP_COMPANIES"] = str(config_path)
        stderr_path = smoke_directory / "stderr.log"
        process: subprocess.Popen[bytes] | None = None
        exit_code: int | None = None
        try:
            with stderr_path.open("wb") as stderr_file:
                process = subprocess.Popen(
                    [str(binary), "--companies", str(config_path)],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=stderr_file,
                    env=environment,
                    bufsize=0,
                )
                client = JSONRPCClient(process)
                client.send(
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {},
                            "clientInfo": {"name": "asc-mcp-ci-smoke", "version": "1.0"},
                        },
                    }
                )
                initialize_result = response_result(client.receive(1, 30), "initialize")
                version = validate_initialize(initialize_result, arguments.expected_version)

                client.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
                client.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
                tools_result = response_result(client.receive(2, 30), "tools/list")
                tool_names, prefix_count = validate_tools(
                    tools_result,
                    arguments.expected_tool_count,
                    arguments.expected_prefix,
                    arguments.expected_prefix_count,
                    arguments.error_tool,
                )

                client.send(
                    {
                        "jsonrpc": "2.0",
                        "id": 3,
                        "method": "tools/call",
                        "params": {"name": arguments.error_tool, "arguments": {}},
                    }
                )
                error_result = response_result(client.receive(3, 30), "tools/call")
                validate_error_result(error_result, arguments.error_tool)
                exit_code = close_process(process)
                if exit_code != 0:
                    raise SmokeFailure(f"MCP process exited with code {exit_code}")
        except Exception as error:
            if process is not None:
                exit_code = close_process(process)
            stderr_tail = stderr_path.read_text(encoding="utf-8", errors="replace")[-4000:]
            if stderr_tail:
                raise SmokeFailure(f"{error}; MCP stderr: {stderr_tail.strip()}") from error
            raise

    return {
        "status": "ok",
        "version": version,
        "toolCount": len(tool_names),
        "prefix": arguments.expected_prefix,
        "prefixCount": prefix_count,
        "errorTool": arguments.error_tool,
        "structuredErrorVerified": True,
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        report = run_smoke(arguments)
    except Exception as error:
        print(
            json.dumps(
                {"status": "error", "error": str(error)},
                separators=(",", ":"),
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 1
    print(json.dumps(report, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
