// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {OptionMath} from "../libraries/OptionMath.sol";

import {IReferral} from "./IReferral.sol";

library ReferralStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.Referral");

    struct Layout {
        UD60x18[] primaryRebatePercents;
        UD60x18 secondaryRebatePercent;
        mapping(address user => IReferral.RebateTier tier) rebateTiers;
        mapping(address user => address referrer) referrals;
        mapping(address user => mapping(address token => uint256 amount)) rebates;
        mapping(address user => EnumerableSet.AddressSet tokens) rebateTokens;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function toPoolTokenDecimals(
        address token,
        UD60x18 value
    ) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return OptionMath.scaleDecimals(value.unwrap(), 18, decimals);
    }
}
