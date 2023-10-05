// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {Constants} from "./Constants.sol";
import {Defaults} from "./Defaults.sol";
import {Utils} from "./Utils.sol";

abstract contract Fuzzers is Constants, Utils {
    function gcd(uint8 a, uint8 b) internal pure returns (uint8) {
        return (b == 0) ? a : gcd(b, a % b);
    }

    function gcd(uint8[] memory array) internal pure returns (uint8) {
        uint8 d = array[0];

        for (uint256 i = 1; i < array.length; i++) {
            d = gcd(d, array[i]);
        }

        return d;
    }

    function fuzzRatios(uint8[2] memory ratios) internal pure returns (int256[] memory, UD60x18) {
        uint8[] memory r = new uint8[](ratios.length);
        for (uint256 i = 0; i < ratios.length; i++) {
            r[i] = ratios[i];
        }
        return fuzzRatios(r);
    }

    function fuzzRatios(uint8[] memory ratios) internal pure returns (int256[] memory, UD60x18) {
        uint8 d = gcd(ratios);
        for (uint256 i = 0; i < ratios.length; i++) {
            ratios[i] /= d;
        }

        int256[] memory r = new int256[](ratios.length);

        for (uint256 i = 0; i < ratios.length; i++) {
            r[i] = int256(uint256(ratios[i]));
        }

        return (r, ud(uint256(d) * WAD));
    }
}
