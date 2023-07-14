// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

type UD50x28 is uint256;

UD60x18 constant SCALING_FACTOR = UD60x18.wrap(1e28);
uint256 constant uMAX_UD50x28 = 11579208923731619542357098500868790785326998466564_0564039457584007913129639935;

error UD50x28_IntoUD50x28_Overflow(UD60x18 x);

function ud50x28(uint256 x) pure returns (UD50x28 result) {
    result = UD50x28.wrap(x);
}

function intoUD50x28(UD60x18 x) pure returns (UD50x28 result) {
    uint256 xUint = UD60x18.unwrap(x / SCALING_FACTOR);
    if (xUint > uMAX_UD50x28) revert UD50x28_IntoUD50x28_Overflow(x);
    result = UD50x28.wrap(xUint);
}

function intoUD60x18(UD50x28 x) pure returns (UD60x18 result) {
    result = UD60x18.wrap(UD50x28.unwrap(x)) * SCALING_FACTOR;
}
