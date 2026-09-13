# Reserved-payment order workflow

This document is the shared contract for the manual-first $19 order workflow. It is intentionally explicit so the Rails and React implementations can be developed independently.

## Product invariant

- The customer uploads one to three source photographs and creates an order.
- The customer then authorizes a $19 USD card hold through Stripe Checkout. The application does not capture the money yet.
- Only an operator can accept the order. Acceptance captures the existing PaymentIntent exactly once and queues premium generation.
- Declining an order cancels the uncaptured PaymentIntent and releases the hold.
- Astra generation runs only after a verified capture and behind server-side enablement and spend/concurrency limits.
- Generated output remains private while an operator reviews it. The customer receives the interactive preview and `.rbxlx` only after approval.
- A result download is never exposed unless payment is captured, the order is approved, and a result file exists.

## Order states

| State | Meaning | Customer-visible action |
| --- | --- | --- |
| `payment_pending` | Order exists but no usable card authorization has been confirmed. | Authorize $19 hold |
| `submitted` | Stripe confirmed an uncaptured authorization; the order waits for an operator. | Wait or cancel request |
| `accepted` | Operator accepted and capture has been requested. | Wait |
| `building` | Payment is captured and premium generation is running or queued. | Wait |
| `reviewing` | Generated SceneIR/`.rbxlx` exists and awaits operator QA. | Wait |
| `preview_ready` | Optional customer preview stage; output is approved but final release is not marked complete. | Explore preview |
| `ready` | Approved paid result is available. | Preview and download |
| `delivered` | Customer delivery is complete. | Preview and download |
| `declined` | Operator declined before capture and released the hold. | Create a new order |
| `cancelled` | Customer/operator cancelled before fulfillment. | Create a new order |
| `failed` | Payment or generation needs operator attention. | Contact support / wait |

## Payment states

`unpaid -> authorization_pending -> authorized -> capture_pending -> paid`

Terminal/exception paths: `released`, `refund_pending`, `refunded`, `failed`.

The database stores the Stripe Checkout Session ID and PaymentIntent ID, authorization/capture/release timestamps, and a unique record for every processed Stripe event. Webhook processing and operator actions use row locks plus Stripe idempotency keys.

## HTTP API

All customer and operator mutations require the existing session and CSRF token.

### Customer

- `POST /api/v1/orders`
  - Creates `payment_pending` / `unpaid` order and stores private source photographs.
- `POST /api/v1/orders/:public_id/authorize_payment`
  - Creates or safely reuses Stripe Checkout with `payment_intent_data.capture_method=manual`.
  - Returns `{ order, checkout_url }`.
- `POST /api/v1/orders/:public_id/cancel`
  - Allowed before capture. Cancels/release an authorization when present.
  - Returns `{ order }`.
- `GET /api/v1/orders` and `GET /api/v1/orders/:public_id`
  - Return the serialized state and progress fields.

### Operator

- `POST /api/v1/admin/orders/:public_id/accept`
  - Requires `submitted` + `authorized`.
  - Captures the PaymentIntent once; queues generation after capture is confirmed.
  - Returns `{ order }`.
- `POST /api/v1/admin/orders/:public_id/decline`
  - Requires uncaptured payment. Cancels the PaymentIntent and marks `declined` / `released`.
  - Returns `{ order }`.
- `POST /api/v1/admin/orders/:public_id/approve`
  - Requires `reviewing` + `paid` + attached `.rbxlx` + preview SceneIR.
  - Marks the order `ready` and sends the existing customer notification/email.
- `PATCH /api/v1/admin/orders/:public_id`
  - Keeps notes and replacement artifact upload. Direct state changes must still satisfy model transition rules.

### Stripe

- `POST /api/v1/payments/stripe/webhook`
  - Handles Checkout completion, capturable authorization, successful capture, failure/cancellation, and refund events.
  - Validates order ID, amount, currency, Checkout Session/PaymentIntent identity, and deduplicates by Stripe event ID.

## Serialized fields

In addition to existing order fields:

- `authorization_expires_at`
- `authorized_at`
- `capture_requested_at`
- `released_at`
- `generation_started_at`
- `generation_finished_at`
- `generation_attempts`
- `generation_metrics` (admin always; customer only after approval)
- `generation_error` (admin only)
- booleans `can_authorize`, `can_cancel`, `can_accept`, `can_decline`, `can_approve`, `can_download`

## Generation boundary

`GenerateOrderJob` is the only production entry point for automatic fulfillment. It:

1. Locks and verifies `paid` + `building` before spending money.
2. Refuses to run unless `ASTRA_ORDER_AUTOMATION_ENABLED=true`, `ASTRA_QUALITY_ENABLED=true`, and an API key is present.
3. Enforces one active premium generation by default and a configurable daily cost ceiling.
4. Runs `Vision::SceneAnalyzer.for_quality("astra_max")`, normalization, validation, compilation, and export using the first source photo and the order brief.
5. Stores SceneIR, `.rbxlx`, actual metrics/cost, timing, and attempt count.
6. Ends in `reviewing`; it never publishes directly to the customer.
7. Ends in `failed` with a private error on configuration/API/build failure and never retries blindly after an expensive attempt.

Required environment controls:

- `ASTRA_ORDER_AUTOMATION_ENABLED=false`
- `ASTRA_ORDER_MAX_CONCURRENT=1`
- `ASTRA_ORDER_DAILY_SPEND_LIMIT_USD=30`

Tests must stub Stripe/OpenAI and must not make network calls or spend money.
