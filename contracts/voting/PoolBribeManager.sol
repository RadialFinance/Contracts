//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolVoting {
    function getUserVoteData(address user, address pool, uint256 week) external returns(int256, int256);
    function poolRewardWeight(address pool, uint256 week) external returns(uint256);
}

contract PoolBribeManager {
    uint256 constant WEEK = 60*60*24*7;

    uint256 immutable FUTURE_WEEKS_TO_BRIBE;
    uint256 immutable START_TIME;
    IPoolVoting immutable POOL_VOTING;

    // briber -> pool -> week -> token -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => mapping(address => uint256)))) bribes;
    // briber -> pool -> week -> token -> isClaimed
    mapping(address => mapping(address => mapping(uint256 => mapping(address => bool)))) bribeClaimed;
    // pool -> week -> token -> bribeAmount
    mapping(address => mapping(uint256 => mapping(address => uint256))) poolBribes;

    constructor(address _poolVoting, uint256 _startTime, uint256 _futureWeeksToBribe) {
        POOL_VOTING = IPoolVoting(_poolVoting);
        START_TIME = _startTime;
        FUTURE_WEEKS_TO_BRIBE = _futureWeeksToBribe;
    }

    function deposit(address _pool, uint256 _week, address[] memory _bribeTokens, uint256[] memory _bribeAmounts) external {
        require(_bribeTokens.length == _bribeAmounts.length, "Invalid inputs");
        uint256 _currentWeek = getWeek();
        require(_week > _currentWeek && _week <= _currentWeek + FUTURE_WEEKS_TO_BRIBE, "Can bribe only for next few weeks");
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            uint256 _amount = _bribeAmounts[i];
            require(_amount != 0, "0 bribe");

            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            bribes[msg.sender][_pool][_currentWeek][_token] += _amount;
            poolBribes[_pool][_currentWeek][_token] += _amount;
        }
    }

    function withdraw(address _pool, uint256 _week, address[] memory _bribeTokens) external {
        uint256 _currentWeek = getWeek();
        require(_week > _currentWeek, "only past weeks");
        require(POOL_VOTING.poolRewardWeight(_pool, _currentWeek) == 0, "users voted");
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            uint256 _amount = bribes[msg.sender][_pool][_week][_token];

            if(_amount == 0) continue;

            delete bribes[msg.sender][_token][_week][_token];
            poolBribes[_token][_week][_token] -= _amount;

            IERC20(_token).transfer(msg.sender, _amount);
        }
    }

    function claimBribes(address _pool, uint256 _week, address[] memory _bribeTokens) external {
        uint256 _currentWeek = getWeek();
        require(_week > _currentWeek, "only past weeks");
        (int256 _userVote, int256 _totalPoolVotes) = POOL_VOTING.getUserVoteData(msg.sender, _pool, _week);
        require(_userVote >  0 && _totalPoolVotes > 0, "not voted for pool");
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            require(!bribeClaimed[msg.sender][_pool][_week][_token], "claimed");
            uint256 _totalPoolBribe = poolBribes[_pool][_week][_token];
            uint256 _userBribe = uint256(_userVote) * _totalPoolBribe / uint256(_totalPoolVotes);
            bribeClaimed[msg.sender][_pool][_week][_token] = true;

            IERC20(_token).transfer(msg.sender, _userBribe);
        }
    }

    function getWeek() public view returns (uint256) {
        return (block.timestamp - START_TIME) / WEEK;
    }
}
