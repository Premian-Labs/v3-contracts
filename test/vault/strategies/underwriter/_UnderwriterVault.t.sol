// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UnderwriterVaultErc4626Test} from "./UnderwriterVault.erc4626.t.sol";
import {UnderwriterVaultInternalTest} from "./UnderwriterVault.internal.t.sol";
import {UnderwriterVaultFeesTest} from "./UnderwriterVault.fees.t.sol";
import {UnderwriterVaultPpsTest} from "./UnderwriterVault.pps.t.sol";
import {UnderwriterVaultStorageTest} from "./UnderwriterVault.storage.t.sol";
import {UnderwriterVaultVaultTest} from "./UnderwriterVault.vault.t.sol";

abstract contract UnderwriterVaultTest is
    UnderwriterVaultErc4626Test,
    UnderwriterVaultFeesTest,
    UnderwriterVaultInternalTest,
    UnderwriterVaultPpsTest,
    UnderwriterVaultStorageTest,
    UnderwriterVaultVaultTest
{}
