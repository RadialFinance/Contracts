//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILPManager {
    function getTotalDeposits(address _user, address _pool) external view returns(uint256);
}