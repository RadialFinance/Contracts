//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./VoteLock.sol";

interface IRadialVoting {
    function receiveRDL(address user, uint256 amount) external;
    function withdrawRDL(address user, uint256 amount) external;
}


// TODO: Add non renentrancy
contract RDLManager is VoteLock {
    IERC20 immutable RDL;
    IRadialVoting immutable RADIAL_VOTING;

    mapping(address => uint256) deposits;

    constructor(address _rdlToken, address _radialVoting, uint256 _startTime, uint256 _minLockWeeks) VoteLock(_minLockWeeks) {
        RDL = IERC20(_rdlToken);
        RADIAL_VOTING = IRadialVoting(_radialVoting);
        startTime = _startTime;
    }

    function lock(uint256 _amount) public {
        RDL.transferFrom(msg.sender, address(this), _amount);
        RADIAL_VOTING.receiveRDL(msg.sender, _amount);
        _lock(msg.sender, _amount);
        deposits[msg.sender] += _amount;
    }

    function withdrawLocked(uint256 _amount) public {
        deposits[msg.sender] -= _amount;

        _unlock(msg.sender, _amount);

        // inform radial voting about tokens locked
        RADIAL_VOTING.withdrawRDL(msg.sender, _amount);
        RDL.transfer(msg.sender, _amount);
    }
}