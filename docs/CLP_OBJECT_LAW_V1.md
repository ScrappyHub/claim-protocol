# Claim Protocol (CLP) Object Law v1

## Status

DRAFT FOR LOCK

This document defines the canonical object surface for Claim Protocol (CLP) v1.

This law extends the sealed CLP identity core and defines what a valid CLP object is.

It does not redefine ClaimId or ReceiptId hashing. It defines the objects those hashes apply to.

---

# 0. Purpose

CLP needs a strict object boundary before it can become a full standalone instrument.

This law defines:

- canonical object families
- required and optional fields
- extension field rules
- invalid object conditions
- object meaning boundaries

Until this law is locked, CLP remains a sealed identity substrate and not a full Tier-0 standalone protocol instrument.

---

# 1. Canonical Object Families

CLP v1 defines exactly three canonical object families:

1. `clp.claim.v1`
2. `clp.receipt.v1`
3. `clp.decision.v1`

No other top-level schema is canonical under this law.

Future object families require a new law version or an explicit additive extension law.

---

# 2. Global Object Rules

All CLP objects MUST satisfy all of the following:

- top-level value MUST be a JSON object
- file encoding on disk MUST be UTF-8 without BOM
- line endings on disk MUST be LF
- object bytes MUST be canonicalized before hashing
- duplicate keys are invalid
- NaN and Infinity are invalid
- object fields are hashed exactly as present after canonical serialization
- verifier behavior is non-mutating

CLP hashes meaningfully structured objects, not arbitrary blobs pretending to be objects.

---

# 3. Canonical Field Rules

## 3.1 `schema`

Every CLP object MUST contain:

- `schema`

The `schema` field MUST be a string and MUST be one of:

- `clp.claim.v1`
- `clp.receipt.v1`
- `clp.decision.v1`

If `schema` is missing or incorrect, the object is invalid.

## 3.2 String fields

All protocol identity-bearing string fields are hashed exactly as emitted.

CLP does not trim, lowercase, normalize Unicode, reinterpret timezones, or rewrite strings before hashing.

## 3.3 Object and array fields

Object and array fields are permitted only where explicitly allowed by the object family rules below.

---

# 4. Claim Object Law

## 4.1 Schema identifier

Claim objects MUST use:

- `schema = "clp.claim.v1"`

## 4.2 Required fields

A valid `clp.claim.v1` object MUST contain:

- `schema`
- `claim_type`
- `producer`
- `timestamp`
- `payload`

## 4.3 Optional fields

A valid `clp.claim.v1` object MAY contain:

- `signature`
- `prev_links`
- `meta`
- `strength`
- `labels`

## 4.4 Field meanings

### `claim_type`
String.
Producer-defined claim kind.
Must be namespaced and versioned.

Example:

- `core.commit.v1`

### `producer`
String.
Stable producer identifier for the emitting system or actor label.

### `timestamp`
String.
Hashed as-is.
CLP does not reinterpret or normalize it.

### `payload`
Object.
Must satisfy the payload law once that law is frozen.
For now, payload MUST exist and MUST be an object.

### `signature`
Optional.
Excluded from ClaimId derivation.

### `prev_links`
Optional.
Array.
Used for lineage or prior references.

### `meta`
Optional.
Object.
Additional structured metadata.

### `strength`
Optional.
Number or string, depending on producer convention.
Hashed as-is if present.

### `labels`
Optional.
Array of strings.

## 4.5 Claim identity law

Claim identity is:

`ClaimId = SHA-256(canonical_bytes(claim_without_signature))`

Only `signature` is excluded by the core law.

All other present fields participate in identity.

---

# 5. Receipt Object Law

## 5.1 Schema identifier

Receipt objects MUST use:

- `schema = "clp.receipt.v1"`

## 5.2 Required fields

A valid `clp.receipt.v1` object MUST contain:

- `schema`
- `receipt_type`
- `for_claim`
- `result`
- `timestamp`

## 5.3 Optional fields

A valid `clp.receipt.v1` object MAY contain:

- `signature`
- `meta`
- `producer`
- `inputs`

## 5.4 Field meanings

### `receipt_type`
String.
Namespaced and versioned receipt kind.

Example:

- `watchtower.verify.receipt.v1`

### `for_claim`
String.
ClaimId referenced by this receipt.

### `result`
Object.
Structured outcome object.
Must be present and must be a JSON object.

### `timestamp`
String.
Hashed as-is.

### `signature`
Optional.
Excluded from ReceiptId derivation.

### `meta`
Optional.
Structured metadata object.

### `producer`
Optional.
Stable identifier of the receipt emitter.

### `inputs`
Optional.
Array or object, depending on receipt design.
Used for structured explanation and proof inputs.

## 5.5 Receipt identity law

Receipt identity is:

`ReceiptId = SHA-256(canonical_bytes(receipt_without_signature))`

Only `signature` is excluded by the core law.

All other present fields participate in identity.

---

# 6. Decision Object Law

## 6.1 Schema identifier

Decision objects MUST use:

- `schema = "clp.decision.v1"`

## 6.2 Required fields

A valid `clp.decision.v1` object MUST contain:

- `schema`
- `decision_type`
- `inputs`
- `result`
- `producer`
- `timestamp`
- `payload`

## 6.3 Optional fields

A valid `clp.decision.v1` object MAY contain:

- `signature`
- `prev_links`
- `meta`
- `strength`
- `labels`
- `policy_ref`

## 6.4 Field meanings

### `decision_type`
String.
Namespaced and versioned decision kind.

### `inputs`
Array.
References to ClaimIds and/or ReceiptIds that informed the decision.

### `result`
Object.
Structured decision result.

### `producer`
String.
Decision-emitting system identifier.

### `timestamp`
String.
Hashed as-is.

### `payload`
Object.
Decision payload object.

### `policy_ref`
Optional string.
Reference to policy basis.

## 6.5 Decision identity law

Decision identity follows claim identity law unless a future law says otherwise.

So for CLP v1:

`DecisionId = SHA-256(canonical_bytes(decision_without_signature))`

DecisionId is computed using the same exclusion rule as ClaimId.

---

# 7. Unknown Field Policy

CLP v1 allows unknown fields only if all of the following are true:

- they do not replace or shadow required canonical fields
- they are valid canonical JSON values
- they are preserved by non-mutating parsing and verification
- they do not claim to redefine schema semantics

Unknown fields are hashed if present.

This means extension fields affect identity.

CLP does not silently drop unknown fields.

---

# 8. Invalid Object Conditions

A CLP object is invalid if any of the following is true:

- top-level value is not an object
- `schema` is missing
- `schema` is not one of the canonical CLP object schemas
- a required field is missing
- a required field has the wrong top-level type
- duplicate keys exist
- canonical serialization fails
- payload is missing where required
- payload exists but is not an object where object form is required
- result is missing where required
- result exists but is not an object where object form is required
- inputs is missing for decisions
- inputs exists but is not an array for decisions

---

# 9. Minimal Type Constraints

These type constraints are mandatory for CLP v1:

## `clp.claim.v1`
- `schema`: string
- `claim_type`: string
- `producer`: string
- `timestamp`: string
- `payload`: object

## `clp.receipt.v1`
- `schema`: string
- `receipt_type`: string
- `for_claim`: string
- `result`: object
- `timestamp`: string

## `clp.decision.v1`
- `schema`: string
- `decision_type`: string
- `inputs`: array
- `result`: object
- `producer`: string
- `timestamp`: string
- `payload`: object

---

# 10. Canonical Truth Statement

This law defines what counts as a canonical CLP object.

Uploading arbitrary JSON is not sufficient.

A JSON artifact becomes a CLP object only if it satisfies this object law and the sealed identity core can canonicalize it deterministically.

---

# 11. Definition of Done for Object Law Lock

This object law is ready to lock when:

- this document is frozen
- schema files match this document exactly
- positive object vectors exist for claim, receipt, and decision
- negative vectors exist for missing fields, wrong schema, wrong top-level type, and wrong required field type
- verifier failure tokens for object-law failures are frozen

Until then, this law remains DRAFT FOR LOCK.
