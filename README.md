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

## Live on Monad mainnet (chain 143)

| | |
| ---------------- | -------------------------------------------- |
| MonadSentry      | `0x30059c82c2a252Bd27b6bAD56fC7B7ce995afc5C` |
| ERC-8004 agentId | `10245` |
| Agent wallet     | the contract itself (registry auto-set on `register()`) |
| Operator (owner) | `0xBae72FdEF2fC7F66Ef626c5c18e09BC11d78D977` |
| Agent card       | https://carly17.my.id/monadsentry/agent-card.json |
| Frontend         | https://carly17.my.id/monadsentry/ |

Deploy transactions:

| Step | Tx |
| ---- | -- |
| deploy | `0x1ed00ad7b8e2c8f394940b211ac5fc9a486b012b6401587bf788af794697fb87` |
| `registerAgent` | `0x7fcd98ca19ba3c668b530b8b6a26acee846f3a2f244a55e0c50ea9fe52abf62a` |
| `setPriceTier(0, 0.5 MON, 0)` | `0x7c1a98858915582ce68d26adb082d8b7fbc48e0c646d0d77873f11a54c3104a4` |
| `setPriceTier(1, 2 MON, 3)` | `0x56e4988ea7833478111285e6256eea9e1d16d805dfee34157c10da4257cc71ea` |

Verify the live state without a wallet:

```shell
cast call 0x30059c82c2a252Bd27b6bAD56fC7B7ce995afc5C "tierCount()(uint256)" --rpc-url https://rpc.monad.xyz
cast call 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 "getAgentWallet(uint256)(address)" 10245 --rpc-url https://rpc.monad.xyz
```

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
