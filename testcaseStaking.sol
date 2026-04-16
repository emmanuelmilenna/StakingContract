// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol"; 
import {StakingContract} from "../src/StakingContract.sol";

contract StakingContractTest is Test {
    StakingContract stakingContract;      
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    uint256 constant MIN_STAKE = 0.01 ether;
    uint256 constant MAX_STAKE = 5 ether;
    uint256 constant FUND_AMOUNT = 100000 ether;
    uint256 constant APY_BP = 500;

    event Staked(address indexed user, uint256 amount, uint256 totalStaked);
    event RewardsFunded(uint256 amount);
    event APYUpdated(uint256 newAPY);
    event MinStakeUpdated(uint256 newMin);
    event MaxStakeUpdated(uint256 newMax);

    function setUp() public {
        vm.prank(owner);
        stakingContract = new StakingContract();
        deal(address(stakingContract), FUND_AMOUNT);
    }

    function testStakeValidAmount() public {
        uint256 stakeAmount = 1 ether;
        
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: stakeAmount}();
        
        (uint256 staked,) = stakingContract.userInfo(user1);
        assertEq(staked, stakeAmount);
        assertEq(stakingContract.totalStakedAmount(), stakeAmount);
    }

    function testStakeBelowMinAmountReverts() public {
        uint256 invalidAmount = 0.001 ether;
        
        vm.prank(user1);
        deal(user1, 10 ether);
        
        vm.expectRevert("amount below minimum stake");
        stakingContract.stake{value: invalidAmount}();
    }

    function testStakeExceedsMaxLimitReverts() public {
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: MAX_STAKE}();
        
        vm.expectRevert("exceeds max stake limit");
        stakingContract.stake{value: 10 ether}();
    }

    function testMultipleUsersStaking() public {
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: 1 ether}();
        
        vm.prank(user2);
        deal(user2, 10 ether);
        stakingContract.stake{value: 2 ether}();
        
        assertEq(stakingContract.totalStakedAmount(), 3 ether);
    }

    function testPendingRewardsAfterTime() public {
        vm.prank(owner);
        deal(owner, 10 ether);
        stakingContract.fundRewards{value: 10 ether}();
        
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: 1 ether}();
        
        skip(30 days);
        
        uint256 pending = stakingContract.pendingRewards(user1);
        assertGt(pending, 0);
    }

    function testClaimRewards() public {
    vm.prank(user1);
    deal(user1, 10 ether);
    stakingContract.stake{value: 1 ether}();
    
    skip(10 days);
    
    uint256 reward = stakingContract.pendingRewards(user1);
    
    
    deal(address(stakingContract), reward + 1 ether); 
    
    uint256 balanceBefore = user1.balance;
    vm.prank(user1);
    stakingContract.claimRewards();
    
    assertEq(stakingContract.pendingRewards(user1), 0);
    assertGt(user1.balance, balanceBefore);
}

    function testRewardCalculationFormula() public {
        vm.prank(owner);
        deal(owner, 10 ether);
        stakingContract.fundRewards{value: 10 ether}();
        
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: 1 ether}();
        
        skip(365 days);
        
        uint256 actualReward = stakingContract.pendingRewards(user1);
        assertGt(actualReward, 0);
    }

    function testWithdrawPrincipalAndRewards() public {
    vm.prank(user1);
    deal(user1, 10 ether);
    stakingContract.stake{value: 1 ether}();
    
    skip(10 days);
    
    uint256 reward = stakingContract.pendingRewards(user1);
    deal(address(stakingContract), reward + 1 ether);
    
    uint256 balanceBefore = user1.balance;
    vm.prank(user1);
    stakingContract.withdraw(1 ether);
    
    (uint256 staked,) = stakingContract.userInfo(user1);
    assertEq(staked, 0);
    assertEq(stakingContract.totalStakedAmount(), 0);
    assertGt(user1.balance, balanceBefore);
}

    function testWithdrawNoStakeReverts() public {
        vm.expectRevert("No stake");
        vm.prank(user1);
        stakingContract.withdraw(1 ether);
    }

    function testWithdrawInvalidAmountReverts() public {
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: 1 ether}();
        
        vm.expectRevert("Invalid amount");
        vm.prank(user1);
        stakingContract.withdraw(2 ether);
    }

    function testOwnerFundRewards() public {
        uint256 fundAmount = 10 ether;
        uint256 balanceBefore = address(stakingContract).balance;
        
        vm.prank(owner);
        deal(owner, 20 ether);
        stakingContract.fundRewards{value: fundAmount}();
        
        assertEq(address(stakingContract).balance, balanceBefore + fundAmount);
    }

    function testNonOwnerFundRewardsReverts() public {
        vm.expectRevert();
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.fundRewards{value: 1 ether}();
    }

    function testOwnerUpdateApy() public {
        uint256 newApy = 1000;
        
        vm.prank(owner);
        stakingContract.setApyBasisPoints(newApy);
        
        assertEq(stakingContract.apyBasisPoints(), newApy);
    }

    function testStakingPause() public {
        vm.prank(owner);
        stakingContract.setStakingEnabled(false);
        
        vm.prank(user1);
        deal(user1, 10 ether);
        
        vm.expectRevert("StakingPaused");
        stakingContract.stake{value: 1 ether}();
    }

    function testEmergencyWithdrawOwner() public {
    vm.prank(owner);
    deal(owner, 10 ether);
    stakingContract.stake{value: 1 ether}();
    
    skip(10 days);
    
    uint256 reward = stakingContract.pendingRewards(owner);
    deal(address(stakingContract), reward + 1 ether);
    
    uint256 ownerBalanceBefore = owner.balance;
    vm.prank(owner);
    stakingContract.emergencyWithdraw();
    
    (uint256 staked,) = stakingContract.userInfo(owner);
    assertEq(staked, 0);
    assertGt(owner.balance, ownerBalanceBefore);
}

    function testGetUserInfo() public {
        vm.prank(owner);
        deal(owner, 10 ether);
        stakingContract.fundRewards{value: 10 ether}();
        
        vm.prank(user1);
        deal(user1, 10 ether);
        stakingContract.stake{value: 1 ether}();
        
        skip(1 days);
        
        (uint256 amount, uint256 pending, uint256 apy) = stakingContract.getUserInfo(user1);
        assertEq(amount, 1 ether);
        assertGt(pending, 0);
        assertEq(apy, APY_BP);   
    } 

   
function testEventStaked() public {
    vm.prank(user1);
    deal(user1, 10 ether);
    
    vm.expectEmit(true, true, false, true);
    emit Staked(user1, 1 ether, 1 ether);
    
    stakingContract.stake{value: 1 ether}();
}

 
function testEventRewardsFunded() public {
    vm.prank(owner);
    deal(owner, 10 ether);
    
    vm.expectEmit(false, false, false, true);
    emit RewardsFunded(10 ether);
    
    stakingContract.fundRewards{value: 10 ether}();
}


function testEventAPYUpdated() public {
    vm.prank(owner);
    
    vm.expectEmit(false, false, false, true);
    emit APYUpdated(1000);
    
    stakingContract.setApyBasisPoints(1000);
}


function testEventMinStakeUpdated() public {
    vm.prank(owner);
    
    vm.expectEmit(false, false, false, true);
    emit MinStakeUpdated(0.001 ether);
    
    stakingContract.setMinStakeAmount(0.001 ether);
}


function testEventMaxStakeUpdated() public {
    vm.prank(owner);
    
    vm.expectEmit(false, false, false, true);
    emit MaxStakeUpdated(10 ether);
    
    stakingContract.setMaxStakePerUser(10 ether);
}


    function testContractBalance() public {
        assertEq(stakingContract.getContractBalance(), FUND_AMOUNT);
    }

    function testGetPauseStatus() public {
        (bool stakingEnabled, bool withdrawingEnabled) = stakingContract.getPauseStatus();
        assertTrue(stakingEnabled);
        assertTrue(withdrawingEnabled);
    }
}