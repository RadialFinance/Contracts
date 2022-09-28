//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IRadialVoting {
    function balanceOfLP(address user) external returns(uint256);
    function receiveLP(address from, uint256 amount) external;
    function withdrawLP(address _from, uint256 _amount) external;
    function receiveRDL(address user, uint256 amount) external;
    function withdrawRDL(address user, uint256 amount) external;
    function getVotingPower(address user) external returns(uint256);
}