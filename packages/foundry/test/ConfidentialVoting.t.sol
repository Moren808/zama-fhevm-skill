// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {ConfidentialVoting} from "../src/ConfidentialVoting.sol";
import {euint64, externalEbool} from "encrypted-types/EncryptedTypes.sol";

contract ConfidentialVotingTest is FhevmTest {
    ConfidentialVoting voting;
    address votingAddress;

    address owner;
    uint256 internal constant ALICE_PK = 0xA11CE;
    uint256 internal constant BOB_PK = 0xB0B;
    uint256 internal constant CAROL_PK = 0xCAFE;
    address alice;
    address bob;
    address carol;

    function setUp() public override {
        super.setUp();
        owner = address(this);
        voting = new ConfidentialVoting();
        votingAddress = address(voting);
        alice = vm.addr(ALICE_PK);
        bob = vm.addr(BOB_PK);
        carol = vm.addr(CAROL_PK);
    }

    function _vote(address voter, bool support) internal {
        (externalEbool enc, bytes memory proof) = encryptBool(support, voter, votingAddress);
        vm.prank(voter);
        voting.vote(enc, proof);
    }

    function test_initialState() public view {
        assertTrue(voting.votingOpen());
        assertFalse(voting.resultsRevealed());
        assertEq(voting.owner(), owner);
    }

    function test_singleYesVote_recordsVoter() public {
        _vote(alice, true);
        assertTrue(voting.hasVoted(alice));
    }

    function test_doubleVote_reverts() public {
        _vote(alice, true);
        (externalEbool enc, bytes memory proof) = encryptBool(false, alice, votingAddress);
        vm.prank(alice);
        vm.expectRevert(bytes("Already voted"));
        voting.vote(enc, proof);
    }

    function test_voteAfterClose_reverts() public {
        voting.closeVoting();
        (externalEbool enc, bytes memory proof) = encryptBool(true, alice, votingAddress);
        vm.prank(alice);
        vm.expectRevert(bytes("Voting closed"));
        voting.vote(enc, proof);
    }

    function test_closeVoting_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Not owner"));
        voting.closeVoting();
    }

    function test_tally_revealsCorrectCounts() public {
        // 2 yes (alice, carol) + 1 no (bob)
        _vote(alice, true);
        _vote(bob, false);
        _vote(carol, true);

        voting.closeVoting();
        assertTrue(voting.resultsRevealed());
        assertFalse(voting.votingOpen());

        // Public-decrypt the encrypted tallies via the mock KMS
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = euint64.unwrap(voting.getEncryptedYesVotes());
        handles[1] = euint64.unwrap(voting.getEncryptedNoVotes());

        (uint256[] memory cleartexts,) = publicDecrypt(handles);
        assertEq(cleartexts[0], 2, "yes votes");
        assertEq(cleartexts[1], 1, "no votes");
    }

    function test_tally_allNo() public {
        _vote(alice, false);
        _vote(bob, false);
        voting.closeVoting();

        bytes32[] memory handles = new bytes32[](2);
        handles[0] = euint64.unwrap(voting.getEncryptedYesVotes());
        handles[1] = euint64.unwrap(voting.getEncryptedNoVotes());

        (uint256[] memory cleartexts,) = publicDecrypt(handles);
        assertEq(cleartexts[0], 0, "yes votes");
        assertEq(cleartexts[1], 2, "no votes");
    }

    function test_doubleClose_reverts() public {
        voting.closeVoting();
        vm.expectRevert(bytes("Already closed"));
        voting.closeVoting();
    }
}
