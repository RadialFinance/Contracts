//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IRDLInflationManager {
    function getRDLForWeek(uint256 _week) external returns(uint256);
}