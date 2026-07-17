#!/usr/bin/env python3
"""Verify an installed claude-litellm package before managed code executes.

This verifier is stdlib-only and must be run by an external Python 3.13 with
``-I -B -S``. The entrypoint first checks this file's digest against the
manifest; the public launcher also pins the manifest digest. Only after this
check succeeds may package shell code or the managed Python runtime execute.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata as metadata
import json
import os
import re
import stat
import sys
from pathlib import Path


HEX_SHA256 = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
RUNTIME_BUILD_EPOCH = "2026-07-13.3"
LITELLM_VERSION = "1.92.0"
PRISMA_VERSION = "0.15.0"

EXPECTED_PACKAGE_FILES = {
    "bin/claude-litellm",
    "config/litellm_config.base.yaml",
    "config/python-requirements.in",
    "config/python-requirements.lock",
    "config/ai_litellm_callbacks/__init__.py",
    "config/ai_litellm_callbacks/chatgpt_stream_compat.py",
    "config/ai_litellm_callbacks/oauth_guard.py",
    "config/ai_litellm_callbacks/output_clamp.py",
    "config/ai_litellm_callbacks/proxy_bootstrap.py",
    "config/ai-litellm/context-observations.json",
    "config/ai-litellm/lib.zsh",
    "config/ai-litellm/settings.json",
    "config/ai-litellm/harnesses/schema.json",
    "config/ai-litellm/harnesses/claude.json",
    "config/claude-litellm/settings.base.json",
    "config/claude-litellm/oauth.py",
    "config/claude-litellm/shell.zsh",
    "docs/ARCHITECTURE.md",
    "docs/MIGRATION.md",
    "docs/MODEL-RUNBOOK.md",
    "docs/PROVIDERS.md",
    "scripts/migrate-legacy.zsh",
    "scripts/render-user-config.py",
    "scripts/runtime-fingerprint.py",
    "scripts/task-ledger.py",
    "scripts/verify-install.py",
    "scripts/verify_tool_call_fidelity.py",
    "scripts/uninstall.zsh",
}
GENERATED_PACKAGE_FILES = {
    "config/litellm_config.yaml",
    "config/claude-litellm/settings.json",
}
ALLOWED_PACKAGE_DIRS = {
    "bin",
    "config",
    "config/ai_litellm_callbacks",
    "config/ai-litellm",
    "config/ai-litellm/harnesses",
    "config/claude-litellm",
    "docs",
    "scripts",
}


class VerificationError(RuntimeError):
    """The installed package cannot be trusted for execution."""


def _read_regular_file(path: Path, *, required_mode: int | None = None) -> bytes:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise VerificationError(f"not a regular file: {path}")
        if required_mode is not None and stat.S_IMODE(info.st_mode) != required_mode:
            raise VerificationError(f"unsafe mode for file: {path}")
        chunks: list[bytes] = []
        while chunk := os.read(descriptor, 1024 * 1024):
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def _validate_external_interpreter(prefix: Path) -> None:
    if sys.version_info[:2] != (3, 13):
        raise VerificationError("external verifier must be Python 3.13")
    executable = Path(sys.executable).resolve(strict=True)
    if _is_within(executable, prefix.resolve(strict=True)):
        raise VerificationError("refusing the managed runtime as integrity verifier")


def _load_manifest(prefix: Path, expected_digest: str | None) -> dict[str, object]:
    manifest = prefix / "install-manifest.json"
    raw = _read_regular_file(manifest, required_mode=0o600)
    actual_digest = hashlib.sha256(raw).hexdigest()
    if expected_digest is not None and actual_digest != expected_digest:
        raise VerificationError("manifest digest does not match the public launcher")
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as error:
        raise VerificationError("manifest is not valid JSON") from error
    if not isinstance(payload, dict):
        raise VerificationError("manifest root is not an object")
    return payload


def _validate_manifest_contract(prefix: Path, payload: dict[str, object]) -> None:
    source = payload.get("source")
    runtime = payload.get("runtime")
    user_config = payload.get("userConfig")
    package_files = payload.get("packageFiles")
    if not (
        payload.get("product") == "claude-litellm"
        and payload.get("schemaVersion") == 2
        and payload.get("prefix") == str(prefix)
        and isinstance(package_files, dict)
        and set(package_files) == EXPECTED_PACKAGE_FILES
        and payload.get("managedMutableFiles") == {}
        and isinstance(source, dict)
        and isinstance(source.get("origin"), str)
        and bool(source.get("origin"))
        and isinstance(source.get("commit"), str)
        and (source.get("commit") == "unknown" or COMMIT.fullmatch(source.get("commit")))
        and isinstance(source.get("dirty"), bool)
        and isinstance(user_config, dict)
        and user_config.get("upgradePolicy")
        == "preserve-and-render-over-package-defaults"
        and isinstance(user_config.get("models"), str)
        and isinstance(user_config.get("claudeSettings"), str)
        and isinstance(runtime, dict)
        and runtime.get("litellm") == LITELLM_VERSION
        and runtime.get("prisma") == PRISMA_VERSION
        and runtime.get("venv") == str(prefix / "runtime" / "venv")
        and runtime.get("buildEpoch") == RUNTIME_BUILD_EPOCH
        and isinstance(runtime.get("contentFingerprint"), str)
        and HEX_SHA256.fullmatch(runtime.get("contentFingerprint"))
        and isinstance(runtime.get("dependencyFingerprint"), str)
        and HEX_SHA256.fullmatch(runtime.get("dependencyFingerprint"))
    ):
        raise VerificationError("manifest contract mismatch")
    build_rust = runtime.get("buildRust")
    if build_rust:
        try:
            version = tuple(int(part) for part in str(build_rust).split(".")[:2])
        except ValueError as error:
            raise VerificationError("invalid Rust version in manifest") from error
        if version < (1, 97):
            raise VerificationError("runtime was built with an unsupported Rust version")


def _validate_package_tree(prefix: Path, payload: dict[str, object]) -> bytes:
    package_files = payload["packageFiles"]
    assert isinstance(package_files, dict)
    fingerprint_helper: bytes | None = None
    for relative, expected in package_files.items():
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise VerificationError("invalid package file entry")
        if not HEX_SHA256.fullmatch(expected):
            raise VerificationError(f"invalid package digest: {relative}")
        path = prefix / relative
        try:
            raw = _read_regular_file(path)
        except OSError as error:
            raise VerificationError(f"missing package file: {relative}") from error
        if hashlib.sha256(raw).hexdigest() != expected:
            raise VerificationError(f"package digest mismatch: {relative}")
        if relative == "scripts/runtime-fingerprint.py":
            fingerprint_helper = raw

    allowed_files = EXPECTED_PACKAGE_FILES | GENERATED_PACKAGE_FILES
    for root_name in ("bin", "config", "docs", "scripts"):
        root = prefix / root_name
        info = root.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise VerificationError(f"unsafe package root: {root_name}")
        pending = [root]
        while pending:
            directory = pending.pop()
            with os.scandir(directory) as entries:
                for entry in entries:
                    path = Path(entry.path)
                    info = entry.stat(follow_symlinks=False)
                    relative = path.relative_to(prefix).as_posix()
                    if stat.S_ISDIR(info.st_mode):
                        if relative not in ALLOWED_PACKAGE_DIRS:
                            raise VerificationError(f"unexpected package directory: {relative}")
                        pending.append(path)
                    elif stat.S_ISREG(info.st_mode):
                        if relative not in allowed_files:
                            raise VerificationError(f"unexpected package file: {relative}")
                    else:
                        raise VerificationError(f"unsafe package path: {relative}")
    if fingerprint_helper is None:
        raise VerificationError("runtime fingerprint helper was not verified")
    return fingerprint_helper


def _site_packages(runtime_root: Path) -> list[Path]:
    roots: list[Path] = []
    for lib_name in ("lib", "lib64"):
        lib = runtime_root / lib_name
        if not lib.exists():
            continue
        for python_root in lib.iterdir():
            if re.fullmatch(r"python\d+\.\d+", python_root.name):
                candidate = python_root / "site-packages"
                if candidate.is_dir() and not candidate.is_symlink():
                    roots.append(candidate)
    if not roots:
        raise VerificationError("runtime has no site-packages directory")
    return sorted(roots)


def _pyvenv_version(runtime_root: Path) -> str:
    try:
        lines = (runtime_root / "pyvenv.cfg").read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise VerificationError("cannot read pyvenv.cfg") from error
    for line in lines:
        key, separator, value = line.partition("=")
        if separator and key.strip() == "version":
            return value.strip()
    raise VerificationError("pyvenv.cfg has no version")


def _validate_runtime(
    prefix: Path, payload: dict[str, object], fingerprint_helper: bytes
) -> None:
    runtime = payload["runtime"]
    assert isinstance(runtime, dict)
    runtime_root = prefix / "runtime" / "venv"
    helper_path = prefix / "scripts" / "runtime-fingerprint.py"
    namespace: dict[str, object] = {
        "__name__": "claude_litellm_verified_runtime_fingerprint",
        "__file__": str(helper_path),
    }
    try:
        exec(compile(fingerprint_helper, str(helper_path), "exec"), namespace)
        actual_fingerprint = namespace["runtime_fingerprint"](runtime_root)  # type: ignore[operator]
    except Exception as error:
        raise VerificationError(f"runtime fingerprint failed: {error}") from error
    if actual_fingerprint != runtime["contentFingerprint"]:
        raise VerificationError("runtime fingerprint mismatch")

    version = _pyvenv_version(runtime_root)
    if version != runtime.get("python") or not version.startswith("3.13."):
        raise VerificationError("managed Python version mismatch")
    distributions = list(metadata.distributions(path=[str(path) for path in _site_packages(runtime_root)]))
    versions = {
        str(dist.metadata["Name"]).lower().replace("_", "-"): dist.version
        for dist in distributions
        if dist.metadata.get("Name")
    }
    if versions.get("litellm") != LITELLM_VERSION or versions.get("prisma") != PRISMA_VERSION:
        raise VerificationError("managed dependency version mismatch")
    packages = sorted(
        f"{str(dist.metadata['Name']).lower().replace('_', '-')}=={dist.version}"
        for dist in distributions
        if dist.metadata.get("Name")
    )
    dependency_fingerprint = hashlib.sha256("\n".join(packages).encode()).hexdigest()
    if dependency_fingerprint != runtime.get("dependencyFingerprint"):
        raise VerificationError("managed dependency inventory mismatch")

    script = runtime_root / "bin" / "litellm"
    info = script.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise VerificationError("LiteLLM console script is unsafe")
    first = script.read_text(encoding="utf-8", errors="replace").splitlines()[:3]
    if not first or not any(str(runtime_root / "bin") in line for line in first):
        raise VerificationError("LiteLLM console script targets another runtime")


def verify(prefix: Path, expected_manifest_digest: str | None) -> None:
    prefix = Path(os.path.abspath(prefix))
    info = prefix.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise VerificationError("package prefix is not a regular directory")
    _validate_external_interpreter(prefix)
    payload = _load_manifest(prefix, expected_manifest_digest)
    _validate_manifest_contract(prefix, payload)
    fingerprint_helper = _validate_package_tree(prefix, payload)
    _validate_runtime(prefix, payload, fingerprint_helper)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--expect-manifest-sha256")
    args = parser.parse_args()
    if args.expect_manifest_sha256 is not None and not HEX_SHA256.fullmatch(
        args.expect_manifest_sha256
    ):
        parser.error("--expect-manifest-sha256 must be a lowercase SHA-256 digest")
    try:
        verify(args.prefix, args.expect_manifest_sha256)
    except (OSError, VerificationError) as error:
        print(f"installed integrity verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
