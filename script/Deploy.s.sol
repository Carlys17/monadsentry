// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MonadSentry} from "../src/MonadSentry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";

/// @notice Deploy MonadSentry against the canonical ERC-8004 registries on Monad mainnet,
///         register the agent identity, and publish the price book in one broadcast.
/// @dev Monad mainnet (chain 143):
///      Identity Registry   = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
///      Reputation Registry = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63
///      Both are ERC-1967 proxies (impl v2.0.0). They are NOT deployed on Monad
///      testnet (chain 10143) - both addresses return empty code there, so this
///      script is mainnet-only. Requires evm_version = "cancun" (proxies use PUSH0).
///
///      register() safeMints the agent NFT to the MonadSentry contract, so the
///      contract itself becomes the agent wallet. The broadcasting EOA stays
///      `owner` and is the operator that can deliver reports.
contract Deploy is Script {
    // Mainnet canonical pair
    address constant IDENTITY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    /// @dev Served from this repo's app/ directory.
    string constant AGENT_CARD = "https://carly17.my.id/monadsentry/agent-card.json";

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        require(IDENTITY.code.length > 0, "identity registry not deployed on this chain");
        require(REPUTATION.code.length > 0, "reputation registry not deployed on this chain");

        vm.startBroadcast(pk);

        MonadSentry ms = new MonadSentry(IDENTITY, REPUTATION);
        console.log("MonadSentry deployed at:", address(ms));

        // Mint the ERC-8004 identity. The NFT lands on the contract itself.
        uint256 agentId = ms.registerAgent(AGENT_CARD);
        console.log("agentId:", agentId);
        console.log("agent wallet:", IIdentityRegistry(IDENTITY).getAgentWallet(agentId));

        // Price book: tier 0 is the cold start, tier 1 needs a real track record.
        ms.setPriceTier(0, 0.5 ether, 0);
        ms.setPriceTier(1, 2 ether, 3);
        console.log("tiers published:", ms.tierCount());

        vm.stopBroadcast();

        console.log("---");
        console.log("Write these into app/index.html (SENTRY, AGENT_ID) and app/agent-card.json registrations[].");
    }
}
