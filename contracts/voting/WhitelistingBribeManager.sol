//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDepositor {
    function whitelist(address _token, int256 _votes) external;
}

interface IRadialVoting {
    function getVotingPower(address user) external returns(uint256);
}

contract WhitelistingBribeManager {
    uint256 constant WEEK = 60*60*24*7;
    IDepositor immutable DEPOSITOR;
    IRadialVoting immutable RADIAL_VOTING;
    uint256 immutable START_TIME;
    mapping(address => bool) isWhitelisted;
    // briber -> tokenToWhitelist -> week -> token -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => mapping(address => uint256)))) bribes;
    // user -> tokenToWhitelist -> week -> token -> bribeAmount
    mapping(address => mapping(address => mapping(uint256 => mapping(address => bool)))) bribeClaimed;
    // tokenToWhitelist -> week -> token -> bribeAmount
    mapping(address => mapping(uint256 => mapping(address => uint256))) tokenBribes;
    // user -> tokenToWhitelist -> week -> votes
    mapping(address => mapping(address => mapping(uint256 => uint256))) votesUsed;
    // user -> tokenToWhitelist -> week -> votes
    mapping(address => mapping(address => mapping(uint256 => int256))) votes;
    // tokenToWhitelist -> week -> votes
    mapping(address => mapping(uint256 => int256)) tokenVotes;
    // tokenToWhitelist -> week -> votes
    mapping(address => mapping(uint256 => uint256)) totalRewardWeight;

    constructor(address _depositor, address _radialVoting, uint256 _startTime) {
        DEPOSITOR = IDepositor(_depositor);
        RADIAL_VOTING = IRadialVoting(_radialVoting);
        START_TIME = _startTime;
    }

    // TODO: Investigate possibility of attacks using tokens with receive callbacks
    function deposit(address _tokenToWhitelist, address[] memory _bribeTokens, uint256[] memory _bribeAmounts) external {
        require(!isWhitelisted[_tokenToWhitelist], "already whitelisted");
        require(_bribeTokens.length == _bribeAmounts.length, "Invalid inputs");
        uint256 _currentWeek = getWeek();
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            uint256 _amount = _bribeAmounts[i];
            require(_amount != 0, "0 bribe");

            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            bribes[msg.sender][_tokenToWhitelist][_currentWeek][_token] += _amount;
            tokenBribes[_tokenToWhitelist][_currentWeek][_token] += _amount;
        }
    }

    function withdraw(address _tokenToWhitelist, uint256 _week, address[] memory _bribeTokens) external {
        require(!isWhitelisted[_tokenToWhitelist], "whitelisted");
        uint256 _currentWeek = getWeek();
        require(_week > _currentWeek, "proposal not over");
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            uint256 _amount = bribes[msg.sender][_tokenToWhitelist][_week][_token];

            if(_amount == 0) continue;

            delete bribes[msg.sender][_tokenToWhitelist][_week][_token];
            delete tokenBribes[_tokenToWhitelist][_week][_token];

            IERC20(_token).transfer(msg.sender, _amount);
        }
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
    }

    function whitelist(address _tokenToWhitelist) external {
        uint256 _currentWeek = getWeek();
        DEPOSITOR.whitelist(_tokenToWhitelist, tokenVotes[_tokenToWhitelist][_currentWeek]);
        isWhitelisted[_tokenToWhitelist] = true;
    }

    function claimBribes(address _whitelistedToken, uint256 _week, address[] memory _bribeTokens) external {
        require(isWhitelisted[_whitelistedToken], "not whitelisted");
        int256 _userVote = votes[msg.sender][_whitelistedToken][_week];
        uint256 _totalTokenVotes = totalRewardWeight[_whitelistedToken][_week];
        require(_userVote > 0 && _totalTokenVotes > 0, "not voted for token");
        for(uint256 i; i < _bribeTokens.length; i++) {
            address _token = _bribeTokens[i];
            require(!bribeClaimed[msg.sender][_whitelistedToken][_week][_token], "claimed");
            uint256 _totalTokenBribe = tokenBribes[_whitelistedToken][_week][_token];
            uint256 _userBribe = uint256(_userVote) * _totalTokenBribe / _totalTokenVotes;
            bribeClaimed[msg.sender][_whitelistedToken][_week][_token] = true;

            IERC20(_token).transfer(msg.sender, _userBribe);
        }
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
