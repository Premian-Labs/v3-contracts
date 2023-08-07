// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO} from "../libraries/Constants.sol";
import {UD50x28} from "../libraries/UD50x28.sol";

import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

import {IERC20Router} from "../router/IERC20Router.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

library PoolStorage {
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    // Token id for SHORT
    uint256 internal constant SHORT = 0;
    // Token id for LONG
    uint256 internal constant LONG = 1;

    // The version of LP token, used to know how to decode it, if upgrades are made
    uint8 internal constant TOKEN_VERSION = 1;

    UD60x18 internal constant MIN_TICK_DISTANCE = UD60x18.wrap(0.001e18); // 0.001
    UD60x18 internal constant MIN_TICK_PRICE = UD60x18.wrap(0.001e18); // 0.001
    UD60x18 internal constant MAX_TICK_PRICE = UD60x18.wrap(1e18); // 1

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.Pool");

    struct Layout {
        // ERC20 token addresses
        address base;
        address quote;
        address oracleAdapter;
        // token metadata
        uint8 baseDecimals;
        uint8 quoteDecimals;
        uint256 maturity;
        // Whether its a call or put pool
        bool isCallPool;
        // Index of all existing ticks sorted
        DoublyLinkedList.Bytes32List tickIndex;
        mapping(UD60x18 normalizedPrice => IPoolInternal.Tick) ticks;
        UD50x28 marketPrice;
        UD50x28 globalFeeRate;
        UD60x18 protocolFees;
        UD60x18 strike;
        UD50x28 liquidityRate;
        UD50x28 longRate;
        UD50x28 shortRate;
        // Current tick normalized price
        UD60x18 currentTick;
        // Settlement price of option
        UD60x18 settlementPrice;
        mapping(bytes32 key => Position.Data) positions;
        // Size of OB quotes already filled
        mapping(address provider => mapping(bytes32 hash => UD60x18 amountFilled)) quoteOBAmountFilled;
        // Set to true after maturity, to remove factory initialization discount
        bool initFeeDiscountRemoved;
        EnumerableSet.UintSet tokenIds;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function getPoolTokenDecimals(Layout storage l) internal view returns (uint8) {
        return l.isCallPool ? l.baseDecimals : l.quoteDecimals;
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(Layout storage l, uint256 value) internal view returns (uint256) {
        uint8 decimals = l.getPoolTokenDecimals();
        return OptionMath.scaleDecimals(value, 18, decimals);
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(Layout storage l, int256 value) internal view returns (int256) {
        uint8 decimals = l.getPoolTokenDecimals();
        return OptionMath.scaleDecimals(value, 18, decimals);
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(Layout storage l, UD60x18 value) internal view returns (uint256) {
        return l.toPoolTokenDecimals(value.unwrap());
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(Layout storage l, SD59x18 value) internal view returns (int256) {
        return l.toPoolTokenDecimals(value.unwrap());
    }

    /// @notice Adjust decimals of a value with pool token decimals to 18 decimals
    function fromPoolTokenDecimals(Layout storage l, uint256 value) internal view returns (UD60x18) {
        uint8 decimals = l.getPoolTokenDecimals();
        return ud(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Adjust decimals of a value with pool token decimals to 18 decimals
    function fromPoolTokenDecimals(Layout storage l, int256 value) internal view returns (SD59x18) {
        uint8 decimals = l.getPoolTokenDecimals();
        return sd(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Get the token used as options collateral and for payment of premium. (quote for PUT pools, base for CALL
    ///         pools)
    function getPoolToken(Layout storage l) internal view returns (address) {
        return l.isCallPool ? l.base : l.quote;
    }

    /// @notice calculate ERC1155 token id for given option parameters
    /// @param operator The current operator of the position
    /// @param lower The lower bound normalized option price (18 decimals)
    /// @param upper The upper bound normalized option price (18 decimals)
    /// @return tokenId token id
    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal pure returns (uint256 tokenId) {
        if (lower >= upper || lower < MIN_TICK_PRICE || upper > MAX_TICK_PRICE)
            revert IPoolInternal.Pool__InvalidRange(lower, upper);

        tokenId =
            (uint256(TOKEN_VERSION) << 252) +
            (uint256(orderType) << 180) +
            (uint256(uint160(operator)) << 20) +
            ((upper.unwrap() / MIN_TICK_DISTANCE.unwrap()) << 10) +
            (lower.unwrap() / MIN_TICK_DISTANCE.unwrap());
    }

    /// @notice derive option maturity and strike price from ERC1155 token id
    /// @param tokenId token id
    /// @return version The version of LP token, used to know how to decode it, if upgrades are made
    /// @return operator The current operator of the position
    /// @return lower The lower bound normalized option price (18 decimals)
    /// @return upper The upper bound normalized option price (18 decimals)
    function parseTokenId(
        uint256 tokenId
    )
        internal
        pure
        returns (uint8 version, address operator, UD60x18 lower, UD60x18 upper, Position.OrderType orderType)
    {
        uint256 minTickDistance = MIN_TICK_DISTANCE.unwrap();

        assembly {
            version := shr(252, tokenId)
            orderType := and(shr(180, tokenId), 0xF) // 4 bits mask
            operator := shr(20, tokenId)
            upper := mul(
                and(shr(10, tokenId), 0x3FF), // 10 bits mask
                minTickDistance
            )
            lower := mul(
                and(tokenId, 0x3FF), // 10 bits mask
                minTickDistance
            )
        }
    }

    /// @notice Converts `value` to pool token decimals and approves `spender`
    function approve(IERC20 token, address spender, UD60x18 value) internal {
        token.approve(spender, PoolStorage.layout().toPoolTokenDecimals(value));
    }

    /// @notice Converts `value` to pool token decimals and transfers `token`
    function safeTransferFrom(IERC20Router router, address token, address from, address to, UD60x18 value) internal {
        router.safeTransferFrom(token, from, to, PoolStorage.layout().toPoolTokenDecimals(value));
    }

    function safeTransferIgnoreDust(IERC20 token, address to, uint256 value) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 balance = IERC20(l.getPoolToken()).balanceOf(address(this));
        if (balance < value) value = balance;
        token.safeTransfer(to, value);
    }

    function safeTransferIgnoreDust(IERC20 token, address to, UD60x18 value) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        safeTransferIgnoreDust(token, to, toPoolTokenDecimals(l, value));
    }
}
