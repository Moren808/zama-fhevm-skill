// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { FHE, euint64, ebool, externalEbool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title ConfidentialVoting
/// @notice Encrypted yes/no voting. Individual votes stay private; only the
///         final tally is revealed publicly after the owner closes the election.
contract ConfidentialVoting is ZamaEthereumConfig {
    address public immutable owner;

    euint64 private encryptedYesVotes;
    euint64 private encryptedNoVotes;

    mapping(address => bool) public hasVoted;

    bool public votingOpen;
    bool public resultsRevealed;

    event Voted(address indexed voter);
    event VotingClosed();
    event ResultsPublic();

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        votingOpen = true;

        encryptedYesVotes = FHE.asEuint64(0);
        encryptedNoVotes = FHE.asEuint64(0);
        FHE.allowThis(encryptedYesVotes);
        FHE.allowThis(encryptedNoVotes);
    }

    /// @notice Cast an encrypted vote. `support` is an externalEbool produced
    ///         off-chain via fhevmjs (`encInput.addBool(true|false)`).
    ///         `inputProof` is the matching proof for that input.
    function vote(externalEbool support, bytes calldata inputProof) external {
        require(votingOpen, "Voting closed");
        require(!hasVoted[msg.sender], "Already voted");

        hasVoted[msg.sender] = true;

        ebool isYes = FHE.fromExternal(support, inputProof);
        FHE.allowThis(isYes);

        euint64 one = FHE.asEuint64(1);
        euint64 zero = FHE.asEuint64(0);

        // Branchless tally: if isYes, add 1 to yes counter, else 1 to no counter.
        encryptedYesVotes = FHE.add(encryptedYesVotes, FHE.select(isYes, one, zero));
        encryptedNoVotes = FHE.add(encryptedNoVotes, FHE.select(isYes, zero, one));

        FHE.allowThis(encryptedYesVotes);
        FHE.allowThis(encryptedNoVotes);

        emit Voted(msg.sender);
    }

    /// @notice Close voting and mark the encrypted tallies as publicly
    ///         decryptable so anyone can decrypt the final counts via the Gateway.
    function closeVoting() external onlyOwner {
        require(votingOpen, "Already closed");
        votingOpen = false;

        FHE.makePubliclyDecryptable(encryptedYesVotes);
        FHE.makePubliclyDecryptable(encryptedNoVotes);

        resultsRevealed = true;

        emit VotingClosed();
        emit ResultsPublic();
    }

    /// @notice Encrypted yes-vote handle. Readable on-chain only after closeVoting()
    ///         (or by addresses with explicit ACL access — currently just this contract).
    function getEncryptedYesVotes() external view returns (euint64) {
        return encryptedYesVotes;
    }

    /// @notice Encrypted no-vote handle. Same access rules as yes votes.
    function getEncryptedNoVotes() external view returns (euint64) {
        return encryptedNoVotes;
    }
}
