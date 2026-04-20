# Firebase Security Setup

Project: `memoirai-7db06`

## 1) Publish Firestore Rules

- Open: `https://console.firebase.google.com/project/memoirai-7db06/firestore/rules`
- Replace rules with the contents of `firestore.rules`.
- Publish.

## 2) Publish Storage Rules

- Open: `https://console.firebase.google.com/project/memoirai-7db06/storage/rules`
- Replace rules with the contents of `storage.rules`.
- Publish.

## 3) Enable App Check (balanced-private setup)

- Open: `https://console.firebase.google.com/project/memoirai-7db06/appcheck`
- Add App Check for iOS app `com.Buildr.MemoirAI`.
- Production: use DeviceCheck or App Attest.
- Simulator/dev: use debug provider token for local testing.

## 4) Validate Rules Quickly

1. Sign in as user A and generate a book.
2. In Firestore, verify writes under `users/{uid}/bookVersions/{bookVersionId}`.
3. In Storage, verify paths under `users/{uid}/books/{bookVersionId}/...`.
4. Sign in as user B and confirm user B cannot read user A data paths.

## 5) Notes

- Download URLs still work if someone has the tokenized URL.
- Rules still prevent unauthenticated listing and direct path access.
- For stricter privacy later, move to short-lived signed access via backend.
