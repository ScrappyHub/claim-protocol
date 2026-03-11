## Status

**Negative Tier (-1) sealed identity core**

Claim Protocol currently has a sealed deterministic substrate for:

- canonical claim identity
- canonical receipt identity
- frozen minimal vectors
- deterministic selftest
- double-run determinism proof

## What Is Sealed

- `_lib_clp_v1.ps1`
- `clp_hash_claim_v1.ps1`
- `clp_hash_receipt_v1.ps1`
- `clp_run_test_vectors_v1.ps1`
- `_selftest_clp_v1.ps1`
- `_RUN_clp_freeze_tier0_v1.ps1`

## Frozen Outputs

- `claim_id = 52a2b139dcf0b0f44bec850dcd121d3be3092988a50a15e112c06f51b78b84fd`
- `receipt_id = ee1ec699389f6fae72c032cbb7086c0c962cb4f050e515a48461a0b95f7b10c8`
- `root_hash = c756bfa7fd323246659229a11563550f7691360c84e72d52f8bbd9e7071c4b28`

## What Is Not Yet Locked

The following are not yet frozen:

- object law
- media / storage law
- verifier law
- licensing / entitlement boundary
- expanded conformance vectors

## Tier Meaning

Negative Tier (-1) means the substrate works and is canonically proven.

It does not yet mean CLP is a full standalone instrument.

Tier-0 is only earned once CLP can stand alone end-to-end as its own complete instrument surface.
