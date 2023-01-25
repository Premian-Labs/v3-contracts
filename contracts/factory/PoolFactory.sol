// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";

import {OptionMath} from "../libraries/OptionMath.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for uint256;

    address internal immutable DIAMOND;

    constructor(address diamond) {
        DIAMOND = diamond;
    }

    function getDeploymentAddress(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (address) {
        return
            _getDeploymentAddress(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            );
    }

    function _getDeploymentAddress(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal view returns (address) {
        bytes memory args = abi.encode(
            DIAMOND,
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            isCallPool
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), // 0
                address(this), // address of factory contract
                keccak256(args), // salt
                // The contract bytecode
                keccak256(abi.encodePacked(type(PoolProxy).creationCode, args))
            )
        );

        // Cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool) {
        return
            _isPoolDeployed(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            );
    }

    function _isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) internal view returns (bool) {
        return
            _getDeploymentAddress(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            ).code.length > 0;
    }

    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external returns (address poolAddress) {
        if (base == underlying || baseOracle == underlyingOracle)
            revert PoolFactory__IdenticalAddresses();

        if (
            base == address(0) ||
            baseOracle == address(0) ||
            underlying == address(0) ||
            underlyingOracle == address(0)
        ) revert PoolFactory__ZeroAddress();

        _ensureOptionStrikeIsValid(strike, baseOracle, underlyingOracle);
        _ensureOptionMaturityIsValid(maturity);

        if (
            _isPoolDeployed(
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        ) revert PoolFactory__PoolAlreadyDeployed();

        // Deterministic pool addresses
        bytes32 salt = keccak256(
            abi.encode(
                DIAMOND,
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        );

        poolAddress = address(
            new PoolProxy{salt: salt}(
                DIAMOND,
                base,
                underlying,
                baseOracle,
                underlyingOracle,
                strike,
                maturity,
                isCallPool
            )
        );

        emit PoolDeployed(
            base,
            underlying,
            baseOracle,
            underlyingOracle,
            strike,
            maturity,
            poolAddress
        );
    }

    function _ensureOptionStrikeIsValid(
        uint256 strike,
        address baseOracle,
        address underlyingOracle
    ) internal view {
        if (strike.toInt256() == 0)
            revert PoolFactory__OptionStrikeEqualsZero();

        int256 basePrice = PoolStorage.getSpotPrice(baseOracle);
        int256 underlyingPrice = PoolStorage.getSpotPrice(underlyingOracle);

        int256 spot = (underlyingPrice * 1e18) / basePrice;
        int256 strikeInterval = OptionMath.calculateStrikeInterval(spot);

        if (strike.toInt256() % strikeInterval != 0)
            revert PoolFactory__OptionStrikeInvalid();
    }

    function _ensureOptionMaturityIsValid(uint64 maturity) internal view {
        if (maturity <= block.timestamp) revert PoolFactory__OptionExpired();

        if ((maturity % 24 hours) % 8 hours != 0)
            revert PoolFactory__OptionMaturityNot8UTC();

        uint256 ttm = OptionMath.calculateTimeToMaturity(maturity);

        if (ttm >= 3 days && ttm <= 31 days) {
            if (!OptionMath.isFriday(maturity))
                revert PoolFactory__OptionMaturityNotFriday();
        }

        if (ttm > 31 days) {
            if (!OptionMath.isLastFriday(maturity))
                revert PoolFactory__OptionMaturityNotLastFriday();
        }

        // TODO: Check if leap year?
        if (ttm > 365 days) revert PoolFactory__OptionMaturityExceedsMax();
    }
}
