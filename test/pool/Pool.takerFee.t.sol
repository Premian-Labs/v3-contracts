// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO} from "contracts/libraries/Constants.sol";
import {PRBMathExtra} from "contracts/libraries/PRBMathExtra.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTakerFeeTest is DeployTest {
    UD60x18 internal constant AMM_PREMIUM_FEE_PERCENTAGE = UD60x18.wrap(0.03e18); // 3%
    UD60x18 internal constant AMM_NOTIONAL_FEE_PERCENTAGE = UD60x18.wrap(0.003e18); // 0.3%
    UD60x18 internal constant ORDERBOOK_NOTIONAL_FEE_PERCENTAGE = UD60x18.wrap(0.0008e18); // 0.08% of notional
    UD60x18 internal constant MAX_PREMIUM_FEE_PERCENTAGE = UD60x18.wrap(0.125e18); // 12.5%

    function stake(uint256 amount) internal {
        vm.startPrank(users.trader);

        deal(address(premia), users.trader, amount);
        premia.approve(address(vxPremia), amount);
        vxPremia.stake(amount, uint64(2.5 * 365 days));

        vm.stopPrank();
    }

    function _test_takerFee(
        bool premiumIsFee,
        bool isPremiumNormalized,
        UD60x18 size,
        UD60x18 price,
        UD60x18 discount
    ) internal {
        if (price == ZERO) {
            price = (AMM_NOTIONAL_FEE_PERCENTAGE / AMM_PREMIUM_FEE_PERCENTAGE) * size;
            isPremiumNormalized = true;
        }

        UD60x18 deNormalizedPremium = contractsToCollateral(price * size);

        UD60x18 normalizedPremium = collateralToContracts(deNormalizedPremium);

        uint256 premium = toTokenDecimals(isPremiumNormalized ? normalizedPremium : deNormalizedPremium);

        UD60x18 fee;

        {
            UD60x18 premiumFee1 = normalizedPremium * AMM_PREMIUM_FEE_PERCENTAGE;
            UD60x18 premiumFee2 = normalizedPremium * MAX_PREMIUM_FEE_PERCENTAGE;
            UD60x18 notionalFee = size * AMM_NOTIONAL_FEE_PERCENTAGE;

            assertEq(
                premiumFee1 > notionalFee || premiumFee2 > notionalFee,
                premiumIsFee,
                "premiumFee1 or premium 2 should be greater than notionalFee"
            );

            fee = PRBMathExtra.min(premiumFee2, PRBMathExtra.max(premiumFee1, notionalFee));

            if (discount > ud(0)) {
                fee = fee - fee * discount;
            }
        }

        assertEq(
            pool.takerFee(users.trader, size, premium, isPremiumNormalized, false),
            toTokenDecimals(contractsToCollateral(fee)),
            "protocol fee should equal expected"
        );

        UD60x18 orderbookFee = PRBMathExtra.min(
            normalizedPremium * MAX_PREMIUM_FEE_PERCENTAGE,
            size * ORDERBOOK_NOTIONAL_FEE_PERCENTAGE
        );

        if (discount > ud(0)) {
            orderbookFee = orderbookFee - orderbookFee * discount;
        }

        assertEq(
            pool.takerFee(users.trader, size, premium, isPremiumNormalized, true),
            toTokenDecimals(contractsToCollateral(orderbookFee))
        );
    }

    function test_takerFee_premium_fee_without_discount() public {
        _test_takerFee(true, false, ud(100 ether), ud(1 ether), ud(0));
    }

    function test_takerFee_premium_fee_without_discount_premium_normalized() public {
        _test_takerFee(true, true, ud(100 ether), ud(1 ether), ud(0));
    }

    function test_takerFee_collateral_fee_without_discount() public {
        _test_takerFee(false, false, ud(100 ether), ud(0.01 ether), ud(0));
    }

    function test_takerFee_collateral_fee_without_discount_premium_normalized() public {
        _test_takerFee(false, true, ud(100 ether), ud(0.01 ether), ud(0));
    }

    function test_takerFee_premium_fee_without_discount_zero_price() public {
        _test_takerFee(true, false, ud(100 ether), ud(0 ether), ud(0));
    }

    function test_takerFee_collateral_fee_without_discount_low_price() public {
        _test_takerFee(false, true, ud(100 ether), ud(0.0001 ether), ud(0));
    }

    function test_takerFee_premium_fee_with_discount() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(true, false, ud(100 ether), ud(1 ether), ud(discount));

        vm.stopPrank();
    }

    function test_takerFee_premium_fee_with_discount_null_address() public {
        stake(100_000 ether);

        users.trader = address(0);

        vm.startPrank(users.trader);

        _test_takerFee(true, false, ud(100 ether), ud(1 ether), ZERO);

        vm.stopPrank();
    }

    function test_takerFee_premium_fee_with_discount_premium_normalized() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(true, true, ud(100 ether), ud(1 ether), ud(discount));

        vm.stopPrank();
    }

    function test_takerFee_collateral_fee_with_discount() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(false, false, ud(100 ether), ud(0.01 ether), ud(discount));

        vm.stopPrank();
    }

    function test_takerFee_collateral_fee_with_discount_premium_normalized() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(false, true, ud(100 ether), ud(0.01 ether), ud(discount));

        vm.stopPrank();
    }
}
