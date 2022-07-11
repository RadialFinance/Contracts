//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISolidVoter {
    function whitelist(address token, uint256 tokenId) external;
    function vote(uint tokenId, address[] calldata _poolVote, int256[] calldata _weights) external;
    function gauges(address pool) external returns(address gauge);
}

interface ISolidMinter {
    function update_period() external;
}

interface ISolidGauge {
    function getReward(address account, address[] memory tokens) external;
    function deposit(uint amount, uint tokenId) external;
    function withdraw(uint amount) external;
}

contract Depositor {
    address immutable LP_MANAGER;
    address immutable WHITELISTING_BRIBE_MANAGER;
    IERC20 immutable RDL;
    IERC20 immutable SOLID;
    address immutable POOL_VOTING;
    ISolidMinter immutable SOLID_MINTER;
    ISolidVoter immutable SOLID_VOTER;

    uint256 constant SCALING_FACTOR = 1e18;
    uint256 constant RADIAL_NFT_ID = 12;

    uint256 whitelistThreshold;

    mapping(address => uint256) cummulativeRewardPerToken;
    mapping(address => mapping(address => uint256)) userCummulativeRewardPerToken;
    mapping(address => mapping(address => uint256)) claimable;
    mapping(address => uint256) totalPoolLPDeposits;

    mapping(address => address) gaugeForPool;

    modifier onlyLPManager {
        require(msg.sender == LP_MANAGER, "unauthorized");
        _;
    }

    constructor(
        uint256 _whitelistThreshold,
        address _lpManager, 
        address _whitelistingBribeManager, 
        address _rdl, 
        address _solid, 
        address _poolVoting, 
        address _solidMinter, 
        address _solidVoter
    ) {
        whitelistThreshold = _whitelistThreshold;
        LP_MANAGER = _lpManager;
        WHITELISTING_BRIBE_MANAGER = _whitelistingBribeManager;
        RDL = IERC20(_rdl);
        SOLID = IERC20(_solid);
        POOL_VOTING = _poolVoting;
        SOLID_MINTER = ISolidMinter(_solidMinter);
        SOLID_VOTER = ISolidVoter(_solidVoter);
    }

    function whitelist(address _token, int256 _votes) public {
        require(msg.sender == WHITELISTING_BRIBE_MANAGER, "unauthorized");
        require(_votes > 0 && RDL.totalSupply()*whitelistThreshold/SCALING_FACTOR <= uint256(_votes), "Not enough votes");
        SOLID_VOTER.whitelist(_token, RADIAL_NFT_ID);
    }

    function vote(address[] memory _pools, int256[] memory _weights) public {
        require(msg.sender == POOL_VOTING, "unauthorized");
        require(_pools.length == _weights.length, "invalid inputs");
        SOLID_MINTER.update_period();
        SOLID_VOTER.vote(RADIAL_NFT_ID, _pools, _weights);
    }

    function receiveLP(address _from, address _pool, uint256 _amount, uint256 _currentBalance) public onlyLPManager {
        require(_amount != 0, "0 deposit");
        uint256 _currentPoolDeposits = totalPoolLPDeposits[_pool];
        address _gauge = gaugeForPool[_pool];
        if(_gauge == address(0)) {
            _gauge = SOLID_VOTER.gauges(_pool);
            require(_gauge != address(0), "No gauge");
            gaugeForPool[_pool] = _gauge;
            IERC20(_pool).approve(_gauge, type(uint256).max);
        } else {
            _updateRewards(_pool, _gauge, _currentPoolDeposits);
            _updateUserRewards(_from, _pool, _currentBalance);
        }

        ISolidGauge(_gauge).deposit(_amount, RADIAL_NFT_ID);
        totalPoolLPDeposits[_pool] = _currentPoolDeposits + _amount;
    }

    function withdrawLP(address _from, address _pool, uint256 _amount, uint256 _currentBalance) public onlyLPManager {
        require(_amount != 0, "0 deposit");
        uint256 _currentPoolDeposits = totalPoolLPDeposits[_pool];
        address _gauge = gaugeForPool[_pool];
        _updateRewards(_pool, _gauge, _currentPoolDeposits);
        _updateUserRewards(_from, _pool, _currentBalance);

        totalPoolLPDeposits[_pool] = _currentPoolDeposits - _amount;

        ISolidGauge(_gauge).withdraw(_amount);
        IERC20(_pool).transfer(_from, _amount);
    }

    function claimSolidRewards(address _user, address[] calldata _pools, uint256[] calldata _currentBalances) external onlyLPManager {
        uint256 _claimedAmount;

        for(uint256 i; i < _pools.length; i++) {
            address _pool = _pools[i];
            address _gauge = gaugeForPool[_pool];
            uint256 _currentPoolDeposits = totalPoolLPDeposits[_pool];
            _updateRewards(_pool, _gauge, _currentPoolDeposits);
            _updateUserRewards(_user, _pool, _currentBalances[i]);
            _claimedAmount += claimable[_user][_pool];
        }

        if(_claimedAmount != 0) {
            SOLID.transfer(_user, _claimedAmount);
        }
    }

    function _updateRewards(address _pool, address _gauge, uint256 _totalPoolLPDeposits) internal {
        if(_totalPoolLPDeposits != 0) {
            uint256 _initialBalance = SOLID.balanceOf(address(this));
            address[] memory _tokens;
            _tokens[0] =  address(SOLID);
            ISolidGauge(_gauge).getReward(address(this), _tokens);
            uint256 _finalBalance =  SOLID.balanceOf(address(this));
            uint256 _reward = _finalBalance - _initialBalance;
            if(_reward != 0) {
                cummulativeRewardPerToken[_pool] += SCALING_FACTOR * _reward / _totalPoolLPDeposits;
            }
        }
    }

    function _updateUserRewards(address _user, address _pool, uint256 _balance) internal {
        uint256 _userLastUpdatedCummulativeRewardPerToken = userCummulativeRewardPerToken[_user][_pool];
        uint256 _poolRewardPerToken = cummulativeRewardPerToken[_pool]; 
        if(_poolRewardPerToken > _userLastUpdatedCummulativeRewardPerToken) {
            uint256 _claimable = claimable[_user][_pool];
            claimable[_user][_pool] = _claimable + _balance * (_poolRewardPerToken - _userLastUpdatedCummulativeRewardPerToken) / SCALING_FACTOR;
            userCummulativeRewardPerToken[_user][_pool] = _poolRewardPerToken;
        }
    }

    function updateWhitelistThreshold() public {
        // TODO: add access control
    }

    function emergencyWithdrawRadialveNFT() public {
        // TODO: add access control
    }
}
