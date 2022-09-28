//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IDepositor {
    function receiveLP(address from, address _pool, uint256 amount, uint256 currentBalance) external;
    function withdrawLP(address from, address _pool, uint256 amount, uint256 currentBalance) external;

    function claimSolidRewards(address _user, address[] calldata _pools, uint256[] calldata _currentBalances) external;
    function vote(address[] memory pools, int256[] memory weights) external;

    function whitelist(address _token, int256 _votes) external;

    function extendLockTime() external;
}