// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Math} from "../libraries/Math.sol";
import {PricingCurve} from "../libraries/PricingCurve.sol";

import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolInternal is ERC1155EnumerableInternal {
    using PoolStorage for PoolStorage.Layout;
    using LinkedList for LinkedList.List;

    error PoolInternal__ZeroSize();
    error PoolInternal__ExpiredOption();

    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    uint256 private constant PROTOCOL_FEE_RATE = 3e3; // 30%

    /**
     * @notice Calculates the fee for a trade based on the `size` and `premium` of the trade
     * @param size The size of a trade (number of contracts)
     * @param premium The total cost of option(s) for a purchase
     * @return The taker fee for an option trade
     */
    function _takerFee(uint256 size, uint256 premium)
        internal
        pure
        returns (uint256)
    {
        uint256 premiumFee = (premium * 300) / INVERSE_BASIS_POINT; // 3% of premium
        uint256 notionalFee = (size * 30) / INVERSE_BASIS_POINT; // 0.3% of notional
        return Math.max(premiumFee, notionalFee);
    }

    function _getQuote(uint256 size, PoolStorage.Side tradeSide)
        internal
        view
        returns (uint256)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (size == 0) revert PoolInternal__ZeroSize();
        if (block.timestamp > l.maturity) revert PoolInternal__ExpiredOption();

        bool isBuy = tradeSide == PoolStorage.Side.BUY;

        uint256 totalPremium = 0;
        uint256 marketPrice = l.marketPrice;
        uint256 currentTick = l.tick;

        while (size > 0) {
            PricingCurve.Args memory args = PricingCurve.Args(
                l.liquidityRate,
                l.minTickDistance(),
                l.tickIndex.getPreviousNode(currentTick),
                l.tickIndex.getNextNode(currentTick),
                tradeSide
            );

            uint256 maxSize = PricingCurve.maxTradeSize(args, l.marketPrice);
            uint256 tradeSize = Math.min(size, maxSize);

            uint256 nextMarketPrice = PricingCurve.nextPrice(
                args,
                marketPrice,
                tradeSize
            );
            uint256 quotePrice = PricingCurve.mean(
                marketPrice,
                nextMarketPrice
            );
            uint256 premium = (quotePrice * tradeSize) / 1e18;
            uint256 takerFee = _takerFee(tradeSize, premium);
            uint256 takerPremium = premium + takerFee;

            // Update price and liquidity variables
            uint256 protocolFee = (takerFee * PROTOCOL_FEE_RATE) /
                INVERSE_BASIS_POINT;
            uint256 makerRebate = takerFee - protocolFee;
            uint256 makerPremium = premium + makerRebate;

            // ToDo : Remove ?
            // l.globalFeeRate += (makerRebate * 1e18) / l.liquidityRate;
            totalPremium += isBuy ? takerPremium : makerPremium;

            marketPrice = nextMarketPrice;

            // Check if a tick cross is required
            if (maxSize > size) {
                // The trade can be done within the current tick range
                size = 0;
            } else {
                // The trade will require crossing into the next tick range
                size -= maxSize;

                if (isBuy) {
                    currentTick = args.upper;
                } else {
                    currentTick = args.lower;
                }
            }
        }

        return totalPremium;
    }
}
