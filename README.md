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

- Bash 3.2+
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

## Top 5 Ops Commands

```bash
# 1) Quick inspect (no CA required)
./certgen verify --cert output/vault-0/tls.crt

# 2) Show SAN values only
./certgen verify --cert output/vault-0/tls.crt --query san

# 3) Validate chain + expected SANs
./certgen verify \
  --cert output/vault-0/tls.crt \
  --ca output/ca/ca.crt \
  --expected-dns "vault-0,localhost" \
  --expected-ip "127.0.0.1"

# 4) Alert if cert expires within 30 days
./certgen verify --cert output/vault-0/tls.crt --check-expiry-days 30

# 5) Optional revocation check (best effort)
./certgen verify --cert output/vault-0/tls.crt --ca output/ca/ca.crt --revocation ocsp
```

## Troubleshooting

### SAN validation fails

Symptom:
- `SAN validation failed ... missing DNS:<value>` or `missing IP:<value>`

Checks:
- Inspect actual SANs:
  - `./certgen verify --cert <cert-path> --query san`
- Compare with expected values passed to `--expected-dns` / `--expected-ip`

Fix:
- Regenerate cert with correct SAN values in CLI or config (`cert.<name>.san_dns`, `cert.<name>.san_ip`).

### Certificate expiring soon

Symptom:
- `Certificate expires within <n> day(s).`

Checks:
- `./certgen verify --cert <cert-path> --query not_after`
- `./certgen verify --cert <cert-path> --check-expiry-days 30`

Fix:
- Reissue certificate with updated validity and deploy the new files.

### Revocation status unknown/unavailable

Symptom:
- `OCSP URI not present ... status unknown`
- `CRL URI not present ... status unknown`
- fetch/parsing warnings for CRL/OCSP endpoints

Checks:
- `./certgen verify --cert <cert-path> --query ocsp_uri`
- `./certgen verify --cert <cert-path> --query crl_uri`

Fix:
- For internal/dev certs, this is often expected.
- Use `--strict-revocation` only where revocation metadata and network access are guaranteed.

### Chain validation fails

Symptom:
- `unable to get local issuer certificate`, `self-signed certificate in certificate chain`, or verify failure

Checks:
- Ensure `--ca` points to the correct CA certificate for the leaf cert
- Verify issuer quickly:
  - `./certgen verify --cert <cert-path> --query issuer`

Fix:
- Use the matching CA from the same output set (for example `output/ca/ca.crt`).

### JKS not generated

Symptom:
- Warning about `keytool`/Java runtime unavailable

Checks:
- `./certgen doctor`

Fix:
- Install a Java runtime with `keytool` on PATH, or use PEM/PKCS#12 outputs.

## CLI Usage

```bash
./certgen --config <file> [--fresh-ca] [--output-root <dir>] [--package-web|--no-package-web]
./certgen <config-file> [--fresh-ca] [--output-root <dir>]   # shorthand
./certgen server --cn <name> [--name <id>] [--san-dns <csv>] [--san-ip <csv>] [--formats <csv>] [--fresh-ca] [--output-root <dir>] [--package-web|--no-package-web]
./certgen client --cn <name> [--name <id>] [--san-dns <csv>] [--san-ip <csv>] [--formats <csv>] [--fresh-ca] [--output-root <dir>]
./certgen ca [--fresh] [--info] [--output-root <dir>]
./certgen verify --cert <path> [--ca <path>] [--expected-dns <csv>] [--expected-ip <csv>]
                [--query <field>] [--text] [--check-expiry-days <n>]
                [--revocation ocsp|crl] [--strict-revocation]
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

### Inspect a certificate (view-only)

```bash
./certgen verify --cert output/vault-0/tls.crt
```

### Verify chain and SAN values

```bash
./certgen verify \
  --cert output/vault-0/tls.crt \
  --ca output/ca/ca.crt \
  --expected-dns "vault-0,localhost" \
  --expected-ip "127.0.0.1"
```

### Query a specific field

```bash
./certgen verify --cert output/vault-0/tls.crt --query san
./certgen verify --cert output/vault-0/tls.crt --query serial
./certgen verify --cert output/vault-0/tls.crt --query signature_algorithm
```

Supported `--query` values:
- `subject`, `issuer`, `serial`
- `not_before`, `not_after`, `dates`, `fingerprint`
- `san`
- `key_usage`, `eku`, `basic_constraints`, `ski`, `aki`
- `signature_algorithm`, `public_key_algorithm`, `public_key_size`, `curve`
- `ocsp_uri`, `crl_uri`

### Full certificate text

```bash
./certgen verify --cert output/vault-0/tls.crt --text
```

### Expiry threshold check

```bash
./certgen verify --cert output/vault-0/tls.crt --check-expiry-days 30
```

### Optional revocation checks (best effort)

```bash
./certgen verify --cert output/vault-0/tls.crt --ca output/ca/ca.crt --revocation ocsp
./certgen verify --cert output/vault-0/tls.crt --ca output/ca/ca.crt --revocation crl
```

Use strict mode if you want revocation check unavailability to fail:

```bash
./certgen verify --cert output/vault-0/tls.crt --ca output/ca/ca.crt --revocation ocsp --strict-revocation
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


