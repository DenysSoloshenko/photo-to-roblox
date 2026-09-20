# SceneFoundry: remaining launch steps

Updated 2026-09-20. Scope: finish a small, manual-first paid MVP; automated AI generation is a separate milestone. The case study and web deployment are demonstration milestones, not proof that paid production is ready.

The September 16 review is historical: its commits reached the remote release branch, and GitHub has recorded a successful Render deployment at `1b2cf42`. The new case release must likewise be verified against its own deployment SHA. Release branch: `deploy/render-free`; app: https://scenefoundry-roblox.onrender.com.

## 1. Approve the offer and budget — owner: Denys

Keep the first release manual: 1–3 owned/licensed photos, one small location, an editable `.rbxlx`, clearly stated inclusions, exclusions and revision policy. Decide when the 24-hour target begins. Current code sets `delivery_due_at` from submission, not operator acceptance; resolve this mismatch before promising an acceptance-based SLA. District-size requests need separate scope/pricing. Approve a budget for durable hosting, database, storage and mail; do not enable live payments yet.

Done when: the customer page, terms, operator process and due-date code say the same thing.

## 2. Make files and data survive a restart — owner: developer + Denys for accounts/budget

The checked-in Render preview uses local Active Storage. Move private uploads/results to a private S3-compatible bucket, migrate existing blobs, and use a durable database with backups. Restore a backup to a separate environment. Confirm source photos and final maps still download after a redeploy and another customer's account cannot read them. Update runtime versions consistently in CI and hosting after testing.

Done when: a staged order survives deploy, database restore and worker restart, with no public bucket access.

## 3. Finish account access and reliable notifications — owner: developer

Verify Google OAuth and email reset on the actual domain; confirm only verified admin identities enter the operator queue. Configure a real mail provider and domain authentication. Add persistent jobs/outbox delivery and retries so a restart cannot lose ready/reset emails. Test delivery to an external inbox, including a failed-send retry, without duplicate notifications.

Done when: a new customer can sign in/recover access and receive a real delivery notification; an unverified admin-email registration has no admin powers.

## 4. Complete the Stripe test matrix — owner: developer; Denys approves live credentials later

In test mode run authorize → accept/capture → fulfill; decline/release; cancel before capture; expiration; failure/retry; duplicate and out-of-order webhooks; and refund. The current fallback uses a fixed six-day authorization expiry; use the provider's actual capture deadline and reconciliation before live launch. Keep capture idempotent and download access consistent with the chosen refund policy.

Done when: each path has API tests plus staging evidence, and no path duplicates a charge or delivers unpaid work.

## 5. Establish the Roblox acceptance checklist — owner: operator/Denys + developer

Open the new Springer Park file and at least one photo-derived result in Roblox Studio. Run Play, test spawn, collision, boundaries, stairs, scale and low-end/mobile performance; verify no unwanted scripts or external assets. Preserve OSM attribution for the open-data example. Fix issues and export a private test experience. Do not call the browser rendering a Roblox Studio test.

Done when: each deliverable has recorded Studio QA and a playable result; geography-derived and customer-photo rights are documented.

## 6. Close operational and customer-policy gaps — owner: developer + Denys

Set upload/account/request rate limits, capacity and payment alerts, error monitoring, failed-job visibility, operator audit logs and a rollback procedure. Review terms, privacy, refund/revision policy and image-rights wording; set file-retention/deletion rules. Keep private photos, payment data and tokens out of public logs and demos. Do not advertise a commercially cleared Google-derived district.

Done when: a deliberate failed order is visible, recoverable and explainable to the customer.

## 7. Run one complete staging order, then a limited pilot — owner: both

Use two separate accounts. Create request → authorize in Stripe test mode → operator accepts → build/upload → Studio QA → deliver email → customer preview/download → cancellation/refund checks. Redeploy mid-process. Repeat the critical flow after deployment; record the release SHA, backup/rollback instructions and results. Only then, with explicit approval, enable live payments and accept a small capped pilot (for example 3–5 orders).

Done when: all earlier gates pass and the first small batch can be fulfilled reliably within the agreed scope.

## After the manual MVP

Automated photo → AI → Roblox needs durable generation jobs, saved intermediate artifacts, idempotency, global cost/concurrency limits and a fixed quality benchmark. It is not required to finish the manual MVP and is not proved by the open-data case.
