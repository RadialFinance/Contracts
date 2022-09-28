//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IRDLInflationManager.sol";
import "../interfaces/IPoolVoting.sol";

interface ISolidlyVoter {
    function gauges(address pool) external returns(address);
}

contract PoolBribeManager {
    uint256 constant WEEK = 60*60*24*7;

    uint256 immutable FUTURE_WEEKS_TO_BRIBE;
    uint256 immutable START_TIME;
    IPoolVoting immutable POOL_VOTING;
    IERC20 immutable RDL;
    ISolidlyVoter immutable SOLIDLY_VOTER;
    IRDLInflationManager immutable RDL_INFLATION_MANAGER;

    // briber -> pool -> week -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public bribes;
    // briber -> pool -> week -> isClaimed
    mapping(address => mapping(address => mapping(uint256 => bool))) bribeClaimed;
    // user -> week -> isClaimed
    mapping(address => mapping(uint256 => bool)) public rdlClaimed;
    // pool -> week -> bribeAmount
    mapping(address => mapping(uint256 => uint256)) poolBribes;

    event BribeDeposited(address indexed user, address indexed pool, uint256 indexed week, uint256 bribeAmount);
    event BribeWithdrawn(address indexed user, address indexed pool, uint256 indexed week, uint256 bribeAmount);
    event BribeClaimed(address indexed user, address indexed pool, uint256 indexed week, uint256 amount);
    event RDLClaimed(address indexed user, uint256 indexed week, uint256 amount);

    constructor(address _poolVoting, address _rdl, address _solidlyVoter, address _rdlInflationManager, uint256 _startTime, uint256 _futureWeeksToBribe) {
        POOL_VOTING = IPoolVoting(_poolVoting);
        RDL = IERC20(_rdl);
        SOLIDLY_VOTER = ISolidlyVoter(_solidlyVoter);
        RDL_INFLATION_MANAGER = IRDLInflationManager(_rdlInflationManager);
        START_TIME = _startTime;
        FUTURE_WEEKS_TO_BRIBE = _futureWeeksToBribe;
    }

    function deposit(address _pool, uint256 _week, uint256 _bribeAmount) external payable {
        uint256 _currentWeek = getWeek();
        require(SOLIDLY_VOTER.gauges(_pool) != address(0), "Pool doesnt have gauge");
        require(_week > _currentWeek && _week <= _currentWeek + FUTURE_WEEKS_TO_BRIBE, "Can bribe only for next few weeks");
        require(_bribeAmount != 0, "0 bribe");
        require(msg.value == _bribeAmount, "Insufficient tokens");

        bribes[msg.sender][_pool][_week] += _bribeAmount;
        poolBribes[_pool][_week] += _bribeAmount;
        emit BribeDeposited(msg.sender, _pool, _week, _bribeAmount);
    }

    function withdraw(address _pool, uint256 _week) external {
        uint256 _currentWeek = getWeek();
        require(_week < _currentWeek, "only past weeks");
        require(POOL_VOTING.poolRewardWeight(_pool, _currentWeek) == 0, "users voted");
        uint256 _amount = bribes[msg.sender][_pool][_week];
        require(_amount != 0, "No bribes");

        delete bribes[msg.sender][_pool][_week];
        poolBribes[_pool][_week] -= _amount;

        payable(msg.sender).transfer(_amount);
        emit BribeWithdrawn(msg.sender, _pool, _week, _amount);
    }

    function claimBribes(address[] memory _pools, uint256 _week) external {
        uint256 _currentWeek = getWeek();
        require(_week < _currentWeek, "only past weeks");
        uint256 _totalBribe;
        for(uint256 i=0; i < _pools.length; i++) {
            address _pool = _pools[i];
            (int256 _userVote, int256 _totalPoolVotes) = POOL_VOTING.getUserVoteData(msg.sender, _pool, _week);
            require(_userVote >  0 && _totalPoolVotes > 0, "not voted for pool");
            require(!bribeClaimed[msg.sender][_pool][_week], "claimed");
            uint256 _totalPoolBribe = poolBribes[_pool][_week];
            uint256 _userBribe = uint256(_userVote) * _totalPoolBribe / uint256(_totalPoolVotes);
            bribeClaimed[msg.sender][_pool][_week] = true;

            _totalBribe += _userBribe;
            emit BribeClaimed(msg.sender, _pool, _week, _userBribe);
        }

        payable(msg.sender).transfer(_totalBribe);
    }

    function claimBribes(address _pool, uint256 _week) external {
        uint256 _currentWeek = getWeek();
        require(_week < _currentWeek, "only past weeks");
        (int256 _userVote, int256 _totalPoolVotes) = POOL_VOTING.getUserVoteData(msg.sender, _pool, _week);
        require(_userVote >  0 && _totalPoolVotes > 0, "not voted for pool");
        require(!bribeClaimed[msg.sender][_pool][_week], "claimed");
        uint256 _totalPoolBribe = poolBribes[_pool][_week];
        uint256 _userBribe = uint256(_userVote) * _totalPoolBribe / uint256(_totalPoolVotes);
        bribeClaimed[msg.sender][_pool][_week] = true;

        payable(msg.sender).transfer(_userBribe);
        emit BribeClaimed(msg.sender, _pool, _week, _userBribe);
    }

    function getRDLToClaim(address _user, uint256[] memory _weeks) external returns(uint256[] memory) {
        uint256[] memory _rdlToClaim = new uint256[](_weeks.length);
        for(uint256 i=0; i < _weeks.length; i++) {
            uint256 _week = _weeks[i];
            (uint256 _userWeeklyVotes, uint256 _totalWeeklyVotes) = POOL_VOTING.getWeeklyVoteData(_user, _week);
            if(_userWeeklyVotes == 0 || _totalWeeklyVotes == 0 || rdlClaimed[_user][_week]) {
                _rdlToClaim[i] = 0;
                continue;
            }
            uint256 _weeklyInflation = RDL_INFLATION_MANAGER.getRDLForWeek(_week);
            uint256 _amount = _weeklyInflation*_userWeeklyVotes/_totalWeeklyVotes;
            _rdlToClaim[i] = _amount;
        }
        return _rdlToClaim;
    }

    function claimRDL(uint256[] memory _weeks) external {
        for(uint256 i=0; i < _weeks.length; i++) {
            claimRDL(_weeks[i]);
        }
    }

    function claimRDL(uint256 _week) public {
        (uint256 _userWeeklyVotes, uint256 _totalWeeklyVotes) = POOL_VOTING.getWeeklyVoteData(msg.sender, _week);
        require(_userWeeklyVotes != 0 && _totalWeeklyVotes != 0, "not voted for pool");
        require(!rdlClaimed[msg.sender][_week], "claimed");
        rdlClaimed[msg.sender][_week] = true;
        uint256 _weeklyInflation = RDL_INFLATION_MANAGER.getRDLForWeek(_week);
        uint256 _amount = _weeklyInflation*_userWeeklyVotes/_totalWeeklyVotes;

        RDL.transfer(msg.sender, _amount);
        emit RDLClaimed(msg.sender, _week, _amount);
    }

    function getWeek() public view returns (uint256) {
        return (block.timestamp - START_TIME) / WEEK;
    }
}
