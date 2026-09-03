# MonadSentry

On-chain front desk for an autonomous smart-contract audit agent, wired directly into the
**canonical ERC-8004 registries on Monad mainnet** (chain 143).

Built for Monad Metropolis, track 04 (Trust, Identity & AI Infrastructure).

## What it does

MonadSentry gives an AI audit agent a verifiable on-chain identity and a reputation-gated
price book, so clients can check who they are hiring and what that agent's track record is
before paying for a report.

The lifecycle, all anchored on-chain:

1. `registerAgent(agentURI)` — mints the agent's ERC-8004 identity NFT on the canonical
   Identity Registry. The registry `safeMint`s the NFT to this contract, so MonadSentry
   itself holds the identity and is the default agent wallet.
2. `setPriceTier(tierId, price, minFeedbackCount)` — operator publishes tiers. Each tier
   carries a minimum reputation requirement.
3. `requestAudit(agentId, targetHash, targetURI, tierId)` — a client opens an audit. The
   call reverts with `ReputationTooLow` if the agent has not earned enough feedback on the
   canonical Reputation Registry for that tier.
4. `deliverAudit(auditId, reportHash, reportURI)` — the agent posts the report reference.
   `reportHash` lets anyone verify the delivered artifact.
5. `attestReport(auditId, feedbackValue)` — the client closes the audit record.
6. Client writes the reputation entry themselves on the canonical Reputation Registry,
   using the uniform tags from `feedbackParams(auditId)`.

## Canonical registries (Monad mainnet, chain 143)

| Registry   | Address                                      |
| ---------- | -------------------------------------------- |
| Identity   | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Reputation | `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63` |

Both are ERC-1967 proxies (implementation version `2.0.0`). They are **not** deployed on
Monad testnet (chain 10143) — testnet returns empty code at both addresses.

## Integration notes learned the hard way

These are the non-obvious constraints the canonical registries impose. All of them are
covered by the fork tests.

**`evm_version` must be `cancun`.** The registry proxies' runtime bytecode uses `PUSH0`.
Compiling MonadSentry with `paris` makes every proxy call revert with no error data.

**A contract that registers an agent must implement `IERC721Receiver`.** `register()` calls
`_safeMint(msg.sender, agentId)`, so a plain contract gets rejected with
`ERC721InvalidReceiver`.

**`register()` auto-sets `agentWallet` to `msg.sender`.** There is no wallet argument. The
registering contract becomes the agent wallet by default.

**`setAgentWallet` needs a signature from the new wallet.** The real signature is
`setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes signature)`,
where `signature` is EIP-712 (`AgentWalletSet(uint256 agentId,address newWallet,address
owner,uint256 deadline)`, domain `ERC8004IdentityRegistry` v`1`) or ERC-1271, produced by
`newWallet`, with `deadline` at most 5 minutes out.

**A contract cannot write feedback for an agent it holds.** `giveFeedback()` rejects any
caller for which `isAuthorizedOrOwner(msg.sender, agentId)` is true. Since MonadSentry holds
the agent NFT, it can never call `giveFeedback` on its own agent. The client must call the
registry directly; `feedbackParams()` exists so every MonadSentry feedback entry still
carries identical `tag1`/`tag2`/`endpoint`.

**NFT transfer clears `agentWallet`.** The registry's `_update` override wipes the wallet
metadata on transfer so a verified wallet never carries over to a new holder.

## Test

Unit tests run against a mock and need no network:

```shell
forge test
```

The fork suite exercises the live mainnet registries. It self-skips when run without a fork
URL (the registries have no code locally), so CI stays green:

```shell
forge test --fork-url https://rpc.monad.xyz
```

Expected: 13 passing (4 unit, 9 fork).

## Deploy

```shell
PRIVATE_KEY=0x... forge script script/Deploy.s.sol \
  --rpc-url https://rpc.monad.xyz --broadcast
```

## Layout

```
src/MonadSentry.sol              audit lifecycle + reputation-gated pricing
src/interfaces/                  canonical ERC-8004 registry interfaces
test/MonadSentry.t.sol           unit tests against a mock registry
test/Fork.t.sol                  end-to-end against live mainnet registries
script/Deploy.s.sol              deployment
```
