// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {PoolProxy} from "../pool/PoolProxy.sol";
import {IPoolFactoryDeployer} from "./IPoolFactoryDeployer.sol";
import {IPoolFactory} from "./IPoolFactory.sol";

contract PoolFactoryDeployer is IPoolFactoryDeployer, ReentrancyGuard {
    address public immutable DIAMOND;
    address public immutable POOL_FACTORY;

    constructor(address diamond, address poolFactory) {
        DIAMOND = diamond;
        POOL_FACTORY = poolFactory;
    }

    /// @inheritdoc IPoolFactoryDeployer
    function deployPool(IPoolFactory.PoolKey calldata k) external nonReentrant returns (address poolAddress) {
        _revertIfNotPoolFactory(msg.sender);

        bytes32 salt = keccak256(_encodePoolProxyArgs(k));
        poolAddress = address(
            new PoolProxy{salt: salt}(DIAMOND, k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool)
        );
    }

    /// @inheritdoc IPoolFactoryDeployer
    function calculatePoolAddress(IPoolFactory.PoolKey calldata k) external view returns (address) {
        _revertIfNotPoolFactory(msg.sender);

        bytes memory args = _encodePoolProxyArgs(k);

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), // 255
                address(this), // address of factory contract
                keccak256(args), // salt
                // The contract bytecode
                keccak256(abi.encodePacked(type(PoolProxy).creationCode, args))
            )
        );

        // Cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /// @notice Returns the encoded arguments for the pool proxy using pool key `k`
    function _encodePoolProxyArgs(IPoolFactory.PoolKey calldata k) internal view returns (bytes memory) {
        return abi.encode(DIAMOND, k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool);
    }

    function _revertIfNotPoolFactory(address caller) internal view {
        if (caller != POOL_FACTORY) revert PoolFactoryDeployer__NotPoolFactory(caller);
    }
}
