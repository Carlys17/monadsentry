// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MonadSentry} from "../src/MonadSentry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {IReputationRegistry} from "../src/interfaces/IReputationRegistry.sol";

/// @notice End-to-end test against the LIVE canonical ERC-8004 registries on
///         Monad mainnet (chain 143), executed on a fork.
/// @dev Run: forge test --fork-url https://rpc.monad.xyz --match-contract ForkTest
///      IMPORTANT: requires evm_version = "cancun" — the canonical registries are
///      ERC-1967 proxies whose runtime bytecode uses PUSH0, which reverts under
///      the "paris" EVM version.
contract ForkTest is Test {
    address constant IDENTITY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address constant REPUTATION = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    MonadSentry sentry;

    address deployer = address(this);
    address client = address(0xC11E27);

    /// @dev These tests only mean anything against a real Monad fork. When run
    ///      without --fork-url (e.g. plain `forge test` in CI) the canonical
    ///      registries have no code, so skip instead of reporting false failures.
    function setUp() public {
        if (IDENTITY.code.length == 0 || REPUTATION.code.length == 0) {
            vm.skip(true);
            return;
        }
        sentry = new MonadSentry(IDENTITY, REPUTATION);
    }

    // ------------------------------------------------------------------
    // Canonical registry reachability
    // ------------------------------------------------------------------

    function test_reputationPointsAtIdentity() public view {
        address idRef = IReputationRegistry(REPUTATION).getIdentityRegistry();
        assertEq(idRef, IDENTITY, "reputation registry must reference canonical identity");
    }

    // ------------------------------------------------------------------
    // Real agent registration through MonadSentry against live registry
    // ------------------------------------------------------------------

    function test_registerAgent_onLiveRegistry() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");

        assertGt(agentId, 0, "agentId must be minted");
        console.log("minted agentId:", agentId);

        // The registry auto-set the wallet to msg.sender == the sentry contract
        address stored = IIdentityRegistry(IDENTITY).getAgentWallet(agentId);
        assertEq(stored, address(sentry), "agent wallet defaults to the sentry contract");

        // MonadSentry (as NFT holder) is authorized for the agent
        assertTrue(
            IIdentityRegistry(IDENTITY).isAuthorizedOrOwner(address(sentry), agentId),
            "MonadSentry must be authorized for the agent it registered"
        );
    }

    // ------------------------------------------------------------------
    // Full audit lifecycle: register -> tier -> request -> deliver -> attest
    // ------------------------------------------------------------------

    function test_fullAuditLifecycle() public {
        // 1. Register the audit agent on the live registry
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");

        // 2. Owner opens a tier with no reputation requirement (cold start)
        sentry.setPriceTier(0, 0.5 ether, 0);

        // 3. Client requests an audit
        vm.prank(client);
        uint256 auditId = sentry.requestAudit(
            agentId, keccak256("contract source bundle"), "https://github.com/Carlys17/monadsentry", 0
        );
        assertEq(auditId, 1);

        // 4. The agent (MonadSentry owner == this test) delivers the report
        sentry.deliverAudit(auditId, keccak256("report v1"), "ipfs://QmReportHash");
        assertTrue(_delivered(auditId), "report must be marked delivered");

        // 5. Client attests on-chain, then writes reputation DIRECTLY to the
        //    canonical registry (self-feedback guard prevents the contract
        //    from doing it as NFT holder)
        vm.prank(client);
        sentry.attestReport(auditId, 1);
        assertTrue(_attested(auditId), "audit must be attested");

        // 6. Client writes reputation using the uniform params the contract
        //    publishes, then it must be readable from the canonical registry
        _clientGivesFeedback(auditId);

        assertEq(
            IReputationRegistry(REPUTATION).getLastIndex(agentId, client),
            1,
            "one feedback entry must exist for this client"
        );
        _assertFeedback(agentId);
    }

    // ---- helpers (kept separate to avoid stack-too-deep) ----

    function _delivered(uint256 auditId) internal view returns (bool d) {
        (,,,,, d,,) = sentry.getAudit(auditId);
    }

    function _attested(uint256 auditId) internal view returns (bool a) {
        (,,,,,, a,) = sentry.getAudit(auditId);
    }

    function _clientGivesFeedback(uint256 auditId) internal {
        (
            uint256 fbAgentId,
            int128 fbValue,
            uint8 fbDecimals,
            string memory tag1,
            string memory tag2,
            string memory endpoint,
            string memory fbURI
        ) = sentry.feedbackParams(auditId);

        assertEq(fbValue, 1);
        assertEq(fbDecimals, 0);
        assertEq(tag1, "monadsentry");
        assertEq(tag2, "audit");
        assertEq(endpoint, "audit:1");

        vm.prank(client);
        IReputationRegistry(REPUTATION)
            .giveFeedback(fbAgentId, fbValue, fbDecimals, tag1, tag2, endpoint, fbURI, keccak256(bytes(fbURI)));
    }

    function _assertFeedback(uint256 agentId) internal view {
        (int128 value,, string memory rTag1, string memory rTag2, bool revoked) =
            IReputationRegistry(REPUTATION).readFeedback(agentId, client, 1);
        assertEq(value, 1);
        assertEq(rTag1, "monadsentry");
        assertEq(rTag2, "audit");
        assertFalse(revoked);
    }

    // ------------------------------------------------------------------
    // Reputation gate
    // ------------------------------------------------------------------

    function test_reputationGate_blocksUnprovenAgent() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");

        // Tier requiring 3 prior feedbacks; the fresh agent has none
        sentry.setPriceTier(1, 2 ether, 3);

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(MonadSentry.ReputationTooLow.selector, agentId, 1, uint64(0)));
        sentry.requestAudit(agentId, keccak256("x"), "ipfs://x", 1);
    }

    function test_quote_returnsTierPrice() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");
        sentry.setPriceTier(0, 0.42 ether, 0);
        assertEq(sentry.quote(agentId, 0), 0.42 ether);
    }

    // ------------------------------------------------------------------
    // Access control
    // ------------------------------------------------------------------

    function test_nonOwnerCannotSetTier() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(MonadSentry.NotAuthorized.selector, address(0xBAD)));
        sentry.setPriceTier(0, 1 ether, 1);
    }

    function test_nonRequesterCannotAttest() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");
        sentry.setPriceTier(0, 1 ether, 0);

        vm.prank(client);
        uint256 auditId = sentry.requestAudit(agentId, keccak256("x"), "ipfs://x", 0);
        sentry.deliverAudit(auditId, keccak256("r"), "ipfs://r");

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(MonadSentry.NotAuthorized.selector, address(0xBAD)));
        sentry.attestReport(auditId, 1);
    }

    function test_cannotAttestBeforeDelivery() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");
        sentry.setPriceTier(0, 1 ether, 0);

        vm.prank(client);
        uint256 auditId = sentry.requestAudit(agentId, keccak256("x"), "ipfs://x", 0);

        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(MonadSentry.AuditNotDelivered.selector, auditId));
        sentry.attestReport(auditId, 1);
    }

    function test_cannotDeliverTwice() public {
        uint256 agentId = sentry.registerAgent("https://carly17.my.id/monadsentry/agent-card.json");
        sentry.setPriceTier(0, 1 ether, 0);

        vm.prank(client);
        uint256 auditId = sentry.requestAudit(agentId, keccak256("x"), "ipfs://x", 0);
        sentry.deliverAudit(auditId, keccak256("r"), "ipfs://r");

        vm.expectRevert(abi.encodeWithSelector(MonadSentry.AlreadyDelivered.selector, auditId));
        sentry.deliverAudit(auditId, keccak256("r2"), "ipfs://r2");
    }
}
