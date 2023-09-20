// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Position} from "contracts/libraries/Position.sol";
import {IPosition} from "contracts/libraries/IPosition.sol";
import {PRBMathExtra} from "contracts/libraries/PRBMathExtra.sol";
import {UD50x28, ud50x28} from "contracts/libraries/UD50x28.sol";
import {PositionMock} from "contracts/test/libraries/PositionMock.sol";

import {Base_Test} from "../Base.t.sol";

contract Position_Unit_Concrete_Test is Base_Test {
    using Position for Position.KeyInternal;
    using PRBMathExtra for UD60x18;

    // Test contracts
    PositionMock internal position;

    // Variables
    Position.KeyInternal internal key;

    function setUp() public virtual override {
        super.setUp();

        key = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.25e18),
            upper: ud(0.75e18),
            orderType: Position.OrderType.CSUP,
            isCall: true,
            strike: ud(1000e18)
        });
    }

    function deploy() internal virtual override {
        position = new PositionMock();
        //user = address(123);
    }

    function test_keyHash_ReturnsKeyHash() public {
        assertEq(key.keyHash(), keccak256(abi.encode(key.owner, key.operator, key.lower, key.upper, key.orderType)));
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
        assertEq(key.pieceWiseLinear(key.lower.intoUD50x28()), ud50x28(0));
        assertEq(key.pieceWiseLinear(key.lower.intoUD50x28() - ud50x28(1)), ud50x28(0));
    }

    function test_pieceWiseLinear_ReturnExpectedValue_IfPriceInRange() public {
        assertEq(key.pieceWiseLinear(ud50x28(0.3e28)), ud50x28(0.1e28));
        assertEq(key.pieceWiseLinear(ud50x28(0.5e28)), ud50x28(0.5e28));
        assertEq(key.pieceWiseLinear(ud50x28(0.7e28)), ud50x28(0.9e28));
    }

    function test_pieceWiseLinear_Return1_IfPriceGreaterOrEqualUpper() public {
        assertEq(key.pieceWiseLinear(key.upper.intoUD50x28()), ud50x28(1e28));
        assertEq(key.pieceWiseLinear(key.upper.intoUD50x28() + ud50x28(1)), ud50x28(1e28));
    }

    function test_pieceWiseLinear_RevertIf_LowerGreaterOrEqualUpper() public {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(IPosition.Position__LowerGreaterOrEqualUpper.selector, key.lower, key.upper)
        );
        position.pieceWiseLinear(key, ud50x28(0));

        //

        key.lower = key.upper + ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(IPosition.Position__LowerGreaterOrEqualUpper.selector, key.lower, key.upper)
        );
        position.pieceWiseLinear(key, ud50x28(0));
    }

    function test_pieceWiseQuadratic_Return0_IfLowerGreaterOrEqualPrice() public {
        assertEq(key.pieceWiseQuadratic(key.lower.intoUD50x28()), ud50x28(0));
        assertEq(key.pieceWiseQuadratic(key.lower.intoUD50x28() - ud50x28(1)), ud50x28(0));
    }

    function test_pieceWiseQuadratic_ReturnExpectedValue_IfPriceInRange() public {
        assertEq(key.pieceWiseQuadratic(ud50x28(0.3e28)), ud50x28(0.0275e28));
        assertEq(key.pieceWiseQuadratic(ud50x28(0.5e28)), ud50x28(0.1875e28));
        assertEq(key.pieceWiseQuadratic(ud50x28(0.7e28)), ud50x28(0.4275e28));
    }

    function test_pieceWiseQuadratic_ReturnAvgPrice_IfPriceGreaterOrEqualUpper() public {
        UD50x28 avg = key.lower.avg(key.upper).intoUD50x28();
        assertEq(key.pieceWiseQuadratic(key.upper.intoUD50x28()), avg);
        assertEq(key.pieceWiseQuadratic(key.upper.intoUD50x28() + ud50x28(1)), avg);
    }

    function test_pieceWiseQuadratic_RevertIf_LowerGreaterOrEqualUpper() public {
        key.lower = key.upper;
        vm.expectRevert(
            abi.encodeWithSelector(IPosition.Position__LowerGreaterOrEqualUpper.selector, key.lower, key.upper)
        );
        position.pieceWiseQuadratic(key, ud50x28(0));

        //

        key.lower = key.upper + ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(IPosition.Position__LowerGreaterOrEqualUpper.selector, key.lower, key.upper)
        );
        position.pieceWiseQuadratic(key, ud50x28(0));
    }

    function _test_collateralToContracts_ReturnExpectedValue(bool isCall) internal {
        UD60x18 strike = key.strike;

        UD60x18 a;
        UD60x18 b;

        a = ud(1e18);
        b = ud(0.001e18);
        assertEq(Position.collateralToContracts(a, strike, isCall), isCall ? a : b);

        a = ud(77e18);
        b = ud(0.077e18);
        assertEq(Position.collateralToContracts(a, strike, isCall), isCall ? a : b);

        a = ud(344e18);
        b = ud(0.344e18);
        assertEq(Position.collateralToContracts(a, strike, isCall), isCall ? a : b);

        a = ud(5235e18);
        b = ud(5.235e18);
        assertEq(Position.collateralToContracts(a, strike, isCall), isCall ? a : b);

        a = ud(99999e18);
        b = ud(99.999e18);
        assertEq(Position.collateralToContracts(a, strike, isCall), isCall ? a : b);
    }

    function test_collateralToContracts_ReturnExpectedValue_Call() public {
        _test_collateralToContracts_ReturnExpectedValue(true);
    }

    function test_collateralToContracts_ReturnExpectedValue_Put() public {
        _test_collateralToContracts_ReturnExpectedValue(false);
    }

    function _test_contractsToCollateral_ReturnExpectedValue(bool isCall) internal {
        UD60x18 strike = key.strike;

        UD60x18 a;
        UD60x18 b;

        a = ud(0.001e18);
        b = ud(1e18);
        assertEq(Position.contractsToCollateral(a, strike, isCall), isCall ? a : b);

        a = ud(0.077e18);
        b = ud(77e18);
        assertEq(Position.contractsToCollateral(a, strike, isCall), isCall ? a : b);

        a = ud(0.344e18);
        b = ud(344e18);
        assertEq(Position.contractsToCollateral(a, strike, isCall), isCall ? a : b);

        a = ud(5.235e18);
        b = ud(5235e18);
        assertEq(Position.contractsToCollateral(a, strike, isCall), isCall ? a : b);

        a = ud(99.999e18);
        b = ud(99999e18);
        assertEq(Position.contractsToCollateral(a, strike, isCall), isCall ? a : b);
    }

    function test_contractsToCollateral_ReturnExpectedValue_Call() public {
        _test_contractsToCollateral_ReturnExpectedValue(true);
    }

    function test_contractsToCollateral_ReturnExpectedValue_Put() public {
        _test_contractsToCollateral_ReturnExpectedValue(false);
    }

    function test_liquidityPerTick_ReturnExpectedValue() public {
        key.lower = ud(0.25e18);
        key.upper = ud(0.75e18);

        UD60x18 size;
        UD60x18 result;

        size = ud(250e18);
        result = ud(0.5e18);
        assertEq(key.liquidityPerTick(size).intoUD60x18(), result);

        size = ud(500e18);
        result = ud(1e18);
        assertEq(key.liquidityPerTick(size).intoUD60x18(), result);

        size = ud(1000e18);
        result = ud(2e18);
        assertEq(key.liquidityPerTick(size).intoUD60x18(), result);
    }

    function _test_bid_ReturnExpectedValue_Call(bool isCall) internal {
        key.isCall = isCall;

        UD60x18 result;

        result = ud(0.01375e18);
        assertEq(key.bid(ud(0.5e18), ud50x28(0.3e28)), isCall ? result : result * key.strike);

        result = ud(0.1875e18);
        assertEq(key.bid(ud(1e18), ud50x28(0.5e28)), isCall ? result : result * key.strike);

        result = ud(0.855e18);
        assertEq(key.bid(ud(2e18), ud50x28(0.7e28)), isCall ? result : result * key.strike);
    }

    function test_bid_ReturnExpectedValue_Call() public {
        _test_bid_ReturnExpectedValue_Call(true);
    }

    function test_bid_ReturnExpectedValue_Put() public {
        _test_bid_ReturnExpectedValue_Call(false);
    }

    function _test_collateral_ReturnExpectedValue(Position.OrderType orderType) internal {
        key.orderType = orderType;

        UD60x18 size = ud(2e18);

        UD60x18[7] memory inputs = [
            ud(0.2e18),
            ud(0.25e18),
            ud(0.3e18),
            ud(0.5e18),
            ud(0.7e18),
            ud(0.75e18),
            ud(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [ud(1e18), ud(1e18), ud(0.855e18), ud(0.375e18), ud(0.055e18), ud(0), ud(0)];
        } else if (orderType == Position.OrderType.CS) {
            results = [ud(2e18), ud(2e18), ud(1.855e18), ud(1.375e18), ud(1.055e18), ud(1e18), ud(1e18)];
        } else if (orderType == Position.OrderType.LC) {
            results = [ud(0), ud(0), ud(0.055e18), ud(0.375e18), ud(0.855e18), ud(1e18), ud(1e18)];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.collateral(size, inputs[i].intoUD50x28()), results[i]);
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

    function _test_contracts_ReturnExpectedValue(Position.OrderType orderType) internal {
        key.orderType = orderType;

        UD60x18 size = ud(2e18);

        UD60x18[7] memory inputs = [
            ud(0.2e18),
            ud(0.25e18),
            ud(0.3e18),
            ud(0.5e18),
            ud(0.7e18),
            ud(0.75e18),
            ud(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [ud(0), ud(0), ud(0.2e18), ud(1e18), ud(1.8e18), ud(2e18), ud(2e18)];
        } else if (orderType == Position.OrderType.CS) {
            results = [ud(0), ud(0), ud(0.2e18), ud(1e18), ud(1.8e18), ud(2e18), ud(2e18)];
        } else if (orderType == Position.OrderType.LC) {
            results = [ud(2e18), ud(2e18), ud(1.8e18), ud(1e18), ud(0.2e18), ud(0), ud(0)];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.contracts(size, inputs[i].intoUD50x28()), results[i]);
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

    function _test_long_ReturnExpectedValue(Position.OrderType orderType) internal {
        key.orderType = orderType;

        UD60x18 size = ud(2e18);

        UD60x18[7] memory inputs = [
            ud(0.2e18),
            ud(0.25e18),
            ud(0.3e18),
            ud(0.5e18),
            ud(0.7e18),
            ud(0.75e18),
            ud(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [ud(0), ud(0), ud(0), ud(0), ud(0), ud(0), ud(0)];
        } else if (orderType == Position.OrderType.CS) {
            results = [ud(0), ud(0), ud(0), ud(0), ud(0), ud(0), ud(0)];
        } else if (orderType == Position.OrderType.LC) {
            results = [ud(2e18), ud(2e18), ud(1.8e18), ud(1e18), ud(0.2e18), ud(0), ud(0)];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.long(size, inputs[i].intoUD50x28()), results[i]);
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

    function _test_short_ReturnExpectedValue(Position.OrderType orderType) internal {
        key.orderType = orderType;

        UD60x18 size = ud(2e18);

        UD60x18[7] memory inputs = [
            ud(0.2e18),
            ud(0.25e18),
            ud(0.3e18),
            ud(0.5e18),
            ud(0.7e18),
            ud(0.75e18),
            ud(0.8e18)
        ];

        UD60x18[7] memory results;

        if (orderType == Position.OrderType.CSUP) {
            results = [ud(0), ud(0), ud(0.2e18), ud(1e18), ud(1.8e18), ud(2e18), ud(2e18)];
        } else if (orderType == Position.OrderType.CS) {
            results = [ud(0), ud(0), ud(0.2e18), ud(1e18), ud(1.8e18), ud(2e18), ud(2e18)];
        } else if (orderType == Position.OrderType.LC) {
            results = [ud(0), ud(0), ud(0), ud(0), ud(0), ud(0), ud(0)];
        }

        for (uint256 i = 0; i < inputs.length; i++) {
            assertEq(key.short(size, inputs[i].intoUD50x28()), results[i]);
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

    function _test_calculatePositionUpdate_ReturnExpectedValue(Position.OrderType orderType) internal {
        key.orderType = orderType;

        UD60x18[6] memory prices = [ud(0.2e18), ud(0.25e18), ud(0.3e18), ud(0.6e18), ud(0.75e18), ud(0.8e18)];

        SD59x18[2] memory deltas = [sd(0.8e18), sd(1.2e18)];
        bool[2] memory actions = [true, false];
        UD60x18 currentBalance = ud(2e18);

        SD59x18[3][24] memory expected;

        // prettier-ignore
        if (orderType == Position.OrderType.CSUP) {
            expected[0]  = [sd(0.4e18),    sd(0), sd(0)];
            expected[1]  = [sd(0.4e18),    sd(0), sd(0)];
            expected[2]  = [sd(0.342e18),  sd(0), sd(0.08e18)];
            expected[3]  = [sd(0.078e18),  sd(0), sd(0.56e18)];
            expected[4]  = [sd(0),         sd(0), sd(0.8e18)];
            expected[5]  = [sd(0),         sd(0), sd(0.8e18)];
            expected[6]  = [sd(0.6e18),    sd(0), sd(0)];
            expected[7]  = [sd(0.6e18),    sd(0), sd(0)];
            expected[8]  = [sd(0.513e18),  sd(0), sd(0.12e18)];
            expected[9]  = [sd(0.117e18),  sd(0), sd(0.84e18)];
            expected[10] = [sd(0),         sd(0), sd(1.2e18)];
            expected[11] = [sd(0),         sd(0), sd(1.2e18)];
            expected[12] = [sd(-0.4e18),   sd(0), sd(0)];
            expected[13] = [sd(-0.4e18),   sd(0), sd(0)];
            expected[14] = [sd(-0.342e18), sd(0), sd(-0.08e18)];
            expected[15] = [sd(-0.078e18), sd(0), sd(-0.56e18)];
            expected[16] = [sd(0),         sd(0), sd(-0.8e18)];
            expected[17] = [sd(0),         sd(0), sd(-0.8e18)];
            expected[18] = [sd(-0.6e18),   sd(0), sd(0)];
            expected[19] = [sd(-0.6e18),   sd(0), sd(0)];
            expected[20] = [sd(-0.513e18), sd(0), sd(-0.12e18)];
            expected[21] = [sd(-0.117e18), sd(0), sd(-0.84e18)];
            expected[22] = [sd(0),         sd(0), sd(-1.2e18)];
            expected[23] = [sd(0),         sd(0), sd(-1.2e18)];
        } else if (orderType == Position.OrderType.CS) {
            expected[0]  = [sd(0.8e18),    sd(0), sd(0)];
            expected[1]  = [sd(0.8e18),    sd(0), sd(0)];
            expected[2]  = [sd(0.742e18),  sd(0), sd(0.08e18)];
            expected[3]  = [sd(0.478e18),  sd(0), sd(0.56e18)];
            expected[4]  = [sd(0.4e18),    sd(0), sd(0.8e18)];
            expected[5]  = [sd(0.4e18),    sd(0), sd(0.8e18)];
            expected[6]  = [sd(1.2e18),    sd(0), sd(0)];
            expected[7]  = [sd(1.2e18),    sd(0), sd(0)];
            expected[8]  = [sd(1.113e18),  sd(0), sd(0.12e18)];
            expected[9]  = [sd(0.717e18),  sd(0), sd(0.84e18)];
            expected[10] = [sd(0.6e18),    sd(0), sd(1.2e18)];
            expected[11] = [sd(0.6e18),    sd(0), sd(1.2e18)];
            expected[12] = [sd(-0.8e18),   sd(0), sd(0)];
            expected[13] = [sd(-0.8e18),   sd(0), sd(0)];
            expected[14] = [sd(-0.742e18), sd(0), sd(-0.08e18)];
            expected[15] = [sd(-0.478e18), sd(0), sd(-0.56e18)];
            expected[16] = [sd(-0.4e18),   sd(0), sd(-0.8e18)];
            expected[17] = [sd(-0.4e18),   sd(0), sd(-0.8e18)];
            expected[18] = [sd(-1.2e18),   sd(0), sd(0)];
            expected[19] = [sd(-1.2e18),   sd(0), sd(0)];
            expected[20] = [sd(-1.113e18), sd(0), sd(-0.12e18)];
            expected[21] = [sd(-0.717e18), sd(0), sd(-0.84e18)];
            expected[22] = [sd(-0.6e18),   sd(0), sd(-1.2e18)];
            expected[23] = [sd(-0.6e18),   sd(0), sd(-1.2e18)];
        } else if (
            orderType == Position.OrderType.LC
        ) {
            expected[0]  = [sd(0),         sd(0.8e18),   sd(0)];
            expected[1]  = [sd(0),         sd(0.8e18),   sd(0)];
            expected[2]  = [sd(0.022e18),  sd(0.72e18),  sd(0)];
            expected[3]  = [sd(0.238e18),  sd(0.24e18),  sd(0)];
            expected[4]  = [sd(0.4e18),    sd(0),        sd(0)];
            expected[5]  = [sd(0.4e18),    sd(0),        sd(0)];
            expected[6]  = [sd(0),         sd(1.2e18),   sd(0)];
            expected[7]  = [sd(0),         sd(1.2e18),   sd(0)];
            expected[8]  = [sd(0.033e18),  sd(1.08e18),  sd(0)];
            expected[9]  = [sd(0.357e18),  sd(0.36e18),  sd(0)];
            expected[10] = [sd(0.6e18),    sd(0),        sd(0)];
            expected[11] = [sd(0.6e18),    sd(0),        sd(0)];
            expected[12] = [sd(0),         sd(-0.8e18),  sd(0)];
            expected[13] = [sd(0),         sd(-0.8e18),  sd(0)];
            expected[14] = [sd(-0.022e18), sd(-0.72e18), sd(0)];
            expected[15] = [sd(-0.238e18), sd(-0.24e18), sd(0)];
            expected[16] = [sd(-0.4e18),   sd(0),        sd(0)];
            expected[17] = [sd(-0.4e18),   sd(0),        sd(0)];
            expected[18] = [sd(0),         sd(-1.2e18),  sd(0)];
            expected[19] = [sd(0),         sd(-1.2e18),  sd(0)];
            expected[20] = [sd(-0.033e18), sd(-1.08e18), sd(0)];
            expected[21] = [sd(-0.357e18), sd(-0.36e18), sd(0)];
            expected[22] = [sd(-0.6e18),   sd(0),        sd(0)];
            expected[23] = [sd(-0.6e18),   sd(0),        sd(0)];
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
                        price.intoUD50x28()
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
        _test_calculatePositionUpdate_ReturnExpectedValue(Position.OrderType.CSUP);
    }

    function test_calculatePositionUpdate_ReturnExpectedValue_CS() public {
        _test_calculatePositionUpdate_ReturnExpectedValue(Position.OrderType.CS);
    }

    function test_calculatePositionUpdate_ReturnExpectedValue_LC() public {
        _test_calculatePositionUpdate_ReturnExpectedValue(Position.OrderType.LC);
    }
}
