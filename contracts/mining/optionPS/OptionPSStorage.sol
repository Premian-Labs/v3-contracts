// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {OptionMath} from "../../libraries/OptionMath.sol";

import {IOptionPS} from "./IOptionPS.sol";

library OptionPSStorage {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.OptionPS");

    struct Layout {
        bool isCall;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address base;
        address quote;
        // Total options underwritten for this strike/maturity (Annihilating options decreases this total amount, but exercise does not)
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) totalUnderwritten;
        // Amount of contracts exercised for this strike/maturity
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) totalExercised;
        EnumerableSet.UintSet tokenIds;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Calculate ERC1155 token id for given option parameters
    function formatTokenId(
        IOptionPS.TokenType tokenType,
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
    ) internal pure returns (IOptionPS.TokenType tokenType, uint64 maturity, int128 strike) {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike := tokenId
        }
    }

    function getCollateral(Layout storage l) internal view returns (address) {
        return l.isCall ? l.base : l.quote;
    }

    function getExerciseToken(Layout storage l) internal view returns (address) {
        return l.isCall ? l.quote : l.base;
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function toTokenDecimals(Layout storage l, UD60x18 value, address token) internal view returns (uint256) {
        uint8 decimals = token == l.base ? l.baseDecimals : l.quoteDecimals;
        return OptionMath.scaleDecimals(value.unwrap(), 18, decimals);
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(Layout storage l, uint256 value, address token) internal view returns (UD60x18) {
        uint8 decimals = token == l.base ? l.baseDecimals : l.quoteDecimals;
        return ud(OptionMath.scaleDecimals(value, decimals, 18));
    }

    /// @notice Converts `UD60x18` to `int128`
    function fromUD60x18ToInt128(UD60x18 u) internal pure returns (int128) {
        return u.unwrap().toInt256().toInt128();
    }
}
