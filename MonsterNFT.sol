// SPDX-License-Identifier: GPL-3.0


pragma solidity >=0.7.0 <0.9.0;

import "./base/ERC721Checkpointable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MonsterNFT is Ownable, ERC721Checkpointable {

    using Strings for uint256;

    string private baseTokenURI = "https:///";

    mapping(address => bool) public enabledMinter;  

    uint256 public maxSupply =  40000;  
    bool public paused = false;

    mapping(uint256 => uint256) public MonsterCategory; //ID to Int Status
    mapping(uint256 => uint256) public miscSetting;


    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI,
        uint256 _maxSupply
    ) ERC721(_name, _symbol){
        setBaseURI(_initBaseURI);
        maxSupply = _maxSupply;
    }

    // public
    function mint(address _to, uint256 _mintNumber) public {
        require(enabledMinter[msg.sender] , "!minter");
        require(!_exists(_mintNumber), "already minted!");
        uint256 supply = totalSupply();
        require(!paused, "paused" );
        require(supply + 1 <= maxSupply, "OverMaxSupply" );

        _safeMint(address(0),_to, _mintNumber, "");
    }

    function mintWithCategory(address _to, uint256 _mintNumber, uint256 _category) public {
        require(enabledMinter[msg.sender] , "!minter");
        uint256 supply = totalSupply();
        require(!paused, "paused" );
        require(supply + 1 <= maxSupply, "OverMaxSupply" );
        _safeMint(address(0),_to, _mintNumber, "");
        MonsterCategory[_mintNumber] = _category;
    }

    function _baseURI() internal view virtual override returns (string memory) {
      return baseTokenURI;
    }
    function setBaseURI(string memory _value) public onlyOwner{
      baseTokenURI = _value;
    }

    function setMinter(address _minter, bool _option) public onlyOwner {
      enabledMinter[_minter] = _option;
    }
    function setMisc(uint256[] calldata  _ids, uint256[] calldata  _values) public onlyOwner {
      require(_ids.length == _values.length, "Must provide equal ids and values" );
      for(uint256 i = 0; i < _ids.length; i++){
        miscSetting[_ids[i]] = _values[i];
      }
    }
    function setMonsterCategory(uint256[] calldata  _ids, uint256[] calldata  _values) public onlyOwner {
      require(_ids.length == _values.length, "Must provide equal ids and values" );
      for(uint256 i = 0; i < _ids.length; i++){
        MonsterCategory[_ids[i]] = _values[i];
      }
    }
    function pause(bool _state) public onlyOwner {
      paused = _state;
    }
}