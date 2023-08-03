// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {OptionMath} from "../../libraries/OptionMath.sol";

import {IOptionReward} from "./IOptionReward.sol";
import {IOptionPS} from "../optionPS/IOptionPS.sol";

library OptionRewardStorage {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.OptionReward");

    struct Layout {
        IOptionPS option;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address base;
        address quote;
        address priceRepository;
        address paymentSplitter;
        // percentage of the asset spot price used to set the strike price
        UD60x18 discount;
        // percentage of the intrinsic value that is reduced after lockup period (ie 80% penalty (0.80e18), means the
        // long holder receives 20% of the options intrinsic value, the remaining collateral is refunded).
        UD60x18 penalty;
        // amount of time the underwritten options should last (in seconds)
        uint256 optionDuration;
        // amount of time the lockup period lasts (in seconds)
        uint256 lockupDuration;
        // amount of time during which rewards can be claimed after the lockup period
        uint256 claimDuration;
        // Total amount of contracts for which the user can trade longs against % of intrinsic value after the lockupDuration
        mapping(address user => mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount))) redeemableLongs;
        // Total amount of contracts underwritten for this strike/maturity
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) totalUnderwritten;
        // Intrinsic value per contract claimable after lockup period
        mapping(UD60x18 strike => mapping(uint64 maturity => UD60x18 amount)) rewardPerContract;
        // Total amount of base tokens (not yet claimed) and reserved as locked rewards for users
        uint256 totalBaseReserved;
        // Amount of base tokens reserved for a strike/maturity
        mapping(UD60x18 strike => mapping(uint64 maturity => uint256 amount)) baseReserved;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
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
}
