// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UnderwriterVaultErc4626Test} from "./UnderwriterVault.erc4626.t.sol";
import {UnderwriterVaultFeesTest} from "./UnderwriterVault.fees.t.sol";

abstract contract UnderwriterVaultTest is
    UnderwriterVaultErc4626Test,
    UnderwriterVaultFeesTest
{}
