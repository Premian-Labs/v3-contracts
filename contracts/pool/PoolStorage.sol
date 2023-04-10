// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO} from "../libraries/Constants.sol";

import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

import {IERC20Router} from "../router/IERC20Router.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

library PoolStorage {
    using SafeCast for uint64;
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    // Token id for SHORT
    uint256 internal constant SHORT = 0;
    // Token id for LONG
    uint256 internal constant LONG = 1;

    // The version of LP token, used to know how to decode it, if upgrades are made
    uint8 internal constant TOKEN_VERSION = 1;

    UD60x18 internal constant MIN_TICK_DISTANCE = UD60x18.wrap(0.001e18); // 0.001

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.Pool");

    struct Layout {
        // ERC20 token addresses
        address base;
        address quote;
        address oracleAdapter;
        // token metadata
        uint8 baseDecimals;
        uint8 quoteDecimals;
        uint64 maturity;
        // Whether its a call or put pool
        bool isCallPool;
        // Index of all existing ticks sorted
        DoublyLinkedList.Bytes32List tickIndex;
        mapping(UD60x18 => IPoolInternal.Tick) ticks;
        UD60x18 marketPrice;
        UD60x18 globalFeeRate;
        UD60x18 protocolFees;
        UD60x18 strike;
        UD60x18 liquidityRate;
        UD60x18 longRate;
        UD60x18 shortRate;
        // Current tick normalized price
        UD60x18 currentTick;
        // Settlement price of option
        UD60x18 settlementPrice;
        // key -> positionData
        mapping(bytes32 => Position.Data) positions;
        // Size of RFQ quotes already filled (provider -> quoteHash -> amountFilled)
        mapping(address => mapping(bytes32 => UD60x18)) quoteRFQAmountFilled;
        // Set to true after maturity, to handle factory initialization discount
        bool hasRemoved;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function getPoolTokenDecimals(
        Layout storage l
    ) internal view returns (uint8) {
        return l.isCallPool ? l.baseDecimals : l.quoteDecimals;
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(
        Layout storage l,
        uint256 value
    ) internal view returns (uint256) {
        uint8 decimals = l.getPoolTokenDecimals();
        return OptionMath.scaleDecimals(value, 18, decimals);
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(
        Layout storage l,
        int256 value
    ) internal view returns (int256) {
        uint8 decimals = l.getPoolTokenDecimals();
        return OptionMath.scaleDecimals(value, 18, decimals);
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(
        Layout storage l,
        UD60x18 value
    ) internal view returns (uint256) {
        return l.toPoolTokenDecimals(value.unwrap());
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the pool token decimals
    function toPoolTokenDecimals(
        Layout storage l,
        SD59x18 value
    ) internal view returns (int256) {
        return l.toPoolTokenDecimals(value.unwrap());
    }

    /// @notice Adjust decimals of a value with pool token decimals to 18 decimals
    function fromPoolTokenDecimals(
        Layout storage l,
        uint256 value
    ) internal view returns (UD60x18) {
        uint8 decimals = l.getPoolTokenDecimals();
        return UD60x18.wrap(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Adjust decimals of a value with pool token decimals to 18 decimals
    function fromPoolTokenDecimals(
        Layout storage l,
        int256 value
    ) internal view returns (SD59x18) {
        uint8 decimals = l.getPoolTokenDecimals();
        return SD59x18.wrap(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Get the token used as options collateral and for payment of premium. (quote for PUT pools, base for CALL pools)
    function getPoolToken(Layout storage l) internal view returns (address) {
        return l.isCallPool ? l.base : l.quote;
    }

    function getSettlementPrice(Layout storage l) internal returns (UD60x18) {
        if (l.settlementPrice == ZERO) {
            l.settlementPrice = IOracleAdapter(l.oracleAdapter).quoteFrom(
                l.base,
                l.quote,
                l.maturity.toUint32()
            );
        }

        return l.settlementPrice;
    }

    /// @notice calculate ERC1155 token id for given option parameters
    /// @param operator The current operator of the position
    /// @param lower The lower bound normalized option price | 18 decimals
    /// @param upper The upper bound normalized option price | 18 decimals
    /// @return tokenId token id
    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal pure returns (uint256 tokenId) {
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
    /// @return lower The lower bound normalized option price | 18 decimals
    /// @return upper The upper bound normalized option price | 18 decimals
    function parseTokenId(
        uint256 tokenId
    )
        internal
        pure
        returns (
            uint8 version,
            address operator,
            UD60x18 lower,
            UD60x18 upper,
            Position.OrderType orderType
        )
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

    function safeTransfer(IERC20 token, address to, UD60x18 value) internal {
        token.safeTransfer(to, PoolStorage.layout().toPoolTokenDecimals(value));
    }

    function safeTransferFrom(
        IERC20Router router,
        address token,
        address from,
        address to,
        UD60x18 value
    ) internal {
        router.safeTransferFrom(
            token,
            from,
            to,
            PoolStorage.layout().toPoolTokenDecimals(value)
        );
    }
}
