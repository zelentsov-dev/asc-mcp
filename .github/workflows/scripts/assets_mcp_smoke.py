#!/usr/bin/env python3
"""Exercise a candidate MCP process against a credential-free loopback ASC fixture."""

import argparse
import base64
from contextlib import ExitStack
import hashlib
import json
import os
import pwd
import queue
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlsplit


ASSET_TOOLS = {
    "assets_get_library", "assets_get_reference_data", "assets_list_images",
    "assets_list_videos", "assets_get_image", "assets_get_video",
    "assets_list_placements", "assets_get_placement", "assets_prepare_change",
    "assets_apply_change", "assets_get_operation",
}
SIGNED_URL = "https://invalid.example/upload?signature=smoke-signed-url-must-not-escape"
UPLOAD_HEADER = "smoke-upload-authorization-must-not-escape"
JWT_PATTERN = re.compile(rb"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")


class SmokeFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SmokeFailure(message)


def compact(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")


class OwnedJournals:
    def __init__(self, companies: list[dict[str, str]]) -> None:
        user_directory = Path(pwd.getpwuid(os.getuid()).pw_dir)
        require(Path(os.environ.get("HOME", str(user_directory))).resolve() == user_directory.resolve(),
                "Controlled smoke requires the current user's standard home directory")
        root = user_directory / ".local/state/asc-mcp/asset-operations"
        self.directories = [root / hashlib.sha256(compact([
            company["id"], company["key_id"], company["issuer_id"]])).hexdigest()
            for company in companies]
        self.created: dict[Path, tuple[int, int]] = {}
        self.missing_parents: list[Path] = []
        parent = root
        while not parent.exists():
            self.missing_parents.append(parent)
            parent = parent.parent
        require(all(not path.exists() and not path.is_symlink() for path in self.directories),
                "Generated smoke account unexpectedly has existing journal state")
        try:
            root.mkdir(mode=0o700, parents=True, exist_ok=True)
            info = root.lstat()
            require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
                    and info.st_mode & 0o077 == 0, "Asset journal root is not a private directory")
            for directory in self.directories:
                directory.mkdir(mode=0o700)
                info = directory.lstat()
                self.created[directory] = (info.st_dev, info.st_ino)
        except Exception:
            self.close()
            raise

    def close(self) -> None:
        for directory, identity in list(self.created.items()):
            info = directory.lstat()
            require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
                    and info.st_mode & 0o077 == 0 and (info.st_dev, info.st_ino) == identity,
                    "Refusing cleanup: fake-account journal ownership or identity changed")
            shutil.rmtree(directory)
            del self.created[directory]
        for parent in self.missing_parents:
            try:
                parent.rmdir()
            except OSError:
                pass


class Fixture:
    def __init__(self, companies: list[dict[str, str]]) -> None:
        self.lock = threading.Lock()
        self.credentials = {company["key_id"]: company["issuer_id"] for company in companies}
        self.tokens: set[str] = set()
        self.reference_name = "initial"
        self.drop_next_patch = False
        self.requests = 0
        self.patches = 0
        self.lost_responses = 0
        self.failures: list[str] = []

    def counts(self) -> tuple[int, int]:
        with self.lock:
            require(not self.failures, "Loopback fixture rejected an unexpected or unsafe request")
            return self.requests, self.patches

    def change_name(self, name: str) -> None:
        with self.lock:
            self.reference_name = name

    def lose_next_response(self) -> None:
        with self.lock:
            self.drop_next_patch = True

    def asset(self) -> dict[str, Any]:
        return {"type": "appAssetLibraryImages", "id": "image", "attributes": {
            "state": "PREPARE_FOR_SUBMISSION", "referenceName": self.reference_name,
            "uploadOperations": [{"method": "PUT", "url": SIGNED_URL, "offset": 0,
                                  "length": 1, "requestHeaders": [
                                      {"name": "Authorization", "value": UPLOAD_HEADER}]}],
        }}

    def authenticate(self, authorization: str | None) -> None:
        require(isinstance(authorization, str) and authorization.startswith("Bearer "),
                "Fixture request is missing its fake bearer token")
        token = authorization[7:]
        self.tokens.add(token)
        try:
            parts = token.split(".")
            require(len(parts) == 3, "Fixture bearer token is malformed")
            header, payload = [json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
                               for part in parts[:2]]
            require(header.get("alg") == "ES256" and header.get("kid") in self.credentials,
                    "Fixture received credentials outside its generated accounts")
            require(payload.get("iss") == self.credentials[header["kid"]],
                    "Fixture account issuer does not match its generated key")
        except (ValueError, TypeError, KeyError) as error:
            raise SmokeFailure("Fixture bearer token could not be decoded") from error

    def respond(self, method: str, target: str, authorization: str | None,
                body: bytes) -> tuple[dict[str, Any], bool]:
        with self.lock:
            self.requests += 1
            self.authenticate(authorization)
            parsed = urlsplit(target)
            require(not parsed.scheme and not parsed.netloc, "Fixture received a nonlocal target")
            path, query = parsed.path, parse_qs(parsed.query)
            library = {"type": "appAssetLibraries", "id": "library"}
            if method == "GET":
                if path in {"/v1/apps/app/assetLibrary", "/v1/appAssetLibraries/library"}:
                    return {"data": library}, False
                if path == "/v1/appAssetLibraryRefData":
                    return {"data": [{"type": "appAssetLibraryRefData", "id": "catalog",
                                      "attributes": {key: [] for key in (
                                          "features", "placementProfileGroups", "imageSpecs",
                                          "videoSpecs", "placementTypes", "displayClasses")}}]}, False
                if path == "/v1/appAssetLibraries/library/images":
                    requested = query.get("filter[id]", ["image"])
                    require(requested in (["image"], ["foreign-image"]),
                            "Fixture received an unexpected asset membership filter")
                    return {"data": [self.asset()] if requested == ["image"] else []}, False
                if path == "/v1/appAssetLibraryImages/image":
                    return {"data": self.asset()}, False
                if path == "/v1/appAssetLibraryImages/image/placements":
                    return {"data": []}, False
            if method == "PATCH" and path == "/v1/appAssetLibraryImages/image":
                try:
                    value = json.loads(body)
                    name = value["data"]["attributes"]["referenceName"]
                except (ValueError, KeyError, TypeError) as error:
                    raise SmokeFailure("Fixture received an invalid rename body") from error
                require(isinstance(name, str) and value == {"data": {
                    "type": "appAssetLibraryImages", "id": "image",
                    "attributes": {"referenceName": name}}},
                    "Fixture PATCH changed fields outside the prepared rename")
                self.patches += 1
                self.reference_name = name
                drop = self.drop_next_patch
                self.drop_next_patch = False
                self.lost_responses += int(drop)
                return {"data": self.asset()}, drop
            raise SmokeFailure("Fixture received an endpoint outside the smoke scenario")


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False

    def __init__(self, fixture: Fixture) -> None:
        self.fixture = fixture
        super().__init__(("127.0.0.1", 0), FixtureHandler)

    def handle_error(self, request: Any, client_address: Any) -> None:
        with self.fixture.lock:
            self.fixture.failures.append("Fixture request handler failed")


class FixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(3)

    def log_message(self, format: str, *args: Any) -> None:
        pass

    def handle_fixture(self) -> None:
        fixture = self.server.fixture
        try:
            require(self.headers.get("Transfer-Encoding") is None,
                    "Fixture does not accept streamed request bodies")
            size = int(self.headers.get("Content-Length", "0"))
            require(0 <= size <= 65536, "Fixture request exceeded its body limit")
            body = self.rfile.read(size)
            require(len(body) == size, "Fixture request body was truncated")
            response, drop = fixture.respond(self.command, self.path,
                                             self.headers.get("Authorization"), body)
            if drop:
                self.close_connection = True
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
                return
            self.reply(200, response)
        except Exception:
            with fixture.lock:
                fixture.failures.append("Fixture request validation failed")
            try:
                self.reply(400, {"errors": [{"status": "400", "code": "SMOKE_FIXTURE_REJECTED",
                                             "title": "Controlled fixture rejected request"}]})
            except OSError:
                pass

    def reply(self, status: int, response: dict[str, Any]) -> None:
        body = compact(response)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        self.close_connection = True

    do_GET = handle_fixture
    do_PATCH = handle_fixture
    do_POST = handle_fixture
    do_PUT = handle_fixture
    do_DELETE = handle_fixture


class MCPProcess:
    def __init__(self, binary: Path, config: Path, environment: dict[str, str],
                 workers: str, read_only: bool, deadline: float) -> None:
        command = [str(binary), "--companies", str(config), "--workers", workers]
        if read_only:
            command.append("--read-only")
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, env=environment, bufsize=0,
                                        cwd=config.parent)
        self.deadline = deadline
        self.responses: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=1024)
        self.stdout = bytearray()
        self.stderr = bytearray()
        self.failure: str | None = None
        self.closed = False
        self.next_id = 0
        self.readers = [threading.Thread(target=self.read_stream, args=(True,), daemon=True),
                        threading.Thread(target=self.read_stream, args=(False,), daemon=True)]
        for reader in self.readers:
            reader.start()

    def read_stream(self, stdout: bool) -> None:
        stream = self.process.stdout if stdout else self.process.stderr
        capture = self.stdout if stdout else self.stderr
        pending = bytearray()
        limit = 8 * 1024 * 1024 if stdout else 2 * 1024 * 1024
        try:
            while chunk := os.read(stream.fileno(), 65536):
                require(len(capture) + len(chunk) <= limit, "MCP output exceeded its capture limit")
                capture.extend(chunk)
                if not stdout:
                    continue
                pending.extend(chunk)
                while b"\n" in pending:
                    line, _, rest = pending.partition(b"\n")
                    pending = bytearray(rest)
                    payload = json.loads(line)
                    require(isinstance(payload, dict) and payload.get("jsonrpc") == "2.0",
                            "MCP stdout contained a non-JSON-RPC message")
                    self.responses.put_nowait(payload)
                require(len(pending) <= 2 * 1024 * 1024, "MCP stdout line exceeded its limit")
            require(not stdout or not pending.strip(), "MCP stdout ended with an incomplete message")
        except Exception:
            self.failure = "MCP output was malformed, excessive, or unreadable"
            if self.process.poll() is None:
                self.process.kill()

    def send(self, method: str, params: dict[str, Any], response_id: int | None) -> None:
        require(self.process.poll() is None, "MCP process exited before a request")
        payload = {"jsonrpc": "2.0", "method": method, "params": params}
        if response_id is not None:
            payload["id"] = response_id
        try:
            self.process.stdin.write(compact(payload) + b"\n")
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise SmokeFailure("MCP stdin closed unexpectedly") from error

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        self.next_id += 1
        response_id = self.next_id
        self.send(method, params, response_id)
        deadline = min(self.deadline, time.monotonic() + 25)
        while time.monotonic() < deadline:
            require(self.failure is None, "MCP output failed JSON-RPC validation")
            try:
                payload = self.responses.get(timeout=0.1)
            except queue.Empty:
                require(self.process.poll() is None, "MCP process exited before responding")
                continue
            if "id" not in payload:
                require(isinstance(payload.get("method"), str), "MCP notification is malformed")
                continue
            require(payload.get("id") == response_id, "MCP returned an unexpected response ID")
            require("error" not in payload, "MCP returned an unexpected JSON-RPC error")
            result = payload.get("result")
            require(isinstance(result, dict), "MCP response result is not an object")
            return result
        raise SmokeFailure("MCP request exceeded its bounded timeout")

    def initialize(self, version: str) -> None:
        result = self.request("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                              "clientInfo": {"name": "asc-assets-controlled-smoke", "version": "1"}})
        require(result.get("serverInfo", {}).get("version") == version,
                "MCP candidate version differs from the expected release")
        self.send("notifications/initialized", {}, None)

    def tool(self, name: str, arguments: dict[str, Any], *, error: bool = False,
             contains: str | None = None) -> dict[str, Any]:
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        require((result.get("isError") is True) == error, "MCP tool returned an unexpected error state")
        structured = result.get("structuredContent")
        require(isinstance(structured, dict), "MCP tool omitted structuredContent")
        require(structured.get("success") is (not error), "MCP tool success flag is inconsistent")
        text_blocks = [block.get("text") for block in result.get("content", [])
                       if isinstance(block, dict) and block.get("type") == "text"]
        require(bool(text_blocks) and isinstance(text_blocks[-1], str),
                "MCP tool omitted its final JSON text mirror")
        if name != "company_switch" or error:
            try:
                require(json.loads(text_blocks[-1]) == structured, "MCP text and structured results differ")
            except ValueError as exception:
                raise SmokeFailure("MCP final tool text is not JSON for " + name) from exception
        if contains:
            require(contains.lower() in str(structured.get("error", "")).lower(),
                    "MCP tool did not report the expected rejection reason")
        return structured

    def close(self) -> None:
        if self.closed:
            return
        try:
            self.process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        for reader in self.readers:
            reader.join(timeout=3)
        require(not any(reader.is_alive() for reader in self.readers), "MCP output reader did not stop")
        self.process.stdout.close()
        self.process.stderr.close()
        self.closed = True
        require(self.failure is None, "MCP output failed final JSON-RPC validation")


def check_discovery(client: MCPProcess, read_only: bool, review: bool) -> None:
    result = client.request("tools/list", {})
    tools = result.get("tools")
    require(isinstance(tools, list) and result.get("nextCursor") is None,
            "MCP tool discovery returned an invalid collection")
    names = [tool.get("name") for tool in tools if isinstance(tool, dict)]
    require(len(names) == len(tools) and all(isinstance(name, str) for name in names)
            and len(set(names)) == len(names), "MCP tool discovery contains invalid or duplicate names")
    expected = ASSET_TOOLS
    require({name for name in names if name.startswith("assets_")} == expected,
            "MCP asset tool discovery differs from the required eleven-tool surface")
    require(all(name.startswith(("assets_", "company_", "auth_", "review_submissions_"))
                for name in names), "MCP worker filter exposed an unrelated tool")
    require(("review_submissions_add_item" in names) == review,
            "MCP review worker filtering did not match the requested surface")
    for tool in tools:
        if tool["name"] in ASSET_TOOLS:
            require(tool.get("annotations", {}).get("readOnlyHint")
                    is (tool["name"] != "assets_apply_change"),
                    "MCP asset operation annotation is incorrect")


def rename_arguments(name: str, asset: str = "image") -> dict[str, str]:
    return {"app_id": "app", "action": "update_reference_name", "asset_kind": "image",
            "asset_id": asset, "reference_name": name}


def prepare(client: MCPProcess, name: str) -> dict[str, Any]:
    preview = client.tool("assets_prepare_change", rename_arguments(name))
    require(preview.get("writes_performed") is False, "Preview reported a remote mutation")
    require(all(isinstance(preview.get(key), str) and preview[key]
                for key in ("preview_id", "operation_id", "expires_at")),
            "Preview omitted its execution identity or expiry")
    return preview


def check_operation(result: dict[str, Any], preview: dict[str, Any], status: str) -> None:
    operation = result.get("operation", {})
    require(operation.get("id") == preview["operation_id"] and operation.get("status") == status,
            "Operation identity or status did not match the expected outcome")
    require(result.get("retry_safe") is False, "Mutation result incorrectly permitted blind retry")


def assert_no_secrets(data: bytes, needles: list[bytes]) -> None:
    require(not JWT_PATTERN.search(data), "A JWT escaped into MCP output or the operation journal")
    require(not any(needle and needle in data for needle in needles),
            "A private key, upload header, or signed URL escaped into output or the journal")


def audit_journals(directories: list[Path], needles: list[bytes]) -> int:
    records = 0
    for directory in directories:
        if not directory.exists():
            continue
        info = directory.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid()
                and info.st_mode & 0o077 == 0, "Fake account journal is not private")
        entries = list(directory.iterdir())
        require(len(entries) <= 64, "Fake account journal exceeded the smoke record bound")
        for entry in entries:
            descriptor = os.open(entry, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            try:
                info = os.fstat(descriptor)
                require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                        and info.st_mode & 0o077 == 0 and info.st_nlink == 1,
                        "Fake account journal contains an unsafe file")
                require(info.st_size <= 2 * 1024 * 1024, "Journal record exceeded its size limit")
                with os.fdopen(descriptor, "rb", closefd=False) as stream:
                    content = stream.read(2 * 1024 * 1024 + 1)
                assert_no_secrets(content, needles)
                if entry.suffix == ".json":
                    record = json.loads(content)
                    require(record.get("account") == directory.name,
                            "Operation journal crossed account boundaries")
                    records += 1
            finally:
                os.close(descriptor)
    require(records > 0, "No persisted fake-account operation journal was found")
    return records


def run(arguments: argparse.Namespace) -> dict[str, Any]:
    binary = Path(arguments.binary).expanduser().resolve()
    require(binary.is_file() and os.access(binary, os.X_OK), "Candidate binary is not executable")
    deadline = time.monotonic() + 240
    checks: list[str] = []
    processes: list[MCPProcess] = []
    with tempfile.TemporaryDirectory(prefix="asc-assets-controlled-smoke-") as temporary, ExitStack() as cleanup:
        directory = Path(temporary)
        key_path = directory / "AuthKey.p8"
        subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt",
                        "ec_paramgen_curve:P-256", "-out", str(key_path)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        key_path.chmod(0o600)
        companies = [{"id": "smoke-" + uuid.uuid4().hex, "name": "Controlled Smoke " + str(index),
                      "key_id": "SMOKE" + uuid.uuid4().hex[:5].upper(),
                      "issuer_id": str(uuid.uuid4()), "key_path": str(key_path)}
                     for index in range(2)]
        journals = OwnedJournals(companies)
        cleanup.callback(journals.close)
        fixture = Fixture(companies)
        server = FixtureServer(fixture)
        cleanup.callback(server.server_close)
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()

        def stop_server() -> None:
            server.shutdown()
            server_thread.join(timeout=3)
            require(not server_thread.is_alive(), "Loopback fixture server did not stop")

        cleanup.callback(stop_server)
        config = directory / "companies.json"
        config.write_bytes(compact({"defaultURL": "http://127.0.0.1:" + str(server.server_port),
                                    "companies": companies}))
        config.chmod(0o600)
        local_tmp = directory / "tmp"
        local_tmp.mkdir(mode=0o700)
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("ASC_", "DYLD_"))
                       and key.lower() not in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}
                       and key != "CFFIXED_USER_HOME"}
        environment["TMPDIR"] = str(local_tmp) + "/"
        needles = [SIGNED_URL.encode(), UPLOAD_HEADER.encode(), b"-----BEGIN PRIVATE KEY-----"]
        needles.extend(line for line in key_path.read_bytes().splitlines()
                       if line and not line.startswith(b"-----"))

        def start(workers: str = "assets,review_submissions", read_only: bool = False) -> MCPProcess:
            require(time.monotonic() < deadline, "Controlled smoke exceeded its total time budget")
            process = MCPProcess(binary, config, environment, workers, read_only, deadline)
            processes.append(process)
            cleanup.callback(process.close)
            process.initialize(arguments.expected_version)
            return process

        try:
            client = start()
            check_discovery(client, read_only=False, review=True)
            checks.append("initialize_discovery_worker_filter_annotations")
            client.tool("assets_get_library", {"app_id": "app"})
            client.tool("assets_get_image", {"app_id": "app", "asset_id": "image"})
            checks.append("library_asset_read_and_sensitive_field_projection")
            before = fixture.counts()[1]
            client.tool("assets_prepare_change", rename_arguments("forbidden", "foreign-image"),
                        error=True, contains="does not belong")
            require(fixture.counts()[1] == before, "Ownership rejection performed a PATCH")
            checks.append("foreign_asset_rejected_before_write")

            drift = prepare(client, "drift-target")
            fixture.change_name("concurrent-edit")
            result = client.tool("assets_apply_change", {"preview_id": drift["preview_id"]},
                                 error=True, contains="state changed")
            check_operation(result, drift, "failed")
            require(fixture.counts()[1] == before, "Remote drift rejection performed a PATCH")
            checks.append("remote_drift_rejected_before_write")

            success = prepare(client, "confirmed")
            requests = fixture.counts()
            client.tool("assets_apply_change", {"preview_id": success["preview_id"],
                                                "reference_name": "substitution"}, error=True)
            require(fixture.counts() == requests, "Preview parameter substitution reached ASC")
            result = client.tool("assets_apply_change", {"preview_id": success["preview_id"]})
            check_operation(result, success, "succeeded")
            require(fixture.counts()[1] == before + 1, "Successful apply did not perform exactly one PATCH")
            readback = client.tool("assets_get_image", {"app_id": "app", "asset_id": "image"})
            require(readback.get("asset", {}).get("attributes", {}).get("referenceName") == "confirmed",
                    "MCP read-back did not confirm the prepared reference name")
            requests = fixture.counts()
            client.tool("assets_apply_change", {"preview_id": success["preview_id"]}, error=True)
            require(fixture.counts() == requests, "Consumed preview replay reached ASC")
            checks.append("single_use_preview_parameter_binding_success_and_readback")

            lost = prepare(client, "reconciled")
            before = fixture.counts()[1]
            fixture.lose_next_response()
            result = client.tool("assets_apply_change", {"preview_id": lost["preview_id"]})
            check_operation(result, lost, "succeeded")
            require(fixture.counts()[1] == before + 1 and fixture.lost_responses == 1,
                    "Lost PATCH response was blindly retried or was not injected")
            result = client.tool("assets_get_operation", {"operation_id": lost["operation_id"]})
            check_operation(result, lost, "succeeded")
            checks.append("lost_patch_response_reconciled_without_duplicate_write")

            switched = prepare(client, "wrong-account")
            requests = fixture.counts()
            client.tool("company_switch", {"company": companies[1]["id"]})
            client.tool("assets_apply_change", {"preview_id": switched["preview_id"]}, error=True)
            client.tool("assets_get_operation", {"operation_id": lost["operation_id"]}, error=True)
            client.tool("company_switch", {"company": companies[0]["id"]})
            client.tool("assets_apply_change", {"preview_id": switched["preview_id"]}, error=True)
            require(fixture.counts() == requests, "Account-switch rejection reached ASC")
            checks.append("company_switch_invalidates_preview_and_isolates_journal")
            restart_preview = prepare(client, "restart-rejected")
            client.close()
            client = start()
            requests = fixture.counts()
            client.tool("assets_apply_change", {"preview_id": restart_preview["preview_id"]}, error=True)
            result = client.tool("assets_get_operation", {"operation_id": lost["operation_id"]})
            check_operation(result, lost, "succeeded")
            require(fixture.counts() == requests, "Restarted preview unexpectedly reached ASC")
            checks.append("restart_invalidates_preview_preserves_operation_result")
            client.close()

            client = start(workers="assets", read_only=True)
            check_discovery(client, read_only=True, review=False)
            read_only_preview = prepare(client, "read-only-rejected")
            requests = fixture.counts()
            client.tool("assets_apply_change", {"preview_id": read_only_preview["preview_id"]},
                        error=True, contains="read-only")
            client.tool("review_submissions_add_item", {
                "submission_id": "submission", "app_asset_library_image_id": "image",
                "preview_id": read_only_preview["preview_id"]}, error=True, contains="read-only")
            require(fixture.counts() == requests, "Read-only direct or hidden alias call reached ASC")
            checks.append("read_only_prepare_allowed_apply_and_hidden_alias_blocked")
            client.close()

            client = start(workers="review_submissions")
            tools = client.request("tools/list", {}).get("tools", [])
            require(not any(tool.get("name", "").startswith("assets_") for tool in tools),
                    "Disabled assets worker remained discoverable")
            requests = fixture.counts()
            client.tool("assets_apply_change", {"preview_id": read_only_preview["preview_id"]},
                        error=True, contains="disabled")
            require(fixture.counts() == requests, "Disabled asset tool direct call reached ASC")
            checks.append("disabled_worker_direct_call_rejected")
            client.close()
            fixture.counts()
            needles.extend(token.encode() for token in fixture.tokens)
            for process in processes:
                assert_no_secrets(bytes(process.stdout), needles)
                assert_no_secrets(bytes(process.stderr), needles)
            records = audit_journals(journals.directories, needles)
            checks.append("pure_json_rpc_stdout_private_journal_no_credential_or_url_leaks")
            return {"status": "pass", "transport": "real MCP stdio with loopback ASC fixture",
                    "apple_network_used": False, "checks": checks, "journal_records_checked": records,
                    "patches": fixture.patches, "candidate_version": arguments.expected_version}
        finally:
            for process in processes:
                if not process.closed:
                    try:
                        process.close()
                    except Exception:
                        if process.process.poll() is None:
                            process.process.kill()
                            process.process.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, help="Previously built candidate asc-mcp executable")
    parser.add_argument("--expected-version", default="4.2.0")
    arguments = parser.parse_args()
    try:
        report = run(arguments)
    except SmokeFailure as error:
        print(json.dumps({"status": "fail", "error": str(error)}, sort_keys=True), file=sys.stderr)
        return 1
    except Exception as error:
        print(json.dumps({"status": "fail", "error": "Harness failed without exposing raw diagnostics",
                          "exception_type": type(error).__name__}, sort_keys=True), file=sys.stderr)
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
