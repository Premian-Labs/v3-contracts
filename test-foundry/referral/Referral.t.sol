// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {ZERO} from "contracts/libraries/OptionMath.sol";

import {IReferral} from "contracts/referral/IReferral.sol";

import {DeployTest} from "../Deploy.t.sol";

contract ReferralTest is DeployTest {
    address constant secondaryReferrer = address(0x999);

    function test_getRebates_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary(true);

        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary(false);

        (address[] memory tokens, uint256[] memory rebates) = referral
            .getRebates(users.referrer);

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

    function test_setReferrer_No_Referrer_Provided_Referrer_Not_Set() public {
        vm.prank(users.trader);
        referral.setReferrer(address(0));
        assertEq(referral.getReferrer(users.trader), address(0));
    }

    function test_setReferrer_Referrer_Provided_Referrer_Not_Set() public {
        vm.prank(users.trader);
        referral.setReferrer(users.referrer);
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_setReferrer_No_Referrer_Provided_Referrer_Set() public {
        vm.prank(users.trader);
        referral.setReferrer(users.referrer);
        vm.prank(users.trader);
        referral.setReferrer(address(0));
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_setReferrer_RevertIf_Referrer_Provided_Referrer_Set() public {
        vm.prank(users.trader);
        referral.setReferrer(users.referrer);

        vm.expectRevert(
            abi.encodeWithSelector(
                IReferral.Referral__ReferrerAlreadySet.selector,
                users.referrer
            )
        );

        vm.prank(users.trader);
        referral.setReferrer(secondaryReferrer);
    }

    function test_setRebateTier_Success() public {
        assertEq(
            uint8(referral.getRebateTier(users.referrer)),
            uint8(IReferral.RebateTier.PRIMARY_REBATE_1)
        );

        referral.setRebateTier(
            users.referrer,
            IReferral.RebateTier.PRIMARY_REBATE_2
        );

        assertEq(
            uint8(referral.getRebateTier(users.referrer)),
            uint8(IReferral.RebateTier.PRIMARY_REBATE_2)
        );
    }

    function test_setRebateTier_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);

        referral.setRebateTier(
            users.referrer,
            IReferral.RebateTier.PRIMARY_REBATE_2
        );
    }

    function test_setPrimaryRebatePercent_Success() public {
        UD60x18 percent = UD60x18.wrap(100e18);

        referral.setPrimaryRebatePercent(
            percent,
            IReferral.RebateTier.PRIMARY_REBATE_1
        );

        (UD60x18[] memory primaryRebatePercents, ) = referral
            .getRebatePercents();

        assertEq(primaryRebatePercents[0], percent);
    }

    function test_setPrimaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);

        referral.setPrimaryRebatePercent(
            UD60x18.wrap(100e18),
            IReferral.RebateTier.PRIMARY_REBATE_1
        );
    }

    function test_setSecondaryRebatePercent_Success() public {
        UD60x18 percent = UD60x18.wrap(100e18);
        referral.setSecondaryRebatePercent(percent);

        (, UD60x18 secondaryRebatePercent) = referral.getRebatePercents();

        assertEq(secondaryRebatePercent, percent);
    }

    function test_setSecondaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(users.trader);
        referral.setSecondaryRebatePercent(UD60x18.wrap(100e18));
    }

    function _test_useReferral_No_Rebate(bool isCall) internal {
        uint256 tradingFee = 1 ether;
        address token = getPoolToken(isCall);

        vm.startPrank(users.trader);

        deal(token, users.trader, tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        UD60x18 __rebate = referral.useReferral(
            users.trader,
            address(0),
            token,
            scaleDecimals(tradingFee, isCall)
        );

        vm.stopPrank();

        assertEq(__rebate, ZERO);
        assertEq(referral.getReferrer(users.trader), address(0));

        assertEq(IERC20(token).balanceOf(users.trader), tradingFee);
        assertEq(IERC20(token).balanceOf(address(referral)), 0);
    }

    function test_useReferral_No_Rebate() public {
        _test_useReferral_No_Rebate(true);
    }

    function _test_useReferral_Rebate_Primary_Only(bool isCall) internal {
        uint256 tradingFee = 1 ether;
        address token = getPoolToken(isCall);

        vm.startPrank(users.trader);

        deal(token, users.trader, tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        UD60x18 __rebate = referral.useReferral(
            users.trader,
            users.referrer,
            token,
            scaleDecimals(tradingFee, isCall)
        );

        vm.stopPrank();

        (
            UD60x18 primaryRebatePercent,
            UD60x18 secondaryRebatePercent
        ) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent *
            scaleDecimals(tradingFee, isCall);

        UD60x18 _secondaryRebate = secondaryRebatePercent *
            scaleDecimals(tradingFee, isCall);

        uint256 primaryRebate = scaleDecimals(_primaryRebate, isCall);
        uint256 secondaryRebate = scaleDecimals(_secondaryRebate, isCall);

        uint256 totalRebate = primaryRebate + secondaryRebate;

        assertEq(__rebate, _primaryRebate + _secondaryRebate);
        assertEq(referral.getReferrer(users.trader), users.referrer);

        assertEq(
            IERC20(token).balanceOf(users.trader),
            tradingFee - totalRebate
        );

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_useReferral_Rebate_Primary_Only() public {
        _test_useReferral_Rebate_Primary_Only(true);
    }

    function _test_useReferral_Rebate_Primary_And_Secondary(
        bool isCall
    )
        internal
        returns (address token, uint256 primaryRebate, uint256 secondaryRebate)
    {
        uint256 tradingFee = 1 ether;
        token = getPoolToken(isCall);

        vm.prank(users.referrer);

        referral.setReferrer(secondaryReferrer);

        vm.startPrank(users.trader);

        deal(token, users.trader, tradingFee);
        IERC20(token).approve(address(referral), tradingFee);

        UD60x18 __rebate = referral.useReferral(
            users.trader,
            users.referrer,
            token,
            scaleDecimals(tradingFee, isCall)
        );

        vm.stopPrank();

        (
            UD60x18 primaryRebatePercent,
            UD60x18 secondaryRebatePercent
        ) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent *
            scaleDecimals(tradingFee, isCall);

        UD60x18 _secondaryRebate = secondaryRebatePercent *
            scaleDecimals(tradingFee, isCall);

        primaryRebate = scaleDecimals(_primaryRebate, isCall);
        secondaryRebate = scaleDecimals(_secondaryRebate, isCall);

        uint256 totalRebate = primaryRebate + secondaryRebate;

        assertEq(__rebate, _primaryRebate + _secondaryRebate);
        assertEq(referral.getReferrer(users.trader), users.referrer);

        assertEq(
            IERC20(token).balanceOf(users.trader),
            tradingFee - totalRebate
        );

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_useReferral_Rebate_Primary_And_Secondary() public {
        _test_useReferral_Rebate_Primary_And_Secondary(true);
    }

    function test_claimRebate_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary(true);

        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary(false);

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

        (address[] memory tokens, uint256[] memory rebates) = referral
            .getRebates(users.referrer);

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
