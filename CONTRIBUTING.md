# Contributing to Kapsule

Thanks for your interest in Kapsule! It's an early-stage, build-in-the-open project,
and contributions of all kinds are welcome — code, documentation, testing, design,
triage, and ideas.

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Code** — pick up a [good first issue](https://github.com/prakashsolanki28/kapsule/labels/good%20first%20issue) or propose a change in an issue first.
- **Testing** — build from source, run VMs, and file detailed bug reports.
- **Docs** — improve the README, architecture notes, or guides.
- **Design** — UI/UX for the VM library, settings, and onboarding.
- **Triage** — reproduce and label incoming issues.

## Before you start

For anything larger than a small fix, **open an issue first** so we can agree on the
approach before you invest time. This avoids duplicate or wasted work.

## Development setup

You need an Apple Silicon Mac, macOS 14+, and Xcode 16+. See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full setup, the virtualization
entitlement, and how to run a VM locally.

## Pull request process

1. **Fork** the repo and create a branch from `main`:
   `git switch -c feature/short-description`
2. Keep PRs **focused** — one logical change per PR.
3. Follow the [coding standards](#coding-standards).
4. Make sure the project **builds** and existing tests pass.
5. Update **docs** and add **tests** for new behavior.
6. Write a clear PR description: what changed, why, and how you tested it. Link the issue.
7. A maintainer will review. Expect iteration — that's normal and healthy.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add shared-folder configuration to VM settings
fix: prevent crash when ISO path is missing
docs: clarify entitlement setup in DEVELOPMENT.md
```

## Coding standards

- **Swift**, formatted with [`swift-format`](https://github.com/apple/swift-format)
  (CI checks this).
- SwiftUI for UI; keep platform/virtualization logic out of views.
- Follow the layering in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): UI → ViewModel →
  VM engine (`VMBackend`). Don't call `Virtualization` APIs directly from views.
- Public types and non-obvious logic get doc comments.
- No force-unwraps in non-test code without a clear invariant comment.

## Licensing of contributions

Kapsule is licensed under **Apache-2.0**. By submitting a contribution, you agree that
your work is licensed under the same terms (the "inbound = outbound" rule). Don't submit
code you didn't write or that you aren't permitted to license this way. **Never** paste
decompiled, disassembled, or copied code from any commercial product — that would
jeopardize the whole project. Kapsule is a clean-room, from-scratch implementation.

## Questions

Open a [Discussion](https://github.com/prakashsolanki28/kapsule/discussions) or ask in an issue.
