# CLP Local Pledge Law v1

Status: LOCKED

## Purpose

CLP Local Pledge Law v1 defines the minimum standalone append-only local ledger behavior for Claim Protocol.

This law turns CLP from a pure object/verifier engine into a standalone instrument that can:

- accept a valid claim object
- derive ClaimId deterministically
- append a pledge entry to a local append-only ledger
- preserve ledger continuity using entry hashes
- verify the ledger deterministically without mutation

## Ledger location

Canonical ledger path:

`proofs/local_pledge/claims.ndjson`

The ledger is append-only NDJSON.

Each line is exactly one canonical JSON object encoded as:

- UTF-8
- no BOM
- LF line endings

## Entry schema

Each pledge entry is a canonical JSON object with fields:

- `schema`
- `event_type`
- `actor`
- `claim_id`
- `object_sha256`
- `previous_entry_hash`
- `timestamp`
- `entry_hash`

## Identity layers

CLP Local Pledge Law uses three independent deterministic identities:

### 1. Claim identity

`ClaimId = SHA-256(canonical_bytes(claim_without_signature))`

This is the identity of the claim object.

### 2. Object bytes hash

`object_sha256 = SHA-256(exact_file_bytes(object.json))`

This binds the ledger entry to the exact on-disk bytes of the pledged object.

### 3. Ledger continuity hash

`entry_hash = SHA-256(canonical_bytes(entry_without_entry_hash))`

This binds the ledger chain.

## First entry rule

For the first ledger entry:

`previous_entry_hash = ""`

Empty string is canonical for genesis.

## Subsequent entry rule

For every later entry:

`previous_entry_hash` MUST equal the `entry_hash` of the immediately previous ledger line.

## Canonical event type

For this law version the event type is:

`clp.local_pledge.append.v1`

## Non-mutation rule

Verification MUST NOT mutate the ledger.

Verification only reads:

- ledger bytes
- ledger lines
- canonical entry hashes
- continuity relations

Repairs are new entries or new artifacts, never silent rewrites.

## Verification rules

A ledger is valid if:

- each line is valid JSON object
- each line has required fields
- each `schema` equals `clp.pledge.entry.v1`
- each `event_type` equals `clp.local_pledge.append.v1`
- each `claim_id` is non-empty string
- each `object_sha256` is non-empty lowercase hex string
- first entry has empty `previous_entry_hash`
- later entries point to prior `entry_hash`
- each `entry_hash` equals SHA-256(canonical_bytes(entry_without_entry_hash))

## Stable fail tokens

Implementations MUST use stable deterministic fail reasons, including:

- `LEDGER_EMPTY`
- `INVALID_LEDGER_LINE`
- `INVALID_ENTRY_SCHEMA`
- `MISSING_REQUIRED_FIELD`
- `INVALID_FIELD_TYPE`
- `PREVIOUS_ENTRY_HASH_MISMATCH`
- `ENTRY_HASH_MISMATCH`
- `CLAIM_ID_MISMATCH`

## Stable pass tokens

Implementations MUST use stable deterministic pass tokens:

- `LOCAL_PLEDGE_APPEND_OK`
- `LOCAL_PLEDGE_VERIFY_OK`
- `LOCAL_PLEDGE_VECTOR_OK`

## Definition of done for this slice

CLP Local Pledge Law v1 is complete when:

- a claim can be appended deterministically to the canonical ledger
- a second claim links correctly to the first
- the ledger verifies deterministically
- negative vectors fail with stable reason tokens
- selftest can include this law without mutation