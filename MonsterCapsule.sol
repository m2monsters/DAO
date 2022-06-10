// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MonsterCapsule is ERC1155, Ownable {
    // Keep track of generations
    using Counters for Counters.Counter;
    //In order to simplify things for clients we track generations with a counter.
    Counters.Counter public generationCounter;
    mapping(uint256 => uint256) public generations;
    mapping(uint256 => uint256) public generationsMax;
    uint256 public maxSupply = 0;
    uint256 public currentSupply = 0;

    // Contract whitelist
    mapping(address => bool) public contractWhitelist;

    uint public maxGenerations = 3;

    uint256 public minGeneration = 1;

    bool public paused;

    // TODO: Change url to the production one
    constructor(uint256 _maxSupply)
        ERC1155(
            "https:///capsule/{id}"
        )
    {
        paused = false;
        maxSupply = _maxSupply;
    }

    function setBaseURI(string memory _value) public onlyOwner{
        _setURI(_value);
    }

    function setMaxPerGen(uint256 _gen, uint _value) public onlyOwner{
        require(_value <= maxGenerations && _value >= minGeneration, "invalid value");
        generationsMax[_gen] = _value;
    }

    function mint(address _recipient, uint256 _amount, uint256 _generation)
        external
        onlyWhitelisted
    {
        require(!paused, "Contract is paused.");
        require(_generation >= minGeneration, "gen < 1");
        require(_generation <= maxGenerations, "gen > 3");
        require(currentSupply + 1 <= maxSupply, "over max supply");
        require(generations[_generation] + _amount < generationsMax[_generation], "> max per gen");
        generations[_generation] += _amount;
        currentSupply ++;
        _mint(_recipient, _generation, _amount, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public virtual {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _burn(account, id, value);
    }

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) public virtual {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "ERC1155: caller is not owner nor approved"
        );
        _burnBatch(account, ids, values);
    }

    function whitelistContract(address _contract, bool _whitelisted)
        external
        onlyOwner
    {
        contractWhitelist[_contract] = _whitelisted;
    }

    function isWhitelisted(address _contract) public view returns (bool) {
        return contractWhitelist[_contract];
    }

    function pauseContract(bool _paused) external onlyOwner {
        paused = _paused;
    }

    modifier onlyWhitelisted() {
        require(contractWhitelist[msg.sender], "Not whitelisted.");
        _;
    }
}