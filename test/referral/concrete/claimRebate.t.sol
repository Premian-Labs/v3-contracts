// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

contract Referral_ClaimRebate_Concrete_Test is Referral_Integration_Shared_Test {
    function test_claimRebate_Success() public {
        uint256 referrerBaseBefore = base.balanceOf(users.referrer);
        uint256 referrerQuoteBefore = quote.balanceOf(users.referrer);

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

            changePrank(users.referrer);
            referral.claimRebate(tokens);

            changePrank(secondaryReferrer);
            referral.claimRebate(tokens);
        }

        assertEq(mockToken.balanceOf(address(referral)), mockTokenBalance);
        assertEq(IERC20(token0).balanceOf(address(referral)), 0);
        assertEq(IERC20(token1).balanceOf(address(referral)), 0);

        assertEq(mockToken.balanceOf(users.referrer), 0);
        assertEq(mockToken.balanceOf(secondaryReferrer), 0);

        assertEq(IERC20(token0).balanceOf(users.referrer), referrerBaseBefore + primaryRebate0);
        assertEq(IERC20(token0).balanceOf(secondaryReferrer), secondaryRebate0);

        assertEq(IERC20(token1).balanceOf(users.referrer), referrerQuoteBefore + primaryRebate1);
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

    function _test_useReferral_Rebate_Primary_And_Secondary(
        uint256 __tradingFee
    ) internal returns (address, uint256, uint256) {
        address token = getPoolToken();
        changePrank({msgSender: users.referrer});

        referral.__trySetReferrer(secondaryReferrer);

        changePrank(address(pool));
        deal(token, address(pool), __tradingFee);

        (UD60x18 __primaryRebate, UD60x18 __secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            users.referrer,
            fromTokenDecimals(__tradingFee)
        );

        UD60x18 __totalRebate = __primaryRebate + __secondaryRebate;

        IERC20(token).approve(address(referral), toTokenDecimals(__totalRebate));

        referral.useReferral(users.trader, users.referrer, token, __primaryRebate, __secondaryRebate);

        assertEq(referral.getReferrer(users.trader), users.referrer);
        assertEq(IERC20(token).balanceOf(address(pool)), __tradingFee - toTokenDecimals(__totalRebate));
        assertEq(IERC20(token).balanceOf(address(referral)), toTokenDecimals(__totalRebate));

        return (token, toTokenDecimals(__primaryRebate), toTokenDecimals(__secondaryRebate));
    }
}
