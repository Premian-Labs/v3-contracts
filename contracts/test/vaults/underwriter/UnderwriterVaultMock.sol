// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UnderwriterVault, SolidStateERC4626} from "../../../vaults/underwriter/UnderwriterVault.sol";
import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";

contract UnderwriterVaultMock is UnderwriterVault {

    constructor(address oracleAddress)
        UnderwriterVault(oracleAddress) {}

}