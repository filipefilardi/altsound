# Contributing to AltSound

Thanks for your interest in contributing to AltSound.

This guide explains how to propose changes, set up your environment, and submit pull requests that are easy to review.

## Code of Conduct

By participating in this project, you agree to follow our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Before You Start

- Check existing issues and pull requests to avoid duplicate work.
- For non-trivial features or refactors, open an issue first so we can align on scope and approach.
- Keep contributions focused: one fix or feature per pull request whenever possible.

## Development Setup

### Prerequisites

- Flutter SDK (stable) with Dart `^3.8.1`
- A running Jellyfin server with a music library for manual testing
- Platform tooling as needed:
  - Xcode for iOS/macOS
  - Android SDK / Android Studio for Android

### Clone and Run

```bash
git clone https://github.com/filipefilardi/altsound.git
cd altsound
flutter pub get
flutter run
```

## Branching

- Branch from `main`.
- Use descriptive branch names, for example:
  - `feat/offline-playlist-filter`
  - `fix/player-seekbar-snap`
  - `chore/dependency-updates`

## Coding Guidelines

- Follow existing architecture and style in `lib/`.
- Use package imports (`package:altsound/...`) rather than relative imports where applicable.
- Keep widgets and controllers small and focused.
- Avoid unrelated formatting-only changes in functional PRs.
- Add comments only when logic is non-obvious.

## Quality Checks

Run these before opening a PR:

```bash
flutter analyze
flutter test
```

If your change touches platform-specific behavior, also run the app on the relevant platform (Android, iOS, and/or macOS) and include the result in the PR description.

## Pull Request Checklist

Include the following in your PR:

- Clear title and summary of what changed
- Why the change is needed
- Screenshots or short recordings for UI changes (if applicable)
- Testing notes (what you ran and what you validated manually)
- Linked issue(s), using `Closes #<issue-number>` when appropriate

## Commit Messages

Use clear, imperative commit messages. Examples:

- `fix: prevent duplicate tracks in queue`
- `feat: add artist download button`
- `chore: bump flutter_riverpod to latest`

## Reporting Bugs

When opening a bug report, include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- Platform/device details
- App version (`Settings -> Version`) if available
- Relevant logs or screenshots

## Feature Requests

Feature requests are welcome. Please describe:

- The problem you are trying to solve
- The proposed solution
- Any alternatives considered

## Release and CI Notes

This repository includes an Android release workflow under `.github/workflows/android-deploy-google-play.yml` that builds and deploys from `main`.

Contributors do not need to handle release secrets or deployment setup; maintainers manage those credentials.

## Questions

If anything is unclear, open an issue and ask. Small, iterative PRs are encouraged.
