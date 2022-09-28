//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IRadialVoting.sol";
import "./interfaces/IDepositor.sol";

import "./VoteLock.sol";

contract LPManager is VoteLock, ReentrancyGuard {
    //----------------------------------- Constants ----------------------------------------//
    address public immutable RDL_FTM_POOL;
    IRadialVoting public immutable RADIAL_VOTING;
    IDepositor public immutable DEPOSITOR;

    //----------------------------------- State variables ----------------------------------------//
    // user -> pool -> amount
    mapping(address => mapping(address => uint256)) public staked;
    mapping(address => uint256) public locked; // only RDL_FTM pool LPs can be locked

    //----------------------------------- Events ----------------------------------------//
    event StakeLP(address indexed user, address indexed pool, uint256 amount);
    event UnstakeLP(address indexed user, address indexed pool, uint256 amount);

    //----------------------------------- Initialize ----------------------------------------//
    constructor(
        address _rdlFtmPool, 
        address _radialVoting,
        address _depositor,
        uint256 _startTime, 
        uint256 _lockWeeks
    ) VoteLock(_lockWeeks, _startTime) ReentrancyGuard() {
        RDL_FTM_POOL = _rdlFtmPool;
        RADIAL_VOTING = IRadialVoting(_radialVoting);
        DEPOSITOR = IDepositor(_depositor);
    }

    //----------------------------------- Staking ----------------------------------------//
    function stake(address _pool, uint256 _amount) external nonReentrant {
        require(block.timestamp > START_TIME, "not started");
        // receive LP tokens
        IERC20(_pool).transferFrom(msg.sender, address(DEPOSITOR), _amount);
        // inform depositor that tokens were received
        uint256 _totalDeposit = staked[msg.sender][_pool];
        if(_pool == address(RDL_FTM_POOL)) {
            _totalDeposit += locked[msg.sender];
        }
        DEPOSITOR.receiveLP(msg.sender, _pool, _amount, _totalDeposit);
        // update deposit locally
        staked[msg.sender][_pool] += _amount;
        emit StakeLP(msg.sender, _pool, _amount);
    }

    function unStake(address _pool, uint256 _amount) external nonReentrant {
        uint256 _stake = staked[msg.sender][_pool];
        require(_stake >= _amount, "More than Staked amount");
        uint256 _totalDeposit = _stake;
        if(_pool == address(RDL_FTM_POOL)) {
            _totalDeposit += locked[msg.sender];
        }
        staked[msg.sender][_pool] -= _amount;
        // withdraws tokens from depositor
        DEPOSITOR.withdrawLP(msg.sender, _pool, _amount, _totalDeposit);
        emit UnstakeLP(msg.sender, _pool, _amount);
    }

    //----------------------------------- Locking ----------------------------------------//
    function lock(uint256 _amount) external nonReentrant {
        // receive LP Tokens
        IERC20(RDL_FTM_POOL).transferFrom(msg.sender, address(DEPOSITOR), _amount);
        // inform radial voting about tokens locked, can vote from next week
        RADIAL_VOTING.receiveLP(msg.sender, _amount);
        _lock(msg.sender, _amount);
        // inform depositor that tokens were received
        uint256 _locked = locked[msg.sender];
        DEPOSITOR.receiveLP(msg.sender, RDL_FTM_POOL, _amount, _locked + staked[msg.sender][RDL_FTM_POOL]);
        // update deposit locally
        locked[msg.sender] = _locked + _amount;
    }

    function unlock(uint256 _amount) external nonReentrant {
        uint256 _locked = locked[msg.sender];
        locked[msg.sender] = _locked - _amount;

        _unlock(msg.sender, _amount);

        // inform radial voting about tokens locked
        RADIAL_VOTING.withdrawLP(msg.sender, _amount);

        DEPOSITOR.withdrawLP(msg.sender, RDL_FTM_POOL, _amount, _locked + staked[msg.sender][RDL_FTM_POOL]);
    }

    //----------------------------------- Claim Boosted LP rewards ----------------------------------------//
    function claimSolidRewards(address[] memory _pools) external nonReentrant {
        uint256[] memory _currentBalances = new uint256[](_pools.length);
        for(uint i=0; i < _pools.length; i++) {
            address _pool = _pools[i];
            _currentBalances[i] = staked[msg.sender][_pool];
            if(_pool == RDL_FTM_POOL) {
                _currentBalances[i] += locked[msg.sender];
            }
        }
        DEPOSITOR.claimSolidRewards(msg.sender, _pools, _currentBalances);
    }

    function getTotalDeposits(address _user, address _pool) external view returns(uint256) {
        uint256 _staked = staked[_user][_pool];
        return _pool == RDL_FTM_POOL ? locked[_user] + _staked : _staked;
    }
}