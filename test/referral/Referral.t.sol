// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {ZERO} from "contracts/libraries/OptionMath.sol";

import {IReferral} from "contracts/referral/IReferral.sol";

import {DeployTest} from "../Deploy.t.sol";

contract ReferralTest is DeployTest {
    address internal constant secondaryReferrer = address(0x999);

    uint256 internal tradingFee = 200e18;
    UD60x18 internal _tradingFee;

    uint256 internal primaryRebate = 10e18;
    uint256 internal secondaryRebate = 1e18;
    uint256 internal totalRebate = primaryRebate + secondaryRebate;

    UD60x18 internal _primaryRebate;
    UD60x18 internal _secondaryRebate;
    UD60x18 internal _totalRebate;

    function setUp() public override {
        super.setUp();

        isCallTest = true;
        poolKey.isCallPool = true;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));

        _tradingFee = fromTokenDecimals(tradingFee);
        _primaryRebate = fromTokenDecimals(primaryRebate);
        _secondaryRebate = fromTokenDecimals(secondaryRebate);
        _totalRebate = _primaryRebate + _secondaryRebate;
    }

    function test_getRebates_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary(200e18);

        isCallTest = false;
        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary(100e18);

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

    function test_getRebateAmounts_Success() public {
        vm.prank(users.trader);
        (UD60x18 __primaryRebate, UD60x18 __secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            address(0),
            _tradingFee
        );

        UD60x18 __totalRebate = __primaryRebate + __secondaryRebate;

        assertEq(__totalRebate, ZERO);
        assertEq(__primaryRebate, ZERO);
        assertEq(__secondaryRebate, ZERO);

        vm.prank(users.trader);
        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, users.referrer, _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _primaryRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, ZERO);

        vm.prank(users.trader);
        referral.__trySetReferrer(users.referrer);

        vm.prank(users.trader);
        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _primaryRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, ZERO);

        vm.prank(users.referrer);
        referral.__trySetReferrer(secondaryReferrer);

        vm.prank(users.trader);
        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _totalRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, _secondaryRebate);
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
        address token = getPoolToken();

        vm.startPrank(address(pool));
        deal(token, address(pool), tradingFee);
        IERC20(token).approve(address(referral), type(uint256).max);

        referral.useReferral(users.trader, address(0), token, ZERO, ZERO);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), address(0));
        assertEq(IERC20(token).balanceOf(address(pool)), tradingFee);
        assertEq(IERC20(token).balanceOf(address(referral)), 0);
    }

    function test_useReferral_No_Rebate() public {
        _test_useReferral_No_Rebate();
    }

    function _test_useReferral_Rebate_Primary_Only() internal {
        address token = getPoolToken();

        vm.startPrank(address(pool));
        deal(token, address(pool), tradingFee);
        IERC20(token).approve(address(referral), primaryRebate);

        referral.useReferral(users.trader, users.referrer, token, _primaryRebate, ZERO);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
        assertEq(IERC20(token).balanceOf(address(pool)), tradingFee - primaryRebate);
        assertEq(IERC20(token).balanceOf(address(referral)), primaryRebate);
    }

    function test_useReferral_Rebate_Primary_Only() public {
        _test_useReferral_Rebate_Primary_Only();
    }

    function _test_useReferral_Rebate_Primary_And_Secondary(
        uint256 __tradingFee
    ) internal returns (address, uint256, uint256) {
        address token = getPoolToken();

        vm.prank(users.referrer);
        referral.__trySetReferrer(secondaryReferrer);

        vm.startPrank(address(pool));
        deal(token, address(pool), __tradingFee);

        (UD60x18 __primaryRebate, UD60x18 __secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            users.referrer,
            fromTokenDecimals(__tradingFee)
        );

        UD60x18 __totalRebate = __primaryRebate + __secondaryRebate;

        IERC20(token).approve(address(referral), toTokenDecimals(__totalRebate));

        referral.useReferral(users.trader, users.referrer, token, __primaryRebate, __secondaryRebate);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
        assertEq(IERC20(token).balanceOf(address(pool)), __tradingFee - toTokenDecimals(__totalRebate));
        assertEq(IERC20(token).balanceOf(address(referral)), toTokenDecimals(__totalRebate));

        return (token, toTokenDecimals(__primaryRebate), toTokenDecimals(__secondaryRebate));
    }

    function test_useReferral_Rebate_Primary_And_Secondary() public {
        _test_useReferral_Rebate_Primary_And_Secondary(200e18);
    }

    function test_useReferral_RevertIf_Pool_Not_Authorized() public {
        vm.prank(users.trader);
        vm.expectRevert(IReferral.Referral__PoolNotAuthorized.selector);

        referral.useReferral(users.trader, users.referrer, address(0), ud(0), ud(0));
    }

    function test_claimRebate_Success() public {
        (
            address token0,
            uint256 primaryRebate0,
            uint256 secondaryRebate0
        ) = _test_useReferral_Rebate_Primary_And_Secondary(200e18);

        isCallTest = false;
        (
            address token1,
            uint256 primaryRebate1,
            uint256 secondaryRebate1
        ) = _test_useReferral_Rebate_Primary_And_Secondary(100e18);

        ERC20Mock mockToken = new ERC20Mock("MOCK", 18);
        uint256 mockTokenBalance = 1000e18;
        mockToken.mint(address(referral), mockTokenBalance);

        {
            address[] memory tokens = new address[](3);
            tokens[0] = address(mockToken);
            tokens[1] = token0;
            tokens[2] = token1;

            vm.prank(users.referrer);
            referral.claimRebate(tokens);

            vm.prank(secondaryReferrer);
            referral.claimRebate(tokens);
        }

        assertEq(mockToken.balanceOf(address(referral)), mockTokenBalance);
        assertEq(IERC20(token0).balanceOf(address(referral)), 0);
        assertEq(IERC20(token1).balanceOf(address(referral)), 0);

        assertEq(mockToken.balanceOf(users.referrer), 0);
        assertEq(mockToken.balanceOf(secondaryReferrer), 0);

        assertEq(IERC20(token0).balanceOf(users.referrer), primaryRebate0);
        assertEq(IERC20(token0).balanceOf(secondaryReferrer), secondaryRebate0);

        assertEq(IERC20(token1).balanceOf(users.referrer), primaryRebate1);
        assertEq(IERC20(token1).balanceOf(secondaryReferrer), secondaryRebate1);

        {
            (address[] memory tokens, uint256[] memory rebates) = referral.getRebates(users.referrer);

            assertEq(tokens.length, 0);
            assertEq(rebates.length, 0);

            (tokens, rebates) = referral.getRebates(secondaryReferrer);

            assertEq(tokens.length, 0);
            assertEq(rebates.length, 0);
        }
    }
}
