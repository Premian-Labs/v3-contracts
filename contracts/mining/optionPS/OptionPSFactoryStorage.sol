// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IOptionPSFactory} from "./IOptionPSFactory.sol";

library OptionPSFactoryStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.OptionPSFactory");

    struct Layout {
        mapping(address proxy => bool) isProxyDeployed;
        mapping(bytes32 key => address proxy) proxyByKey;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Returns the encoded option reward key using `args`
    function keyHash(IOptionPSFactory.OptionPSArgs memory args) internal pure returns (bytes32) {
        return keccak256(abi.encode(args.base, args.quote, args.isCall));
    }
}
