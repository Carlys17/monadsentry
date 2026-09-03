// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReputationRegistry {
    /// @notice Give feedback for an agent after a completed interaction
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Read a single feedback entry
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);

    /// @notice Get summary stats for an agent across a list of clients filtered by tags
    function getSummary(uint256 agentId, address[] calldata clientAddresses, string calldata tag1, string calldata tag2)
        external
        view
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);

    /// @notice Get the last feedback index for a client-agent pair
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);

    /// @notice Get all clients that left feedback for an agent
    function getClients(uint256 agentId) external view returns (address[] memory);

    /// @notice Append a response to a feedback entry (agent rebuttal)
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;

    /// @notice Revoke own feedback (soft delete, still readable)
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;

    /// @notice Chain identity registry address
    function getIdentityRegistry() external view returns (address);
}
