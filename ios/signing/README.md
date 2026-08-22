# iOS signing, with no Mac anywhere in it

Apple requires a signed `.ipa` for TestFlight and the App Store. This directory
holds everything needed to produce one on GitHub Actions from a Linux
workstation: `openssl` makes the key and the request, Apple's web UI issues the
certificate, and the runner does the signing.

The chain is not theoretical. The same four files, on this same Apple team,
produced a signed TestFlight build for Rósa Parks on 2026-07-14 with
`processingState VALID`. What follows is that path with the names changed, and
with the one failure that cost a day called out where it bites.

## What is already true

Unlike the first time this was set up, nothing is pending:

- **Apple Developer Program enrollment: Active** since 2026-05-20, as an
  organization. Entity name `Sosialistaflokkur Islands`.
- **Team ID `B4724Z74TM`**, already pinned as `DEVELOPMENT_TEAM` in
  `ios/project.yml`. App Store Connect team UUID
  `12165069-3bdf-40d1-a2f0-3c8805b54eb6`.
- **Annual fee waived** under the non-profit waiver; renews 2027-05-20.
- **Account Holder: Guðröður**, Apple ID `gudrodur@gmail.com`. Some steps below
  can only be done by that account, and they say so.
- **Program License Agreement accepted** 2026-08-22. This one matters more than
  it looks: an unaccepted agreement makes every App Store Connect API call
  return `403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`, which mentions
  no agreement anywhere in its text. If a step below 403s for no visible reason,
  check the agreements page first (issue #37).

Borgarland is Samtak svf.'s app shipping on the party's Apple team, on purpose
and temporarily, so one tester can install it on one phone. A bundle identifier
moves between teams later. See issue #37 for the reasoning and what it does not
commit us to.

## Most of this was already done, and this section says which

**An Apple Distribution certificate and an App Store Connect API key are scoped
to the TEAM, not to an app.** Verified 2026-08-22 by reading the certificate:
`UID=B4724Z74TM`, `OU=B4724Z74TM`, valid to 2027-05-20. The App Store Connect
API key's issuer identifies the same team and its App Manager role reaches every
app on it.

So for Borgarland, **steps 1 to 4 and step 7 below were already done** and cost
nothing. They stay written down because the certificate expires in May 2027 and
somebody will have to do them then.

| Step | For a new app on this team |
|---|---|
| 1-3 key, certificate, `.p12` | **already exists**, reuse it |
| 4 App Store Connect API key | **already exists**, reuse it |
| 5 App ID and app record | **must be created**, once per app |
| 6 Provisioning profile | **must be created**, once per app |
| 7 GitHub secrets | copy the same five values from GCP |

The five values live in GCP Secret Manager, project `fedora-setup-secrets`,
account `gudrodur@gmail.com`, and the whole of step 7 is:

```bash
gcloud secrets versions access latest --secret=samtakamatt-rosaparks-ios-signing-p12 \
  | gh secret set IOS_SIGNING_P12_BASE64
gcloud secrets versions access latest --secret=samtakamatt-rosaparks-ios-signing-p12-password \
  | gh secret set IOS_SIGNING_P12_PASSWORD
gcloud secrets versions access latest --secret=samtakamatt-rosaparks-asc-api-key-id \
  | gh secret set ASC_API_KEY_ID
gcloud secrets versions access latest --secret=samtakamatt-rosaparks-asc-api-issuer-id \
  | gh secret set ASC_API_ISSUER_ID
gcloud secrets versions access latest --secret=samtakamatt-rosaparks-asc-api-key-p8 \
  | gh secret set ASC_API_KEY_P8
```

The names say `rosaparks` because that is the app they were made for. They are
not specific to it. **Do not create a second certificate for a new app.**

**Steps 5 and 6 do not need the web UI either, except for one part.** The App
Store Connect API registers a bundle id and creates a profile in seconds:

```
POST /v1/bundleIds   {identifier, name, platform: IOS}
POST /v1/profiles    {name, profileType: IOS_APP_STORE} + bundleId + certificate
```

What it will not do is create the **app record**, and it says so plainly:
`The resource 'apps' does not allow 'CREATE'`. That one is the web UI, and so is
creating an API key in the first place.

## Setup, in order

### 1. Key and certificate request, on Linux

```bash
cd ios/signing
./1-generate-csr.sh
```

Writes `.secrets/ios-signing.key` and `.secrets/ios-signing.csr`. The directory
is gitignored; the key never leaves the machine.

### 2. Have Apple issue the certificate

1. <https://developer.apple.com/account/resources/certificates/add>
2. Under **Software**, choose **Apple Distribution**
3. Continue, upload `.secrets/ios-signing.csr`, download the `.cer`

### 3. Bundle it, on Linux

```bash
./2-convert-cert.sh ~/Downloads/distribution.cer
```

Prints the password and writes `.secrets/ios-signing.p12`.

### 4. App Store Connect API key

1. <https://appstoreconnect.apple.com/access/api>
2. **Generate API Key**, name it `borgarland-ci`, access **App Manager**
3. Download the `.p8` **immediately**. Apple allows exactly one download.
4. Note the **Key ID** (10 characters) and the **Issuer ID** (a UUID above the
   table)

### 5. Register the identifier and the app record

1. <https://developer.apple.com/account/resources/identifiers/add> — an explicit
   App ID, `is.borgarland`, matching `PRODUCT_BUNDLE_IDENTIFIER` in
   `ios/project.yml`.
2. <https://appstoreconnect.apple.com/apps> → **+** → **New App**. Platform iOS,
   bundle ID `is.borgarland`, SKU `is.borgarland`.
   App Store metadata does not support Icelandic as a primary language; pick
   English (U.S.). In-app strings are Icelandic regardless, and localize
   separately from the listing.

### 6. Provisioning profile

1. <https://developer.apple.com/account/resources/profiles/add>
2. **App Store** distribution
3. App ID `is.borgarland`, certificate: the Apple Distribution one from step 2
4. Name it exactly **`Borgarland App Store`** — `ExportOptions.plist` and
   `ios/project.yml` both name it as a string, and a mismatch fails the export
   with a message that blames neither file
5. Do not download it. The workflow fetches profiles through the API key.

### 7. GitHub secrets

<https://github.com/samtak-svf/borgarland/settings/secrets/actions>

| Secret | Value |
|---|---|
| `IOS_SIGNING_P12_BASE64` | `base64 -w0 ios/signing/.secrets/ios-signing.p12` |
| `IOS_SIGNING_P12_PASSWORD` | the password printed by `2-convert-cert.sh` |
| `ASC_API_KEY_ID` | the 10-character Key ID from step 4 |
| `ASC_API_ISSUER_ID` | the Issuer UUID from step 4 |
| `ASC_API_KEY_P8` | the **raw PEM** contents of `AuthKey_*.p8` |

**`ASC_API_KEY_P8` is raw PEM, not base64.** Base64-encoding it fails inside the
JWT signer with `error:1E08010C:DECODER routines::unsupported`, an error that
says nothing about encoding. This cost a day on the other app.

The Team ID is not a secret here. The workflow signs manually against a named
profile, and neither `import-codesign-certs` nor `download-provisioning-profiles`
takes a team input, so nothing reads it.

### 8. Build

```bash
gh workflow run ios-release.yml
```

or push a tag matching `ios-v*`. The workflow archives, exports a signed `.ipa`
and uploads it to TestFlight. Internal testers with a role on the team get an
email; internal testing does not wait for Beta App Review.

## Verifying a failure honestly

When TestFlight rejects a build, **unpack the `.ipa` and look**. Apple's error
strings run past 400 characters and a naive `grep` of the logs truncates them,
which once produced a confident and entirely false "fixed". The artifact is
uploaded on every run for exactly this.

## Layout

```
ios/signing/
├── README.md             ← this file
├── 1-generate-csr.sh     ← Linux, step 1
├── 2-convert-cert.sh     ← Linux, step 3
├── ExportOptions.plist   ← read by xcodebuild -exportArchive in CI
└── .secrets/             ← gitignored, created by the scripts
    ├── ios-signing.key   ← KEEP SECRET
    ├── ios-signing.csr   ← disposable once the certificate is issued
    ├── ios-distribution.pem
    └── ios-signing.p12   ← what the runner imports
```

## Rotation

The certificate is valid for one year. Before it expires: delete
`.secrets/ios-signing.key`, re-run both scripts, re-issue the certificate, and
update `IOS_SIGNING_P12_BASE64` and `IOS_SIGNING_P12_PASSWORD`. App Store
Connect API keys do not expire, but can be revoked in the web UI.
