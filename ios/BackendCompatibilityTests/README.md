# iOS backend compatibility tests

The rules fixture is an unchanged copy of `app/firestore.rules` from the Android
`v1.0.0` release tag in Arnab-apk/Hopping_Guide. It is a test fixture, not a
replacement for deployed rules. No Android source or production rules are changed.

Tests reproduce native iOS membership batches and subsequent welcome/join notices,
Android group flows, hopping-plan/queue writes, public browsing, and access restrictions.
Two regression cases verify that sending welcome/join notices in the initial batch
is rejected by Android's rules; the iOS service sends them after membership commits.

Requires Node 22+ and Java 21+:

```sh
cd ios/BackendCompatibilityTests
npm ci
npm test
```

The `demo-uma-rules` local emulator is used. No production Firebase project is contacted.
