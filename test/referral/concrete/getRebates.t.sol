// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";

contract Referral_GetRebates_Success_Concrete_Test is Referral_Integration_Shared_Test {
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
        changePrank(users.trader);
        (UD60x18 __primaryRebate, UD60x18 __secondaryRebate) = referral.getRebateAmounts(
            users.trader,
            address(0),
            _tradingFee
        );

        UD60x18 __totalRebate = __primaryRebate + __secondaryRebate;

        assertEq(__totalRebate, ZERO);
        assertEq(__primaryRebate, ZERO);
        assertEq(__secondaryRebate, ZERO);

        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, users.referrer, _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _primaryRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, ZERO);

        referral.__trySetReferrer(users.referrer);

        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _primaryRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, ZERO);

        changePrank({msgSender: users.referrer});
        referral.__trySetReferrer(secondaryReferrer);

        changePrank({msgSender: users.trader});
        (__primaryRebate, __secondaryRebate) = referral.getRebateAmounts(users.trader, address(0), _tradingFee);
        __totalRebate = __primaryRebate + __secondaryRebate;
        assertEq(__totalRebate, _totalRebate);
        assertEq(__primaryRebate, _primaryRebate);
        assertEq(__secondaryRebate, _secondaryRebate);
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
