// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IOptionRewardFactory} from "./IOptionRewardFactory.sol";

library OptionRewardFactoryStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.OptionRewardFactory");

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
    function keyHash(IOptionRewardFactory.OptionRewardArgs memory args) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    args.option,
                    args.priceRepository,
                    args.paymentSplitter,
                    args.discount,
                    args.penalty,
                    args.expiryDuration,
                    args.exerciseDuration,
                    args.lockupDuration
                )
            );
    }
}
