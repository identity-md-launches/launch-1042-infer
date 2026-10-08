# Infer (INFER)

Infer is a fixed supply ERC-20. Its constructor mints **1,000,000,000 INFER**,
with **18 decimals**, to `msg.sender` exactly once. The supply in minor units is
**1000000000000000000000000000** (`10^27`).

The implementation is `src/Infer.sol:Infer`, using the vendored OpenZeppelin
Contracts v5.0.2 ERC-20 implementation. There are no constructor arguments,
initialization calls, linked libraries, or external service settings.

## Behavior and assumptions

- The immediate deployer receives the entire supply. When a factory uses CREATE
  or CREATE2, the factory receives it; the transaction origin does not.
- Transfers deliver their exact amount. There are no fees, rebases, transfer
  limits, privileged exemptions, or recipient callbacks.
- Supply remains constant after construction. There is no external mint or burn
  function, owner, pause, blacklist, seizure, proxy, or upgrade mechanism.
- Standard `transfer`, `approve`, and `transferFrom` return `true` on success and
  revert with ERC-6093 custom errors on failure. Zero-value transfers and self
  transfers are supported. Transfers to the zero address are rejected.
- Approvals replace the current allowance. Finite allowances decrease when
  spent; `type(uint256).max` is an unlimited allowance and does not decrease.
  Approving a zero spender is rejected. Explicit approvals emit `Approval`;
  `transferFrom` emits `Transfer` without an allowance-update event.

## Build and test

Use Foundry with Solidity **0.8.26**, as pinned in `foundry.toml`. Settings include
the Cancun EVM target, optimization with 200 runs, and `bytecode_hash = "none"`.
The deployment chain must support Cancun. FFI and filesystem cheatcode access
are disabled. With Foundry and the pinned compiler installed, all build and test
dependencies are present in this repository; network access is unnecessary.

```sh
forge build
forge test
forge fmt --check
```

The tests cover metadata and mint events, CREATE2 factory allocation, exact
distribution and claims, transfer and approval events, allowance consumption and
revocation, maximum allowances, zero and self transfers, insufficient balances
and allowances, atomic rollback, zero-address rejection, unsupported privileged
calls, and prohibited runtime opcodes. Five fuzz tests run 512 cases each,
including sequences of 64 transfers checked against an independent balance
model. Tests use a local minimal cheatcode interface and do not read environment
variables, fork a network, access files, or depend on test order.

The supplied protected integration harness depends on the launch system's
factory, Uniswap v4 support contracts, manifest, and environment. Those are not
part of this token project. Local factory and transfer tests validate token
behavior; they do not claim to execute the full protected pool/swap harness.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Contract | `src/Infer.sol:Infer` |
| Constructor arguments | `[]` (empty) |
| Constructor ETH value | `0` (nonpayable) |
| Name / symbol | `Infer` / `INFER` |
| Decimals | `18` |
| Total supply, minor units | `1000000000000000000000000000` |
| Initial recipient | Immediate creator, `msg.sender` |
| Additional application contracts | None |

For a reviewed launch, use the creation bytecode in `out/Infer.sol/Infer.json` or
obtain it with `forge inspect src/Infer.sol:Infer bytecode`. No constructor data
is appended. For CREATE2, the launch operator supplies its factory and salt.
This project requires no chain-specific addresses. The factory is responsible
for subsequent allocation, including distributor funding, liquidity, and the
requester's remainder; the token applies the same exact transfer rules to each.
Launch economics and the launch manifest belong to the launch system.

## After launch

No token configuration or admin handover is required. The operator must confirm
the deployed contract's metadata, supply, initial mint recipient, and bytecode
against the reviewed build, then perform and verify the authorized distribution.
Verify source on the target chain's explorer using the pinned compiler settings.
The deployer controls only the tokens it holds and permissions holders explicitly
grant it. There is no administrator who can recover a mistaken transfer or tokens
sent to the token contract itself.

Holders are responsible for protecting their wallets and checking recipients and
spenders. Prefer bounded approvals; when replacing a live allowance, revoke it
and confirm revocation before granting the replacement to reduce the standard
ERC-20 allowance race. Unlimited allowances authorize spending future balances.

The local security review covers supply accounting, caller/allowance boundaries,
error rollback, and the absence of external calls and privileged entry points.
Foundry tests are not an independent security audit. Slither and Mythril are not
part of this validation. Independent adversarial review and deployment/source
verification remain release responsibilities. No transaction is broadcast and no
wallet key is needed by this project.
