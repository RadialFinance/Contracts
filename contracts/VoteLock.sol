//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

contract VoteLock {
    uint256 constant WEEK = 60*60*24*7;
    uint256 immutable MIN_LOCK_WEEKS;

    uint256 startTime;

    struct Lock {
        uint256 unlocksAtWeek;
        uint256 amount;
    }

    mapping(address => Lock[]) locks;
    mapping(address => uint256) lockIndexToStartWithdraw;

    constructor(uint256 _minLockWeeks) {
        MIN_LOCK_WEEKS = _minLockWeeks;
    }

    function _lock(address _user, uint256 _amount) internal {
        require(_amount != 0, "0 deposit");
        locks[_user].push(Lock(getWeek() + MIN_LOCK_WEEKS, _amount));
    }

    function _unlock(address _user, uint256 _amount) internal {
        Lock[] memory _locks = locks[_user];
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        for(uint256 i = _indexToWithdraw; i < _locks.length; i++) {
            Lock memory _lockInfo = _locks[i];

            require(_lockInfo.unlocksAtWeek >= _currentWeek, "Not yet unlocked");

            if(_lockInfo.amount > _amount) {
                locks[_user][i].amount = _lockInfo.amount - _amount;
                _amount = 0;
                lockIndexToStartWithdraw[_user] = i;
                return;
            } else if(_lockInfo.amount == _amount) {
                delete locks[_user][i];
                lockIndexToStartWithdraw[_user] = i+1;
                return;
            } else {
                delete locks[_user][i];
                _amount -= _lockInfo.amount;
            }
        }
        revert("Insufficient amount to unlock");
    }

    function unlockableBalance(address _user) external view returns(uint256) {
        Lock[] memory _locks = locks[_user];
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        uint256 _amount;
        for(uint256 i = _indexToWithdraw; i < _locks.length; i++) {
            Lock memory _lockInfo = _locks[i];
            if(_lockInfo.unlocksAtWeek >= _currentWeek) {
                break;
            }
            _amount += _lockInfo.amount;
        }
        return _amount;
    }

    function isAmountUnlockable(address _user, uint256 _amount) external view returns(bool) {
        Lock[] memory _locks = locks[_user];
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        if(_amount == 0) return true;
        for(uint256 i = _indexToWithdraw; i < _locks.length; i++) {
            Lock memory _lockInfo = _locks[i];
            if(_lockInfo.unlocksAtWeek >= _currentWeek) {
                return false;
            }
            if(_lockInfo.amount >= _amount) {
                return true;
            } else {
                _amount -= _lockInfo.amount;
            }
        }
        return false;
    }

    function getWeek() public view returns (uint256) {
        return (block.timestamp - startTime) / WEEK;
    }
}
