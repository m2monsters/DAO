// SPDX-License-Identifier: BSD-3-Clause

/// @title M2 Monsters DAO Logic interfaces and events

// LICENSE
// M2MonstersDAOInterfaces.sol is a modified version of Nounders DAO NounsDAOInterfaces.sol:
// https://github.com/nounsDAO/nouns-monorepo/tree/master/packages/nouns-contracts/contracts/governance/NounsDAOInterfaces.sol
//
// NounsDAOInterfaces.sol source code Copyright (C) 2021 Nounders DAO licensed under the BSD-3-Clause license.
// With modifications by M2 Monsters DAO.
//
// Additional conditions of BSD-3-Clause can be found here: https://opensource.org/licenses/BSD-3-Clause
//
// MODIFICATIONS
// Voter is no longer an address, but instead an array of NFTs ids which casted a vote.
// Add ownerOf function to validate ownership of NFT.
// Remove getPriorVotes function since is no longer used.
// See CrownDAOLogic.sol for more details.
//

pragma solidity ^0.8.6;

contract M2MonstersDAOEvents {
    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        uint256 proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalCreatedWithRequirements(
        uint256 id,
        uint256 proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        uint256 proposalThreshold,
        uint256 quorumVotes,
        string description
    );

    /// @notice An event emitted when a vote has been cast on a proposal
    /// @param voter The address which casted a vote
    /// @param proposalId The proposal id which was voted on
    /// @param support Support value for the vote. 0=against, 1=for, 2=abstain
    /// @param votes Number of votes which were cast by the voter
    /// @param reason The reason given for the vote by the voter
    event VoteCast(
        uint256[] indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the M2MonstersDAOExecutor
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the M2MonstersDAOExecutor
    event ProposalExecuted(uint256 id);

    /// @notice An event emitted when a proposal has been vetoed by vetoAddress
    event ProposalVetoed(uint256 id);

    /// @notice An event emitted when the voting delay is set
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /// @notice An event emitted when the voting period is set
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /// @notice Emitted when implementation is changed
    event NewImplementation(
        address oldImplementation,
        address newImplementation
    );

    /// @notice Emitted when proposal threshold basis points is set
    event ProposalThresholdBPSSet(
        uint256 oldProposalThresholdBPS,
        uint256 newProposalThresholdBPS
    );

    /// @notice Emitted when quorum votes basis points is set
    event QuorumVotesBPSSet(
        uint256 oldQuorumVotesBPS,
        uint256 newQuorumVotesBPS
    );

    /// @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    /// @notice Emitted when vetoer is changed
    event NewVetoer(address oldVetoer, address newVetoer);
}

contract M2MonstersDAOProxyStorage {
    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    /// @notice Active brains of Governor
    address public implementation;
}

/**
 * @title Storage for Governor Bravo Delegate
 * @notice For future upgrades, do not change M2MonstersDAOStorageV1. Create a new
 * contract which implements M2MonstersDAOStorageV1 and following the naming convention
 * M2MonstersDAOStorageVX.
 */
contract M2MonstersDAOStorageV1 is M2MonstersDAOProxyStorage {
    /// @notice Vetoer who has the ability to veto any proposal
    address public vetoer;

    /// @notice The delay before voting on a proposal may take place, once proposed, in blocks
    uint256 public votingDelay;

    /// @notice The duration of voting on a proposal, in blocks
    uint256 public votingPeriod;

    /// @notice The basis point number of votes required in order for a voter to become a proposer. *DIFFERS from GovernerBravo
    uint256 public proposalThresholdBPS;

    /// @notice The basis point number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed. *DIFFERS from GovernerBravo
    uint256 public quorumVotesBPS;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice The address of the M2Monsters DAO Executor M2MonstersDAOExecutor
    IM2MonstersDAOExecutor public timelock;

    /// @notice The address of the M2Monsters tokens
    M2MonstersTokenLike public monsters;

    /// @notice The official record of all proposals ever proposed
    mapping(uint256 => ProposalGeo) public proposals;

    /// @notice The latest proposal for each proposer
    mapping(uint256 => uint256) public latestProposalIds;

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        uint256 proposer;
        /// @notice The number of votes needed to create a proposal at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 proposalThreshold;
        /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 quorumVotes;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        uint256 abstainVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been vetoed
        bool vetoed;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(uint256 => Receipt) receipts;
    }

    struct ProposalVotes {
        /// @notice The number of votes needed to create a proposal at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 proposalThreshold;
        /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed at the time of proposal creation. *DIFFERS from GovernerBravo
        uint256 quorumVotes;
        /// @notice Number of cities in geo cohort
        uint256 geoCount;
        /// @notice Current number of votes in favor of this proposal
        uint256 geoForVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 geoAgainstVotes;
        /// @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        /// @notice Current number of votes in favor of this proposal
        uint256 crownForVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint256 crownAgainstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        uint256 abstainVotes;

        uint256 geoVotingTime;
    }

    struct ProposalGeo {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        uint256 proposer;
        /// @notice The number of votes needed to create a proposal at the time of proposal creation. *DIFFERS from GovernerBravo
        // uint256 proposalThreshold;
        /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed at the time of proposal creation. *DIFFERS from GovernerBravo
        // uint256 quorumVotes;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        /// @notice Merkle Root to check allowed voters based on Geo Proximity
        bytes32 geoRoot;
        /// @notice Number of cities in geo cohort
        // uint256 geoCount;
        /// @notice Current number of votes in favor of this proposal
        // uint256 geoForVotes;
        /// @notice Current number of votes in opposition to this proposal
        // uint256 geoAgainstVotes;
        /// @notice Current number of votes in favor of this proposal
        // uint256 forVotes;
        /// @notice Current number of votes in opposition to this proposal
        // uint256 againstVotes;
        /// @notice Current number of votes in favor of this proposal
        // uint256 crownForVotes;
        /// @notice Current number of votes in opposition to this proposal
        // uint256 crownAgainstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        // uint256 abstainVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been vetoed
        bool vetoed;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
        /// @notice Receipts of ballots for the entire set of voters
        mapping(uint256 => Receipt) receipts;
        
        ProposalVotes votes;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal or abstains
        uint8 support;
        /// @notice The number of votes the voter had, which were cast
        uint96 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        GeoVoting,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed,
        Vetoed
    }
}

interface IM2MonstersDAOExecutor {
    function delay() external view returns (uint256);

    function GRACE_PERIOD() external view returns (uint256);

    function acceptAdmin() external;

    function queuedTransactions(bytes32 hash) external view returns (bool);

    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external returns (bytes32);

    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external;

    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable returns (bytes memory);
}

interface M2MonstersTokenLike {
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint96);

    function ownerOf(uint256 _id) external view returns (address);

    function MonsterCategory(uint256 _id) external view returns (uint256);

    function totalSupply() external view returns (uint96);
}
