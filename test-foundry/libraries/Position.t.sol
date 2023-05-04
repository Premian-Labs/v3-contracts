// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {IPosition} from "contracts/libraries/IPosition.sol";

contract PositionTest is Test, Assertions {
    using Position for Position.KeyInternal;

    Position.KeyInternal key;
    address user;

    function setUp() public {
        user = address(123);
        key = Position.KeyInternal({
            owner: user,
            operator: user,
            lower: UD60x18.wrap(0.25e18),
            upper: UD60x18.wrap(0.75e18),
            orderType: Position.OrderType.CSUP,
            isCall: true,
            strike: UD60x18.wrap(1000e18)
        });
    }

    function test_keyHash_ReturnsKeyHash() public {
        assertEq(
            key.keyHash(),
            keccak256(
                abi.encode(
                    key.owner,
                    key.operator,
                    key.lower,
                    key.upper,
                    key.orderType
                )
            )
        );
    }

    function test_isShort_ReturnTrue_IfShort() public {
        assertTrue(Position.isShort(Position.OrderType.CS));
        assertTrue(Position.isShort(Position.OrderType.CSUP));
    }

    function test_isShort_ReturnFalse_IfNotShort() public {
        assertFalse(Position.isShort(Position.OrderType.LC));
    }

    function test_isLong_ReturnTrue_IfLong() public {
        assertTrue(Position.isLong(Position.OrderType.LC));
    }

    function test_isLong_ReturnFalse_IfNotLong() public {
        assertFalse(Position.isLong(Position.OrderType.CS));
        assertFalse(Position.isLong(Position.OrderType.CSUP));
    }

    function test_pieceWiseLinear_Return0_IfLowerGreaterOrEqualPrice() public {
        assertEq(key.pieceWiseLinear(key.lower), ZERO);
        assertEq(key.pieceWiseLinear(key.lower - UD60x18.wrap(1)), ZERO);
    }

    function test_pieceWiseLinear_ReturnExpectedValue_IfPriceInRange() public {
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.3e18)),
            UD60x18.wrap(0.1e18)
        );
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.5e18)),
            UD60x18.wrap(0.5e18)
        );
        assertEq(
            key.pieceWiseLinear(UD60x18.wrap(0.7e18)),
            UD60x18.wrap(0.9e18)
        );
    }

    function test_pieceWiseLinear_Return1_IfPriceGreaterOrEqualUpper() public {
        assertEq(key.pieceWiseLinear(key.upper), ONE);
        assertEq(key.pieceWiseLinear(key.upper + UD60x18.wrap(1)), ONE);
    }

    function test_pieceWiseLinear_RevertIf_LowerGreaterOrEqualUpper() public {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseLinear(ZERO);

        //

        key.lower = key.upper + UD60x18.wrap(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseLinear(ZERO);
    }

    function test_pieceWiseQuadratic_Return0_IfLowerGreaterOrEqualPrice()
        public
    {
        assertEq(key.pieceWiseQuadratic(key.lower), ZERO);
        assertEq(key.pieceWiseQuadratic(key.lower - UD60x18.wrap(1)), ZERO);
    }

    function test_pieceWiseQuadratic_ReturnExpectedValue_IfPriceInRange()
        public
    {
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.3e18)),
            UD60x18.wrap(0.0275e18)
        );
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.5e18)),
            UD60x18.wrap(0.1875e18)
        );
        assertEq(
            key.pieceWiseQuadratic(UD60x18.wrap(0.7e18)),
            UD60x18.wrap(0.4275e18)
        );
    }

    function test_pieceWiseQuadratic_ReturnAvgPrice_IfPriceGreaterOrEqualUpper()
        public
    {
        UD60x18 avg = key.lower.avg(key.upper);
        assertEq(key.pieceWiseQuadratic(key.upper), avg);
        assertEq(key.pieceWiseQuadratic(key.upper + UD60x18.wrap(1)), avg);
    }

    function test_pieceWiseQuadratic_RevertIf_LowerGreaterOrEqualUpper()
        public
    {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseQuadratic(ZERO);

        //

        key.lower = key.upper + UD60x18.wrap(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPosition.Position__LowerGreaterOrEqualUpper.selector,
                key.lower,
                key.upper
            )
        );
        key.pieceWiseQuadratic(ZERO);
    }

    function _test_collateralToContracts_ReturnExpectedValue(
        bool isCall
    ) internal {
        UD60x18 strike = key.strike;

        UD60x18 a;
        UD60x18 b;

        a = UD60x18.wrap(1e18);
        b = UD60x18.wrap(0.001e18);
        assertEq(
            Position.collateralToContracts(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(77e18);
        b = UD60x18.wrap(0.077e18);
        assertEq(
            Position.collateralToContracts(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(344e18);
        b = UD60x18.wrap(0.344e18);
        assertEq(
            Position.collateralToContracts(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(5235e18);
        b = UD60x18.wrap(5.235e18);
        assertEq(
            Position.collateralToContracts(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(99999e18);
        b = UD60x18.wrap(99.999e18);
        assertEq(
            Position.collateralToContracts(a, strike, isCall),
            isCall ? a : b
        );
    }

    function test_collateralToContracts_ReturnExpectedValue_Call() public {
        _test_collateralToContracts_ReturnExpectedValue(true);
    }

    function test_collateralToContracts_ReturnExpectedValue_Put() public {
        _test_collateralToContracts_ReturnExpectedValue(false);
    }

    function _test_contractsToCollateral_ReturnExpectedValue(
        bool isCall
    ) internal {
        UD60x18 strike = key.strike;

        UD60x18 a;
        UD60x18 b;

        a = UD60x18.wrap(0.001e18);
        b = UD60x18.wrap(1e18);
        assertEq(
            Position.contractsToCollateral(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(0.077e18);
        b = UD60x18.wrap(77e18);
        assertEq(
            Position.contractsToCollateral(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(0.344e18);
        b = UD60x18.wrap(344e18);
        assertEq(
            Position.contractsToCollateral(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(5.235e18);
        b = UD60x18.wrap(5235e18);
        assertEq(
            Position.contractsToCollateral(a, strike, isCall),
            isCall ? a : b
        );

        a = UD60x18.wrap(99.999e18);
        b = UD60x18.wrap(99999e18);
        assertEq(
            Position.contractsToCollateral(a, strike, isCall),
            isCall ? a : b
        );
    }

    function test_contractsToCollateral_ReturnExpectedValue_Call() public {
        _test_contractsToCollateral_ReturnExpectedValue(true);
    }

    function test_contractsToCollateral_ReturnExpectedValue_Put() public {
        _test_contractsToCollateral_ReturnExpectedValue(false);
    }

    function test_liquidityPerTick_ReturnExpectedValue() public {
        key.lower = UD60x18.wrap(0.25e18);
        key.upper = UD60x18.wrap(0.75e18);

        UD60x18 size;
        UD60x18 result;

        size = UD60x18.wrap(250e18);
        result = UD60x18.wrap(0.5e18);
        assertEq(key.liquidityPerTick(size), result);

        size = UD60x18.wrap(500e18);
        result = UD60x18.wrap(1e18);
        assertEq(key.liquidityPerTick(size), result);

        size = UD60x18.wrap(1000e18);
        result = UD60x18.wrap(2e18);
        assertEq(key.liquidityPerTick(size), result);
    }

    function _test_bid_ReturnExpectedValue_Call(bool isCall) internal {
        key.isCall = isCall;

        UD60x18 result;

        result = UD60x18.wrap(0.01375e18);
        assertEq(
            key.bid(UD60x18.wrap(0.5e18), UD60x18.wrap(0.3e18)),
            isCall ? result : result * key.strike
        );

        result = UD60x18.wrap(0.1875e18);
        assertEq(
            key.bid(UD60x18.wrap(1e18), UD60x18.wrap(0.5e18)),
            isCall ? result : result * key.strike
        );

        result = UD60x18.wrap(0.855e18);
        assertEq(
            key.bid(UD60x18.wrap(2e18), UD60x18.wrap(0.7e18)),
            isCall ? result : result * key.strike
        );
    }

    function test_bid_ReturnExpectedValue_Call() public {
        _test_bid_ReturnExpectedValue_Call(true);
    }

    function test_bid_ReturnExpectedValue_Put() public {
        _test_bid_ReturnExpectedValue_Call(false);
    }

    function _test_collateral_ReturnExpectedValue(
        Position.OrderType orderType
    ) internal {
        key.orderType = orderType;

        UD60x18 size = UD60x18.wrap(2e18);

        UD60x18[7] memory inputs = [
            UD60x18.wrap(0.2e18),
            UD60x18.wrap(0.25e18),
            UD60x18.wrap(0.3e18),
            UD60x18.wrap(0.5e18),
            UD60x18.wrap(0.7e18),
            UD60x18.wrap(0.75e18),
            UD60x18.wrap(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [
                UD60x18.wrap(1e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(0.855e18),
                UD60x18.wrap(0.375e18),
                UD60x18.wrap(0.055e18),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        } else if (orderType == Position.OrderType.CS) {
            results = [
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(1.855e18),
                UD60x18.wrap(1.375e18),
                UD60x18.wrap(1.055e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1e18)
            ];
        } else if (orderType == Position.OrderType.LC) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0.055e18),
                UD60x18.wrap(0.375e18),
                UD60x18.wrap(0.855e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1e18)
            ];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.collateral(size, inputs[i]), results[i]);
        }
    }

    function test_collateral_ReturnExpectedValue_CSUP() public {
        _test_collateral_ReturnExpectedValue(Position.OrderType.CSUP);
    }

    function test_collateral_ReturnExpectedValue_CS() public {
        _test_collateral_ReturnExpectedValue(Position.OrderType.CS);
    }

    function test_collateral_ReturnExpectedValue_LC() public {
        _test_collateral_ReturnExpectedValue(Position.OrderType.LC);
    }

    function _test_contracts_ReturnExpectedValue(
        Position.OrderType orderType
    ) internal {
        key.orderType = orderType;

        UD60x18 size = UD60x18.wrap(2e18);

        UD60x18[7] memory inputs = [
            UD60x18.wrap(0.2e18),
            UD60x18.wrap(0.25e18),
            UD60x18.wrap(0.3e18),
            UD60x18.wrap(0.5e18),
            UD60x18.wrap(0.7e18),
            UD60x18.wrap(0.75e18),
            UD60x18.wrap(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18)
            ];
        } else if (orderType == Position.OrderType.CS) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18)
            ];
        } else if (orderType == Position.OrderType.LC) {
            results = [
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.contracts(size, inputs[i]), results[i]);
        }
    }

    function test_contracts_ReturnExpectedValue_CSUP() public {
        _test_contracts_ReturnExpectedValue(Position.OrderType.CSUP);
    }

    function test_contracts_ReturnExpectedValue_CS() public {
        _test_contracts_ReturnExpectedValue(Position.OrderType.CS);
    }

    function test_contracts_ReturnExpectedValue_LC() public {
        _test_contracts_ReturnExpectedValue(Position.OrderType.LC);
    }

    function _test_long_ReturnExpectedValue(
        Position.OrderType orderType
    ) internal {
        key.orderType = orderType;

        UD60x18 size = UD60x18.wrap(2e18);

        UD60x18[7] memory inputs = [
            UD60x18.wrap(0.2e18),
            UD60x18.wrap(0.25e18),
            UD60x18.wrap(0.3e18),
            UD60x18.wrap(0.5e18),
            UD60x18.wrap(0.7e18),
            UD60x18.wrap(0.75e18),
            UD60x18.wrap(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        } else if (orderType == Position.OrderType.CS) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        } else if (orderType == Position.OrderType.LC) {
            results = [
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.long(size, inputs[i]), results[i]);
        }
    }

    function test_long_ReturnExpectedValue_CSUP() public {
        _test_long_ReturnExpectedValue(Position.OrderType.CSUP);
    }

    function test_long_ReturnExpectedValue_CS() public {
        _test_long_ReturnExpectedValue(Position.OrderType.CS);
    }

    function test_long_ReturnExpectedValue_LC() public {
        _test_long_ReturnExpectedValue(Position.OrderType.LC);
    }

    function _test_short_ReturnExpectedValue(
        Position.OrderType orderType
    ) internal {
        key.orderType = orderType;

        UD60x18 size = UD60x18.wrap(2e18);

        UD60x18[7] memory inputs = [
            UD60x18.wrap(0.2e18),
            UD60x18.wrap(0.25e18),
            UD60x18.wrap(0.3e18),
            UD60x18.wrap(0.5e18),
            UD60x18.wrap(0.7e18),
            UD60x18.wrap(0.75e18),
            UD60x18.wrap(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18)
            ];
        } else if (orderType == Position.OrderType.CS) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0.2e18),
                UD60x18.wrap(1e18),
                UD60x18.wrap(1.8e18),
                UD60x18.wrap(2e18),
                UD60x18.wrap(2e18)
            ];
        } else if (orderType == Position.OrderType.LC) {
            results = [
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0),
                UD60x18.wrap(0)
            ];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.short(size, inputs[i]), results[i]);
        }
    }

    function test_short_ReturnExpectedValue_CSUP() public {
        _test_short_ReturnExpectedValue(Position.OrderType.CSUP);
    }

    function test_short_ReturnExpectedValue_CS() public {
        _test_short_ReturnExpectedValue(Position.OrderType.CS);
    }

    function test_short_ReturnExpectedValue_LC() public {
        _test_short_ReturnExpectedValue(Position.OrderType.LC);
    }

    function _test_calculatePositionUpdate_ReturnExpectedValue(
        Position.OrderType orderType
    ) internal {
        key.orderType = orderType;

        UD60x18 size = UD60x18.wrap(2e18);

        UD60x18[6] memory prices = [
            UD60x18.wrap(0.2e18),
            UD60x18.wrap(0.25e18),
            UD60x18.wrap(0.3e18),
            UD60x18.wrap(0.6e18),
            UD60x18.wrap(0.75e18),
            UD60x18.wrap(0.8e18)
        ];

        SD59x18[2] memory deltas = [SD59x18.wrap(0.8e18), SD59x18.wrap(1.2e18)];
        bool[2] memory actions = [true, false];
        UD60x18 currentBalance = UD60x18.wrap(2e18);

        SD59x18[3][24] memory expected;

        // prettier-ignore
        if (orderType == Position.OrderType.CSUP) {
            expected[0]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[1]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[2]  = [SD59x18.wrap(0.342e18),  SD59x18.wrap(0), SD59x18.wrap(0.08e18)];
            expected[3]  = [SD59x18.wrap(0.078e18),  SD59x18.wrap(0), SD59x18.wrap(0.56e18)];
            expected[4]  = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(0.8e18)];
            expected[5]  = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(0.8e18)];
            expected[6]  = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[7]  = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[8]  = [SD59x18.wrap(0.513e18),  SD59x18.wrap(0), SD59x18.wrap(0.12e18)];
            expected[9]  = [SD59x18.wrap(0.117e18),  SD59x18.wrap(0), SD59x18.wrap(0.84e18)];
            expected[10] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(1.2e18)];
            expected[11] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(1.2e18)];
            expected[12] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[13] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[14] = [SD59x18.wrap(-0.342e18), SD59x18.wrap(0), SD59x18.wrap(-0.08e18)];
            expected[15] = [SD59x18.wrap(-0.078e18), SD59x18.wrap(0), SD59x18.wrap(-0.56e18)];
            expected[16] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(-0.8e18)];
            expected[17] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(-0.8e18)];
            expected[18] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[19] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[20] = [SD59x18.wrap(-0.513e18), SD59x18.wrap(0), SD59x18.wrap(-0.12e18)];
            expected[21] = [SD59x18.wrap(-0.117e18), SD59x18.wrap(0), SD59x18.wrap(-0.84e18)];
            expected[22] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(-1.2e18)];
            expected[23] = [SD59x18.wrap(0),         SD59x18.wrap(0), SD59x18.wrap(-1.2e18)];
        } else if (orderType == Position.OrderType.CS) {
            expected[0]  = [SD59x18.wrap(0.8e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[1]  = [SD59x18.wrap(0.8e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[2]  = [SD59x18.wrap(0.742e18),  SD59x18.wrap(0), SD59x18.wrap(0.08e18)];
            expected[3]  = [SD59x18.wrap(0.478e18),  SD59x18.wrap(0), SD59x18.wrap(0.56e18)];
            expected[4]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0), SD59x18.wrap(0.8e18)];
            expected[5]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0), SD59x18.wrap(0.8e18)];
            expected[6]  = [SD59x18.wrap(1.2e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[7]  = [SD59x18.wrap(1.2e18),    SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[8]  = [SD59x18.wrap(1.113e18),  SD59x18.wrap(0), SD59x18.wrap(0.12e18)];
            expected[9]  = [SD59x18.wrap(0.717e18),  SD59x18.wrap(0), SD59x18.wrap(0.84e18)];
            expected[10] = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0), SD59x18.wrap(1.2e18)];
            expected[11] = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0), SD59x18.wrap(1.2e18)];
            expected[12] = [SD59x18.wrap(-0.8e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[13] = [SD59x18.wrap(-0.8e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[14] = [SD59x18.wrap(-0.742e18), SD59x18.wrap(0), SD59x18.wrap(-0.08e18)];
            expected[15] = [SD59x18.wrap(-0.478e18), SD59x18.wrap(0), SD59x18.wrap(-0.56e18)];
            expected[16] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0), SD59x18.wrap(-0.8e18)];
            expected[17] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0), SD59x18.wrap(-0.8e18)];
            expected[18] = [SD59x18.wrap(-1.2e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[19] = [SD59x18.wrap(-1.2e18),   SD59x18.wrap(0), SD59x18.wrap(0)];
            expected[20] = [SD59x18.wrap(-1.113e18), SD59x18.wrap(0), SD59x18.wrap(-0.12e18)];
            expected[21] = [SD59x18.wrap(-0.717e18), SD59x18.wrap(0), SD59x18.wrap(-0.84e18)];
            expected[22] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0), SD59x18.wrap(-1.2e18)];
            expected[23] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0), SD59x18.wrap(-1.2e18)];
        } else if (
            orderType == Position.OrderType.LC
        ) {
            expected[0]  = [SD59x18.wrap(0),         SD59x18.wrap(0.8e18),   SD59x18.wrap(0)];
            expected[1]  = [SD59x18.wrap(0),         SD59x18.wrap(0.8e18),   SD59x18.wrap(0)];
            expected[2]  = [SD59x18.wrap(0.022e18),  SD59x18.wrap(0.72e18),  SD59x18.wrap(0)];
            expected[3]  = [SD59x18.wrap(0.238e18),  SD59x18.wrap(0.24e18),  SD59x18.wrap(0)];
            expected[4]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[5]  = [SD59x18.wrap(0.4e18),    SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[6]  = [SD59x18.wrap(0),         SD59x18.wrap(1.2e18),   SD59x18.wrap(0)];
            expected[7]  = [SD59x18.wrap(0),         SD59x18.wrap(1.2e18),   SD59x18.wrap(0)];
            expected[8]  = [SD59x18.wrap(0.033e18),  SD59x18.wrap(1.08e18),  SD59x18.wrap(0)];
            expected[9]  = [SD59x18.wrap(0.357e18),  SD59x18.wrap(0.36e18),  SD59x18.wrap(0)];
            expected[10] = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[11] = [SD59x18.wrap(0.6e18),    SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[12] = [SD59x18.wrap(0),         SD59x18.wrap(-0.8e18),  SD59x18.wrap(0)];
            expected[13] = [SD59x18.wrap(0),         SD59x18.wrap(-0.8e18),  SD59x18.wrap(0)];
            expected[14] = [SD59x18.wrap(-0.022e18), SD59x18.wrap(-0.72e18), SD59x18.wrap(0)];
            expected[15] = [SD59x18.wrap(-0.238e18), SD59x18.wrap(-0.24e18), SD59x18.wrap(0)];
            expected[16] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[17] = [SD59x18.wrap(-0.4e18),   SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[18] = [SD59x18.wrap(0),         SD59x18.wrap(-1.2e18),  SD59x18.wrap(0)];
            expected[19] = [SD59x18.wrap(0),         SD59x18.wrap(-1.2e18),  SD59x18.wrap(0)];
            expected[20] = [SD59x18.wrap(-0.033e18), SD59x18.wrap(-1.08e18), SD59x18.wrap(0)];
            expected[21] = [SD59x18.wrap(-0.357e18), SD59x18.wrap(-0.36e18), SD59x18.wrap(0)];
            expected[22] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0),        SD59x18.wrap(0)];
            expected[23] = [SD59x18.wrap(-0.6e18),   SD59x18.wrap(0),        SD59x18.wrap(0)];
        }

        uint256 counter;
        for (uint256 i = 0; i < actions.length; i++) {
            bool isDeposit = actions[i];
            for (uint256 j = 0; j < deltas.length; j++) {
                for (uint256 k = 0; k < prices.length; k++) {
                    SD59x18 deltaBalance = isDeposit ? deltas[j] : -deltas[j];
                    UD60x18 price = prices[k];

                    Position.Delta memory delta = key.calculatePositionUpdate(
                        currentBalance,
                        deltaBalance,
                        price
                    );

                    // prettier-ignore
                    assertEq(delta.collateral, expected[counter][0], "collateral");
                    assertEq(delta.longs, expected[counter][1], "longs");
                    assertEq(delta.shorts, expected[counter][2], "shorts");
                    counter++;
                }
            }
        }
    }

    function test_calculatePositionUpdate_ReturnExpectedValue_CSUP() public {
        _test_calculatePositionUpdate_ReturnExpectedValue(
            Position.OrderType.CSUP
        );
    }

    function test_calculatePositionUpdate_ReturnExpectedValue_CS() public {
        _test_calculatePositionUpdate_ReturnExpectedValue(
            Position.OrderType.CS
        );
    }

    function test_calculatePositionUpdate_ReturnExpectedValue_LC() public {
        _test_calculatePositionUpdate_ReturnExpectedValue(
            Position.OrderType.LC
        );
    }
}
