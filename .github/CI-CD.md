# Podinfo CI/CD

The application and GitOps repositories both protect their default branches
with pull requests. Feature code is tested in the shared `lab-a-dev`
environment before a human can merge it into `podinfo-emrah/master`.

## Application pull-request delivery

The `application PR delivery` workflow runs for same-repository pull requests
targeting `master`:

1. Run unit tests and send source analysis to the homelab SonarQube.
2. Build `linux/amd64` and publish only the immutable
   `ghcr.io/emrht/podinfo-emrah:sha-<full-head-sha>` image.
3. Scan that digest with the Trivy client against the homelab Trivy server.
4. Open and automatically merge a digest-only GitOps PR for lab-a dev.
5. Ask Argo CD to sync dev, then verify the expected digest and Healthy state.
6. Run the in-cluster ZAP plan against the internal dev Service.
7. Publish the `PR delivery gate` check. The application PR cannot merge until
   every preceding stage succeeds.

The workflow group `podinfo-lab-a-delivery` serializes access to the shared dev
environment. Pull requests from forks are deliberately rejected because the
homelab credentials are available only to trusted branches in this repository.

## Application PR decision

The repository owner manually merges or closes the application PR. The
workflow and GitHub App never merge `podinfo-emrah/master`.

When the PR is merged, `application PR close handler`:

1. Resolves the exact full-SHA image that passed the PR delivery gate.
2. Moves the mutable `accepted` registry tag to that same digest without a
   rebuild. GitOps never deploys this mutable tag; it is only a rollback marker.
3. Opens or updates the fixed `promote/podinfo-lab-a-prod` GitOps PR.
4. Stops and requires `@EmrhT` to approve and manually merge production.

Updating one fixed production PR implements latest-accepted-wins. The GitOps
ruleset must dismiss stale approvals and require approval of the latest push.
Argo CD deploys production after the GitOps PR is manually merged.

When an application PR is closed without merging, the close handler compares
its full-SHA image with the current dev digest. It creates and automatically
merges a dev rollback PR only when dev still runs the rejected image. A newer
feature deployment is never overwritten. The rollback target is the `accepted`
digest, falling back to the current production digest during initial rollout.

## GitHub configuration

Repository secrets:

- `CF_ACCESS_CLIENT_ID`
- `CF_ACCESS_CLIENT_SECRET`
- `SONAR_TOKEN`
- `SONAR_MTLS_PKCS12_BASE64`
- `SONAR_MTLS_KEYSTORE_PASSWORD`
- `ZAP_API_KEY`
- `ARGOCD_AUTH_TOKEN`
- `DEFECTDOJO_API_TOKEN`
- `IAC_PROMOTER_PRIVATE_KEY`

Repository variable:

- `IAC_PROMOTER_CLIENT_ID`
- `DEFECTDOJO_ENGAGEMENT_ID`

The workflow also pins the DefectDojo product to `podinfo` and engagement to
`CI/CD`. Both the numeric engagement ID and its name are sent because background
imports use the names when reconstructing the import context.

The Cloudflare service token is `github-actions-podinfo-dev`. The GitHub App is
scoped to `EmrhT/ultimate-iac` with Contents and Pull requests write
permissions.

Protect `podinfo-emrah/master` with a repository ruleset that requires pull
requests and the `PR delivery gate` status check, but zero formal approvals.
The repository owner cannot approve their own application PR, so the human
decision is the manual Merge or Close action after all checks pass.

Protect `ultimate-iac/main` with pull requests. Production paths remain owned
by `@EmrhT`; require code-owner review, dismiss stale approvals, require
approval of the most recent push, and keep the final merge manual.

## Security and connectivity

The runner has no Kubernetes credentials. SonarQube is reached through its
Cloudflare mTLS-protected CI hostname. Trivy, ZAP, and Argo CD are reached
through Cloudflare Access. Argo CD is the only component that writes to
Kubernetes.

- SonarQube must complete and pass its quality gate.
- Trivy must complete, but vulnerability findings remain non-blocking while
  `TRIVY_ENFORCE=false`.
- ZAP fails on plan errors or High-risk alerts.
- Trivy JSON and ZAP XML reports are reimported into the stable DefectDojo
  engagement through `ci-dojo.no-name.win`. DefectDojo ingestion is enforced:
  a delivery cannot pass when either report is not accepted.
- Trivy, ZAP, and immutable promotion metadata artifacts are retained in the
  application workflow run.

ZAP uses a clean volatile session for every CI scan. Do not run a manual scan
in the shared ZAP instance while application PR delivery is in its DAST job.
