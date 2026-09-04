// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MonadSentry} from "../src/MonadSentry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";

/// @notice Simulates deployment against live mainnet registries WITHOUT broadcasting.
///         Run: forge script script/SimulateDeploy.s.sol --fork-url https://rpc.monad.xyz -vv
///
///         The contract address is deterministic (CREATE2 / address from deployer + nonce),
///         so the address printed here is the exact one you'll get on mainnet once the
///         deployer key has enough MON to pay gas.
///
///         After getting the address, set SENTRY and AGENT_ID in app/index.html
///         and update app/agent-card.json registrations[].
contract SimulateDeploy is Script {
    address constant IDENTITY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;
    string constant AGENT_CARD = "https://carly17.my.id/monadsentry/agent-card.json";

    function run() external {
        require(IDENTITY.code.length > 0, "not on a mainnet fork");
        require(REPUTATION.code.length > 0, "not on a mainnet fork");

        // Simulate from the deployer key without broadcasting
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        MonadSentry ms = new MonadSentry(IDENTITY, REPUTATION);
        console.log("MonadSentry address:", address(ms));

        uint256 agentId = ms.registerAgent(AGENT_CARD);
        console.log("agentId:", agentId);
        console.log("agent wallet:", IIdentityRegistry(IDENTITY).getAgentWallet(agentId));

        ms.setPriceTier(0, 0.5 ether, 0);
        ms.setPriceTier(1, 2 ether, 3);
        console.log("tierCount:", ms.tierCount());

        vm.stopBroadcast();

        console.log("---");
        console.log("SENTRY = replace with above address");
        console.log("AGENT_ID = replace with above agentId");
    }
}
