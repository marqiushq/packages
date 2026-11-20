# marqius-wkhtmltopdf for apt, dnf and apk

Install **marqius-wkhtmltopdf**, the maintained drop-in replacement for wkhtmltopdf, from signed package repositories, and keep it up to date with the rest of the system. This is for teams whose Linux no longer offers wkhtmltopdf, such as Debian 13 and Ubuntu 26.04. It runs on Debian, Ubuntu, Rocky Linux, Red Hat Enterprise Linux, Fedora, Amazon Linux and Alpine, on x86-64 and ARM64.

It is installed as `marqius-wkhtmltopdf`, so a wkhtmltopdf you already have keeps working until you choose to switch.

## Debian and Ubuntu

Add the repository, once:

<!-- test: apt-repo -->
```bash
sudo curl -fsSLo /etc/apt/sources.list.d/marqius.sources https://packages.marqius.com/apt/marqius.sources
```

Install it (run this line again at any time to update it):

<!-- test: apt-install -->
```bash
sudo apt update && sudo apt install marqius-wkhtmltopdf
```

## Rocky Linux, Red Hat Enterprise Linux, Fedora and Amazon Linux

Add the repository, once:

<!-- test: dnf-repo -->
```bash
sudo curl -fsSLo /etc/yum.repos.d/marqius.repo https://packages.marqius.com/rpm/marqius.repo
```

Install it. The first time, dnf asks you to accept the signing key: check that its fingerprint matches the one under [Check what you install](#check-what-you-install).

<!-- test: dnf-install -->
```bash
sudo dnf install marqius-wkhtmltopdf
```

## Alpine

As root, add the repository and its key, then install:

<!-- test: apk -->
```sh
wget -qP /etc/apk/keys https://packages.marqius.com/alpine/marqius.rsa.pub
echo https://packages.marqius.com/alpine >> /etc/apk/repositories
apk add marqius-wkhtmltopdf
```

## In a Dockerfile

On Debian and Ubuntu images, such as `python:3.13`, `ruby:3.4` and `php:8.4`:

<!-- test: docker-apt -->
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates
ADD https://packages.marqius.com/apt/marqius.sources /etc/apt/sources.list.d/
RUN apt-get update && apt-get install -y --no-install-recommends marqius-wkhtmltopdf
```

On Rocky Linux, Red Hat UBI, Fedora and Amazon Linux images:

<!-- test: docker-dnf -->
```dockerfile
ADD https://packages.marqius.com/rpm/marqius.repo /etc/yum.repos.d/
RUN dnf install -y marqius-wkhtmltopdf
```

On Alpine images:

<!-- test: docker-apk -->
```dockerfile
ADD https://packages.marqius.com/alpine/marqius.rsa.pub /etc/apk/keys/
RUN echo https://packages.marqius.com/alpine >> /etc/apk/repositories && apk add --no-cache marqius-wkhtmltopdf
```

## Check it works

It reads wkhtmltopdf's command line as it is. Try it in an empty folder:

<!-- test: check -->
```bash
marqius-wkhtmltopdf --version
echo '<h1>Invoice 42</h1><p>Total €1,234.50</p>' > invoice.html
marqius-wkhtmltopdf --page-size A4 invoice.html invoice.pdf
```

The fonts it needs come with it: the Liberation and DejaVu families, the same as in the `marqius/wkhtmltopdf` Docker images. (Red Hat's UBI images do not offer Liberation; there it comes with DejaVu alone.)

## Switch your application

Keep your library, HTML templates and PDF calls, and point the library at marqius-wkhtmltopdf in either of two ways.

**Name its path in the library's settings:** `/usr/bin/marqius-wkhtmltopdf`. `marqius-wkhtmltopdf help libraries` lists the libraries it knows, from python-pdfkit and Snappy to wicked_pdf and Rotativa, and `marqius-wkhtmltopdf help snappy` (or another name from that list) shows where each one takes the path.

**Or give it the names wkhtmltopdf and wkhtmltoimage**, in `/usr/local/bin`, where libraries look first:

<!-- test: names -->
```bash
sudo marqius-wkhtmltopdf install
```

Programs that run `wkhtmltopdf` now run marqius-wkhtmltopdf, and `wkhtmltopdf -V` says so. A wkhtmltopdf already in `/usr/local/bin` is left as it is; `sudo marqius-wkhtmltopdf install --force` takes its place and keeps it beside it. To take the names away again, and put back what `--force` kept:

<!-- test: names-undo -->
```bash
sudo marqius-wkhtmltopdf install --undo
```

On Alpine, as root, run the same lines without `sudo`.

## Updates

Every new release of marqius-wkhtmltopdf reaches these repositories within the hour, after it has been installed and tested on every system listed under [Tested on every release](#tested-on-every-release). Every earlier release stays in them, so a version you have pinned keeps installing. It updates with the rest of the system, or on its own:

<!-- test: apt-update -->
```bash
sudo apt update && sudo apt install marqius-wkhtmltopdf
```

<!-- test: dnf-update -->
```bash
sudo dnf upgrade --refresh marqius-wkhtmltopdf
```

<!-- test: apk-update -->
```sh
apk upgrade --update-cache marqius-wkhtmltopdf
```

## Check what you install

Every package, and every repository index, is signed. apt, dnf and apk check the signatures before they install anything.

- **apt and dnf key:** `marqius.asc`, fingerprint `D42A F470 6C33 20A8 5512 F721 2408 F335 9788 FAB6`.
- **Alpine key:** `marqius.rsa.pub`, whose SHA-256 is `cfb6f52cbf20f6f9067157cc9e8d864ec42680eca920eb288aa6e4f595aba73f`.

Each release on the [releases page](https://github.com/marqiushq/packages/releases) lists every file of it in one `SHA256SUMS`: the four downloads on marqius.com and the six packages. The file is signed in two ways. Download it and its signatures:

<!-- test: sums-get -->
```bash
curl -fsSLO https://github.com/marqiushq/packages/releases/latest/download/SHA256SUMS
curl -fsSLO https://github.com/marqiushq/packages/releases/latest/download/SHA256SUMS.asc
curl -fsSLO https://github.com/marqiushq/packages/releases/latest/download/SHA256SUMS.sigstore.json
```

Check it with [cosign](https://docs.sigstore.dev/cosign/system_config/installation/). The signature was made by this repository's release workflow and is recorded in Sigstore's public log:

<!-- test: sums-cosign -->
```bash
cosign verify-blob SHA256SUMS --bundle SHA256SUMS.sigstore.json --certificate-identity https://github.com/marqiushq/packages/.github/workflows/packages.yml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Or with gpg, against the key above:

<!-- test: sums-gpg -->
```bash
curl -fsSL https://packages.marqius.com/marqius.asc | gpg --import
gpg --verify SHA256SUMS.asc SHA256SUMS
```

Each package, and `SHA256SUMS`, also carries GitHub's record of how it was made: the workflow run and the exact commit of this repository that built it. Check it with [GitHub's command line](https://cli.github.com/), signed in:

<!-- test: sums-provenance -->
```bash
gh attestation verify SHA256SUMS --repo marqiushq/packages
```

Then, in the folder with your downloads, `sha256sum --ignore-missing -c SHA256SUMS` checks each of them.

## Remove it

Removing it also takes away the names wkhtmltopdf and wkhtmltoimage that `marqius-wkhtmltopdf install` gave it in `/usr/local/bin`, and puts back a program they had replaced.

<!-- test: apt-remove -->
```bash
sudo apt remove marqius-wkhtmltopdf && sudo rm /etc/apt/sources.list.d/marqius.sources
```

<!-- test: dnf-remove -->
```bash
sudo dnf remove marqius-wkhtmltopdf && sudo rm /etc/yum.repos.d/marqius.repo
```

<!-- test: apk-remove -->
```sh
apk del marqius-wkhtmltopdf && sed -i '\|packages.marqius.com|d' /etc/apk/repositories && rm /etc/apk/keys/marqius.rsa.pub
```

## Tested on every release

Debian 12 and 13, Ubuntu 22.04, 24.04 and 26.04, Rocky Linux 9 and 10, Red Hat Enterprise Linux 9 (UBI), Fedora, Amazon Linux 2023, and Alpine 3.22, 3.23 and 3.24, each on x86-64 and ARM64. Before a release reaches the repositories, [the workflow](.github/workflows/packages.yml) checks each download against its published checksum, then installs it on each of these systems with the lines on this page, exactly as printed, and makes a PDF.

## Licence

marqius-wkhtmltopdf is commercial software from Simple AI LLC, with a 30-day free trial counted from its first run; `marqius-wkhtmltopdf licence` shows the days left. After the trial, without a licence, each page carries one line saying the copy is unlicensed. [Plans and licences](https://marqius.com/wkhtmltopdf/) · [Licence terms](https://marqius.com/licence/marqius-wkhtmltopdf)

Questions: hello@marqius.com. The same program is also available [with Homebrew](https://github.com/marqiushq/homebrew-tap), as the [Docker image marqius/wkhtmltopdf](https://hub.docker.com/r/marqius/wkhtmltopdf), and with the one-line installer on [marqius.com](https://marqius.com/wkhtmltopdf/).
