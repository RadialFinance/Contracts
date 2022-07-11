//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./VoteLock.sol";

interface RadialVoting {
    function balanceOfLP(address user) external returns(uint256);
    function receiveLP(address from, uint256 amount) external;
    function withdrawLP(address _from, uint256 _amount) external;
}

interface Depositor {
    function receiveLP(address from, address _pool, uint256 amount, uint256 currentBalance) external;
    function withdrawLP(address from, address _pool, uint256 amount, uint256 currentBalance) external;
}

// TODO: Add non renentrancy

// Note: LPManager holds rewards for LPs
contract LPManager is VoteLock {
    struct RewardPoint {
        uint256 rewardsAccrued; // amount of rewards accrued till `accuredTill`, updates everytime deposit amount changes
        uint256 accruedTill; // timestamp till which rewards accrued were stored above
    }

    address immutable RDL_FTM_POOL;
    IERC20 immutable RDL;
    RadialVoting immutable RADIAL_VOTING;
    Depositor immutable DEPOSITOR;
    uint256 immutable REWARD_PER_BLOCK;
    uint256 immutable REWARD_ENDS_AT;

    // user -> pool -> amount
    mapping(address => mapping(address => uint256)) deposits;
    mapping(address => uint256) locked;
    mapping(address => RewardPoint) accumulatedRewards; // for WFTM/RDL users only

    constructor(
        address _rdlFtmPool, 
        address _rdl, 
        address _radialVoting,
        address _depositor,
        uint256 _rewardPerBlock,
        uint256 _rewardEndsAt,
        uint256 _startTime, 
        uint256 _minLockTime
    ) VoteLock(_minLockTime) {
        RDL_FTM_POOL = _rdlFtmPool;
        startTime = _startTime;
        RDL = IERC20(_rdl);
        RADIAL_VOTING = RadialVoting(_radialVoting);
        DEPOSITOR = Depositor(_depositor);
        REWARD_PER_BLOCK = _rewardPerBlock;
        REWARD_ENDS_AT = uint128(_rewardEndsAt);
    }

    function stake(address _pool, uint256 _amount) public {
        // receive LP tokens
        IERC20(_pool).transferFrom(msg.sender, address(DEPOSITOR), _amount);
        // inform depositor that tokens were received
        uint256 _oldBalance = deposits[msg.sender][_pool];
        if(_pool == address(RDL_FTM_POOL)) {
            // update rewards
            _updateRewards(msg.sender);
            _oldBalance += locked[msg.sender];
        }
        DEPOSITOR.receiveLP(msg.sender, _pool, _amount, _oldBalance);
        // update deposit locally
        deposits[msg.sender][_pool] += _amount;
    }

    function withdrawStaked(address _pool, uint256 _amount) public {
        uint256 _stakedDeposit = deposits[msg.sender][_pool];
        require(_stakedDeposit >= _amount, "More than Staked amount");
        uint256 _oldBalance = deposits[msg.sender][_pool];
        if(_pool == address(RDL_FTM_POOL)) {
            // update rewards
            _updateRewards(msg.sender);
            _oldBalance += locked[msg.sender];
        }
        // withdraws tokens from depositor
        DEPOSITOR.withdrawLP(msg.sender, _pool, _amount, _oldBalance);
        deposits[msg.sender][_pool] -= _amount;
    }

    function lock(uint256 _amount) public {
        // update rewards
        _updateRewards(msg.sender);
        // receive LP Tokens
        IERC20(RDL_FTM_POOL).transferFrom(msg.sender, address(DEPOSITOR), _amount);
        // inform radial voting about tokens locked, TODO: can vote from next week
        RADIAL_VOTING.receiveLP(msg.sender, _amount);
        _lock(msg.sender, _amount);
        // inform depositor that tokens were received
        uint256 _oldBalance = locked[msg.sender];
        DEPOSITOR.receiveLP(msg.sender, RDL_FTM_POOL, _amount, _oldBalance + deposits[msg.sender][RDL_FTM_POOL]);
        // update deposit locally
        locked[msg.sender] = _oldBalance + _amount;
    }

    function withdrawLocked(uint256 _amount) public {
        // update rewards
        _updateRewards(msg.sender);
        uint256 _oldBalance = locked[msg.sender];
        locked[msg.sender] = _oldBalance - _amount;

        _unlock(msg.sender, _amount);

        // inform radial voting about tokens locked
        RADIAL_VOTING.withdrawLP(msg.sender, _amount);

        DEPOSITOR.withdrawLP(msg.sender, RDL_FTM_POOL, _amount, _oldBalance + deposits[msg.sender][RDL_FTM_POOL]);
    }

    // liquidity mining reward for everyone who LPs to RDL/FTM and locks/stakes the LP token
    function claimRDLRewards() public {
        // update rewards
        uint256 _rewardsTillNow = _updateRewards(msg.sender);
        delete accumulatedRewards[msg.sender].rewardsAccrued;
        IERC20(RDL).transfer(msg.sender, _rewardsTillNow);
    }

    function claimSolidRewards(address[] memory _pools) public {

    }

    function _updateRewards(address _lpHolder) internal returns(uint256) {
        RewardPoint memory _lastKnownRewards = accumulatedRewards[_lpHolder];
        uint256 _rewardsTill = _rewardEndTime();
        _lastKnownRewards.rewardsAccrued += (_rewardsTill - _lastKnownRewards.accruedTill)*(deposits[_lpHolder][RDL_FTM_POOL] + locked[_lpHolder]);
        accumulatedRewards[_lpHolder] = RewardPoint(_lastKnownRewards.rewardsAccrued, _rewardsTill);
        return _lastKnownRewards.rewardsAccrued;
    }

    function _rewardEndTime() internal view returns(uint256) {
        return (block.timestamp >= REWARD_ENDS_AT)? REWARD_ENDS_AT : block.timestamp;
    }
}
