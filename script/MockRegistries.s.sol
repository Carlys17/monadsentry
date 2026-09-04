// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/// @notice Deploy minimal mock ERC-8004 registries to testnet so MonadSentry
///         can be deployed there for demo purposes. The real registries
///         (0x8004A169... / 0x8004BAa...) only exist on mainnet (chain 143).
///         This script is for testnet (chain 10143) only.
contract MockRegistries is Script {
    // ---------------------------------------------------------------------------
    // Minimal IdentityRegistry mock (register + getAgentWallet only)
    // ---------------------------------------------------------------------------
    contract MockIdentityRegistry {
        uint256 private _agentCount;
        mapping(uint256 => address) private _wallets;
        mapping(uint256 => string)  private _metas;

        event AgentRegistered(uint256 indexed agentId, address indexed wallet, string uri);

        function register(string calldata /*agentURI*/) external returns (uint256 agentId) {
            _agentCount++;
            agentId = _agentCount;
            _wallets[agentId] = msg.sender;
            emit AgentRegistered(agentId, msg.sender, "");
        }

        function getAgentWallet(uint256 agentId) external view returns (address) {
            return _wallets[agentId];
        }

        function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool) {
            return spender == _wallets[agentId];
        }

        // ERC-165
        function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
            return interfaceId == 0x01ffc9a7; // IERC165
        }
    }

    // ---------------------------------------------------------------------------
    // Minimal ReputationRegistry mock
    // ---------------------------------------------------------------------------
    contract MockReputationRegistry {
        address public identityRegistry;
        uint256 private _dummy;

        constructor(address idReg) { identityRegistry = idReg; }

        function getIdentityRegistry() external view returns (address) { return identityRegistry; }
        function getClients(uint256 /*agentId*/) external pure returns (address[] memory) {
            address[] memory a = new address[](0);
            return a;
        }
        function getLastIndex(uint256 /*agentId*/, address /*client*/) external pure returns (uint64) { return 0; }
        function giveFeedback(
            uint256, int128, uint8,
            string calldata, string calldata, string calldata,
            string calldata, bytes32
        ) external pure {}
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        MockIdentityRegistry idReg  = new MockIdentityRegistry();
        MockReputationRegistry repReg = new MockReputationRegistry(address(idReg));

        console.log("MockIdentityRegistry:", address(idReg));
        console.log("MockReputationRegistry:", address(repReg));

        vm.stopBroadcast();

        console.log("---");
        console.log("To deploy MonadSentry on testnet:");
        console.log("PRIVATE_KEY=... forge script script/Deploy.s.sol \\");
        console.log("  --rpc-url https://testnet-rpc.monad.xyz \\");
        console.log("  -g 999 \\");
        console.log("  --sig 'deploy(address,address)' \\");
        console.log(string.concat(address(idReg), " ", address(repReg)));
    }
}
