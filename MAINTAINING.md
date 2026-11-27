# Maintaining the repositories

Nobody has to do anything at a release. Each hour, [the workflow](.github/workflows/packages.yml) asks marqius.com for its latest release. When that release is newer than the one these repositories serve, the workflow does the following, in order:

1. Downloads the four builds and checks each against the checksum published beside it.
2. Builds and signs six packages: `.deb`, `.rpm` and `.apk`, each for x86-64 and ARM64.
3. Rebuilds the repositories with the new packages and those of the four releases before.
4. Tests on 13 systems, on both architectures, with the README's own lines run exactly as printed. It installs, updates from the release before, gives the program the wkhtmltopdf names, takes them away and removes it.
5. Publishes the release (its packages and a signed `SHA256SUMS`) and then the repositories.
6. Tests the published repositories again, the Dockerfile lines included. If a line fails, it opens an issue.

## Switching publishing on and off

The repository variable `PUBLISHING` (Settings > Secrets and variables > Actions > Variables) must be `on` for anything to be published. Set it to `off` to pause: the hourly check then does nothing, and a run by hand builds and tests the latest release without publishing it.

## The address

Customers' machines use `https://packages.marqius.com`, which GitHub Pages serves for this repository. The address is set up once:

- In Cloudflare's DNS for marqius.com, `packages` is a CNAME to `marqiushq.github.io`, DNS only (not proxied), so that GitHub can issue its certificate.
- In this repository's Settings > Pages, the source is GitHub Actions, the custom domain is `packages.marqius.com`, and HTTPS is enforced.
- marqius.com is a verified domain of the marqiushq organisation (a TXT record that GitHub names). So no other GitHub account can take over the address if this site is ever switched off.

The site can move elsewhere, to Cloudflare R2 for example, without customers changing a line: only the DNS record changes.

## The keys

| Key | Signs | Private half |
|---|---|---|
| OpenPGP, RSA 4096 (`marqius.asc`) | apt's `InRelease`, dnf's `repomd.xml`, every `.rpm`, `SHA256SUMS.asc` | secret `PACKAGES_GPG_KEY` of the `packages` environment, and the owner's offline copy |
| RSA 4096 (`marqius.rsa.pub`) | Alpine's `APKINDEX.tar.gz` and every `.apk` | secret `PACKAGES_APK_KEY` of the `packages` environment, and the owner's offline copy |
| none | `SHA256SUMS.sigstore.json` | cosign signs it in the publishing job and Sigstore logs it publicly; there is no key to keep |
| none | build provenance of each package and of `SHA256SUMS` | GitHub's attestation, made in the publishing job; checked with `gh attestation verify` |

Only the `main` branch may use the `packages` environment. Runs for pull requests and other changes sign with throwaway keys that live only as long as the run. The licence key of marqius-wkhtmltopdf is separate and is never used here.

The keys have no expiry date on purpose. A key that expires stops every customer's updates on the day it does, unless someone renews it in time and every machine fetches the renewed key.

**Changing a key on purpose, without breaking any install.** Allow an overlap of at least three months:

1. Make the new keys with `scripts/make-keys.sh` into a new folder, and add them as secrets beside the old ones.
2. During the overlap, sign with both keys. Machines that know only the old key keep checking it, and machines set up afterwards trust both:
   - **apt:** `InRelease` and `Release.gpg` carry a signature from each key; apt needs one it trusts. `marqius.sources` carries both public keys in its `Signed-By` block.
   - **dnf:** `marqius.asc`, at the same address, holds both public keys, and `repomd.xml.asc` holds both signatures. dnf asks once to accept the new key when it first sees a package signed with it.
   - **Alpine:** the package itself installs the new public key in `/etc/apk/keys`, so an ordinary update delivers it, and the index carries a signature from each key.
3. Announce the change, with the date the old key stops, in the README and the release notes.
4. After the overlap, sign with the new key only and remove the old public key from the published files. An apt machine that has not run the README's setup line since the overlap began needs to run it once.

**If a private key is ever exposed**, there is no overlap:

1. Publish its revocation certificate, kept in the owner's backup.
2. Make new keys, put them in the secrets, and put the new fingerprints in the README.
3. Run the workflow by hand.
4. Tell customers to run the README's setup line once more. dnf users also remove the old key with `rpm -e gpg-pubkey-<its key ID>`.

The addresses of the key files never change.

## Before changing anything

```bash
scripts/test-keys.sh /tmp/keys
```

These throwaway keys are enough for every local test. The scripts need Docker, and nothing else installed:

| Script | What it does |
|---|---|
| `scripts/follow-release.py --site URL --out builds --always` | fetches and checks the latest builds |
| `scripts/build-packages.sh VERSION builds packages` | the six packages |
| `scripts/make-repos.sh packages site https://packages.marqius.com` | the signed repositories |
| `scripts/test-repos.sh site` | README's lines on all 13 systems, through a local stand-in for the real address |
| `scripts/test-repos.sh --upgrade OLD NEW` | the update line, from one site to the next |
| `PHASE=refuse scripts/test-repos.sh SITE` | the install lines must fail on a tampered site |

Every printed command in the README is a block that follows a `<!-- test: NAME -->` line, and the tests run that block as it stands. To change a command, change it there; the next run proves it.

When some of Ubuntu's archive is crawling, the Ubuntu x86-64 tests turn apt to kernel.org's mirror of it before the README's lines run, and the result line says so. Otherwise each system is used as it comes.
