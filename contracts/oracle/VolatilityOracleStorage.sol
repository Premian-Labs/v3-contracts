// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IVolatilityOracle} from "./IVolatilityOracle.sol";

library VolatilityOracleStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VolatilityOracle");

    uint256 internal constant PARAM_BITS = 51;
    uint256 internal constant PARAM_BITS_MINUS_ONE = 50;
    uint256 internal constant PARAM_AMOUNT = 5;
    // START_BIT = PARAM_BITS * (PARAM_AMOUNT - 1)
    uint256 internal constant START_BIT = 204;

    struct Update {
        uint256 updatedAt;
        bytes32 tau;
        bytes32 theta;
        bytes32 psi;
        bytes32 rho;
    }

    struct Params {
        int256[5] tau;
        int256[5] theta;
        int256[5] psi;
        int256[5] rho;
    }

    struct Layout {
        mapping(address token => Update) parameters;
        // Relayer addresses which can be trusted to provide accurate option trades
        EnumerableSet.AddressSet whitelistedRelayers;
        // risk-free rate
        UD60x18 riskFreeRate;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Returns the current parameters for `token`
    function getParams(
        Layout storage l,
        address token
    ) internal view returns (Update memory) {
        return l.parameters[token];
    }

    /// @notice Returns the parsed parameters for the encoded `input`
    function parseParams(
        bytes32 input
    ) internal pure returns (int256[5] memory params) {
        // Value to add to negative numbers to cast them to int256
        int256 toAdd = (int256(-1) >> PARAM_BITS) << PARAM_BITS;

        assembly {
            let i := 0
            // Value equal to -1

            let mid := shl(PARAM_BITS_MINUS_ONE, 1)

            for {

            } lt(i, PARAM_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(PARAM_BITS, i))
                let param := shr(
                    offset,
                    sub(
                        input,
                        shl(
                            add(offset, PARAM_BITS),
                            shr(add(offset, PARAM_BITS), input)
                        )
                    )
                )

                // Check if value is a negative number and needs casting
                if or(eq(param, mid), gt(param, mid)) {
                    param := add(param, toAdd)
                }

                // Store result in the params array
                mstore(add(params, mul(0x20, i)), param)

                i := add(i, 1)
            }
        }
    }

    /// @notice Returns the encoded parameters for `params`
    function formatParams(
        int256[5] memory params
    ) internal pure returns (bytes32 result) {
        int256 max = int256(1 << PARAM_BITS_MINUS_ONE);

        unchecked {
            for (uint256 i = 0; i < PARAM_AMOUNT; i++) {
                if (params[i] >= max || params[i] <= -max)
                    revert IVolatilityOracle.VolatilityOracle__OutOfBounds(
                        params[i]
                    );
            }
        }

        assembly {
            let i := 0

            for {

            } lt(i, PARAM_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(PARAM_BITS, i))
                let param := mload(add(params, mul(0x20, i)))

                result := add(
                    result,
                    shl(
                        offset,
                        sub(param, shl(PARAM_BITS, shr(PARAM_BITS, param)))
                    )
                )

                i := add(i, 1)
            }
        }
    }
}
