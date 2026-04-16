// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract StakingContract is ReentrancyGuard, Ownable {
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 3600;
    uint256 public constant DECIMAL_FACTOR = 1e17;
    uint256 public immutable DEPLOY_TIMESTAMP;

    uint256 public apyBasisPoints = 500;
    uint256 public minStakeAmount = 0.01 ether;

    mapping(address => UserInfo) public userInfo;
    uint256 public totalStakedAmount;
    uint256 public totalRewardPerTokenStored;
    uint256 public totalRewardsMinted;
    uint256 public lastRewardUpdateTime;

    uint256 public maxStakePerUser = 5 ether;
    bool public stakingEnabled = true;
    bool public withdrawingEnabled = true;

    struct UserInfo {
        uint256 ethStaked;
        uint256 rewardDebt;
    }

    event Staked(address indexed user, uint256 amount, uint256 totalStaked);
    event Withdrawn(address indexed user, uint256 principal, uint256 reward, uint256 totalStaked);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardsFunded(uint256 amount);
    event APYUpdated(uint256 newApy);
    event PauseStatusUpdated(bool staking, bool withdrawing);
    event MaxStakeUpdated(uint256 newMax);
    event MinStakeUpdated(uint256 newMin);

    constructor() Ownable(msg.sender) {
        DEPLOY_TIMESTAMP = block.timestamp;
        lastRewardUpdateTime = DEPLOY_TIMESTAMP;
    }

    modifier stakingActive() {
        _stakingActive();
        _;
    }

    modifier withdrawingActive() {
        _withdrawingActive();
        _;
    }

    function _stakingActive() internal view {
        require(stakingEnabled, "StakingPaused");
    }

    function _withdrawingActive() internal view {
        require(withdrawingEnabled, "WithdrawPaused");
    }

    function stake() external payable nonReentrant stakingActive {
        require(msg.value > 0, "Invalid amount");
        require(msg.value >= minStakeAmount, "amount below minimum stake");

        UserInfo storage user = userInfo[msg.sender];
        uint256 newTotal = user.ethStaked + msg.value;
        require(newTotal <= maxStakePerUser, "exceeds max stake limit");

        _updateGlobalRewards();
        uint256 pendingReward = _calculatePendingReward(msg.sender);

        if (pendingReward > 0) {
            user.rewardDebt = Math.mulDiv(user.ethStaked, totalRewardPerTokenStored, DECIMAL_FACTOR);
            _safeTransferEth(msg.sender, pendingReward);
        }

        user.ethStaked = newTotal;
        user.rewardDebt = Math.mulDiv(newTotal, totalRewardPerTokenStored, DECIMAL_FACTOR);
        totalStakedAmount += msg.value;

        emit Staked(msg.sender, msg.value, totalStakedAmount);
    }

    function withdraw(uint256 amount) external nonReentrant withdrawingActive {
        UserInfo storage user = userInfo[msg.sender];
        require(user.ethStaked > 0, "No stake");
        require(amount > 0 && amount <= user.ethStaked, "Invalid amount");

        _updateGlobalRewards();

        uint256 reward = _calculatePendingReward(msg.sender);
        uint256 principal = amount;
        uint256 totalWithdraw = principal + reward;

        totalStakedAmount -= principal;
        user.ethStaked -= principal;
        user.rewardDebt = Math.mulDiv(user.ethStaked, totalRewardPerTokenStored, DECIMAL_FACTOR);

        _safeTransferEth(msg.sender, totalWithdraw);

        if (user.ethStaked == 0) {
            user.rewardDebt = 0;
        }    

        emit Withdrawn(msg.sender, principal, reward, totalStakedAmount);
    }

    function fundRewards() external payable onlyOwner {
        require(msg.value > 0, "Send ETH");
        emit RewardsFunded(msg.value);
    }

    function claimRewards() external nonReentrant withdrawingActive {
        _updateGlobalRewards();
        uint256 reward = _calculatePendingReward(msg.sender);
        require(reward > 0, "No rewards");

        UserInfo storage user = userInfo[msg.sender];
        user.rewardDebt = Math.mulDiv(user.ethStaked, totalRewardPerTokenStored, DECIMAL_FACTOR);

        _safeTransferEth(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function pendingRewards(address user) public view returns (uint256) {
        return _calculatePendingReward(user);
    }

    function getUserInfo(address user)
        external
        view
        returns (
            uint256 amount,
            uint256 pendingReward,
            uint256 apyApplied
        )
    {
        UserInfo memory userData = userInfo[user];
        amount = userData.ethStaked;
        pendingReward = pendingRewards(user);
        apyApplied = apyBasisPoints;
    }

    function _updateGlobalRewards() private {
        uint256 timeElapsed = block.timestamp - lastRewardUpdateTime;
        if (timeElapsed == 0 || totalStakedAmount == 0) {
            return;
        }

        uint256 reward = Math.mulDiv(
            totalStakedAmount * apyBasisPoints * timeElapsed,
            DECIMAL_FACTOR,
            BASIS_POINTS * SECONDS_PER_YEAR
        );

        totalRewardsMinted += reward;
        totalRewardPerTokenStored += Math.mulDiv(reward, DECIMAL_FACTOR, totalStakedAmount);
        lastRewardUpdateTime = block.timestamp;
    }

    function _calculatePendingReward(address user) private view returns (uint256) {
        UserInfo memory userData = userInfo[user];
        if (userData.ethStaked == 0) {
            return 0;
        }

        uint256 currentRewardPerToken = totalRewardPerTokenStored;
        uint256 timeElapsed = block.timestamp - lastRewardUpdateTime;

        if (timeElapsed > 0 && totalStakedAmount > 0) {
            uint256 reward = Math.mulDiv(
                totalStakedAmount * apyBasisPoints * timeElapsed,
                DECIMAL_FACTOR,
                BASIS_POINTS * SECONDS_PER_YEAR
            );
            currentRewardPerToken += Math.mulDiv(reward, DECIMAL_FACTOR, totalStakedAmount);
        }

        uint256 totalReward = Math.mulDiv(userData.ethStaked, currentRewardPerToken, DECIMAL_FACTOR);
        return totalReward - userData.rewardDebt;
    }

    function setMaxStakePerUser(uint256 _maxStake) external onlyOwner {
        require(_maxStake > 0, "Max stake must be > 0");
        maxStakePerUser = _maxStake;
        emit MaxStakeUpdated(_maxStake);
    }

    function setApyBasisPoints(uint256 _apyBasisPoints) external onlyOwner {
        require(_apyBasisPoints <= BASIS_POINTS * 100, "APY too high");
        apyBasisPoints = _apyBasisPoints;
        emit APYUpdated(_apyBasisPoints);
    }

    function setMinStakeAmount(uint256 _minAmount) external onlyOwner {
        require(_minAmount > 0, "Min stake must be > 0");
        minStakeAmount = _minAmount;
        emit MinStakeUpdated(_minAmount);
    }

    function setStakingEnabled(bool _enabled) external onlyOwner {
        stakingEnabled = _enabled;
        emit PauseStatusUpdated(_enabled, withdrawingEnabled);
    }

    function setWithdrawingEnabled(bool _enabled) external onlyOwner {
        withdrawingEnabled = _enabled;
        emit PauseStatusUpdated(stakingEnabled, _enabled);
    }

    function emergencyWithdraw() external onlyOwner {
        UserInfo storage ownerInfo = userInfo[owner()];
        uint256 ownerReward = _calculatePendingReward(owner());
        uint256 ownerTotal = ownerInfo.ethStaked + ownerReward;

        require(ownerTotal > 0, "No owner funds");

        totalStakedAmount -= ownerInfo.ethStaked;
        ownerInfo.ethStaked = 0;
        ownerInfo.rewardDebt = 0;

        _safeTransferEth(owner(), ownerTotal);
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getPauseStatus() external view returns (bool staking, bool withdrawing) {
        return (stakingEnabled, withdrawingEnabled);
    }

    function _safeTransferEth(address to, uint256 amount) private {
        require(address(this).balance >= amount, "Insufficient contract balance");
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}
