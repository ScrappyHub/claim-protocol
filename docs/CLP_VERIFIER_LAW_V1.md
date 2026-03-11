# Claim Protocol (CLP) Verifier Law v1

## Status

DRAFT FOR LOCK

This document defines the canonical verifier behavior for Claim Protocol (CLP) v1.

It extends:

- the sealed CLP identity core
- CLP Object Law v1
- CLP Media / Storage Law v1

It defines what a CLP verifier must check, what outputs it must produce, and what it must never mutate.

---

# 0. Purpose

A protocol is not a standalone instrument until it can verify its own objects deterministically.

This law defines:

- verifier obligations
- verifier output shape
- verifier failure tokens
- object-law and payload-law verification behavior
- non-mutation requirements

Until this law is locked, CLP can describe and hash objects, but it cannot yet claim a complete canonical verification surface.

---

# 1. Verifier Scope

CLP v1 verification in this law covers:

- top-level JSON object requirement
- schema recognition
- object-law required fields
- object-law field types
- payload-law required fields
- payload-law field types
- reference-form metadata validation

This law does not yet require:

- external blob retrieval
- packet verification
- signature verification
- trust policy resolution
- entitlement enforcement

Those remain adjacent or later-layer concerns unless explicitly added by later laws.

---

# 2. Non-Mutation Law

A CLP verifier MUST NOT:

- rewrite object fields
- reorder source files on disk
- normalize strings
- fill in missing fields
- auto-repair invalid objects
- overwrite source artifacts
- mutate packets or blobs

A verifier may only:

- read
- classify
- emit deterministic result objects
- emit deterministic logs or receipts

Repairs must always be expressed as new claims, receipts, or later-layer remediation artifacts.

---

# 3. Canonical Verifier Outcomes

Verifier outcomes are binary at the object level:

- `ok = true`
- `ok = false`

But verifier explanation is structured.

A verifier result MUST include:

- `schema`
- `ok`
- `object_schema`
- `reason_token`

Optional detail fields may be included if deterministic.

---

# 4. Canonical Reason Tokens

CLP v1 freezes the following reason-token classes.

## 4.1 Success token

- `OK`

## 4.2 Parse / shape tokens

- `INVALID_JSON`
- `INVALID_TOP_LEVEL_TYPE`

## 4.3 Schema tokens

- `MISSING_REQUIRED_FIELD:schema`
- `INVALID_FIELD_TYPE:schema`
- `INVALID_SCHEMA:<value>`
- `UNSUPPORTED_SCHEMA:<value>`

## 4.4 Object-law field tokens

- `MISSING_REQUIRED_FIELD:<field>`
- `INVALID_FIELD_TYPE:<field>`

## 4.5 Payload-law tokens

- `INVALID_PAYLOAD_MODE`
- `INVALID_DIGEST_FORMAT`

## 4.6 Implementation rule

A verifier MAY add deterministic suffix detail fields in later laws, but the canonical base token must remain stable.

---

# 5. Verification Surface by Schema

## 5.1 `clp.claim.v1`

A verifier MUST check:

- top-level is object
- `schema` exists and equals `clp.claim.v1`
- `claim_type` exists and is string
- `producer` exists and is string
- `timestamp` exists and is string
- `payload` exists and is object
- payload conforms to a canonical payload mode

## 5.2 `clp.receipt.v1`

A verifier MUST check:

- top-level is object
- `schema` exists and equals `clp.receipt.v1`
- `receipt_type` exists and is string
- `for_claim` exists and is string
- `result` exists and is object
- `timestamp` exists and is string

## 5.3 `clp.decision.v1`

A verifier MUST check:

- top-level is object
- `schema` exists and equals `clp.decision.v1`
- `decision_type` exists and is string
- `inputs` exists and is array
- `result` exists and is object
- `producer` exists and is string
- `timestamp` exists and is string
- `payload` exists and is object
- payload conforms to a canonical payload mode

---

# 6. Payload Verification Surface

## 6.1 `inline_json`

Verifier MUST check:

- `mode` exists and equals `inline_json`
- `value` exists
- `value` is object or array

## 6.2 `inline_text`

Verifier MUST check:

- `mode` exists and equals `inline_text`
- `media_type` exists and is string
- `text` exists and is string

## 6.3 `blob_ref`

Verifier MUST check:

- `mode` exists and equals `blob_ref`
- `media_type` exists and is string
- `digest` exists and is string
- `digest` begins with `sha256:`
- `length` exists and is numeric
- `filename`, if present, is string

This law validates only metadata shape, not external blob presence.

## 6.4 `packet_ref`

Verifier MUST check:

- `mode` exists and equals `packet_ref`
- `packet_id` exists and is string
- `manifest_digest`, if present, is string
- `path`, if present, is string

This law validates only reference metadata shape, not packet existence or packet integrity.

---

# 7. Unsupported Schema Behavior

If a JSON object has a `schema` field but the value is not one of:

- `clp.claim.v1`
- `clp.receipt.v1`
- `clp.decision.v1`

the verifier MUST fail deterministically.

If the schema value resembles a CLP object family but is not supported, use:

- `UNSUPPORTED_SCHEMA:<value>`

If the schema value is structurally invalid for the expected law surface, use:

- `INVALID_SCHEMA:<value>`

For CLP v1 implementation simplicity, unsupported non-canonical schemas may be classified using `UNSUPPORTED_SCHEMA:<value>`.

---

# 8. Verify Result Object

A canonical CLP verifier result object MUST use:

- `schema = "clp.verify.result.v1"`

Required fields:

- `schema`
- `ok`
- `object_schema`
- `reason_token`

Optional fields:

- `object_id`
- `payload_mode`
- `verified_at`
- `meta`

## Field meaning

### `ok`
Boolean verification result.

### `object_schema`
Recognized object schema if available, else empty string.

### `reason_token`
Stable deterministic token from this law.

### `object_id`
Optional derived object identity if known and meaningful for the verifier stage.

### `payload_mode`
Optional recognized payload mode for claim/decision objects.

### `verified_at`
Optional timestamp string if emitted by a higher-level runner.
Base CLP law does not require timestamps inside minimal deterministic vector verification.

---

# 9. Canonical Truth Statement

A CLP verifier classifies canonical CLP objects without mutating them.

Verification success means:

- object-law checks passed
- payload-law checks passed for applicable object families

Verification success does not yet imply:

- signature trust
- external blob existence
- packet integrity
- policy authorization
- entitlement approval

Those are separate surfaces.

---

# 10. Definition of Done for Verifier Law Lock

This verifier law is ready to lock when:

- this document is frozen
- verify result schema matches this document
- deterministic verifier script exists
- positive verifier vectors pass
- negative verifier vectors fail with stable reason tokens
- verifier runner passes deterministically
- no source mutation occurs during verification

Until then, this law remains DRAFT FOR LOCK.
