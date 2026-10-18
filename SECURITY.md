# Security Policy

## Supported versions

Kapsule is in early development and has no stable release yet. Until a `1.0` is tagged,
only the latest `main` is supported for security fixes.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately via GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
("Report a vulnerability" under the repository's **Security** tab), or email
**security@kapsule.example** *(update this address before launch)*.

Please include:

- A description of the issue and its impact
- Steps to reproduce (a proof of concept if possible)
- Affected commit/version and your macOS and hardware

We aim to acknowledge reports within **72 hours** and to provide a remediation timeline
after triage. We will credit reporters who wish to be named once a fix ships.

## Scope notes

Kapsule runs guest operating systems, which are untrusted by nature. Relevant concerns
include: isolation between host and guest, handling of shared folders and clipboard,
disk-image parsing, and the handling of user-supplied OS images. Reports in these areas
are especially valuable. Issues in Apple's `Virtualization.framework` itself should be
reported to Apple, but let us know so we can mitigate or warn users.
