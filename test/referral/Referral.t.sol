// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {ZERO} from "contracts/libraries/OptionMath.sol";

import {IReferral} from "contracts/referral/IReferral.sol";

import {DeployTest} from "../Deploy.t.sol";

contract ReferralTest is DeployTest {
    address internal constant secondaryReferrer = address(0x999);

    function setUp() public override {
        super.setUp();

        isCallTest = true;
        poolKey.isCallPool = true;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
    }

    function test_getRebates_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary();

        isCallTest = false;
        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary();

        (address[] memory tokens, uint256[] memory rebates) = referral.getRebates(users.referrer);

        assertEq(tokens[0], token0);
        assertEq(rebates[0], primaryRebate0);

        assertEq(tokens[1], token1);
        assertEq(rebates[1], primaryRebate1);

        (tokens, rebates) = referral.getRebates(secondaryReferrer);

        assertEq(tokens[0], token0);
        assertEq(rebates[0], secondaryRebate0);

        assertEq(tokens[1], token1);
        assertEq(rebates[1], secondaryRebate1);
    }

    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Not_Set() public {
        vm.prank(users.trader);
        address referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, address(0));
        assertEq(referral.getReferrer(users.trader), address(0));
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Not_Set() public {
        vm.prank(users.trader);
        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Set() public {
        vm.startPrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, users.referrer);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Set() public {
        vm.startPrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(secondaryReferrer);
        assertEq(referrer, users.referrer);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_setRebateTier_Success() public {
        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate1));

        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);

        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate2));
    }

    function test_setRebateTier_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);

        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);
    }

    function test_setPrimaryRebatePercent_Success() public {
        UD60x18 percent = ud(100e18);

        referral.setPrimaryRebatePercent(percent, IReferral.RebateTier.PrimaryRebate1);

        (UD60x18[] memory primaryRebatePercents, ) = referral.getRebatePercents();

        assertEq(primaryRebatePercents[0], percent);
    }

    function test_setPrimaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);

        referral.setPrimaryRebatePercent(ud(100e18), IReferral.RebateTier.PrimaryRebate1);
    }

    function test_setSecondaryRebatePercent_Success() public {
        UD60x18 percent = ud(100e18);
        referral.setSecondaryRebatePercent(percent);

        (, UD60x18 secondaryRebatePercent) = referral.getRebatePercents();

        assertEq(secondaryRebatePercent, percent);
    }

    function test_setSecondaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);
        referral.setSecondaryRebatePercent(ud(100e18));
    }

    function _test_useReferral_No_Rebate() internal {
        uint256 tradingFee = 1 ether;
        address token = getPoolToken();

        vm.startPrank(address(pool));
        deal(token, address(pool), tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        referral.useReferral(users.trader, address(0), token, scaleDecimals(tradingFee));

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), address(0));

        assertEq(IERC20(token).balanceOf(address(pool)), tradingFee);
        assertEq(IERC20(token).balanceOf(address(referral)), 0);
    }

    function test_useReferral_No_Rebate() public {
        _test_useReferral_No_Rebate();
    }

    function _test_useReferral_Rebate_Primary_Only() internal {
        uint256 tradingFee = 1 ether;
        address token = getPoolToken();

        vm.startPrank(address(pool));
        deal(token, address(pool), tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        referral.useReferral(users.trader, users.referrer, token, scaleDecimals(tradingFee));

        vm.stopPrank();

        (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(tradingFee);

        UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(tradingFee);

        uint256 primaryRebate = scaleDecimals(_primaryRebate);
        uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

        uint256 totalRebate = primaryRebate + secondaryRebate;

        assertEq(referral.getReferrer(users.trader), users.referrer);

        assertEq(IERC20(token).balanceOf(address(pool)), tradingFee - totalRebate);

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_useReferral_Rebate_Primary_Only() public {
        _test_useReferral_Rebate_Primary_Only();
    }

    function _test_useReferral_Rebate_Primary_And_Secondary()
        internal
        returns (address token, uint256 primaryRebate, uint256 secondaryRebate)
    {
        uint256 tradingFee = 1 ether;
        token = getPoolToken();

        vm.prank(users.referrer);
        referral.__trySetReferrer(secondaryReferrer);

        vm.startPrank(address(pool));
        deal(token, address(pool), tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        referral.useReferral(users.trader, users.referrer, token, scaleDecimals(tradingFee));

        vm.stopPrank();

        (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(tradingFee);

        UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(tradingFee);

        primaryRebate = scaleDecimals(_primaryRebate);
        secondaryRebate = scaleDecimals(_secondaryRebate);

        uint256 totalRebate = primaryRebate + secondaryRebate;

        assertEq(referral.getReferrer(users.trader), users.referrer);

        assertEq(IERC20(token).balanceOf(address(pool)), tradingFee - totalRebate);

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_useReferral_Rebate_Primary_And_Secondary() public {
        _test_useReferral_Rebate_Primary_And_Secondary();
    }

    function test_useReferral_RevertIf_Pool_Not_Authorized() public {
        vm.prank(users.trader);
        vm.expectRevert(IReferral.Referral__PoolNotAuthorized.selector);

        referral.useReferral(users.trader, users.referrer, address(0), ud(100e18));
    }

    function test_claimRebate_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary();

        isCallTest = false;
        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary();

        vm.prank(users.referrer);
        referral.claimRebate();

        vm.prank(secondaryReferrer);
        referral.claimRebate();

        assertEq(IERC20(token0).balanceOf(address(referral)), 0);
        assertEq(IERC20(token1).balanceOf(address(referral)), 0);

        assertEq(IERC20(token0).balanceOf(users.referrer), primaryRebate0);
        assertEq(IERC20(token0).balanceOf(secondaryReferrer), secondaryRebate0);

        assertEq(IERC20(token1).balanceOf(users.referrer), primaryRebate1);
        assertEq(IERC20(token1).balanceOf(secondaryReferrer), secondaryRebate1);

        (address[] memory tokens, uint256[] memory rebates) = referral.getRebates(users.referrer);

        assertEq(tokens.length, 0);
        assertEq(rebates.length, 0);

        (tokens, rebates) = referral.getRebates(secondaryReferrer);

        assertEq(tokens.length, 0);
        assertEq(rebates.length, 0);
    }

    function test_claimRebate_RevertIf_No_Rebate() public {
        vm.expectRevert(IReferral.Referral__NoRebatesToClaim.selector);
        referral.claimRebate();
    }
}
