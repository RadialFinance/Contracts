//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/**
    @title Contract that manages locking and unlocking of tokens for voting rights
    @author RadialFinance
 */
contract VoteLock {
    //----------------------------------- Declarations ----------------------------------------//
    struct Lock {
        uint256 unlocksAtWeek;
        uint256 amount;
    }

    //----------------------------------- Constants ----------------------------------------//
    uint256 constant WEEK = 60*60*24*7;
    uint256 immutable public LOCK_WEEKS;
    uint256 immutable public START_TIME;

    //----------------------------------- State variables ----------------------------------------//
    mapping(address => Lock[]) public locks;
    mapping(address => uint256) public lockIndexToStartWithdraw;

    //----------------------------------- Events ----------------------------------------//
    event LockForVoting(address user, uint256 amount, uint256 unlockWeek);
    event UnlockFromVoting(address user, uint256 amount);

    //----------------------------------- Initialize ----------------------------------------//
    constructor(uint256 _lockWeeks, uint256 _startTime) {
        LOCK_WEEKS = _lockWeeks;
        START_TIME = _startTime;
    }

    //----------------------------------- Lock tokens ----------------------------------------//
    function _lock(address _user, uint256 _amount) internal {
        require(_amount != 0, "0 deposit");
        uint256 _unlocksAtWeek = getWeek() + LOCK_WEEKS;
        uint256 _totalLocks = locks[_user].length;
        emit LockForVoting(_user, _amount, _unlocksAtWeek);
        if(_totalLocks == 0) {
            locks[_user].push(Lock(_unlocksAtWeek, _amount));
            return;
        }

        Lock storage _lastLock = locks[_user][_totalLocks - 1];
        if(_lastLock.unlocksAtWeek == _unlocksAtWeek) {
            _lastLock.amount += _amount;
        } else {
            locks[_user].push(Lock(_unlocksAtWeek, _amount));
        }
    }

    //----------------------------------- Unlock tokens ----------------------------------------//
    function _unlock(address _user, uint256 _amount) internal {
        uint256 _locksLength = locks[_user].length;
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        emit UnlockFromVoting(_user, _amount);
        for(uint256 i = _indexToWithdraw; i < _locksLength; i++) {
            Lock memory _lockInfo = locks[_user][i];

            require(_lockInfo.unlocksAtWeek < _currentWeek, "Not yet unlocked");

            if(_lockInfo.amount > _amount) {
                locks[_user][i].amount = _lockInfo.amount - _amount;
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

    //----------------------------------- Getter functions ----------------------------------------//
    function unlockableBalance(address _user) external view returns(uint256) {
        uint256 _locksLength = locks[_user].length;
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        uint256 _amount;
        for(uint256 i = _indexToWithdraw; i < _locksLength; i++) {
            Lock memory _lockInfo = locks[_user][i];
            if(_lockInfo.unlocksAtWeek >= _currentWeek) {
                break;
            }
            _amount += _lockInfo.amount;
        }
        return _amount;
    }

    function isAmountUnlockable(address _user, uint256 _amount) external view returns(bool) {
        if(_amount == 0) return true;
        uint256 _locksLength = locks[_user].length;
        uint256 _currentWeek = getWeek();
        uint256 _indexToWithdraw = lockIndexToStartWithdraw[_user];
        for(uint256 i = _indexToWithdraw; i < _locksLength; i++) {
            Lock memory _lockInfo = locks[_user][i];
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
        return (block.timestamp - START_TIME) / WEEK;
    }
}
