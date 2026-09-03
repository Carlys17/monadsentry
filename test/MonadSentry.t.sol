// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MonadSentry} from "../src/MonadSentry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {IReputationRegistry} from "../src/interfaces/IReputationRegistry.sol";

/// @notice Tiny mocked unit tests for MonadSentry wiring against ERC-8004
/// For full fork tests against canonical Monad registries, see Fork.t.sol
contract MockRegistry {
    uint256 public nextAgentId = 0;
    mapping(uint256 => address) public walletOf;
    mapping(uint256 => mapping(address => bool)) public authorized;
    address[] public clients;
    mapping(uint256 => mapping(address => uint64)) public lastIndex;
    mapping(uint256 => mapping(address => mapping(uint64 => int128))) public vals;

    function registerAgent(address owner, address wallet) external returns (uint256 id) {
        id = ++nextAgentId;
        walletOf[id] = wallet;
        authorized[id][owner] = true;
    }

    function setAgentWallet(uint256 id, address wallet) external {
        walletOf[id] = wallet;
    }

    function getAgentWallet(uint256 id) external view returns (address) {
        return walletOf[id];
    }

    function isAuthorizedOrOwner(address spender, uint256 id) external view returns (bool) {
        return authorized[id][spender];
    }

    function setMetadata(uint256, string memory, bytes memory) external {}

    function getMetadata(uint256, string memory) external view returns (bytes memory) {
        return "";
    }
    function setAgentURI(uint256, string calldata) external {}

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8,
        string calldata,
        string calldata,
        string calldata,
        string calldata,
        bytes32
    ) external {
        if (authorized[agentId][msg.sender]) revert("self-feedback");
        if (lastIndex[agentId][msg.sender] == 0) {
            clients.push(msg.sender);
            lastIndex[agentId][msg.sender]; // touch to register
        }
        uint64 idx = ++lastIndex[agentId][msg.sender];
        vals[agentId][msg.sender][idx] = value;
    }

    function getClients(uint256) external view returns (address[] memory) {
        return clients;
    }

    function getLastIndex(uint256 id, address c) external view returns (uint64) {
        return lastIndex[id][c];
    }

    function getIdentityRegistry() external pure returns (address) {
        return address(0xdead);
    }
    function appendResponse(uint256, address, uint64, string calldata, bytes32) external {}
    function revokeFeedback(uint256, uint64) external {}

    function readFeedback(uint256, address, uint64)
        external
        pure
        returns (int128, uint8, string memory, string memory, bool)
    {
        return (0, 0, "", "", false);
    }

    function getSummary(uint256, address[] calldata, string calldata, string calldata)
        external
        pure
        returns (uint64, int128, uint8)
    {
        return (0, 0, 0);
    }
}

contract MonadSentryTest is Test {
    MockRegistry internal mock;
    MonadSentry internal sentry;

    address owner = address(0xA11CE);
    address agentWallet = address(0xB0B);
    address requester = address(0xC0FFEE);

    uint256 agentId;

    function setUp() public {
        mock = new MockRegistry();
        sentry = new MonadSentry(address(mock), address(mock));
        // seed some prior reputation so quote/reputation-gated tier passes
        vm.startPrank(requester);
        // pre-register a client by simulating prior feedback: not possible pre-register; we'll mock it
        vm.stopPrank();

        agentId = mock.registerAgent(owner, agentWallet);

        // Pre-populate reputation for tier gating
        address client1 = address(0xAA);
        address client2 = address(0xBB);
        for (uint160 i = 0; i < 3; i++) {
            address c = address(uint160(0x1000 + i));
            vm.prank(c);
            mock.giveFeedback(agentId, 1, 0, "audit", "x", "e", "u", bytes32(0));
        }

        // Set a tier requiring >= 3 feedbacks (test contract IS the owner)
        sentry.setPriceTier(0, 1 ether, 3);
    }

    function test_requestAudit_works() public {
        vm.prank(requester);
        uint256 aid = sentry.requestAudit(agentId, bytes32(uint256(42)), "ipfs://target", 0);
        assertEq(aid, 1);
        (uint256 aid_,,,, uint256 tier,,,) = sentry.getAudit(aid);
        assertEq(aid_, agentId);
        assertEq(tier, 0);
    }

    function test_quote_reverts_below_tier() public {
        // Make a fresh agent with no reputation
        address freshOwner = address(0xF);
        uint256 fresh = mock.registerAgent(freshOwner, address(0xF0));
        vm.prank(freshOwner);
        // no setPriceTier from here: tier is active already
        vm.expectRevert();
        sentry.quote(fresh, 0);
    }

    function test_deliverAudit_and_attest() public {
        vm.prank(requester);
        uint256 aid = sentry.requestAudit(agentId, bytes32(uint256(7)), "ipfs://x", 0);

        vm.prank(owner);
        sentry.deliverAudit(aid, bytes32(uint256(99)), "ipfs://report");

        vm.prank(requester);
        sentry.attestReport(aid, 1);

        (,,,,, bool delivered, bool attested,) = sentry.getAudit(aid);
        assertTrue(delivered);
        assertTrue(attested);
    }

    function test_attest_onlyRequester() public {
        vm.prank(requester);
        uint256 aid = sentry.requestAudit(agentId, bytes32(uint256(7)), "ipfs://x", 0);
        vm.prank(owner);
        sentry.deliverAudit(aid, bytes32(uint256(99)), "ipfs://report");

        vm.prank(address(0xBAD));
        vm.expectRevert();
        sentry.attestReport(aid, 1);
    }
}
