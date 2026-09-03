// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MonadSentry} from "../src/MonadSentry.sol";

/// @notice Deploy MonadSentry against the canonical ERC-8004 registries on Monad mainnet
/// @dev Monad mainnet (chain 143):
///      Identity Registry   = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
///      Reputation Registry = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63
///      Both are ERC-1967 proxies (impl v2.0.0). They are NOT deployed on Monad
///      testnet (chain 10143) - both addresses return empty code there, so this
///      script is mainnet-only. Requires evm_version = "cancun" (proxies use PUSH0).
contract Deploy is Script {
    // Mainnet canonical pair
    address constant IDENTITY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        require(IDENTITY.code.length > 0, "identity registry not deployed on this chain");
        require(REPUTATION.code.length > 0, "reputation registry not deployed on this chain");

        vm.startBroadcast(pk);
        MonadSentry ms = new MonadSentry(IDENTITY, REPUTATION);
        console.log("MonadSentry deployed at:", address(ms));
        vm.stopBroadcast();
    }
}
