// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./MonsterCapsule.sol";
import "./MonsterNFT.sol";

contract CapsuleConverter is Ownable, ReentrancyGuard {

    bool public paused;

    MonsterCapsule public monsterCapsules;
    MonsterNFT public monsterNFT;
    uint256 public currentQuota = 0;
    constructor(
        address _monsterCapsules,
        address _monsterNFT
    ) {
        monsterCapsules = MonsterCapsule(_monsterCapsules);
        monsterNFT = MonsterNFT(_monsterNFT);
    }

function pseudoRand() private view returns (uint256 _rand){
        return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
    }

    uint256[4] internal counters = [0,20000,10000,600]; //gen 1,2,3
    uint256[4] internal indexes = [400,20000,10000,600]; //End of Crown Monsters,gen 1,2,3

    mapping(uint => uint) openMapping;
    function getNFT(uint intialRandom, uint _gen) internal{
        uint pseudoRandom = intialRandom % counters[_gen];
        uint256 startIndex;
        for(uint i = _gen-1; i > 0; i --){
            startIndex += indexes[i];
        }
        pseudoRandom += startIndex;

        require(counters[_gen] > 0);
        if(openMapping[pseudoRandom] != 0){
            monsterNFT.mintWithCategory(msg.sender, openMapping[pseudoRandom], _gen);
        } else {
            monsterNFT.mintWithCategory(msg.sender, pseudoRandom, _gen);
        }
        if(openMapping[startIndex+counters[_gen]-1] != 0){
            openMapping[pseudoRandom] = openMapping[startIndex+counters[_gen]-1];
        } else {
            openMapping[pseudoRandom] = startIndex+counters[_gen]-1;
        }
        counters[_gen]--;
    }

    function mint(uint256 num, uint256 gen) internal {
        require(!paused,                   "Sale paused");
        require(num <= currentQuota, "Greater than currentQuota");

        uint pseudoRandom = pseudoRand();

        for(uint i = 0; i < num; i++){
            uint currentValue = uint(keccak256(abi.encode(pseudoRandom, i)));
            getNFT(currentValue, gen);
        }
        currentQuota -= num;
    }

    function convertCapsules(uint256[] memory ids, uint256[] memory amounts) public nonReentrant{
        require(ids.length == amounts.length, "ERC1155: amounts and ids length mismatch");

        for (uint256 i = 0; i < ids.length; ++i) {
            require(ids[i] < monsterCapsules.maxGenerations());
            require(monsterCapsules.balanceOf(msg.sender, ids[i]) >= amounts[i], "Insufficient amount");
            //Revisar allowance all?
            mint(amounts[i],ids[i]);
        }
        monsterCapsules.burnBatch(msg.sender, ids, amounts);
    }

    function addToQuota(uint256 _value) external onlyOwner{
        currentQuota += _value;
    }

    function setPause(bool _value) external onlyOwner{
        paused = _value;
    }

}
