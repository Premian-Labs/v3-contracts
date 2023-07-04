// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {IProxy} from "@solidstate/contracts/proxy/IProxy.sol";

/// @title Base proxy contract
abstract contract Proxy is IProxy {
    using AddressUtils for address;

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable virtual {
        (bool result, bytes memory data) = _handleDelegateCalls();

        assembly {
            let size := mload(data)
            switch result
            case 0 {
                revert(add(32, data), size)
            }
            default {
                return(add(32, data), size)
            }
        }
    }

    /// @notice delegate all calls to implementation contract
    /// @dev reverts if implementation address contains no code, for compatibility with metamorphic contracts
    function _handleDelegateCalls() internal virtual returns (bool result, bytes memory data) {
        address implementation = _getImplementation();
        if (!implementation.isContract()) revert Proxy__ImplementationIsNotContract();
        (result, data) = implementation.delegatecall(msg.data);
    }

    /// @notice get logic implementation address
    /// @return implementation address
    function _getImplementation() internal virtual returns (address);
}
