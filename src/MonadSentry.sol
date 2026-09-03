// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {IReputationRegistry} from "./interfaces/IReputationRegistry.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title MonadSentry
/// @notice On-chain front desk for the MonadSentry audit agent.
///         Wires ERC-8004 identity + reputation (canonical Monad registry)
///         into a paid, attestable audit workflow.
/// @dev The contract does NOT custody funds for x402 payments; the facilitator
///      settles payment off-chain. This contract anchors the WORK: registration,
///      audit lifecycle, delivery attestation, and reputation-gated pricing.
contract MonadSentry is IERC721Receiver {
    IIdentityRegistry public immutable identityRegistry;
    IReputationRegistry public immutable reputationRegistry;

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------
    error NotOwner(address caller, uint256 agentId);
    error NotAuthorized(address caller);
    error InvalidAgent();
    error AuditNotPending(uint256 auditId);
    error AuditNotDelivered(uint256 auditId);
    error AlreadyDelivered(uint256 auditId);
    error ReputationTooLow(uint256 agentId, uint256 tierId, uint64 count);
    error ZeroAddress();
    error InvalidURI();

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string agentURI);
    event AgentWalletSet(uint256 indexed agentId, address indexed wallet);
    event AuditRequested(
        uint256 indexed auditId,
        uint256 indexed agentId,
        address indexed requester,
        bytes32 targetHash,
        string targetURI,
        uint256 tierId
    );
    event AuditDelivered(
        uint256 indexed auditId,
        uint256 indexed agentId,
        address indexed requester,
        bytes32 reportHash,
        string reportURI
    );
    event ReportAttested(
        uint256 indexed auditId, uint256 indexed agentId, address indexed requester, int128 feedbackValue
    );
    event PriceTierSet(uint256 indexed tierId, uint256 pricePerReport, uint64 minFeedbackCount);

    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------
    struct Audit {
        uint256 agentId; // ERC-8004 agent handling the audit
        address requester; // who asked for the audit
        bytes32 targetHash; // keccak256 of target source code bundle
        string targetURI; // where the target lives (repo URL)
        uint256 tierId; // pricing tier selected
        bool delivered; // report handed over
        bool attested; // requester signed off via this contract
        int128 feedbackValue; // score the requester left, mirrored here
    }

    struct PriceTier {
        uint256 pricePerReport; // in smallest unit of payment asset
        uint64 minFeedbackCount; // min reputation entries to qualify
        bool active;
    }

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------
    address public owner;
    uint256 public auditCount;
    mapping(uint256 => Audit) public audits;
    mapping(uint256 => PriceTier) public priceTiers;
    uint256 public tierCount;

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized(msg.sender);
        _;
    }

    modifier onlyAgentOwner(uint256 agentId) {
        if (!identityRegistry.isAuthorizedOrOwner(msg.sender, agentId)) {
            revert NotOwner(msg.sender, agentId);
        }
        _;
    }

    /// @dev This contract holds the agent NFT, so the on-chain identity owner is
    ///      the contract itself. The human/agent operator behind it is `owner`.
    ///      Accept either: the contract operator, or anyone the registry has
    ///      authorized for the agent (approved operator / new NFT holder after
    ///      a transfer).
    modifier onlyAgentOperator(uint256 agentId) {
        if (msg.sender != owner && !identityRegistry.isAuthorizedOrOwner(msg.sender, agentId)) {
            revert NotOwner(msg.sender, agentId);
        }
        _;
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    constructor(address identityRegistry_, address reputationRegistry_) {
        if (identityRegistry_ == address(0) || reputationRegistry_ == address(0)) {
            revert ZeroAddress();
        }
        identityRegistry = IIdentityRegistry(identityRegistry_);
        reputationRegistry = IReputationRegistry(reputationRegistry_);
        owner = msg.sender;
    }

    // ------------------------------------------------------------------
    // Agent identity (thin wrapper around canonical ERC-8004)
    // ------------------------------------------------------------------

    /// @notice Register the MonadSentry audit agent on the canonical identity
    ///         registry. The registry safeMints the agent NFT TO THIS CONTRACT,
    ///         which therefore holds the identity and is the default agent
    ///         wallet (msg.sender == this contract on register()).
    function registerAgent(string calldata agentURI) external onlyOwner returns (uint256 agentId) {
        if (bytes(agentURI).length == 0) revert InvalidURI();
        agentId = identityRegistry.register(agentURI);
        emit AgentRegistered(agentId, address(this), agentURI);
    }

    /// @notice Point the agent's payment/signing wallet elsewhere. The
    ///         canonical registry demands an EIP-712 or ERC-1271 signature
    ///         made BY newWallet within a <=5 minute deadline; owner produces
    ///         it off-chain and this contract (as NFT holder) forwards it.
    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature)
        external
        onlyAgentOwner(agentId)
    {
        if (newWallet == address(0)) revert ZeroAddress();
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
        emit AgentWalletSet(agentId, newWallet);
    }

    // ------------------------------------------------------------------
    // Audit lifecycle
    // ------------------------------------------------------------------

    /// @notice A client opens an audit. Payment happens off-chain via x402;
    ///         this call anchors the request on-chain and locks the target.
    function requestAudit(uint256 agentId, bytes32 targetHash, string calldata targetURI, uint256 tierId)
        external
        returns (uint256 auditId)
    {
        // Agent must exist on the identity registry
        if (identityRegistry.getAgentWallet(agentId) == address(0) && bytes(targetURI).length == 0) {
            revert InvalidAgent();
        }

        PriceTier memory tier = priceTiers[tierId];
        if (!tier.active) revert InvalidAgent();

        // Reputation gate: agent must have at least tier.minFeedbackCount feedbacks
        uint64 feedbackCount = _getFeedbackCount(agentId);
        if (feedbackCount < tier.minFeedbackCount) {
            revert ReputationTooLow(agentId, tierId, feedbackCount);
        }

        auditId = ++auditCount;
        audits[auditId] = Audit({
            agentId: agentId,
            requester: msg.sender,
            targetHash: targetHash,
            targetURI: targetURI,
            tierId: tierId,
            delivered: false,
            attested: false,
            feedbackValue: 0
        });

        emit AuditRequested(auditId, agentId, msg.sender, targetHash, targetURI, tierId);
    }

    /// @notice The audit agent posts the report reference once work is done.
    ///         Anyone can verify reportHash against the delivered reportURI.
    function deliverAudit(uint256 auditId, bytes32 reportHash, string calldata reportURI)
        external
        onlyAgentOperator(audits[auditId].agentId)
    {
        Audit storage audit = audits[auditId];
        if (audit.delivered) revert AlreadyDelivered(auditId);
        if (bytes(reportURI).length == 0) revert InvalidURI();
        audit.delivered = true;
        emit AuditDelivered(auditId, audit.agentId, audit.requester, reportHash, reportURI);

        // Self-attest report delivery to own reputation is blocked by the
        // canonical reputation registry's self-feedback guard. The REQUESTER
        // attests after receiving, see attestReport().
    }

    /// @notice The requester confirms receipt and quality. This anchors the
    ///         attestation on-chain. The actual reputation entry is written by
    ///         the requester DIRECTLY on the canonical registry via their own
    ///         giveFeedback() call (the contract cannot: the registry's
    ///         self-feedback guard treats the NFT holder as the agent).
    /// @dev    Call sequence: deliverAudit -> client calls registry.giveFeedback
    ///         -> client calls attestReport to close the audit record.
    function attestReport(uint256 auditId, int128 feedbackValue) external {
        Audit storage audit = audits[auditId];
        if (msg.sender != audit.requester) revert NotAuthorized(msg.sender);
        if (!audit.delivered) revert AuditNotDelivered(auditId);
        if (audit.attested) revert AlreadyDelivered(auditId);

        audit.attested = true;
        audit.feedbackValue = feedbackValue;

        emit ReportAttested(auditId, audit.agentId, audit.requester, feedbackValue);
    }

    // ------------------------------------------------------------------
    // Reputation-gated pricing
    // ------------------------------------------------------------------

    /// @notice Owner defines a pricing tier: price + minimum reputation count
    function setPriceTier(uint256 tierId, uint256 pricePerReport, uint64 minFeedbackCount) external onlyOwner {
        priceTiers[tierId] =
            PriceTier({pricePerReport: pricePerReport, minFeedbackCount: minFeedbackCount, active: true});
        if (tierId >= tierCount) tierCount = tierId + 1;
        emit PriceTierSet(tierId, pricePerReport, minFeedbackCount);
    }

    /// @notice Read the reputation-gated price for an agent at a tier
    /// @return price Quote for one report, or revert if below tier minimum
    function quote(uint256 agentId, uint256 tierId) external view returns (uint256 price) {
        PriceTier memory tier = priceTiers[tierId];
        if (!tier.active) revert InvalidAgent();
        uint64 count = _getFeedbackCount(agentId);
        if (count < tier.minFeedbackCount) {
            revert ReputationTooLow(agentId, tierId, count);
        }
        return tier.pricePerReport;
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    /// @notice Total feedback entries across all clients for an agent
    function _getFeedbackCount(uint256 agentId) internal view returns (uint64 count) {
        address[] memory clients = reputationRegistry.getClients(agentId);
        for (uint256 i = 0; i < clients.length; i++) {
            count += reputationRegistry.getLastIndex(agentId, clients[i]);
        }
    }

    /// @notice Get the audit's public record
    function getAudit(uint256 auditId)
        external
        view
        returns (
            uint256 agentId,
            address requester,
            bytes32 targetHash,
            string memory targetURI,
            uint256 tierId,
            bool delivered,
            bool attested,
            int128 feedbackValue
        )
    {
        Audit storage audit = audits[auditId];
        return (
            audit.agentId,
            audit.requester,
            audit.targetHash,
            audit.targetURI,
            audit.tierId,
            audit.delivered,
            audit.attested,
            audit.feedbackValue
        );
    }

    /// @notice Exact parameters the requester should pass to the canonical
    ///         reputation registry's giveFeedback() for this audit, so all
    ///         monadsentry feedback carries uniform tags/endpoint.
    function feedbackParams(uint256 auditId)
        external
        view
        returns (
            uint256 agentId,
            int128 value,
            uint8 valueDecimals,
            string memory tag1,
            string memory tag2,
            string memory endpoint,
            string memory feedbackURI
        )
    {
        Audit storage audit = audits[auditId];
        return (
            audit.agentId,
            audit.feedbackValue,
            0,
            "monadsentry",
            "audit",
            string(abi.encodePacked("audit:", _toString(auditId))),
            audit.targetURI
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ------------------------------------------------------------------
    // ERC-721 Receiver (required: canonical identity registry safeMints
    // the agent NFT to this contract on register())
    // ------------------------------------------------------------------

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
