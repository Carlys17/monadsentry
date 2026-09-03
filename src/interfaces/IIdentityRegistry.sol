// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIdentityRegistry {
    /// @notice Returns true if `spender` owns or is authorized for agentId
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);

    /// @notice Mint a new agent identity, returns the new agentId (tokenId).
    /// @dev    Canonical registry auto-sets agentWallet to msg.sender.
    function register(string memory agentURI) external returns (uint256 agentId);

    /// @notice Update the agent card URI
    function setAgentURI(uint256 agentId, string calldata newURI) external;

    /// @notice Set the agent's wallet (requires EIP-712 or ERC-1271 proof
    ///         signed BY the new wallet, within a <=5 minute deadline window)
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    /// @notice Get the agent's authorized wallet address
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Clear the agent's wallet
    function unsetAgentWallet(uint256 agentId) external;

    /// @notice Get metadata field for an agent
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);

    /// @notice Set a metadata field for an agent
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external;
}
