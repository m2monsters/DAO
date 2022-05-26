// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./MonsterNFT.sol";

contract MonsterAuction is Ownable, IERC721Receiver {
    // Events would be used for frontend to track the auction
    event LogBid(address indexed bidder, uint256 bid, uint256 monster);
    event Refund(address indexed bidder, uint256 bid, uint256 monster);

    MonsterNFT public monsterNFT;
    IERC20 public erc20;

    uint256 internal counter = 400;
    uint256 internal startIndex = 0;

    mapping(uint256 => uint256) openMapping;

    uint256 public timeStart;
    uint256 public timeEnd;
    uint256 public duration; // should be 380 as stated in document

    // batch => [monsterIDs]
    uint256[] public monsters;

    bool public paused;

    address public highestBidder1;
    uint256 public highestBid1;

    // day => [bidderAddrAsUint, bidAmount, monsterId, block.timestamp]
    mapping(uint256 => uint256[4][]) public bids1;

    // day => [monsterIds]
    mapping(uint256 => uint256) public dailyMonster;

    uint256 public dailyDuration = 82800;
    uint256 public lastExecutionTime = 0;
    uint256 public nextExecutionTime = 0;
    uint256 public lastExecutedDay = 0;
    uint256 public maxExecutionPeriod = 14400; // Defaulting to 4 hours
    bool private initialAuctionSet = false;

    constructor(
        address _monsterNFT,
        address _erc20,
        uint256 _startTime,
        uint256 _duration
    ) {
        monsterNFT = MonsterNFT(_monsterNFT);
        erc20 = IERC20(_erc20);
        paused = false;
        timeStart = _startTime;
        duration = _duration * 1 days;
        timeEnd = timeStart + duration;
    }

    function placeBid(uint256 _bid, uint256 _monsterPosition) external {
        require(!paused, "contract is paused");
        require(block.timestamp > timeStart, "not started");
        require(
            erc20.allowance(msg.sender, address(this)) >= _bid,
            "msg.sender must approve token"
        );
        require(erc20.balanceOf(msg.sender) >= _bid, "insufficient funds");

        // This tell us in which day we are and we use it as id
        uint256 daysSinceStart = (block.timestamp - timeStart) / 60 / 60 / 24;
        uint256 currDay = daysSinceStart + 1; // we add to make 3800 days exactly
        require(currDay <= duration, "auction is over");
        require(
            block.timestamp - lastExecutionTime < dailyDuration,
            "auction on execution period"
        );

        // Convert the msg.sender address to uint256 type in order to store in bids matrix
        uint256 convertedAddr = _addrToUint256(msg.sender);

        uint256 _monsterId = dailyMonster[currDay];
        require(
            _bid > highestBid1,
            "you cannot bid a lower amount than the actual higher"
        );

        erc20.transferFrom(msg.sender, address(this), _bid);

        uint256 previousHighBid = highestBid1;
        address previousHighBidder = highestBidder1;

        highestBid1 = _bid;
        highestBidder1 = msg.sender;

        bids1[currDay].push([convertedAddr, _bid, _monsterId, block.timestamp]);

        returnFunds(previousHighBid, previousHighBidder, _monsterPosition);

        emit LogBid(msg.sender, _bid, _monsterId);
    }

    function returnFunds(
        uint256 _bid,
        address _receiver,
        uint256 _monster
    ) internal {
        if (_receiver != address(0)) {
            erc20.transfer(_receiver, _bid);
            emit Refund(_receiver, _bid, _monster);
        }
    }

    function getMonstersByDay(uint256 _day) public view returns (uint256) {
        return dailyMonster[_day];
    }

    function getBids(uint256 _day) public view returns (uint256[4][] memory) {
        uint256[4][] memory _bids;

        _bids = bids1[_day];

        return _bids;
    }

    function execute(uint256 _day) external {
        require(lastExecutedDay <= _day, "already executed day");
        require(
            block.timestamp - lastExecutionTime > dailyDuration,
            "too soon"
        );


        // Send monster to winner only if there was at least one bid
        if (highestBidder1 != address(0)) {
            // Send monsters to winners
            uint256 monster1 = dailyMonster[_day];
            address winner1 = _uint256ToAddr(
                bids1[_day][bids1[_day].length - 1][0]
            );
            monsterNFT.safeTransferFrom(address(this), winner1, monster1);

            // RESET bids
            highestBid1 = 0;
            highestBidder1 = address(0);

            setMonstersForDailyAuction(_day + 1);
        } else {
            // Moves the current monster to the next day
            dailyMonster[_day + 1] = dailyMonster[_day];
        }

        lastExecutedDay = _day;
        uint256 timeToCompleteTheDay = 86400 - currentDayElapsedTime();
        // if is too late
        if (
            block.timestamp - lastExecutionTime <=
            dailyDuration + 3600 + maxExecutionPeriod
        ) {
            lastExecutionTime = block.timestamp + timeToCompleteTheDay;
        } else {
            lastExecutionTime = nextExecutionTime;
        }

        nextExecutionTime = lastExecutionTime + 1 days;
    }

    function setInitialAuction() external onlyOwner {
        require(!initialAuctionSet, "Initial auction already set");
        setMonstersForDailyAuction(1);
        initialAuctionSet = true;
        lastExecutionTime = block.timestamp;
        nextExecutionTime = block.timestamp + 1 days;
    }

    function setMonstersForDailyAuction(uint256 _day) internal {
        uint256 pseudoRandom = pseudoRand();

        getNFT(uint256(keccak256(abi.encode(pseudoRandom, 0))), _day);
    }

    function pauseAuction(bool _value) external onlyOwner {
        paused = _value;
    }

    // hours in seconds
    function setMaxExecutionPeriod(uint256 _value) external onlyOwner {
        maxExecutionPeriod = _value;
    }

    // UTILS
    function currentDayElapsedTime() public view returns (uint256) {
        return (block.timestamp - timeStart) % 86400;
    }

    function _addrToUint256(address a) internal pure returns (uint256) {
        return uint256(uint160(a));
    }

    function _uint256ToAddr(uint256 a) internal pure returns (address) {
        return address(uint160(a));
    }

    function pseudoRand() private view returns (uint256 _rand) {
        return
            uint256(
                keccak256(abi.encodePacked(block.difficulty, block.timestamp))
            );
    }

    function getNFT(uint256 _initialRandom, uint256 _day) internal {
        uint256 pseudoRandom = _initialRandom % counter;
        pseudoRandom += startIndex;

        _day = _day;

        if (openMapping[pseudoRandom] != 0) {
            monsterNFT.mint(address(this), openMapping[pseudoRandom]);
            dailyMonster[_day] = openMapping[pseudoRandom];
        } else {
            monsterNFT.mint(address(this), pseudoRandom);
            dailyMonster[_day] = pseudoRandom;
        }
        if (openMapping[startIndex + counter - 1] != 0) {
            openMapping[pseudoRandom] = openMapping[startIndex + counter - 1];
        } else {
            openMapping[pseudoRandom] = startIndex + counter - 1;
        }

        counter--;

        if (counter == 0) {
            //Change startIndex
            startIndex += 500;
            //Set counter again
            counter = 500;
        }
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
