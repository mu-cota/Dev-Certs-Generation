# PKI Certificate Generation Toolkit

Enterprise-grade certificate generation for development and production-like internal environments, built with Bash + OpenSSL and designed for easy operation.

## Features

- Self-signed root CA generation and reuse mode
- ECDSA P-384 by default (`secp384r1`)
- Server and client certificate support (mTLS ready)
- Config-driven batch mode + ad-hoc CLI mode
- SAN customization (`DNS` and `IP`)
- Multi-format output: PEM, PKCS#12, JKS (JKS generated when `keytool` exists)
- Post-generation validation (chain + SAN checks + report)
- Safer cleanup workflow with confirmation
- Friendly UX defaults and environment doctor checks

## Repository Layout

```text
.
├── certgen                      # Main CLI
├── certgen.yaml                 # Default config template
├── cleanup.sh                   # Generated-artifact cleanup
├── certs-once.sh.legacy         # Legacy script retained for reference
├── lib/
│   ├── common.sh
│   ├── config.sh
│   ├── ca.sh
│   ├── extensions.sh
│   ├── cert.sh
│   ├── formats.sh
│   └── validate.sh
└── examples/
    ├── single-server.yaml
    ├── multi-service.yaml
    └── mtls-setup.yaml
```

## Prerequisites

- Bash 4+
- OpenSSL
- Optional: `keytool` (required only for JKS generation)

## Quick Start

### 1) Generate all certs from default config

```bash
chmod +x certgen cleanup.sh
./certgen --config certgen.yaml
```

### 2) Force a fresh CA and regenerate

```bash
./certgen --config certgen.yaml --fresh-ca
```

### 3) Use an example config

```bash
./certgen --config examples/mtls-setup.yaml --fresh-ca
```

### 4) Run health checks before first use

```bash
./certgen doctor
```

## CLI Usage

```bash
./certgen --config <file> [--fresh-ca] [--output-root <dir>]
./certgen --config <file> [--fresh-ca] [--output-root <dir>] [--package-web|--no-package-web]
./certgen <config-file> [--fresh-ca] [--output-root <dir>]   # shorthand
./certgen server --cn <name> [--name <id>] [--san-dns <csv>] [--san-ip <csv>] [--formats <csv>] [--fresh-ca] [--output-root <dir>] [--package-web|--no-package-web]
./certgen client --cn <name> [--name <id>] [--san-dns <csv>] [--san-ip <csv>] [--formats <csv>] [--fresh-ca] [--output-root <dir>]
./certgen ca [--fresh] [--info] [--output-root <dir>]
./certgen verify --cert <path> --ca <path> [--expected-dns <csv>] [--expected-ip <csv>]
./certgen doctor
```

## Ad-hoc Examples

### Server cert with custom SANs

```bash
./certgen server \
  --cn vault-0 \
  --name vault-0 \
  --san-dns "vault-0,vault-0.vault.svc,localhost" \
  --san-ip "127.0.0.1" \
  --package-web \
  --formats "pem,pkcs12,jks" \
  --fresh-ca
```

### Client cert for mTLS

```bash
./certgen client \
  --cn payment-service \
  --name payment-client \
  --san-dns "payment-service.internal" \
  --formats "pem,pkcs12,jks"
```

### Friendly SAN defaults

If you omit `--san-dns`, the CLI auto-fills:

- `server`: `<cn>,localhost`
- `client`: `<cn>`

### Verify a generated certificate

```bash
./certgen verify \
  --cert output/vault-0/tls.crt \
  --ca output/ca/ca.crt \
  --expected-dns "vault-0,localhost" \
  --expected-ip "127.0.0.1"
```

## Config Format

`certgen.yaml` uses a simple key-value format that is easy to audit and review in code:

- CA keys: `ca_*`
- Default leaf keys: `default_*`
- Per-certificate keys: `cert.<name>.<property>`

Supported cert properties:

- `type`: `server` or `client`
- `cn`
- `san_dns` (CSV)
- `san_ip` (CSV)
- `formats` (`pem`, `pkcs12`, `jks`)
- `package_web` (`true` or `false`, server certs only, default `true`)
- Optional overrides: `country`, `state`, `locality`, `organization`, `ou`, `validity_days`, `curve`

## Output Structure

```text
output/
├── ca/
│   ├── ca.key
│   ├── ca.crt
│   └── ca.srl
├── <cert-name>/
│   ├── tls.key
│   ├── tls.crt
│   ├── ca.crt
│   ├── full-chain.crt
│   ├── fullchain.pem          # default on for server certs
│   ├── privkey.pem            # default on for server certs
│   ├── tls.p12
│   ├── tls.p12.pass
│   ├── tls.jks
│   └── cert-info.txt
└── generation-report.txt
```

## Security Notes

- Private keys are written with restricted permissions (`0600`)
- Certificate directories are locked down (`0700`)
- Certificates and reports are world-readable (`0644`)
- Generated outputs and secret artifacts are git-ignored by default
- This toolkit intentionally does **not** implement intermediate CAs in this version

By default, server certs include:
- `fullchain.pem` (certificate + CA chain)
- `privkey.pem` (private key)

You can disable this with:
- CLI: `--no-package-web`
- Config: `cert.<name>.package_web: "false"`

## Cleanup

Interactive cleanup:

```bash
./cleanup.sh
```

Non-interactive cleanup:

```bash
./cleanup.sh --force
```


