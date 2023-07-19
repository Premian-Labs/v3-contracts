// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";

import {Pricing} from "contracts/libraries/Pricing.sol";
import {IPricing} from "contracts/libraries/IPricing.sol";
import {PricingMock} from "contracts/test/libraries/PricingMock.sol";

contract PricingTest is Test, Assertions {
    using Pricing for Pricing.Args;

    PricingMock internal pricing;
    Pricing.Args internal args;

    function setUp() public {
        pricing = new PricingMock();
        args = Pricing.Args({
            liquidityRate: ud(1e18),
            marketPrice: ud(0.25e18),
            lower: ud(0.25e18),
            upper: ud(0.75e18),
            isBuy: true
        });
    }

    function test_proportion_ReturnExpectedValue() public {
        UD60x18 lower = ud(0.25e18);
        UD60x18 upper = ud(0.75e18);

        assertEq(Pricing.proportion(lower, upper, ud(0.25e18)), ud(0));
        assertEq(Pricing.proportion(lower, upper, ud(0.75e18)), ud(1e18));
        assertEq(Pricing.proportion(lower, upper, ud(0.5e18)), ud(0.5e18));
    }

    function test_proportion_RevertIf_LowerGteUpper() public {
        UD60x18 lower = ud(0.75e18);
        UD60x18 upper = ud(0.25e18);

        vm.expectRevert(abi.encodeWithSelector(IPricing.Pricing__UpperNotGreaterThanLower.selector, lower, upper));

        pricing.proportion(lower, upper, ud(0));
    }

    function test_proportion_RevertIf_LowerGtMarketPrice() public {
        UD60x18 lower = ud(0.25e18);
        UD60x18 upper = ud(0.75e18);
        UD60x18 marketPrice = ud(0.2e18);

        vm.expectRevert(abi.encodeWithSelector(IPricing.Pricing__PriceOutOfRange.selector, lower, upper, marketPrice));

        pricing.proportion(lower, upper, marketPrice);
    }

    function test_proportion_RevertIf_MarketPriceGtUpper() public {
        UD60x18 lower = ud(0.25e18);
        UD60x18 upper = ud(0.75e18);
        UD60x18 marketPrice = ud(0.8e18);

        vm.expectRevert(abi.encodeWithSelector(IPricing.Pricing__PriceOutOfRange.selector, lower, upper, marketPrice));

        pricing.proportion(lower, upper, marketPrice);
    }

    // prettier-ignore
    function test_amountOfTicksBetween_ReturnExpectedValue() public {
        assertEq(Pricing.amountOfTicksBetween(ud(0.001e18), ud(1e18)), ud(999e18));
        assertEq(Pricing.amountOfTicksBetween(ud(0.05e18), ud(0.95e18)), ud(900e18));
        assertEq(Pricing.amountOfTicksBetween(ud(0.49e18), ud(0.491e18)), ud(1e18));
    }

    function test_amountOfTicksBetween_RevertIf_LowerGteUpper() public {
        UD60x18 lower = ud(0.2e18);
        UD60x18 upper = ud(0.01e18);

        vm.expectRevert(abi.encodeWithSelector(IPricing.Pricing__UpperNotGreaterThanLower.selector, lower, upper));

        pricing.amountOfTicksBetween(lower, upper);

        lower = ud(0.1e18);
        upper = ud(0.1e18);

        vm.expectRevert(abi.encodeWithSelector(IPricing.Pricing__UpperNotGreaterThanLower.selector, lower, upper));

        pricing.amountOfTicksBetween(lower, upper);
    }

    function test_liquidity_ReturnExpectedValue() public {
        UD60x18[4][3] memory expected;

        expected[0] = [ud(1e18), ud(0.001e18), ud(1e18), ud(999e18)];
        expected[1] = [ud(5e18), ud(0.05e18), ud(0.95e18), ud(4500e18)];
        expected[2] = [ud(10e18), ud(0.49e18), ud(0.491e18), ud(10e18)];

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(
                Pricing.liquidity(
                    Pricing.Args({
                        liquidityRate: expected[i][0],
                        marketPrice: ud(0),
                        lower: expected[i][1],
                        upper: expected[i][2],
                        isBuy: true
                    })
                ),
                expected[i][3]
            );
        }
    }

    function test_bidLiquidity_ReturnExpectedValue() public {
        args.isBuy = false;
        assertEq(args.bidLiquidity(), ud(0));

        args.marketPrice = args.lower.avg(args.upper);
        assertEq(args.bidLiquidity(), args.liquidity() / ud(2e18));

        args.marketPrice = ud(0.75e18);
        assertEq(args.bidLiquidity(), args.liquidity());
    }

    function test_askLiquidity_ReturnExpectedValue() public {
        assertEq(args.askLiquidity(), args.liquidity());

        args.marketPrice = args.lower.avg(args.upper);
        assertEq(args.askLiquidity(), args.liquidity() / ud(2e18));

        args.marketPrice = ud(0.75e18);
        assertEq(args.askLiquidity(), ud(0));
    }

    function test_maxTradeSize_ReturnExpectedValue_ForBuyOrder() public {
        args.marketPrice = args.upper;
        assertEq(args.maxTradeSize(), args.askLiquidity());
    }

    function test_maxTradeSize_ReturnExpectedValue_ForSellOrder() public {
        args.marketPrice = args.upper;
        args.isBuy = false;
        assertEq(args.maxTradeSize(), args.bidLiquidity());
    }

    function test_price_ReturnUpperTick_ForBuyOrder_IfLiqIsZero() public {
        args.liquidityRate = ud(0);
        args.marketPrice = ud(0.5e18);
        args.isBuy = true;
        assertEq(args.price(ud(1e18)), args.upper);
    }

    function test_price_ReturnLowerTick_ForSellOrder_IfLiqIsZero() public {
        args.liquidityRate = ud(0);
        args.marketPrice = ud(0.5e18);
        args.isBuy = false;
        assertEq(args.price(ud(1e18)), args.lower);
    }

    function test_price_ReturnPrice_IfTradeSizeIsZero() public {
        args.liquidityRate = ud(1e18);
        args.marketPrice = ud(0.5e18);
        args.isBuy = true;
        assertEq(args.price(ud(0)), args.lower);

        args.isBuy = false;
        assertEq(args.price(ud(0)), args.upper);
    }

    function test_price_ReturnPrice_ForBuyOrder_IfLiqGtZero_AndTradeSizeGtZero() public {
        args.marketPrice = ud(0.75e18);
        args.isBuy = true;

        UD60x18 liq = args.liquidity();
        UD60x18 askLiq = args.askLiquidity();
        UD60x18 bidLiq = args.bidLiquidity();

        // price == upper
        // ask side liquidity == 0
        // bid side liquidity == liquidity

        assertEq(askLiq, ud(0));
        assertEq(bidLiq, liq);

        assertEq(args.price(askLiq), args.lower);
        assertEq(args.price(bidLiq), args.upper);

        args.marketPrice = args.lower;
        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == lower
        // ask side liquidity == liquidity
        // bid side liquidity == 0

        assertEq(askLiq, liq);
        assertEq(bidLiq, ud(0));

        assertEq(args.price(askLiq), args.upper);
        assertEq(args.price(bidLiq), args.lower);

        UD60x18 avg = args.lower.avg(args.upper);
        args.marketPrice = avg;
        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == average(lower, upper)
        // ask side liquidity == liquidity/2
        // bid side liquidity == liquidity/2

        assertEq(askLiq, liq / ud(2e18));
        assertEq(bidLiq, liq / ud(2e18));

        assertEq(args.price(askLiq), avg);
        assertEq(args.price(bidLiq), avg);
    }

    function test_price_ReturnPrice_ForSellOrder_IfLiqGtZero_AndTradeSizeGtZero() public {
        args.marketPrice = ud(0.75e18);
        args.isBuy = false;

        UD60x18 liq = args.liquidity();
        UD60x18 askLiq = args.askLiquidity();
        UD60x18 bidLiq = args.bidLiquidity();

        // price == upper
        // ask side liquidity == 0
        // bid side liquidity == liquidity

        assertEq(askLiq, ud(0));
        assertEq(bidLiq, liq);

        assertEq(args.price(askLiq), args.upper);
        assertEq(args.price(bidLiq), args.lower);

        args.marketPrice = args.lower;
        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == lower
        // ask side liquidity == liquidity
        // bid side liquidity == 0

        assertEq(askLiq, liq);
        assertEq(bidLiq, ud(0));

        assertEq(args.price(askLiq), args.lower);
        assertEq(args.price(bidLiq), args.upper);

        UD60x18 avg = args.lower.avg(args.upper);
        args.marketPrice = avg;
        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == average(lower, upper)
        // ask side liquidity == liquidity/2
        // bid side liquidity == liquidity/2

        assertEq(askLiq, liq / ud(2e18));
        assertEq(bidLiq, liq / ud(2e18));

        assertEq(args.price(askLiq), avg);
        assertEq(args.price(bidLiq), avg);
    }

    // prettier-ignore
    function test_price_RevertIf_PriceOutOfRange() public {
        args.marketPrice = ud(0.75e18);

        UD60x18 liq = args.liquidity();
        vm.expectRevert(IPricing.Pricing__PriceCannotBeComputedWithinTickRange.selector);
        pricing.price(args, liq * ud(2e18));

        args.isBuy = false;
        vm.expectRevert(IPricing.Pricing__PriceCannotBeComputedWithinTickRange.selector);
        pricing.price(args, liq * ud(2e18));
    }

    function test_nextPrice_ReturnUpperTick_ForBuyOrder_IfLiqIsZero() public {
        args.liquidityRate = ud(0);
        args.marketPrice = ud(0.5e18);
        args.isBuy = true;
        assertEq(args.nextPrice(ud(1e18)), args.upper);
    }

    function test_nextPrice_ReturnLowerTick_ForSellOrder_IfLiqIsZero() public {
        args.liquidityRate = ud(0);
        args.marketPrice = ud(0.5e18);
        args.isBuy = false;
        assertEq(args.nextPrice(ud(1e18)), args.lower);
    }

    function test_nextPrice_ReturnPrice_IfTradeSizeIsZero() public {
        args.liquidityRate = ud(1e18);
        args.marketPrice = ud(0.5e18);

        args.isBuy = true;
        assertEq(args.nextPrice(ud(0)), args.marketPrice);

        args.isBuy = false;
        assertEq(args.nextPrice(ud(0)), args.marketPrice);
    }

    function test_nextPrice_ReturnNextPrice_ForBuyOrder_IfLiquidityGtZero_AndTradeSizeGtZero() public {
        args.isBuy = true;

        UD60x18 liq = args.liquidity();
        UD60x18 askLiq = args.askLiquidity();
        UD60x18 bidLiq = args.bidLiquidity();

        // price == lower
        // ask side liquidity == liquidity
        // bid side liquidity == 0

        assertEq(askLiq, liq);
        assertEq(bidLiq, ud(0));

        assertEq(args.nextPrice(askLiq), args.upper);

        UD60x18 avg = args.lower.avg(args.upper); // 0.5e18
        assertEq(args.nextPrice(askLiq / ud(2e18)), avg);

        avg = args.lower.avg(avg); // 0.375e18
        assertEq(args.nextPrice(askLiq / ud(4e18)), avg);

        avg = args.lower.avg(args.upper); // 0.5e18
        args.marketPrice = avg;

        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == average(lower, upper)
        // ask side liquidity == liquidity/2
        // bid side liquidity == liquidity/2

        assertEq(askLiq, liq / ud(2e18));
        assertEq(bidLiq, liq / ud(2e18));

        assertEq(args.nextPrice(askLiq), args.upper);
        assertEq(args.nextPrice(bidLiq), args.upper);

        avg = args.marketPrice.avg(args.upper); // 0.625e18
        assertEq(args.nextPrice(askLiq / ud(2e18)), avg);
        assertEq(args.nextPrice(bidLiq / ud(2e18)), avg);

        avg = args.marketPrice.avg(avg); // 0.5625e18
        assertEq(args.nextPrice(askLiq / ud(4e18)), avg);
        assertEq(args.nextPrice(bidLiq / ud(4e18)), avg);
    }

    function test_nextPrice_ReturnNextPrice_ForSellOrder_IfLiquidityGtZero_AndTradeSizeGtZero() public {
        args.marketPrice = ud(0.75e18);
        args.isBuy = false;

        UD60x18 liq = args.liquidity();
        UD60x18 askLiq = args.askLiquidity();
        UD60x18 bidLiq = args.bidLiquidity();

        // price == upper
        // ask side liquidity == 0
        // bid side liquidity == liquidity

        assertEq(askLiq, ud(0));
        assertEq(bidLiq, liq);

        assertEq(args.nextPrice(bidLiq), args.lower);

        UD60x18 avg = args.lower.avg(args.upper); // 0.5e18
        assertEq(args.nextPrice(bidLiq / ud(2e18)), avg);

        avg = args.upper.avg(avg); // 0.625e18
        assertEq(args.nextPrice(bidLiq / ud(4e18)), avg);

        avg = args.lower.avg(args.upper); // 0.5e18
        args.marketPrice = avg;

        liq = args.liquidity();
        askLiq = args.askLiquidity();
        bidLiq = args.bidLiquidity();

        // price == average(lower, upper)
        // ask side liquidity == liquidity/2
        // bid side liquidity == liquidity/2

        assertEq(askLiq, liq / ud(2e18));
        assertEq(bidLiq, liq / ud(2e18));

        assertEq(args.nextPrice(askLiq), args.lower);
        assertEq(args.nextPrice(bidLiq), args.lower);

        avg = args.marketPrice.avg(args.lower); // 0.375e18
        assertEq(args.nextPrice(askLiq / ud(2e18)), avg);
        assertEq(args.nextPrice(bidLiq / ud(2e18)), avg);

        avg = args.marketPrice.avg(avg); // 0.4375e18
        assertEq(args.nextPrice(askLiq / ud(4e18)), avg);
        assertEq(args.nextPrice(bidLiq / ud(4e18)), avg);
    }

    // prettier-ignore
    function test_nextPrice_RevertIf_PriceOutOfRange() public {
        args.marketPrice = ud(0.75e18);

        UD60x18 liq = args.liquidity();
        vm.expectRevert(IPricing.Pricing__PriceCannotBeComputedWithinTickRange.selector);
        pricing.nextPrice(args, liq * ud(2e18));

        args.isBuy = false;
        vm.expectRevert(IPricing.Pricing__PriceCannotBeComputedWithinTickRange.selector);
        pricing.nextPrice(args, liq * ud(2e18));
    }
}
