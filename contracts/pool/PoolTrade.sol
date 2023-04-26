// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IFlashLoanCallback} from "./IFlashLoanCallback.sol";
import {IPoolTrade} from "./IPoolTrade.sol";

import {iZERO, ZERO} from "../libraries/Constants.sol";
import {Position} from "../libraries/Position.sol";

contract PoolTrade is IPoolTrade, PoolInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    // ToDo : Define final value
    // ToDo : Make this part of global pool settings ?
    UD60x18 constant FLASH_LOAN_FEE = UD60x18.wrap(0.0009e18); // 0.09%

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver
    ) PoolInternal(factory, router, wrappedNativeToken, feeReceiver) {}

    /// @inheritdoc IPoolTrade
    function getQuoteAMM(
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premiumNet, uint256 takerFee) {
        return _getQuoteAMM(size, isBuy);
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteRFQ(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata signature
    )
        external
        nonReentrant
        returns (uint256 premiumTaker, Position.Delta memory delta)
    {
        return
            _fillQuoteRFQ(
                FillQuoteRFQArgsInternal(msg.sender, size, signature, true),
                quoteRFQ
            );
    }

    /// @inheritdoc IPoolTrade
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit
    )
        external
        nonReentrant
        returns (uint256 totalPremium, Position.Delta memory delta)
    {
        return
            _trade(
                TradeArgsInternal(msg.sender, size, isBuy, premiumLimit, true)
            );
    }

    /// @inheritdoc IPoolTrade
    function flashLoan(
        uint256 amount,
        bytes calldata data
    ) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();

        IERC20 token = IERC20(l.getPoolToken());
        uint256 startBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, amount);

        UD60x18 fee = l.fromPoolTokenDecimals(amount) * FLASH_LOAN_FEE;
        uint256 _fee = l.toPoolTokenDecimals(fee);

        IFlashLoanCallback(msg.sender).premiaFlashLoanCallback(
            address(token),
            amount + _fee,
            data
        );

        uint256 endBalance = token.balanceOf(address(this));
        uint256 endBalanceRequired = startBalance + _fee;

        if (endBalance < endBalanceRequired) revert Pool__FlashLoanNotRepayed();

        emit FlashLoan(msg.sender, l.fromPoolTokenDecimals(amount), fee);
    }

    /// @inheritdoc IPoolTrade
    function cancelQuotesRFQ(bytes32[] calldata hashes) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();
        for (uint256 i = 0; i < hashes.length; i++) {
            l.quoteRFQAmountFilled[msg.sender][hashes[i]] = UD60x18.wrap(
                type(uint256).max
            );
            emit CancelQuoteRFQ(msg.sender, hashes[i]);
        }
    }

    /// @inheritdoc IPoolTrade
    function isQuoteRFQValid(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata sig
    ) external view returns (bool, InvalidQuoteRFQError) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        bytes32 quoteRFQHash = _quoteRFQHash(quoteRFQ);
        return
            _areQuoteRFQAndBalanceValid(
                l,
                FillQuoteRFQArgsInternal(msg.sender, size, sig, true),
                quoteRFQ,
                quoteRFQHash
            );
    }

    /// @inheritdoc IPoolTrade
    function getQuoteRFQFilledAmount(
        address provider,
        bytes32 quoteRFQHash
    ) external view returns (UD60x18) {
        return
            PoolStorage.layout().quoteRFQAmountFilled[provider][quoteRFQHash];
    }
}
