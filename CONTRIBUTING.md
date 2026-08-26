# Contributing to MoonBack

Bug reports, documentation improvements, tests, and code contributions are
welcome.

## Report an issue

Before filing an issue, search existing issues and try the latest MoonBack and
MoonBit releases. A useful bug report includes:

- the output of `moon version --all` and your operating system;
- a minimal reproducer;
- the expected and actual behavior; and
- complete error messages or logs with secrets removed.

Use the repository's security reporting process for vulnerabilities instead
of opening a public issue.

## Develop locally

From the repository root, run:

```bash
moon fmt --check
moon check --deny-warn
moon test --deny-warn
```

If a change affects a public API, regenerate and review the checked-in
interfaces:

```bash
moon info
git diff -- '*.mbti'
```

## Submit a pull request

Keep each pull request focused and explain the motivation as well as the
implementation. Add or update tests for behavior changes and update user-facing
documentation when needed. Discuss broad API changes in an issue before doing
substantial implementation work.

The continuous integration checks require formatted code, a warning-free
build, passing tests, and up-to-date generated interface files.

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in MoonBack is licensed under the Apache License 2.0,
in accordance with section 5 of that license.
