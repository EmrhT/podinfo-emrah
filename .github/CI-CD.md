# Podinfo CI/CD

The `delivery` workflow owns the lab-a delivery sequence:

1. Run unit tests and send source analysis to the homelab SonarQube.
2. Build `linux/amd64`, publish `ghcr.io/emrht/podinfo-emrah:sha-<commit>`, and retain its immutable digest.
3. Scan that digest with the Trivy client against the homelab Trivy server.
4. Open and automatically merge a digest-only PR for lab-a dev.
5. Ask Argo CD to sync dev, then wait for the exact Git revision, image digest, and Healthy state.
6. Trigger the in-cluster ZAP automation plan against the internal dev Service and upload its results.
7. Open a digest-only production PR and enable auto-merge. CODEOWNERS approval by `@EmrhT` is required; after approval Argo CD auto-syncs production.

Only pushes to `master` and manual dispatches run delivery. Pull requests keep the existing unit/manifests and Go vulnerability workflows. The resource-intensive kind E2E workflow is manual.

## GitHub configuration

Repository secrets:

- `CF_ACCESS_CLIENT_ID`
- `CF_ACCESS_CLIENT_SECRET`
- `SONAR_TOKEN`
- `SONAR_MTLS_PKCS12_BASE64`
- `SONAR_MTLS_KEYSTORE_PASSWORD`
- `ZAP_API_KEY`
- `ARGOCD_AUTH_TOKEN`
- `IAC_PROMOTER_PRIVATE_KEY`

Repository variable:

- `IAC_PROMOTER_CLIENT_ID`

The Cloudflare service token is named `github-actions-podinfo-dev`. The GitHub App token is scoped to `EmrhT/ultimate-iac` with Contents and Pull requests write permissions.

The runner has no Kubernetes credentials. SonarQube is reached through its Cloudflare mTLS-protected CI hostname; its PKCS#12 client keystore is reconstructed only in the runner's temporary directory. Trivy, ZAP, and Argo CD are reached through their Cloudflare Access-protected CI hostnames. Argo CD is the only component that writes to Kubernetes.

## Security gates

- SonarQube must complete analysis and pass its quality gate.
- Trivy fails on fixed HIGH or CRITICAL image vulnerabilities. JSON, table, and SARIF reports are retained for 14 days.
- ZAP fails on automation-plan errors or High-risk alerts. Its progress and alert JSON are retained for 14 days.
- Production cannot merge until the production overlay receives the required CODEOWNERS approval.

ZAP uses a clean volatile session for every CI scan so findings from manual experiments cannot contaminate a deployment gate. Do not run a manual scan in the shared ZAP instance while `delivery` is in its DAST job.
