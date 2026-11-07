#!/usr/bin/env python3
"""Fail when a markdown doc names code that is not in the repository.

Docs that describe types, files or paths the code no longer has lead a reader to think the
behaviour is there. This reads every tracked markdown file (CLAUDE.md is a symlink to AGENTS.md
and is read once) and checks, outside fenced code blocks:

- a backticked code name (`CamelCase`, `lowerCamel`) appears in a source file, or names a file;
- a backticked path under one of the repository's top-level entries exists, as does a backticked
  `.swift` file wherever it sits (`<Placeholder>` and `*` match anything);
- a relative markdown link resolves, and its `#anchor` names a heading in the target.

A name defined in another codebase goes in EXTERNAL. A name a doc cites as gone goes in REMOVED,
which fails once the code has it again, since the doc that says it is gone is then wrong. Both
fail on an entry no doc cites any more, or that the code now names, so neither grows stale.

Usage: check_doc_references.py [--root DIR]
"""
import argparse
import fnmatch
import os
import re
import subprocess
import sys
from dataclasses import dataclass

# Defined outside this repository, by the codebase named.
EXTERNAL = {
    "CGMManager": "LoopKit",
    "PumpConfig": "Trio",
    "PumpType": "Trio",
    "addPump": "Trio",
    "PumpSetupView.swift": "Trio",
    "rawPumpManager": "Trio",
    "Trio/Sources/APS/DeviceDataManager.swift": "Trio",
    "Trio/Sources/Modules/PumpConfig/PumpConfigDataFlow.swift": "Trio",
    "BolusPermissionHandler": "faketandem",
    "TempRateHandler": "faketandem",
    "LoopAppManager": "Loop",
    "LoopDataManager": "Loop",
    "isAutomaticDosingAllowed": "Loop",
    "pumpIsAllowingAutomation": "Loop",
    "APSError": "Trio",
    "NotLoopingMonitor": "Trio",
    "isManualTempBasal": "Trio",
    "manualBasalTemp": "Trio",
    "TempRateResponseTest": "pumpX2",
    "getProgrammedBasalRate": "pumpX2",
    "PendingCommand": "OmnipodKit",
    "PumpManagerUI/Views/ManualTempBasalEntryView.swift": "OmnipodKit",
    "PumpManagerUI/Views/OmniSettingsView.swift": "OmnipodKit",
    "PumpManagerUI/ViewModels/OmniSettingsViewModel.swift": "OmnipodKit",
    "PumpManager/OmniPumpManager.swift": "OmnipodKit",
    "BasalDeliveryState+Extension.swift": "Trio",
    "UIDatePicker": "UIKit",
    "countDownTimer": "UIKit",
}

# Cited by a doc as no longer in the code.
REMOVED = {
    "dosingDecisionDelegate",
    "pumpManagerRecommendsLoop",
}

CODE_EXTENSIONS = (
    ".swift", ".h", ".py", ".rb", ".sh", ".yml", ".yaml", ".json", ".xcconfig", ".plist",
    ".resolved", ".xcstrings", ".entitlements", ".xcscheme",
)
# They name what they look for.
CORPUS_EXCLUDES = ("check_doc_references.py", "test_check_doc_references.py")
PATH_EXTENSIONS = CODE_EXTENSIONS + (".md", ".xcodeproj", ".xcworkspace", ".txt")

BACKTICK = re.compile(r"`([^`\n]+)`")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NAME_IN_SPAN = re.compile(r"(?<![A-Za-z0-9_/-])[A-Za-z_][A-Za-z0-9_]*")
# Bundle and app group identifiers, and shell, name no code.
NOT_CODE = re.compile(r"^(?:com|org|net|group)\.|\$")
CODE_NAME = re.compile(r"^(?:[A-Z][a-z0-9]+[A-Z]|[A-Z]{2,}[a-z]|[a-z][a-z0-9]*[A-Z])")
LINE_SUFFIX = re.compile(r":\d+(?:-\d+)?$")
LINE_COMMENT = re.compile(r"//.*$", re.M)
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    message: str

    def __str__(self):
        return f"{self.path}:{self.line}: {self.message}" if self.line else f"{self.path}: {self.message}"


class Repository:
    def __init__(self, root, files, read=None):
        self.root = root
        self.files = sorted(files)
        self._read = read or (lambda path: _read_text(os.path.join(root, path)))
        self.paths = set(self.files)
        for path in self.files:
            parent = os.path.dirname(path)
            while parent:
                self.paths.add(parent)
                parent = os.path.dirname(parent)
        self.top_level = {path.split("/", 1)[0] for path in self.paths}
        self._sources = {}
        self.words = set()
        self.uncommented_words = set()
        for path in self.files:
            self.words.update(WORD.findall(path))
            self.uncommented_words.update(WORD.findall(path))
            if path.endswith(CODE_EXTENSIONS) and os.path.basename(path) not in CORPUS_EXCLUDES:
                text = self.read(path)
                self.words.update(WORD.findall(text))
                self.uncommented_words.update(WORD.findall(_strip_comments(path, text)))

    def read(self, path):
        if path not in self._sources:
            self._sources[path] = self._read(path)
        return self._sources[path]

    def docs(self):
        return [path for path in self.files if path.endswith(".md") and not self.is_symlink(path)]

    def is_symlink(self, path):
        return os.path.islink(os.path.join(self.root, path))

    def where_named(self, name):
        """Files whose code (not comments) or path names `name`, for REMOVED's message."""
        hits = [path for path in self.files if name in WORD.findall(path)]
        for path in self.files:
            if path.endswith(CODE_EXTENSIONS) and os.path.basename(path) not in CORPUS_EXCLUDES:
                if name in WORD.findall(_strip_comments(path, self.read(path))):
                    hits.append(path)
        return sorted(set(hits))


def _read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except (IsADirectoryError, FileNotFoundError):
        return ""


def _strip_comments(path, text):
    if path.endswith((".swift", ".h")):
        return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))
    if path.endswith((".py", ".rb", ".sh", ".yml", ".yaml")):
        return re.sub(r"(^|\s)#.*$", r"\1", text, flags=re.M)
    return text


def git_files(root):
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
    )
    return [path for path in output.decode().split("\0") if path and os.path.exists(os.path.join(root, path))]


def doc_lines(text):
    """(line number, line) outside fenced code blocks."""
    fence = None
    for number, line in enumerate(text.split("\n"), 1):
        stripped = line.lstrip()
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            if fence is None:
                fence = marker
            elif marker == fence:
                fence = None
            continue
        if fence is None:
            yield number, line


def slug(heading):
    """GitHub's anchor for a heading."""
    text = re.sub(r"`([^`]*)`", r"\1", heading)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(text):
    seen = {}
    result = set()
    for _, line in doc_lines(text):
        match = HEADING.match(line)
        if not match:
            continue
        base = slug(match.group(2))
        count = seen.get(base, 0)
        seen[base] = count + 1
        result.add(base if count == 0 else f"{base}-{count}")
    return result


def is_path_token(token):
    if " " in token or "://" in token or token.startswith(("/", "~", "$", "-", "@")):
        return False
    if re.fullmatch(r"\.\w+", token):
        return False
    return "/" in token or token.endswith(PATH_EXTENSIONS)


def path_exists(repo, token, doc):
    candidate = LINE_SUFFIX.sub("", token).rstrip("/")
    pattern = re.sub(r"<[^>]+>", "*", candidate)
    beside_doc = os.path.normpath(os.path.join(os.path.dirname(doc), pattern))
    for option in (pattern, beside_doc):
        if "*" in option:
            if any(fnmatch.fnmatch(path, option) for path in repo.paths):
                return True
        elif option in repo.paths:
            return True
    suffix = "*/" + pattern
    return any(path == pattern or fnmatch.fnmatch(path, suffix) for path in repo.paths)


def check_path(repo, token, doc):
    """True when the token is a path this repo should have and it is missing."""
    candidate = LINE_SUFFIX.sub("", token)
    anchored = candidate.split("/", 1)[0] in repo.top_level and "/" in candidate.rstrip("/")
    anchored = anchored or candidate in repo.top_level
    if not anchored and not candidate.endswith(".swift"):
        return False
    return not path_exists(repo, token, doc)


def check(repo, external=EXTERNAL, removed=REMOVED):
    findings = []
    cited = set()
    for doc in repo.docs():
        text = repo.read(doc)
        for number, line in doc_lines(text):
            for span in BACKTICK.findall(line):
                token = span.strip()
                if is_path_token(token):
                    if token in external or token in removed:
                        cited.add(token)
                    elif check_path(repo, token, doc):
                        findings.append(Finding(doc, number, (
                            f"`{token}` is not in the repository. Point it at where the file lives now, "
                            "or drop it; if it lives in another codebase, add it to EXTERNAL in "
                            "scripts/check_doc_references.py."
                        )))
                    continue
                if NOT_CODE.search(token):
                    continue
                for name in NAME_IN_SPAN.findall(token):
                    if not CODE_NAME.match(name):
                        continue
                    if name in external or name in removed:
                        cited.add(name)
                    elif name not in repo.words:
                        findings.append(Finding(doc, number, (
                            f"`{name}` names nothing in the code. Use the name the code has now, or "
                            "drop it; if it lives in another codebase, add it to EXTERNAL, and if the "
                            "doc says it is gone, to REMOVED, in scripts/check_doc_references.py."
                        )))
            for target in LINK.findall(line):
                findings.extend(check_link(repo, doc, number, target))

    tool = "scripts/check_doc_references.py"
    for name in sorted(external):
        if name not in cited:
            findings.append(Finding(tool, 0, f"EXTERNAL lists `{name}`, which no doc cites any more; remove it."))
        elif name in repo.words or (is_path_token(name) and path_exists(repo, name, "")):
            findings.append(Finding(tool, 0, f"EXTERNAL lists `{name}`, which the code now names; remove it."))
    for name in sorted(removed):
        if name not in cited:
            findings.append(Finding(tool, 0, f"REMOVED lists `{name}`, which no doc cites any more; remove it."))
        elif name in repo.uncommented_words:
            where = ", ".join(repo.where_named(name))
            findings.append(Finding(tool, 0, (
                f"REMOVED lists `{name}`, but the code has it again ({where}). The docs that call it "
                "gone are wrong: correct them, then remove it from REMOVED."
            )))
    return findings


def check_link(repo, doc, number, target):
    if re.match(r"^[a-z][a-z0-9+.-]*:", target):
        return []
    path, _, anchor = target.partition("#")
    resolved = os.path.normpath(os.path.join(os.path.dirname(doc), path)) if path else doc
    if resolved not in repo.paths:
        return [Finding(doc, number, f"the link to `{target}` leads to no file in the repository.")]
    if anchor and resolved.endswith(".md") and anchor not in anchors(repo.read(resolved)):
        return [Finding(doc, number, f"the link to `{target}` names no heading in `{resolved}`.")]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = parser.parse_args()

    repo = Repository(args.root, git_files(args.root))
    findings = check(repo)
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    for finding in findings:
        print(finding)
        if annotate:
            location = f"file={finding.path}" + (f",line={finding.line}" if finding.line else "")
            print(f"::error {location}::{finding.message}")
    if findings:
        sys.exit(f"{len(findings)} doc reference(s) to fix.")
    print(f"Doc references: {len(repo.docs())} docs name only what the repository has.")


if __name__ == "__main__":
    main()
