# Shared Firestore rules regression tests

These tests reproduce Android v1.0.0 and iOS group writes using the Firestore
emulator, including the shared hopping plan and queue collections. They also
check that nonmembers cannot access private group data or alter another member.

Requires Node 22+ and Java 21+:

```sh
cd app/rules-tests
npm ci
npm test
```

The `demo-uma-rules` project and local emulator are used; these commands do not
deploy rules or write to a production Firebase project.
