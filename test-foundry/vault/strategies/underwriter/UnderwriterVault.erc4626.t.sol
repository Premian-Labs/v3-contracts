// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {UnderwriterVaultDeployTest} from "./_UnderwriterVault.deploy.t.sol";

abstract contract UnderwriterVaultErc4626Test is UnderwriterVaultDeployTest {
    function test_totalAssets_ReturnExpectedValue() public {
        UD60x18[3] memory cases = [ud(1e18), ud(1.1e18), ud(590.7e18)];

        for (uint256 i; i < cases.length; i++) {
            vault.setTotalAssets(cases[i]);
            assertEq(vault.totalAssets(), scaleDecimals(cases[i]));
        }
    }
}
