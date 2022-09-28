//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/ILPManager.sol";
import "./interfaces/IRDLInflationManager.sol";

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

interface ve {
    function transferFrom(address _from, address _to, uint _tokenId) external;
    function increase_unlock_time(uint _tokenId, uint _lock_duration) external;
    function locked(uint256 tokenId) external returns(int128 amount, uint256 endTime);
    function ownerOf(uint256 _tokenId) external view returns (address);
}

contract Depositor is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address immutable LP_MANAGER;
    address immutable WHITELISTING_BRIBE_MANAGER;
    IERC20 immutable RDL;
    IERC20 immutable SOLID;
    ve immutable VE;
    address immutable POOL_VOTING;
    address immutable RDL_INFLATION_MANAGER;
    ISolidMinter immutable SOLID_MINTER;
    ISolidVoter immutable SOLID_VOTER;
    uint256 immutable FEE;
    uint256 immutable WHITELIST_THRESHOLD;

    uint256 constant SCALING_FACTOR = 1e18;
    uint256 constant WEEK = 7 * 86400;
    uint256 constant MAX_SOLIDLY_LOCK_TIME = 4 * 365 * 86400;

    address feeAccumulator;
    uint256 unlockTime;

    mapping(address => uint256) public cummulativeRewardPerToken;
    mapping(address => mapping(address => uint256)) public userCummulativeRewardPerToken;
    mapping(address => mapping(address => uint256)) public claimable;
    mapping(address => uint256) public totalPoolLPDeposits;
    mapping(address => address) public gaugeForPool;

    uint256 public RADIAL_NFT_ID;

    event ClaimBoostedRewards(address indexed user, address[] pools, uint256 claimedAmount);
    event FeeAccumulatorUpdated(address indexed newFeeAccumulator);
    event UnlockTimeUpdated(uint256 newUnlockTime);

    modifier onlyLPManager {
        require(msg.sender == LP_MANAGER, "unauthorized");
        _;
    }

    constructor(
        uint256 _whitelistThreshold,
        uint256 _fee,
        address _lpManager, 
        address _whitelistingBribeManager, 
        address _rdlInflationManager,
        address _rdl, 
        address _solid, 
        address _ve,
        address _poolVoting, 
        address _solidMinter, 
        address _solidVoter
    ) initializer {
        WHITELIST_THRESHOLD = _whitelistThreshold;
        LP_MANAGER = _lpManager;
        WHITELISTING_BRIBE_MANAGER = _whitelistingBribeManager;
        RDL_INFLATION_MANAGER = _rdlInflationManager;
        RDL = IERC20(_rdl);
        SOLID = IERC20(_solid);
        VE = ve(_ve);
        POOL_VOTING = _poolVoting;
        SOLID_MINTER = ISolidMinter(_solidMinter);
        SOLID_VOTER = ISolidVoter(_solidVoter);
        FEE = _fee;
    }

    function initialize(address _admin, address _feeAccumulator, uint256 _radialNFTId) initializer external {
        __Ownable_init();
        _transferOwnership(_admin);
        feeAccumulator = _feeAccumulator;
        (, unlockTime) = VE.locked(RADIAL_NFT_ID);
        RADIAL_NFT_ID = _radialNFTId;
    }

    function transferOwnership(address newOwner) public pure override {
        revert("");
    }

    function whitelist(address _token, int256 _votes) external {
        require(msg.sender == WHITELISTING_BRIBE_MANAGER, "unauthorized");
        require(_votes > 0 && RDL.totalSupply()*WHITELIST_THRESHOLD/SCALING_FACTOR/1e18 <= uint256(_votes), "Not enough votes");
        SOLID_VOTER.whitelist(_token, RADIAL_NFT_ID);
    }

    function vote(address[] memory _pools, int256[] memory _weights) external {
        require(msg.sender == POOL_VOTING, "unauthorized");
        require(_pools.length == _weights.length, "invalid inputs");
        SOLID_MINTER.update_period();
        SOLID_VOTER.vote(RADIAL_NFT_ID, _pools, _weights);
    }

    function extendLockTime() external {
        _extendLockTime(WEEK);
    }

    function _extendLockTime(uint256 _lag) internal {
        uint256 _maxUnlock = ((block.timestamp + MAX_SOLIDLY_LOCK_TIME) / WEEK) * WEEK;
        uint256 _unlockTime = unlockTime;
        if (_maxUnlock > _unlockTime + _lag) {
            VE.increase_unlock_time(RADIAL_NFT_ID, MAX_SOLIDLY_LOCK_TIME);
            unlockTime = _maxUnlock;
            emit UnlockTimeUpdated(_unlockTime);
        }
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
            delete claimable[_user][_pool];
        }

        if(_claimedAmount != 0) {
            SOLID.transfer(_user, _claimedAmount);
            emit ClaimBoostedRewards(_user, _pools, _claimedAmount);
        }

        _extendLockTime(WEEK);
    }

    function getPendingRewards(address _user, address[] memory _pools) external returns(uint256[] memory) {
        uint256[] memory _pendingRewards = new uint256[](_pools.length);
        for(uint256 i=0; i < _pools.length; i++) {
            address _pool = _pools[i];
            _updateRewards(_pool, gaugeForPool[_pool], totalPoolLPDeposits[_pool]);
            _updateUserRewards(_user, _pool, ILPManager(LP_MANAGER).getTotalDeposits(_user, _pool));
            _pendingRewards[i] = claimable[_user][_pool];
        }
        return _pendingRewards;
    }

    function _updateRewards(address _pool, address _gauge, uint256 _totalPoolLPDeposits) internal {
        if(_totalPoolLPDeposits != 0) {
            uint256 _initialBalance = SOLID.balanceOf(address(this));
            address[] memory _tokens = new address[](1);
            _tokens[0] =  address(SOLID);
            ISolidGauge(_gauge).getReward(address(this), _tokens);
            uint256 _finalBalance = SOLID.balanceOf(address(this));
            uint256 _reward = _finalBalance - _initialBalance;
            if(_reward != 0) {
                uint256 _fee = _reward * FEE / 100;
                _reward = _reward - _fee;
                SOLID.transfer(feeAccumulator, _fee);
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

    function emergencyWithdrawRadialveNFT(address _to) public onlyOwner {
        VE.transferFrom(address(this), _to, RADIAL_NFT_ID);
        RADIAL_NFT_ID = 0;
    }

    function updateRadialNFT(uint256 _NFT_ID) external {
        require(RADIAL_NFT_ID == 0 || msg.sender == owner(), "NFT already exists");
        address nftOwner = VE.ownerOf(_NFT_ID);
        require(nftOwner == address(this), "Invalid NFT");
        RADIAL_NFT_ID = _NFT_ID;
    }

    function updateFeeAccumulator(address _feeAccumulator) external {
        require(msg.sender == feeAccumulator, "Unauthorized");
        feeAccumulator = _feeAccumulator;
        emit FeeAccumulatorUpdated(_feeAccumulator);
    }

    // upgrade
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
