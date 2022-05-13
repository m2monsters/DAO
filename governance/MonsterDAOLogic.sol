// SPDX-License-Identifier: BSD-3-Clause

/// @title Social M2 Monsters DAO logic version 1

// LICENSE
// CrownDAOLogic.sol is a modified version of Nounders DAO NounsDAOLogicV1.sol:
// https://github.com/nounsDAO/nouns-monorepo/tree/master/packages/nouns-contracts/contracts/governance/NounsDAOLogicV1.sol
//
// NounsDAOLogicV1.sol source code Copyright (C) 2021 Nounders DAO // SPDX-License-Identifier: BSD-3-Clause
// With modifications by M2 Monsters DAO.
//
// Additional conditions of BSD-3-Clause can be found here: https://opensource.org/licenses/BSD-3-Clause
//
// MODIFICATIONS
// Logic was changed to cast votes per NFT id instead of per address. Every NFT equals one vote, even if it's from the same address. 
// Added ownerOf function to validate that the executor owns the NFTs casting a vote.  
// Removed getPriorVotes function since is no longer used. 

pragma solidity ^0.8.6;

import './M2MonstersDAOInterfaces.sol';
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "hardhat/console.sol";



contract MonsterDAOLogic is M2MonstersDAOStorageV1, M2MonstersDAOEvents {
    using MerkleProof for bytes32[];

    //mapping(uint256 => bytes32) roots;
    bytes32 public mainRoot; 
    /// @notice The name of this contract
    string public constant name = 'M2Monsters DAO';

    uint256 public constant CROWN_MONSTERS = 400;
    uint256 public constant CROWN_MONSTERS_THRESHOLD_BPS = 8000;
    /// @notice The minimum setable proposal threshold
    uint256 public constant MIN_PROPOSAL_THRESHOLD_BPS = 3000; // 1 basis point or 0.01%

    /// @notice The maximum setable proposal threshold
    uint256 public constant MAX_PROPOSAL_THRESHOLD_BPS = 9_000; // 1,000 basis points or 10%

    /// @notice The minimum setable voting period
    uint256 public constant MIN_VOTING_PERIOD = 5760; // About 24 hours

    /// @notice The max setable voting period
    uint256 public constant MAX_VOTING_PERIOD = 80_640; // About 2 weeks

    /// @notice The min setable voting delay
    uint256 public constant MIN_VOTING_DELAY = 1;

    /// @notice The max setable voting delay
    uint256 public constant MAX_VOTING_DELAY = 40_320; // About 1 week

    /// @notice The minimum setable quorum votes basis points
    uint256 public constant MIN_QUORUM_VOTES_BPS = 500; // 200 basis points or 2%

    /// @notice The maximum setable quorum votes basis points
    uint256 public constant MAX_QUORUM_VOTES_BPS = 7_000; // 2,000 basis points or 20%


    uint256 public constant GEO_VOTING_THRESHOLD = 2000; // 20% 

    uint256 public constant MIN_GEO_VOTING_TIME = 1 days;
    

    /// @notice The maximum number of actions that can be included in a proposal
    uint256 public constant proposalMaxOperations = 10; // 10 actions

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256('EIP712Domain(string name,uint256 chainId,address verifyingContract)');

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256('Ballot(uint256 proposalId,uint8 support)');

    /**
     * @notice Used to initialize the contract during delegator contructor
     * @param timelock_ The address of the M2MonstersDAOExecutor
     * @param monsters_ The address of the NOUN tokens
     * @param vetoer_ The address allowed to unilaterally veto proposals
     * @param votingPeriod_ The initial voting period
     * @param votingDelay_ The initial voting delay
     * @param proposalThresholdBPS_ The initial proposal threshold in basis points
     * * @param quorumVotesBPS_ The initial quorum votes threshold in basis points
     */
    function initialize(
        address timelock_,
        address monsters_,
        address vetoer_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 proposalThresholdBPS_,
        uint256 quorumVotesBPS_,
        bytes32 root_
    ) public virtual {
        require(address(timelock) == address(0), 'M2MonstersDAO::initialize: can only initialize once');
        require(msg.sender == admin, 'M2MonstersDAO::initialize: admin only');
        require(timelock_ != address(0), 'M2MonstersDAO::initialize: invalid timelock address');
        require(monsters_ != address(0), 'M2MonstersDAO::initialize: invalid monsters address');
        require(
            votingPeriod_ >= MIN_VOTING_PERIOD && votingPeriod_ <= MAX_VOTING_PERIOD,
            'M2MonstersDAO::initialize: invalid voting period'
        );
        require(
            votingDelay_ >= MIN_VOTING_DELAY && votingDelay_ <= MAX_VOTING_DELAY,
            'M2MonstersDAO::initialize: invalid voting delay'
        );
        require(
            proposalThresholdBPS_ >= MIN_PROPOSAL_THRESHOLD_BPS && proposalThresholdBPS_ <= MAX_PROPOSAL_THRESHOLD_BPS,
            'M2MonstersDAO::initialize: invalid proposal threshold'
        );
        require(
            quorumVotesBPS_ >= MIN_QUORUM_VOTES_BPS && quorumVotesBPS_ <= MAX_QUORUM_VOTES_BPS,
            'M2MonstersDAO::initialize: invalid proposal threshold'
        );

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit ProposalThresholdBPSSet(proposalThresholdBPS, proposalThresholdBPS_);
        emit QuorumVotesBPSSet(quorumVotesBPS, quorumVotesBPS_);

        timelock = IM2MonstersDAOExecutor(timelock_);
        monsters = M2MonstersTokenLike(monsters_);
        vetoer = vetoer_;
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        proposalThresholdBPS = proposalThresholdBPS_;
        quorumVotesBPS = quorumVotesBPS_;
        mainRoot = root_;
    }

    struct ProposalTemp {
        uint256 totalSupply;
        uint256 proposalThreshold;
        uint256 latestProposalId;
        uint256 startBlock;
        uint256 endBlock;
    }

    /**
     * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold
     * @param targets Target addresses for proposal calls
     * @param values Eth values for proposal calls
     * @param signatures Function signatures for proposal calls
     * @param calldatas Calldatas for proposal calls
     * @param description String description of the proposal
     * @return Proposal id of new proposal
     */
    function propose(
        uint256 proposerId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        bytes32 geoRoot,
        bytes32[] memory _proof1, //proof for geoRoot in base Root
        bytes32[] memory _proof2, //proof that sender is part of geo cohort
        uint256 geoCount, // trheshold,
        uint256 geoVotingTime,
        string memory description
    ) public returns (uint256) {
        ProposalTemp memory temp;

        temp.totalSupply = monsters.totalSupply();

        temp.proposalThreshold = proposalThresholdBPS;

        //require(monsters.MonsterCategory(proposerId) == 0, "Not Crown Monster");
        //Verify Proof of Merkle 

        // Calculamos que el mínimo que estamos pasando en el geoCount entre dentro del mínimo del threshold
        // uint256 geoMin = _calculatePercentage(geoCount, GEO_VOTING_THRESHOLD);
        // geoMin = geoMin;
        // console.log("geoMin", geoMin);
        
        require(monsters.ownerOf(proposerId) == msg.sender, 'Not owner of NFT');
        require(checkProofMain(_proof1, mainRoot, geoRoot, geoCount), "Proposed geoRoot not in main Root");
        require(checkProof(_proof2, geoRoot, proposerId), "Proposer not part of Geo Group");
        require(geoVotingTime *  1 days >= MIN_GEO_VOTING_TIME, "Invalid geo voting time");
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            'M2MonstersDAO::propose: proposal function information arity mismatch'
        );
        require(targets.length != 0, 'M2MonstersDAO::propose: must provide actions');
        require(targets.length <= proposalMaxOperations, 'M2MonstersDAO::propose: too many actions');

        temp.latestProposalId = latestProposalIds[proposerId];
        if (temp.latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(temp.latestProposalId);
            require(
                proposersLatestProposalState != ProposalState.Active,
                'M2MonstersDAO::propose: one live proposal per proposer, found an already active proposal'
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                'M2MonstersDAO::propose: one live proposal per proposer, found an already pending proposal'
            );
        }

        temp.startBlock = block.number + votingDelay;
        temp.endBlock = temp.startBlock + votingPeriod;

        proposalCount++;
        ProposalGeo storage newProposal = proposals[proposalCount];

        newProposal.id = proposalCount;
        newProposal.proposer = proposerId;
        newProposal.votes.proposalThreshold = temp.proposalThreshold;
        newProposal.votes.quorumVotes = bps2Uint(quorumVotesBPS, temp.totalSupply);
        newProposal.eta = 0;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = temp.startBlock;
        newProposal.endBlock = temp.endBlock;
        newProposal.geoRoot = geoRoot;
        newProposal.votes.geoCount = _calculatePercentage(geoCount, GEO_VOTING_THRESHOLD);
        newProposal.votes.forVotes = 0;
        newProposal.votes.againstVotes = 0;
        newProposal.votes.geoForVotes = 0;
        newProposal.votes.geoAgainstVotes = 0;
        newProposal.votes.crownForVotes = 0;
        newProposal.votes.crownAgainstVotes = 0;
        newProposal.votes.abstainVotes = 0;
        newProposal.votes.geoVotingTime = geoVotingTime;
        newProposal.canceled = false;
        newProposal.executed = false;
        newProposal.vetoed = false;


        latestProposalIds[newProposal.proposer] = newProposal.id;

        /// @notice Maintains backwards compatibility with GovernorBravo events
        emit ProposalCreated(
            newProposal.id,
            proposerId,
            targets,
            values,
            signatures,
            calldatas,
            newProposal.startBlock,
            newProposal.endBlock,
            description
        );

        /// @notice Updated event with `proposalThreshold` and `quorumVotes`
        emit ProposalCreatedWithRequirements(
            newProposal.id,
            proposerId,
            targets,
            values,
            signatures,
            calldatas,
            newProposal.startBlock,
            newProposal.endBlock,
            newProposal.votes.proposalThreshold,
            newProposal.votes.quorumVotes,
            description
        );

        return newProposal.id;
    }

    /**
     * @notice Queues a proposal of state succeeded
     * @param proposalId The id of the proposal to queue
     */
    function queue(uint256 proposalId) external {
        require(
            state(proposalId) == ProposalState.Succeeded,
            'M2MonstersDAO::queue: proposal can only be queued if it is succeeded'
        );
        ProposalGeo storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timelock.delay();
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            queueOrRevertInternal(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                eta
            );
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function queueOrRevertInternal(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))),
            'M2MonstersDAO::queueOrRevertInternal: identical proposal action already queued at eta'
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    /**
     * @notice Executes a queued proposal if eta has passed
     * @param proposalId The id of the proposal to execute
     */
    function execute(uint256 proposalId) external {
        require(
            state(proposalId) == ProposalState.Queued,
            'M2MonstersDAO::execute: proposal can only be executed if it is queued'
        );
        ProposalGeo storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancels a proposal only if sender is the proposer, or proposer delegates dropped below proposal threshold
     * @param proposalId The id of the proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        require(state(proposalId) != ProposalState.Executed, 'M2MonstersDAO::cancel: cannot cancel executed proposal');

        ProposalGeo storage proposal = proposals[proposalId];
        require(monsters.MonsterCategory(proposal.proposer) == 0, "Not Crown Monster");
        require(
            msg.sender == monsters.ownerOf(proposal.proposer),
            'M2MonstersDAO::cancel: proposer above threshold'
        );

        proposal.canceled = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Vetoes a proposal only if sender is the vetoer and the proposal has not been executed.
     * @param proposalId The id of the proposal to veto
     */
    function veto(uint256 proposalId) external {
        require(vetoer != address(0), 'M2MonstersDAO::veto: veto power burned');
        require(msg.sender == vetoer, 'M2MonstersDAO::veto: only vetoer');
        require(state(proposalId) != ProposalState.Executed, 'M2MonstersDAO::veto: cannot veto executed proposal');

        ProposalGeo storage proposal = proposals[proposalId];

        proposal.vetoed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalVetoed(proposalId);
    }

    /**
     * @notice Gets actions of a proposal
     * @param proposalId the id of the proposal
     * @return targets
     * @return values
     * @return signatures
     * @return calldatas
     */
    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        ProposalGeo storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
     * @notice Gets the receipt for a voter on a given proposal
     * @param proposalId the id of proposal
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 proposalId, uint256 voter) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @notice Gets the state of a proposal
     * @param proposalId The id of the proposal
     * @return Proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId, 'M2MonstersDAO::state: invalid proposal id');
        ProposalGeo storage proposal = proposals[proposalId];
        if (proposal.vetoed) {
            return ProposalState.Vetoed;
        } else if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if ((proposal.votes.geoForVotes + proposal.votes.geoAgainstVotes) < proposal.votes.geoCount && block.timestamp <= proposal.votes.geoVotingTime + block.timestamp) { 
            return ProposalState.GeoVoting;
        } else if (block.number <= proposal.endBlock &&  block.timestamp >= proposal.votes.geoVotingTime + block.timestamp  && proposal.votes.geoForVotes >= proposal.votes.geoForVotes) {
            return ProposalState.Active;
        } else if (proposal.votes.crownForVotes < proposal.votes.crownForVotes 
                    || (proposal.votes.crownForVotes + proposal.votes.crownForVotes) < bps2Uint(CROWN_MONSTERS_THRESHOLD_BPS, CROWN_MONSTERS) //Crown Quorum
                    || proposal.votes.crownForVotes <= proposal.votes.crownAgainstVotes
                    || proposal.votes.geoForVotes <= proposal.votes.geoAgainstVotes 
                    || proposal.votes.forVotes <= proposal.votes.againstVotes 
                    || (proposal.votes.forVotes + proposal.votes.againstVotes) < proposal.votes.quorumVotes 
                    || proposal.votes.forVotes < bps2Uint(proposal.votes.proposalThreshold, (proposal.votes.forVotes + proposal.votes.againstVotes))) 
             {
            return ProposalState.Defeated;
        } 
        else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @notice Cast a vote for a proposal
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(
        uint256[] memory tokenIds,
        uint256 proposalId,
        uint8 support
    ) external {
        emit VoteCast(tokenIds, proposalId, support, castVoteInternal(tokenIds, proposalId, support), '');
    }
    function castGeoVote(
        uint256[] memory tokenIds,
        uint256 proposalId,
        bytes32[][] memory _proofs,
        uint8 support
    ) external {
        emit VoteCast(tokenIds, proposalId, support, castVoteGeoInternal(tokenIds, proposalId, _proofs, support), '');
    }
    /**
     * @notice Cast a vote for a proposal with a reason
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(
        uint256[] memory tokenIds,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external {
        emit VoteCast(tokenIds, proposalId, support, castVoteInternal(tokenIds, proposalId, support), reason);
    }

    /**
     * @notice Cast a vote for a proposal by signature
     * @dev External function that accepts EIP-712 signatures for voting on proposals.
     */
    // function castVoteBySig(
    //     uint256 proposalId,
    //     uint8 support,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) external {
    //     bytes32 domainSeparator = keccak256(
    //         abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainIdInternal(), address(this))
    //     );
    //     bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
    //     bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
    //     address signatory = ecrecover(digest, v, r, s);
    //     require(signatory != address(0), 'M2MonstersDAO::castVoteBySig: invalid signature');
    //     emit VoteCast(signatory, proposalId, support, castVoteInternal(signatory, proposalId, support), '');
    // }

    // /**
    //  * @notice Internal function that caries out voting logic
    //  * @param voter The voter that is casting their vote
    //  * @param proposalId The id of the proposal to vote on
    //  * @param support The support value for the vote. 0=against, 1=for, 2=abstain
    //  * @return The number of votes cast
    //  */
    function castVoteInternal(
        uint256[] memory tokenIds,
        uint256 proposalId,
        uint8 support
    ) internal returns (uint96) {
        require(state(proposalId) == ProposalState.Active, 'M2MonstersDAO::castVoteInternal: voting is closed');
        require(support <= 2, 'M2MonstersDAO::castVoteInternal: invalid vote type');
        ProposalGeo storage proposal = proposals[proposalId];

        uint96 votes = 0;
        uint96 crownVotes = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            //require(monsters.MonsterCategory(tokenIds[i]) == 0, "Not Crown Monster");
            require(monsters.ownerOf(tokenIds[i]) == msg.sender, 'Sender not owner of Token');
            Receipt storage receipt = proposal.receipts[tokenIds[i]];
            require(receipt.hasVoted == false, 'M2MonstersDAO::castVoteInternal: voter already voted');

            receipt.hasVoted = true;
            receipt.support = support;
            receipt.votes = 1;

            votes += 1;
            if(monsters.MonsterCategory(tokenIds[i]) == 0){
                crownVotes += 1;
            }
        }

        if (support == 0) {
            proposal.votes.againstVotes = proposal.votes.againstVotes + votes;
            proposal.votes.crownAgainstVotes = proposal.votes.crownAgainstVotes + crownVotes;
        } else if (support == 1) {
            proposal.votes.forVotes = proposal.votes.forVotes + votes;
            proposal.votes.crownForVotes = proposal.votes.crownForVotes + crownVotes;
        } else if (support == 2) {
            proposal.votes.abstainVotes = proposal.votes.abstainVotes + votes;
        }

        return votes;
    }

    function castVoteGeoInternal(
        uint256[] memory tokenIds,
        uint256 proposalId,
        bytes32[][] memory _proofs,
        uint8 support
    ) internal returns (uint96) {
        // require(state(proposalId) == ProposalState.Active, 'M2MonstersDAO::castVoteInternal: voting is closed');
        require(state(proposalId) == ProposalState.GeoVoting, 'M2MonstersDAO::castVoteInternal: voting is closed');
        require(support <= 2, 'M2MonstersDAO::castVoteInternal: invalid vote type');
        ProposalGeo storage proposal = proposals[proposalId];

        //(proposal.geoForVotes + proposal.againstVotes) < THRESHOLDFORGEO
        uint96 votes = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(monsters.MonsterCategory(tokenIds[i]) == 0, "Not Crown Monster");
            require(monsters.ownerOf(tokenIds[i]) == msg.sender, 'Sender not owner of Token');
            Receipt storage receipt = proposal.receipts[tokenIds[i]];
            require(checkProof(_proofs[i], proposal.geoRoot, tokenIds[i]), "Sender not part of Geo Group");
            require(receipt.hasVoted == false, 'M2MonstersDAO::castVoteInternal: voter already voted');

            receipt.hasVoted = true;
            receipt.support = support;
            receipt.votes = 1;

            votes += 1;
        }

        if (support == 0) {
            proposal.votes.againstVotes = proposal.votes.againstVotes + votes;
            proposal.votes.geoAgainstVotes = proposal.votes.geoAgainstVotes + votes;
        } else if (support == 1) {
            proposal.votes.forVotes = proposal.votes.forVotes + votes;
            proposal.votes.geoForVotes = proposal.votes.geoForVotes + votes;
        } else if (support == 2) {
            proposal.votes.abstainVotes = proposal.votes.abstainVotes + votes;
        }

        return votes;
    }

    /**
     * @notice Admin function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function _setVotingDelay(uint256 newVotingDelay) external {
        require(msg.sender == admin, 'M2MonstersDAO::_setVotingDelay: admin only');
        require(
            newVotingDelay >= MIN_VOTING_DELAY && newVotingDelay <= MAX_VOTING_DELAY,
            'M2MonstersDAO::_setVotingDelay: invalid voting delay'
        );
        uint256 oldVotingDelay = votingDelay;
        votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, votingDelay);
    }

    /**
     * @notice Admin function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function _setVotingPeriod(uint256 newVotingPeriod) external {
        require(msg.sender == admin, 'M2MonstersDAO::_setVotingPeriod: admin only');
        require(
            newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD,
            'M2MonstersDAO::_setVotingPeriod: invalid voting period'
        );
        uint256 oldVotingPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
    }

    /**
     * @notice Admin function for setting the proposal threshold basis points
     * @dev newProposalThresholdBPS must be greater than the hardcoded min
     * @param newProposalThresholdBPS new proposal threshold
     */
    function _setProposalThresholdBPS(uint256 newProposalThresholdBPS) external {
        require(msg.sender == admin, 'M2MonstersDAO::_setProposalThresholdBPS: admin only');
        require(
            newProposalThresholdBPS >= MIN_PROPOSAL_THRESHOLD_BPS &&
                newProposalThresholdBPS <= MAX_PROPOSAL_THRESHOLD_BPS,
            'M2MonstersDAO::_setProposalThreshold: invalid proposal threshold'
        );
        uint256 oldProposalThresholdBPS = proposalThresholdBPS;
        proposalThresholdBPS = newProposalThresholdBPS;

        emit ProposalThresholdBPSSet(oldProposalThresholdBPS, proposalThresholdBPS);
    }

    /**
     * @notice Admin function for setting the quorum votes basis points
     * @dev newQuorumVotesBPS must be greater than the hardcoded min
     * @param newQuorumVotesBPS new proposal threshold
     */
    function _setQuorumVotesBPS(uint256 newQuorumVotesBPS) external {
        require(msg.sender == admin, 'M2MonstersDAO::_setQuorumVotesBPS: admin only');
        require(
            newQuorumVotesBPS >= MIN_QUORUM_VOTES_BPS && newQuorumVotesBPS <= MAX_QUORUM_VOTES_BPS,
            'M2MonstersDAO::_setProposalThreshold: invalid proposal threshold'
        );
        uint256 oldQuorumVotesBPS = quorumVotesBPS;
        quorumVotesBPS = newQuorumVotesBPS;

        emit QuorumVotesBPSSet(oldQuorumVotesBPS, quorumVotesBPS);
    }

    // Setters for voting thresholds
    /**
     * @notice msg.sender must be the executor contract
     */
    function setVotingDelay(uint256 _votingDelay) external {
        require(msg.sender == admin, 'M2MonstersDAO::setMinProposalThresholdBPS: admin only');
        votingDelay = _votingDelay;
    }

    function setVotingPeriod(uint256 _votingPeriod) external {
        require(msg.sender == admin, 'M2MonstersDAO::setVotingPeriod: admin only');
        votingPeriod = _votingPeriod;
    }

    function setProposalThresholdBPS(uint256 _proposalThresholdBPS) external {
        require(msg.sender == admin, 'M2MonstersDAO::setProposalThresholdBPS: admin only');
        proposalThresholdBPS = _proposalThresholdBPS;
    }

    function setQuorumVotesBPS(uint256 _quorumVotesBPS) external {
        require(msg.sender == admin, 'M2MonstersDAO::setQuorumVotesBPS: admin only');
        quorumVotesBPS = _quorumVotesBPS;
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function _setPendingAdmin(address newPendingAdmin) external {
        // Check caller = admin
        require(msg.sender == admin, 'M2MonstersDAO::_setPendingAdmin: admin only');

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function _acceptAdmin() external {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        require(msg.sender == pendingAdmin && msg.sender != address(0), 'M2MonstersDAO::_acceptAdmin: pending admin only');

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    /**
     * @notice Changes vetoer address
     * @dev Vetoer function for updating vetoer address
     */
    function _setVetoer(address newVetoer) public {
        require(msg.sender == vetoer, 'M2MonstersDAO::_setVetoer: vetoer only');

        emit NewVetoer(vetoer, newVetoer);

        vetoer = newVetoer;
    }

    /**
     * @notice Burns veto priviledges
     * @dev Vetoer function destroying veto power forever
     */
    function _burnVetoPower() public {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        require(msg.sender == vetoer, 'M2MonstersDAO::_burnVetoPower: vetoer only');

        _setVetoer(address(0));
    }

    /**
     * @notice Current proposal threshold using Noun Total Supply
     * Differs from `GovernerBravo` which uses fixed amount
     */
    function proposalThreshold() public view returns (uint256) {
        return bps2Uint(proposalThresholdBPS, monsters.totalSupply());
    }

    /**
     * @notice Current quorum votes using Noun Total Supply
     * Differs from `GovernerBravo` which uses fixed amount
     */
    function quorumVotes() public view returns (uint256) {
        return bps2Uint(quorumVotesBPS, monsters.totalSupply());
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }

    function getChainIdInternal() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    // function setMainRoot(bytes32 _root) external {
    //     require(msg.sender == admin, 'M2MonstersDAO::_setPendingAdmin: admin only');


    // }

    function checkProof(bytes32[] memory _proof, bytes32 _root, uint256 _id)
        internal
        view
        returns (bool)
    {
        return
            _proof.verify(
                _root,
                keccak256(abi.encodePacked(_id))
            );
    }
    function checkProofMain(bytes32[] memory _proof, bytes32 _root, bytes32 _geoRoot, uint256 _totalCities)
        internal
        view
        returns (bool)
    {
        return
            _proof.verify(
                _root,
                keccak256(abi.encodePacked(_geoRoot,_totalCities))
            );
    }

    function _calculatePercentage(uint256 _amount, uint256 _percentage)
        internal
        pure
        returns (uint256)
    {
        return (_amount * _percentage) / 10000;
    }
}

