// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {PRBMathExtra} from "../../contracts/libraries/PRBMathExtra.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTakerFeeTest is DeployTest {
    UD60x18 internal constant PREMIUM_FEE_PERCENTAGE = UD60x18.wrap(0.03e18); // 3%
    UD60x18 internal constant COLLATERAL_FEE_PERCENTAGE =
        UD60x18.wrap(0.003e18); // 0.3%

    function stake(uint256 amount) internal {
        vm.startPrank(users.trader);

        deal(premia, users.trader, amount);
        IERC20(premia).approve(address(vxPremia), amount);
        vxPremia.stake(amount, uint64(2.5 * 365 days));

        vm.stopPrank();
    }

    function _test_takerFee(
        bool isCall,
        bool premiumIsFee,
        bool isPremiumNormalized,
        UD60x18 size,
        UD60x18 price,
        UD60x18 discount
    ) internal {
        UD60x18 deNormalizedPremium = contractsToCollateral(
            price * size,
            isCall
        );

        UD60x18 normalizedPremium = collateralToContracts(
            deNormalizedPremium,
            isCall
        );

        uint256 premium = scaleDecimals(
            isPremiumNormalized ? normalizedPremium : deNormalizedPremium,
            isCall
        );

        UD60x18 fee;

        {
            UD60x18 premiumFee = normalizedPremium * PREMIUM_FEE_PERCENTAGE;
            UD60x18 notionalFee = size * COLLATERAL_FEE_PERCENTAGE;

            assertEq(
                premiumFee > notionalFee,
                premiumIsFee,
                "premiumFee should be greater than notionalFee"
            );

            fee = PRBMathExtra.max(premiumFee, notionalFee);

            if (discount > ud(0)) {
                fee = fee - fee * discount;
            }
        }

        uint256 protocolFee = pool.takerFee(
            users.trader,
            size,
            premium,
            isPremiumNormalized
        );

        uint256 expectedFee = scaleDecimals(
            contractsToCollateral(fee, isCall),
            isCall
        );

        assertEq(
            protocolFee,
            expectedFee,
            "protocol fee should equal expected"
        );
    }

    function test_takerFee_premium_fee_without_discount() public {
        _test_takerFee(
            poolKey.isCallPool,
            true,
            false,
            ud(100 ether),
            ud(1 ether),
            ud(0)
        );
    }

    function test_takerFee_premium_fee_without_discount_premium_normalized()
        public
    {
        _test_takerFee(
            poolKey.isCallPool,
            true,
            true,
            ud(100 ether),
            ud(1 ether),
            ud(0)
        );
    }

    function test_takerFee_collateral_fee_without_discount() public {
        _test_takerFee(
            poolKey.isCallPool,
            false,
            false,
            ud(100 ether),
            ud(0.01 ether),
            ud(0)
        );
    }

    function test_takerFee_collateral_fee_without_discount_premium_normalized()
        public
    {
        _test_takerFee(
            poolKey.isCallPool,
            false,
            true,
            ud(100 ether),
            ud(0.01 ether),
            ud(0)
        );
    }

    function test_takerFee_premium_fee_with_discount() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(
            poolKey.isCallPool,
            true,
            false,
            ud(100 ether),
            ud(1 ether),
            ud(discount)
        );

        vm.stopPrank();
    }

    function test_takerFee_premium_fee_with_discount_premium_normalized()
        public
    {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(
            poolKey.isCallPool,
            true,
            true,
            ud(100 ether),
            ud(1 ether),
            ud(discount)
        );

        vm.stopPrank();
    }

    function test_takerFee_collateral_fee_with_discount() public {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(
            poolKey.isCallPool,
            false,
            false,
            ud(100 ether),
            ud(0.01 ether),
            ud(discount)
        );

        vm.stopPrank();
    }

    function test_takerFee_collateral_fee_with_discount_premium_normalized()
        public
    {
        stake(100_000 ether);
        uint256 discount = vxPremia.getDiscount(users.trader);

        vm.startPrank(users.trader);

        _test_takerFee(
            poolKey.isCallPool,
            false,
            true,
            ud(100 ether),
            ud(0.01 ether),
            ud(discount)
        );

        vm.stopPrank();
    }
}
