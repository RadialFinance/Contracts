//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IRadialVoting.sol";

import "./VoteLock.sol";

contract RDLManager is VoteLock, ReentrancyGuard {
    //----------------------------------- Constants ----------------------------------------//
    IERC20 immutable RDL;
    IRadialVoting immutable RADIAL_VOTING;

    //----------------------------------- State variables ----------------------------------------//
    mapping(address => uint256) public deposits;

    //----------------------------------- Initialize ----------------------------------------//
    constructor(
        address _rdlToken, 
        address _radialVoting, 
        uint256 _startTime, 
        uint256 _lockWeeks
    ) VoteLock(_lockWeeks, _startTime) ReentrancyGuard() {
        RDL = IERC20(_rdlToken);
        RADIAL_VOTING = IRadialVoting(_radialVoting);
    }

    //----------------------------------- Lock RDL ----------------------------------------//
    function lock(uint256 _amount) external nonReentrant {
        RDL.transferFrom(msg.sender, address(this), _amount);
        RADIAL_VOTING.receiveRDL(msg.sender, _amount);
        _lock(msg.sender, _amount);
        deposits[msg.sender] += _amount;
    }

    //----------------------------------- Withdraw RDL ----------------------------------------//
    function unlock(uint256 _amount) external nonReentrant {
        deposits[msg.sender] -= _amount;

        _unlock(msg.sender, _amount);

        // inform radial voting about tokens locked
        RADIAL_VOTING.withdrawRDL(msg.sender, _amount);
        RDL.transfer(msg.sender, _amount);
    }
}