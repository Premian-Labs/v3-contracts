// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";

library DebugUtils {
    using UintUtils for uint256;

    function formatNumber(UD60x18 number) internal returns (string memory result) {
        uint256 n = number.unwrap();
        uint256 integer = n / 1e18;

        result = string(abi.encodePacked((integer).toString(), "."));

        uint256 decimal = n - integer * 1e18;

        uint256 decimalTemp = decimal * 10;

        if (decimalTemp > 0) {
            while (decimalTemp < 1e18) {
                result = string(abi.encodePacked(result, "0"));
                decimalTemp *= 10;
            }
        }

        result = string(abi.encodePacked(result, (decimal).toString()));
    }

    function formatNumber(SD59x18 number) internal returns (string memory result) {
        bool isNegative = number.unwrap() < int256(0);
        uint256 n = isNegative ? uint256(-number.unwrap()) : uint256(number.unwrap());

        if (isNegative) {
            result = string(abi.encodePacked("-"));
        }

        result = string(abi.encodePacked(result, formatNumber(ud(n))));
    }
}
