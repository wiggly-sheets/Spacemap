# Security Policy

## Supported Versions

Spacemap is supported on the latest released version and the current development line. Security fixes are typically published for the latest release and, when practical, backported to the most recent prior release if the issue is significant.

## Reporting a Vulnerability

If you believe you have found a security issue in Spacemap, please report it privately and do not open a public issue or pull request.

Include as much detail as possible:

- A clear description of the issue
- The version of Spacemap you tested
- macOS version and hardware if relevant
- Exact reproduction steps
- Any proof-of-concept code, logs, screenshots, or crash reports
- Whether the issue affects the app bundle, CLI, installer, update flow, or configuration files

## What to Report

Please report issues that could impact confidentiality, integrity, or availability, including:

- Unauthorized code execution or privilege escalation
- Unsafe file handling, symlink traversal, or path validation flaws
- Exposure of local data through logs, settings, cache files, or update metadata
- Weaknesses in app update verification or signing
- Accessibility, Screen Recording, or other permission-related bypasses
- Malicious or unintended interaction with yabai, AeroSpace, optional skhd integrations, sockets, or shell commands

## What Not to Report

The following are generally out of scope unless they create a realistic security impact:

- Missing features or cosmetic bugs
- General usability problems
- Non-security crashes with no data exposure or escalation risk
- Issues limited to your local configuration unless they reveal a broader vulnerability

## Disclosure Process

After a report is received:

1. The issue will be reviewed and triaged.
2. Reproduction details may be requested.
3. A fix will be developed and verified.
4. The issue will be disclosed publicly after a patch is available, when appropriate.

Please allow reasonable time for review before sharing details publicly.

## Safe Handling Guidance

If your report involves local files, logs, or configuration data, sanitize sensitive information before sharing. Do not include private API keys, tokens, or personal files unless they are required to reproduce the issue and you are comfortable disclosing them.
