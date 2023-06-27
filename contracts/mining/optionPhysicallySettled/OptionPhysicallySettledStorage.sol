// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {OptionMath} from "../../libraries/OptionMath.sol";

import {IOptionPhysicallySettled} from "./IOptionPhysicallySettled.sol";

library OptionPhysicallySettledStorage {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.mining.OptionPhysicallySettled");

    struct Layout {
        bool isCall;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address base;
        address quote;
        address priceRepository;
        // amount of time the exercise period lasts (in seconds)
        uint256 exerciseDuration;
        // Total options underwritten for this strike/maturity (Annihilating options decreases this total amount, but exercise does not)
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18)) totalUnderwritten;
        // Amount of contracts exercised for this strike/maturity
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) totalExercised;
        // Total exercise cost paid by long holders to short holders for this strike/maturity (Excluding treasury fee)
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) totalExerciseCost;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Calculate ERC1155 token id for given option parameters
    function formatTokenId(
        IOptionPhysicallySettled.TokenType tokenType,
        uint64 maturity,
        UD60x18 strike
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(tokenType) << 248) +
            (uint256(maturity) << 128) +
            uint256(int256(fromUD60x18ToInt128(strike)));
    }

    /// @notice Derive option maturity and strike price from ERC1155 token id
    function parseTokenId(
        uint256 tokenId
    ) internal pure returns (IOptionPhysicallySettled.TokenType tokenType, uint64 maturity, int128 strike) {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike := tokenId
        }
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function toTokenDecimals(Layout storage l, UD60x18 value, bool isBase) internal view returns (uint256) {
        uint8 decimals = isBase ? l.baseDecimals : l.quoteDecimals;
        return OptionMath.scaleDecimals(value.unwrap(), 18, decimals);
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(Layout storage l, uint256 value, bool isBase) internal view returns (UD60x18) {
        uint8 decimals = isBase ? l.baseDecimals : l.quoteDecimals;
        return ud(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Converts `UD60x18` to `int128`
    function fromUD60x18ToInt128(UD60x18 u) internal pure returns (int128) {
        return u.unwrap().toInt256().toInt128();
    }
}
