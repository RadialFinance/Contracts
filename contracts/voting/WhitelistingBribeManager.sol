//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IRadialVoting.sol";
import "../interfaces/IDepositor.sol";

contract WhitelistingBribeManager {
    uint256 constant WEEK = 60*60*24*7;
    IDepositor immutable DEPOSITOR;
    IRadialVoting immutable RADIAL_VOTING;
    uint256 immutable START_TIME;

    mapping(address => bool) public isWhitelisted;
    // briber -> tokenToWhitelist -> week -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public bribes;
    // user -> tokenToWhitelist -> week -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => bool))) public bribeClaimed;
    // tokenToWhitelist -> week -> bribeAmount
    mapping(address => mapping(uint256 => uint256)) public tokenBribes;
    // user -> tokenToWhitelist -> week -> votes
    mapping(address => mapping(address => mapping(uint256 => uint256))) votesUsed;
    // user -> tokenToWhitelist -> week -> votes
    mapping(address => mapping(address => mapping(uint256 => int256))) votes;
    // tokenToWhitelist -> week -> votes
    mapping(address => mapping(uint256 => int256)) tokenVotes;
    // tokenToWhitelist -> week -> votes
    mapping(address => mapping(uint256 => uint256)) public totalRewardWeight;

    event BribeDeposited(address indexed user, address indexed tokenToWhitelist, uint256 indexed week, uint256 bribeAmount);
    event BribeWithdrawn(address indexed user, address indexed tokenToWhitelist, uint256 indexed week, uint256 bribeAmount);
    event Voted(address indexed user, address indexed tokenToWhitelist, uint256 indexed week, int256 votes);
    event BribeClaimed(address indexed user, address indexed whitelistedToken, uint256 indexed week, uint256 amount);
    event TokenWhitelistedInSolidly(address indexed token, int256 votes, uint256 currentWeek);

    constructor(address _depositor, address _radialVoting, uint256 _startTime) {
        DEPOSITOR = IDepositor(_depositor);
        RADIAL_VOTING = IRadialVoting(_radialVoting);
        START_TIME = _startTime;
    }

    function deposit(address _tokenToWhitelist, uint256 _bribeAmount) external payable {
        require(!isWhitelisted[_tokenToWhitelist], "already whitelisted");
        uint256 _currentWeek = getWeek();
        require(_bribeAmount != 0, "0 bribe");
        require(msg.value == _bribeAmount, "Insufficient tokens");

        bribes[msg.sender][_tokenToWhitelist][_currentWeek] += _bribeAmount;
        tokenBribes[_tokenToWhitelist][_currentWeek] += _bribeAmount;
        emit BribeDeposited(msg.sender, _tokenToWhitelist, _currentWeek, _bribeAmount);
    }

    function withdraw(address _tokenToWhitelist, uint256 _week) external {
        require(!isWhitelisted[_tokenToWhitelist], "whitelisted");
        uint256 _currentWeek = getWeek();
        require(_week < _currentWeek, "proposal not over");
        uint256 _amount = bribes[msg.sender][_tokenToWhitelist][_week];
        require(_amount != 0, "no bribe");

        delete bribes[msg.sender][_tokenToWhitelist][_week];
        tokenBribes[_tokenToWhitelist][_week] -= _amount;

        payable(msg.sender).transfer(_amount);
        emit BribeWithdrawn(msg.sender, _tokenToWhitelist, _week, _amount);
    }

    function vote(address _tokenWhitelist, int256 _votes) external {
        require(!isWhitelisted[_tokenWhitelist], "whitelisted");
        uint256 _maxVotes = RADIAL_VOTING.getVotingPower(msg.sender);
        uint256 _currentWeek = getWeek();
        uint256 _usedVotes = votesUsed[msg.sender][_tokenWhitelist][_currentWeek];
        uint256 _absVotes = abs(_votes);
        require(_usedVotes + _absVotes <= _maxVotes, "more than voting power");

        tokenVotes[_tokenWhitelist][_currentWeek] += _votes;
        int256 _prevUserVotes = votes[msg.sender][_tokenWhitelist][_currentWeek];
        int256 _newUserVotes = _prevUserVotes + _votes;
        int256 _poolRewardWeight = int256(totalRewardWeight[_tokenWhitelist][_currentWeek]);
        if(_prevUserVotes < 0 && _newUserVotes > 0) {
            _poolRewardWeight += _newUserVotes;
        } else if(_prevUserVotes > 0 && _newUserVotes < 0) {
            _poolRewardWeight -= _prevUserVotes;
        } else if(_prevUserVotes >= 0 && _newUserVotes >= 0) {
            _poolRewardWeight += _votes;
        }
        totalRewardWeight[_tokenWhitelist][_currentWeek] = uint256(_poolRewardWeight);
        votes[msg.sender][_tokenWhitelist][_currentWeek] = _newUserVotes;
        votesUsed[msg.sender][_tokenWhitelist][_currentWeek] = _usedVotes + _absVotes;
        emit Voted(msg.sender, _tokenWhitelist, _currentWeek, _votes);
    }

    function whitelist(address _tokenToWhitelist) external {
        require(!isWhitelisted[_tokenToWhitelist], "whitelisted");
        uint256 _currentWeek = getWeek();
        int256 _votes = tokenVotes[_tokenToWhitelist][_currentWeek];
        DEPOSITOR.whitelist(_tokenToWhitelist, _votes);
        isWhitelisted[_tokenToWhitelist] = true;
        emit TokenWhitelistedInSolidly(_tokenToWhitelist, _votes, _currentWeek);
    }

    function claimBribes(address[] memory _whitelistedTokens, uint256[] memory _weeks) external {
        require(_whitelistedTokens.length == _weeks.length, "invalid inputs");
        for(uint256 i=0; i < _weeks.length; i++) {
            claimBribes(_whitelistedTokens[i], _weeks[i]);
        }
    }

    function claimBribes(address _whitelistedToken, uint256 _week) public {
        require(isWhitelisted[_whitelistedToken], "not whitelisted");
        int256 _userVote = votes[msg.sender][_whitelistedToken][_week];
        uint256 _totalTokenVotes = totalRewardWeight[_whitelistedToken][_week];
        require(_userVote > 0 && _totalTokenVotes > 0, "not voted for token");
        require(!bribeClaimed[msg.sender][_whitelistedToken][_week], "claimed");
        bribeClaimed[msg.sender][_whitelistedToken][_week] = true;
        uint256 _totalTokenBribe = tokenBribes[_whitelistedToken][_week];
        uint256 _userBribe = uint256(_userVote) * _totalTokenBribe / _totalTokenVotes;

        payable(msg.sender).transfer(_userBribe);
        emit BribeClaimed(msg.sender, _whitelistedToken, _week, _userBribe);
    }

    function getWeek() public view returns (uint256) {
        return (block.timestamp - START_TIME) / WEEK;
    }

    // Imported from OZ SignedMath https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.7/contracts/utils/math/SignedMath.sol#L37
    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}
