// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

contract OptionMathTest is Test, Assertions {
    // Normal CDF approximation helper
    function test_helperNormal_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][22] memory expected = [
            [sd(-12e18), sd(1.000000000000000000e18)],
            [sd(-11e18), sd(1.000000000000000000e18)],
            [sd(-10e18), sd(1.000000000000000000e18)],
            [sd(-9e18),  sd(1.000000000000000000e18)],
            [sd(-8e18),  sd(1.000000000000000000e18)],
            [sd(-7e18),  sd(0.999999999999892419e18)],
            [sd(-6e18),  sd(0.999999999361484315e18)],
            [sd(-5e18),  sd(0.999999554098525700e18)],
            [sd(-4e18),  sd(0.999941997571472396e18)],
            [sd(-3e18),  sd(0.997937931253017329e18)],
            [sd(-2e18),  sd(0.972787315787072559e18)],
            [sd(-1e18),  sd(0.836009939237039034e18)],
            [sd(0e18),   sd(0.500000000000000000e18)],
            [sd(1e18),   sd(0.153320858106603119e18)],
            [sd(2e18),   sd(0.018287098844188536e18)],
            [sd(3e18),   sd(0.000638104717830912e18)],
            [sd(4e18),   sd(0.000004131584646987e18)],
            [sd(5e18),   sd(0.000000002182904482e18)],
            [sd(6e18),   sd(0.000000000000023121e18)],
            [sd(7e18),   sd(0.000000000000000000e18)],
            [sd(8e18),   sd(0.000000000000000000e18)],
            [sd(9e18),   sd(0.000000000000000000e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertApproxEqAbs(
                OptionMath.helperNormal(expected[i][0]).unwrap(),
                expected[i][1].unwrap(),
                ud(0.0000000000000001e18).unwrap()
            );
        }
    }

    // Normal CDF approximation
    function test_normalCDF_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][25] memory expected = [
            [sd(-12e18), sd(0.000000000000000000e18)],
            [sd(-11e18), sd(0.000000000000000000e18)],
            [sd(-10e18), sd(0.000000000000000000e18)],
            [sd(-9e18),  sd(0.000000000000000000e18)],
            [sd(-8e18),  sd(0.000000000000000000e18)],
            [sd(-7e18),  sd(0.000000000000053770e18)],
            [sd(-6e18),  sd(0.000000000319269417e18)],
            [sd(-5e18),  sd(0.000000224042189416e18)],
            [sd(-4e18),  sd(0.000031067006587271e18)],
            [sd(-3e18),  sd(0.001350086732406808e18)],
            [sd(-2e18),  sd(0.022749891528557986e18)],
            [sd(-1e18),  sd(0.158655459434782014e18)],
            [sd(0e18),   sd(0.500000000000000000e18)],
            [sd(1e18),   sd(0.841344540565218013e18)],
            [sd(2e18),   sd(0.977250108471442002e18)],
            [sd(3e18),   sd(0.998649913267593225e18)],
            [sd(4e18),   sd(0.999968932993412718e18)],
            [sd(5e18),   sd(0.999999775957810532e18)],
            [sd(6e18),   sd(0.999999999680730611e18)],
            [sd(7e18),   sd(0.999999999999946265e18)],
            [sd(8e18),   sd(1.000000000000000000e18)],
            [sd(9e18),   sd(1.000000000000000000e18)],
            [sd(10e18),  sd(1.000000000000000000e18)],
            [sd(11e18),  sd(1.000000000000000000e18)],
            [sd(12e18),  sd(1.000000000000000000e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertApproxEqAbs(
                OptionMath.normalCdf(expected[i][0]).unwrap(),
                expected[i][1].unwrap(),
                0.0000000000000001e18
            );
        }
    }

    function test_relu_ReturnExpectedValue() public {
        // prettier-ignore
        SD59x18[2][7] memory expected = [
            [sd(-3.6e18), sd(0)],
            [sd(-2.2e18), sd(0)],
            [sd(-1.1e18), sd(0)],
            [sd(0),       sd(0)],
            [sd(1.1e18),  sd(1.1e18)],
            [sd(2.1e18),  sd(2.1e18)],
            [sd(3.6e18),  sd(3.6e18)]
        ];

        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(OptionMath.relu(expected[i][0]), expected[i][1].intoUD60x18());
        }
    }

    function _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(bool isCall) internal {
        UD60x18 strike = ud(0.8e18);
        UD60x18 timeToMaturity = ud(0.53e18);
        UD60x18 volAnnualized = ud(0.732e18);
        UD60x18 riskFreeRate = ud(0.13e18);

        UD60x18[2][7] memory cases;

        // prettier-ignore
        if (isCall) {
            cases = [
                [ud(0.001e18), ud(0)],
                [ud(0.5e18),   ud(0.041651656896334266e18)],
                [ud(0.8e18),   ud(0.19044728282561157e18)],
                [ud(1e18),     ud(0.3361595989775169e18)],
                [ud(1.2e18),   ud(0.5037431520530627e18)],
                [ud(2.2e18),   ud(1.45850009070196e18)],
                [ud(11e18),    ud(10.253264047161903e18)]
            ];
        } else {
            cases = [
                [ud(0.001e18), ud(0.745736013930399e18)],
                [ud(0.5e18),   ud(0.28838767082673333e18)],
                [ud(0.8e18),   ud(0.1371832967560106e18)],
                [ud(1e18),     ud(0.08289561290791586e18)],
                [ud(1.2e18),   ud(0.05047916598346175e18)],
                [ud(2.2e18),   ud(0.005236104632358806e18)],
                [ud(11e18),    ud(0.000000061092302312e18)]
            ];
        }

        for (uint256 i = 0; i < cases.length; i++) {
            assertApproxEqAbs(
                OptionMath
                    .blackScholesPrice(cases[i][0], strike, timeToMaturity, volAnnualized, riskFreeRate, isCall)
                    .unwrap(),
                cases[i][1].unwrap(),
                0.00001e18
            );
        }
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices_Call() public {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(true);
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices_Put() public {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingSpotPrices(false);
    }

    function _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(bool isCall) internal {
        UD60x18 spot = ud(1.3e18);
        UD60x18 strike = ud(0.8e18);
        UD60x18 timeToMaturity = ud(0.53e18);
        UD60x18 riskFreeRate = ud(0.13e18);

        UD60x18[2][7] memory cases;

        // prettier-ignore
        if (isCall) {
            cases = [
                [ud(0.001e18), ud(0.553263986069601e18)],
                [ud(0.5e18),   ud(0.5631148171877948e18)],
                [ud(0.8e18),   ud(0.6042473564031341e18)],
                [ud(1e18),     ud(0.6420186597956653e18)],
                [ud(1.2e18),   ud(0.6834990708190316e18)],
                [ud(2.2e18),   ud(0.8941443650200548e18)],
                [ud(11e18),    ud(1.2999387852636883e18)]
            ];
        } else {
            cases = [
                [ud(0.001e18), ud(0)],
                [ud(0.5e18),   ud(0.009850831118193633e18)],
                [ud(0.8e18),   ud(0.05098337033353306e18)],
                [ud(1e18),     ud(0.08875467372606433e18)],
                [ud(1.2e18),   ud(0.13023508474943063e18)],
                [ud(2.2e18),   ud(0.34088037895045364e18)],
                [ud(11e18),    ud(0.7466747991940875e18)]
            ];
        }

        for (uint256 i = 0; i < cases.length; i++) {
            assertApproxEqAbs(
                OptionMath.blackScholesPrice(spot, strike, timeToMaturity, cases[i][0], riskFreeRate, isCall).unwrap(),
                cases[i][1].unwrap(),
                0.00001e18
            );
        }
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility_Call() public {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(true);
    }

    function test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility_Put() public {
        _test_blackScholesPrice_ReturnExpectedValue_VaryingVolatility(false);
    }

    function test_d1d2_ReturnExpectedValue() public {
        UD60x18 strike = ud(0.8e18);
        UD60x18 timeToMaturity = ud(0.95e18);
        UD60x18 volAnnualized = ud(1.61e18);
        UD60x18 riskFreeRate = ud(0.021e18);

        // prettier-ignore
        SD59x18[3][5] memory cases = [
            [sd(0.5e18), sd(0.49781863364936835e18), sd(-1.0714152558648748e18)],
            [sd(0.8e18), sd(0.7973301547720898e18),  sd(-0.7719037347421535e18)],
            [sd(1.0e18), sd(0.9395291939371717e18),  sd(-0.6297046955770715e18)],
            [sd(1.2e18), sd(1.0557142687129861e18),  sd(-0.5135196208012571e18)],
            [sd(2.2e18), sd(1.441976512742106e18),   sd(-0.12725737677213722e18)]
        ];

        for (uint256 i = 0; i < cases.length; i++) {
            (SD59x18 d1, SD59x18 d2) = OptionMath.d1d2(
                cases[i][0].intoUD60x18(),
                strike,
                timeToMaturity,
                volAnnualized,
                riskFreeRate
            );
            assertApproxEqAbs((d1 - cases[i][1]).unwrap(), 0, 0.00000000000001e18);
            assertApproxEqAbs((d2 - cases[i][2]).unwrap(), 0, 0.00000000000001e18);
        }
    }

    function _test_optionDelta_ReturnExpectedValue(bool isCall) internal {
        UD60x18 strike = ud(1e18);
        UD60x18 timeToMaturity = ud(0.246575e18); // 90 days
        UD60x18 varAnnualized = ud(1e18);
        UD60x18 riskFreeRate = ud(0e18);

        SD59x18[2][7] memory cases;

        // prettier-ignore
        if (isCall) {
            cases = [
                [sd(0.3e18), sd(0.01476537073867126e18)],
                [sd(0.5e18), sd(0.12556553467572473e18)],
                [sd(0.7e18), sd(0.31917577351746684e18)],
                [sd(0.9e18), sd(0.5143996619519293e18)],
                [sd(1.0e18), sd(0.5980417972127483e18)],
                [sd(1.5e18), sd(0.85652221419085e18)],
                [sd(2.0e18), sd(0.9499294514418426e18)]
            ];
        } else {
            cases = [
                [sd(0.3e18), sd(0.01476537073867126e18 - 1e18)],
                [sd(0.5e18), sd(0.12556553467572473e18 - 1e18)],
                [sd(0.7e18), sd(0.31917577351746684e18 - 1e18)],
                [sd(0.9e18), sd(0.5143996619519293e18 - 1e18)],
                [sd(1.0e18), sd(0.5980417972127483e18 - 1e18)],
                [sd(1.5e18), sd(0.85652221419085e18 - 1e18)],
                [sd(2.0e18), sd(0.9499294514418426e18 - 1e18)]
            ];
        }

        for (uint256 i = 0; i < cases.length; i++) {
            assertApproxEqAbs(
                OptionMath
                    .optionDelta(cases[i][0].intoUD60x18(), strike, timeToMaturity, varAnnualized, riskFreeRate, isCall)
                    .unwrap(),
                cases[i][1].unwrap(),
                0.00001e18
            );
        }
    }

    function test_optionDelta_ReturnExpectedValue_Call() internal {
        _test_optionDelta_ReturnExpectedValue(true);
    }

    function test_optionDdelta_ReturnExpectedValue_Put() internal {
        _test_optionDelta_ReturnExpectedValue(false);
    }

    function test_isFriday_ReturnFalse_IfNotFriday() public {
        uint32[8] memory timestamps = [
            1674460800,
            1674547200,
            1674633600,
            1674720000,
            1674777599,
            1674864000,
            1674892800,
            1674979200
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isFriday(timestamps[i]));
        }
    }

    function test_isFriday_ReturnTrue_IfFriday() public {
        uint32[3] memory timestamps = [1674777600, 1674806400, 1674863999];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertTrue(OptionMath.isFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnFalse_IfNotLastWeekOfMonth() public {
        uint32[6] memory timestamps = [1675324800, 1675411200, 1675670400, 1676016000, 1676620800, 1676707200];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnFalse_IfLastWeekOfMonthAndNotFriday() public {
        uint32[9] memory timestamps = [
            1677139200,
            1677312000,
            1677571200,
            1695625200,
            1695798000,
            1696057200,
            1703491200,
            1703750400,
            1704009600
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertFalse(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_isLastFriday_ReturnTrue_IfLastWeekOfMonthAndFriday() public {
        uint32[3] memory timestamps = [1677225600, 1695970800, 1703836800];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertTrue(OptionMath.isLastFriday(timestamps[i]));
        }
    }

    function test_calculateTimeToMaturity_ReturnExpectedValue() public {
        uint256 timestamp = 1683240000;
        uint256 oneWeek = 7 * 24 * 3600;
        vm.warp(timestamp);
        assertEq(OptionMath.calculateTimeToMaturity(uint64(timestamp + oneWeek)), oneWeek);
    }

    function test_calculateStrikeInterval_ReturnExpectedValue() public {
        // prettier-ignore
        UD60x18[2][57] memory values = [
            [ud(1e18),       ud(0.1e18)],
            [ud(2e18),       ud(0.1e18)],
            [ud(3e18),       ud(0.1e18)],
            [ud(4e18),       ud(0.1e18)],
            [ud(5e18),       ud(0.5e18)],
            [ud(6e18),       ud(0.5e18)],
            [ud(7e18),       ud(0.5e18)],
            [ud(8e18),       ud(0.5e18)],
            [ud(9e18),       ud(0.5e18)],
            [ud(10e18),      ud(1e18)],
            [ud(11e18),      ud(1e18)],
            [ud(33e18),      ud(1e18)],
            [ud(49e18),      ud(1e18)],
            [ud(50e18),      ud(5e18)],
            [ud(51e18),      ud(5e18)],
            [ud(74e18),      ud(5e18)],
            [ud(99e18),      ud(5e18)],
            [ud(100e18),     ud(10e18)],
            [ud(101e18),     ud(10e18)],
            [ud(434e18),     ud(10e18)],
            [ud(499e18),     ud(10e18)],
            [ud(500e18),     ud(50e18)],
            [ud(501e18),     ud(50e18)],
            [ud(871e18),     ud(50e18)],
            [ud(999e18),     ud(50e18)],
            [ud(1000e18),    ud(100e18)],
            [ud(1001e18),    ud(100e18)],
            [ud(4356e18),    ud(100e18)],
            [ud(4999e18),    ud(100e18)],
            [ud(5000e18),    ud(500e18)],
            [ud(5001e18),    ud(500e18)],
            [ud(5643e18),    ud(500e18)],
            [ud(9999e18),    ud(500e18)],
            [ud(10000e18),   ud(1000e18)],
            [ud(10001e18),   ud(1000e18)],
            [ud(35321e18),   ud(1000e18)],
            [ud(49999e18),   ud(1000e18)],
            [ud(50000e18),   ud(5000e18)],
            [ud(50001e18),   ud(5000e18)],
            [ud(64312e18),   ud(5000e18)],
            [ud(99999e18),   ud(5000e18)],
            [ud(100000e18),  ud(10000e18)],
            [ud(100001e18),  ud(10000e18)],
            [ud(256110e18),  ud(10000e18)],
            [ud(499999e18),  ud(10000e18)],
            [ud(500000e18),  ud(50000e18)],
            [ud(500001e18),  ud(50000e18)],
            [ud(862841e18),  ud(50000e18)],
            [ud(999999e18),  ud(50000e18)],
            [ud(1000000e18), ud(100000e18)],
            [ud(1000001e18), ud(100000e18)],
            [ud(4321854e18), ud(100000e18)],
            [ud(4999999e18), ud(100000e18)],
            [ud(5000000e18), ud(500000e18)],
            [ud(5000001e18), ud(500000e18)],
            [ud(9418355e18), ud(500000e18)],
            [ud(9999999e18), ud(500000e18)]
        ];

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(OptionMath.calculateStrikeInterval(values[i][0]), values[i][1]);
        }
    }

    function test_roundToStrikeInterval_ReturnExpectedValue() public {
        // prettier-ignore
        UD60x18[2][74] memory values = [
                [ud(0.00000000000000001e18), ud(0.00000000000000001e18)],
                [ud(0.00000000000000111e18), ud(0.00000000000000110e18)],
                [ud(0.00000000000000811e18), ud(0.00000000000000800e18)],
                [ud(0.00000000000000116e18), ud(0.00000000000000120e18)],
                [ud(0.00000000010000111e18), ud(0.00000000010000000e18)],
                [ud(0.00000000099000111e18), ud(0.00000000100000000e18)],
                [ud(0.00002345500000000e18), ud(0.00002300000000000e18)],
                [ud(0.00005800000000100e18), ud(0.00006000000000000e18)],
                [ud(1.25778000099000111e18), ud(1.30000000000000000e18)],
                [ud(10.5990000000000000e18), ud(11.0000000000000000e18)],
                [ud(110.599000000000000e18), ud(110.000000000000000e18)],
                [ud(1e18),       ud(1e18)],
                [ud(2e18),       ud(2e18)],
                [ud(3e18),       ud(3e18)],
                [ud(4e18),       ud(4e18)],
                [ud(5e18),       ud(5e18)],
                [ud(6e18),       ud(6e18)],
                [ud(7e18),       ud(7e18)],
                [ud(8e18),       ud(8e18)],
                [ud(9e18),       ud(9e18)],
                [ud(10e18),      ud(10e18)],
                [ud(11e18),      ud(11e18)],
                [ud(33e18),      ud(33e18)],
                [ud(49e18),      ud(49e18)],
                [ud(50e18),      ud(50e18)],
                [ud(51e18),      ud(50e18)],
                [ud(74e18),      ud(75e18)],
                [ud(99e18),      ud(100e18)],
                [ud(100e18),     ud(100e18)],
                [ud(101e18),     ud(100e18)],
                [ud(434e18),     ud(430e18)],
                [ud(499e18),     ud(500e18)],
                [ud(500e18),     ud(500e18)],
                [ud(501e18),     ud(500e18)],
                [ud(871e18),     ud(850e18)],
                [ud(999e18),     ud(1000e18)],
                [ud(1000e18),    ud(1000e18)],
                [ud(1001e18),    ud(1000e18)],
                [ud(4356e18),    ud(4400e18)],
                [ud(4999e18),    ud(5000e18)],
                [ud(5000e18),    ud(5000e18)],
                [ud(5001e18),    ud(5000e18)],
                [ud(5643e18),    ud(5500e18)],
                [ud(9999e18),    ud(10000e18)],
                [ud(10000e18),   ud(10000e18)],
                [ud(10001e18),   ud(10000e18)],
                [ud(35321e18),   ud(35000e18)],
                [ud(49999e18),   ud(50000e18)],
                [ud(50000e18),   ud(50000e18)],
                [ud(50001e18),   ud(50000e18)],
                [ud(64312e18),   ud(65000e18)],
                [ud(99999e18),   ud(100000e18)],
                [ud(100000e18),  ud(100000e18)],
                [ud(100001e18),  ud(100000e18)],
                [ud(256110e18),  ud(260000e18)],
                [ud(499999e18),  ud(500000e18)],
                [ud(500000e18),  ud(500000e18)],
                [ud(500001e18),  ud(500000e18)],
                [ud(862841e18),  ud(850000e18)],
                [ud(999999e18),  ud(1000000e18)],
                [ud(1000000e18), ud(1000000e18)],
                [ud(1000001e18), ud(1000000e18)],
                [ud(4321854e18), ud(4300000e18)],
                [ud(4999999e18), ud(5000000e18)],
                [ud(5000000e18), ud(5000000e18)],
                [ud(5000001e18), ud(5000000e18)],
                [ud(9418355e18), ud(9500000e18)],
                [ud(9999999e18), ud(10000000e18)],
                [ud(592103573508216e18), ud(600000000000000e18)],
                [ud(841200002215070e18), ud(850000000000000e18)],
                [ud(5524000051020708e18), ud(5500000000000000e18)],
                [ud(1874000024100000e18), ud(1900000000000000e18)],
                [ud(4990000000442141e18), ud(5000000000000000e18)],
                [ud(9990000000000000e18), ud(10000000000000000e18)]
            ];

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(OptionMath.roundToStrikeInterval(values[i][0]), values[i][1]);
        }
    }
}
