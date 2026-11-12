"""Check exact synthetic package contents and rehearse restoration in a temp directory."""
import hashlib
import json
from pathlib import Path
import sys
import tarfile
import zipfile

mode, temp, result = sys.argv[1:]
work = Path(temp)
report = {"case": mode, "result": "expected-failure" if mode == "failure" else "passed"}
if mode in {"release", "recovery"}:
    nuget, = (work / "packages").glob("*.nupkg")
    npm, = (work / "packages").glob("*.tgz")
    with zipfile.ZipFile(nuget) as package:
        assert any(name.endswith("/PilotFixture.dll") for name in package.namelist())
    with tarfile.open(npm) as package:
        assert b"module.exports" in package.extractfile("package/index.js").read()
    report["packages"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (nuget, npm)}
    if mode == "recovery":
        retained = {p.name: p.read_bytes() for p in (nuget, npm)}
        feed = work / "feed"
        feed.mkdir()
        staged = feed / (nuget.name + ".partial")
        staged.write_bytes(retained[nuget.name][:32])
        assert not (feed / nuget.name).exists()
        for name, payload in retained.items():
            temp_path = feed / (name + ".partial")
            temp_path.write_bytes(payload)
            temp_path.replace(feed / name)
        for name, payload in retained.items():
            target = feed / name
            assert target.read_bytes() == payload
            try:
                with target.open("xb"):
                    raise AssertionError("Duplicate write was allowed")
            except FileExistsError:
                pass
            assert hashlib.sha256(target.read_bytes()).hexdigest() == report["packages"][name]
        report["recovery"] = "interrupted staging restored exact bytes; duplicate write refused"
Path(result).write_text(json.dumps(report, sort_keys=True) + "\n")
print(json.dumps(report, sort_keys=True))
