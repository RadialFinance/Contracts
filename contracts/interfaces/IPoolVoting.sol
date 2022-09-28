//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IPoolVoting {
    function getWeeklyVoteData(address _user, uint256 _week) external view returns(uint256, uint256);
    function getUserVoteData(address user, address pool, uint256 week) external view returns(int256, int256);
    function poolRewardWeight(address pool, uint256 week) external view returns(uint256);
}