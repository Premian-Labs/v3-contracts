// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {OptionMathMock} from "./OptionMathMock.sol";
import {Base_Test} from "../Base.t.sol";

contract OptionMath_Unit_Test is Base_Test {
    // Test contracts
    OptionMathMock internal optionMath;

    function deploy() internal virtual override {
        optionMath = new OptionMathMock();
    }

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

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_is8AMUTC_ReturnFalse_IfNot8AMUTC(uint256 input) public {
        input = bound(input, 1672531200, 2335219199);
        vm.assume(input % 24 hours != 8 hours);
        assertFalse(OptionMath.is8AMUTC(input));
    }

    function test_is8AMUTC_ReturnTrue_If8AMUTC() public {
        // prettier-ignore
        uint32[100] memory timestamps = [
            1874217600,1856851200,1807430400,2283321600,1730707200,1685520000,1706515200,2185084800,1797580800,
            2115532800,2008051200,1853222400,2003472000,1732003200,2048572800,1679904000,2051596800,1819612800,
            2048659200,1725091200,1722067200,1911801600,1839398400,2116396800,1895990400,2110348800,1962086400,
            1723449600,2100240000,2254377600,1774857600,1812787200,2053929600,2174544000,2194243200,1679990400,
            1874995200,2252995200,2096611200,2186985600,1692950400,1777276800,2126160000,2172556800,1771142400,
            2052633600,2231481600,2321769600,2123654400,1952668800,2152684800,2111731200,2302761600,2201846400,
            1952582400,2280211200,2180764800,1675324800,2319523200,1840262400,2051078400,1887868800,1794124800,
            1796371200,2282544000,1871193600,1681545600,2306131200,2139120000,1762675200,2232345600,2289456000,
            1749456000,1707206400,2106374400,2323497600,1954828800,2322979200,1789459200,1905062400,2314944000,
            2037945600,2134540800,2260598400,2326262400,2287209600,1695283200,2142316800,1762416000,1795766400,
            2144304000,2073801600,1836806400,2150956800,1943424000,1902297600,2230704000,1810195200,2061878400,
            2008137600
        ];

        for (uint256 i = 0; i < timestamps.length; i++) {
            assertTrue(OptionMath.is8AMUTC(timestamps[i]));
        }
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
        uint32[9] memory timestamps = [
            1675324800,
            1675411200,
            1675670400,
            1676016000,
            1676620800,
            1676707200,
            1679644800,
            1695408787,
            1716576787
        ];

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
        uint32[12] memory timestamps = [
            1674777600,
            1677196800,
            1680220800,
            1682640000,
            1685059200,
            1688083200,
            1690502400,
            1692921600,
            1695945600,
            1698364800,
            1700784000,
            1703808000
        ];

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

    /// forge-config: default.fuzz.runs = 10000
    /// forge-config: default.fuzz.max-test-rejects = 500
    function testFuzz_calculateStrikeInterval_ReturnExpectedValue(
        uint256 inputE1,
        uint256 inputE18,
        uint256 inputE34
    ) public {
        {
            inputE1 = bound(inputE1, 1e1, 1e2 - 1);
            UD60x18 interval = ud(1);
            assertEq(OptionMath.calculateStrikeInterval(ud(inputE1)), interval);
        }

        {
            inputE18 = bound(inputE18, 1e18, 1e19 - 1);
            UD60x18 interval = ud(1e17);
            assertEq(OptionMath.calculateStrikeInterval(ud(inputE18)), interval);
        }

        {
            inputE34 = bound(inputE34, 1e33, 1e34 - 1);
            UD60x18 interval = ud(1e32);
            assertEq(OptionMath.calculateStrikeInterval(ud(inputE34)), interval);
        }
    }

    function test_calculateStrikeInterval_RevertIf_OutOfPriceBounds_Lower() public {
        UD60x18 price = UD60x18.wrap(9);
        vm.expectRevert(
            abi.encodeWithSelector(
                OptionMath.OptionMath__OutOfBoundsPrice.selector,
                UD60x18.wrap(1e1),
                UD60x18.wrap(1e34),
                price
            )
        );

        optionMath.calculateStrikeInterval(price);
    }

    function test_calculateStrikeInterval_RevertIf_OutOfPriceBounds_Upper() public {
        UD60x18 price = UD60x18.wrap(10000000000000000000000000000000001);
        vm.expectRevert(
            abi.encodeWithSelector(
                OptionMath.OptionMath__OutOfBoundsPrice.selector,
                UD60x18.wrap(1e1),
                UD60x18.wrap(1e34),
                price
            )
        );

        optionMath.calculateStrikeInterval(price);
    }

    function test_roundToStrikeInterval_ReturnExpectedValue() public {
        // prettier-ignore
        UD60x18[2][74] memory values = [
                [ud(0.00000000000000001e18), ud(0.00000000000000001e18)],
                [ud(0.00000000000000111e18), ud(0.00000000000000110e18)],
                [ud(0.00000000000000811e18), ud(0.00000000000000810e18)],
                [ud(0.00000000000000116e18), ud(0.00000000000000120e18)],
                [ud(0.00000000010000111e18), ud(0.00000000010000000e18)],
                [ud(0.00000000099000111e18), ud(0.00000000099000000e18)],
                [ud(0.00002345500000000e18), ud(0.00002300000000000e18)],
                [ud(0.00005800000000100e18), ud(0.00005800000000000e18)],
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
                [ud(51e18),      ud(51e18)],
                [ud(74e18),      ud(74e18)],
                [ud(99e18),      ud(99e18)],
                [ud(100e18),     ud(100e18)],
                [ud(101e18),     ud(100e18)],
                [ud(434e18),     ud(430e18)],
                [ud(499e18),     ud(500e18)],
                [ud(500e18),     ud(500e18)],
                [ud(501e18),     ud(500e18)],
                [ud(871e18),     ud(870e18)],
                [ud(999e18),     ud(1000e18)],
                [ud(1000e18),    ud(1000e18)],
                [ud(1001e18),    ud(1000e18)],
                [ud(4356e18),    ud(4400e18)],
                [ud(4999e18),    ud(5000e18)],
                [ud(5000e18),    ud(5000e18)],
                [ud(5001e18),    ud(5000e18)],
                [ud(5643e18),    ud(5600e18)],
                [ud(9999e18),    ud(10000e18)],
                [ud(10000e18),   ud(10000e18)],
                [ud(10001e18),   ud(10000e18)],
                [ud(35321e18),   ud(35000e18)],
                [ud(49999e18),   ud(50000e18)],
                [ud(50000e18),   ud(50000e18)],
                [ud(50001e18),   ud(50000e18)],
                [ud(64312e18),   ud(64000e18)],
                [ud(99999e18),   ud(100000e18)],
                [ud(100000e18),  ud(100000e18)],
                [ud(100001e18),  ud(100000e18)],
                [ud(256110e18),  ud(260000e18)],
                [ud(499999e18),  ud(500000e18)],
                [ud(500000e18),  ud(500000e18)],
                [ud(500001e18),  ud(500000e18)],
                [ud(862841e18),  ud(860000e18)],
                [ud(999999e18),  ud(1000000e18)],
                [ud(1000000e18), ud(1000000e18)],
                [ud(1000001e18), ud(1000000e18)],
                [ud(4321854e18), ud(4300000e18)],
                [ud(4999999e18), ud(5000000e18)],
                [ud(5000000e18), ud(5000000e18)],
                [ud(5000001e18), ud(5000000e18)],
                [ud(9418355e18), ud(9400000e18)],
                [ud(9999999e18), ud(10000000e18)],
                [ud(592103573508216e18), ud(590000000000000e18)],
                [ud(841200002215070e18), ud(840000000000000e18)],
                [ud(5524000051020708e18), ud(5500000000000000e18)],
                [ud(1874000024100000e18), ud(1900000000000000e18)],
                [ud(4990000000442141e18), ud(5000000000000000e18)],
                [ud(9990000000000000e18), ud(10000000000000000e18)]
            ];

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(OptionMath.roundToStrikeInterval(values[i][0]), values[i][1]);
        }
    }

    function test_countSignificantDigits_ReturnExpectedValue() public {
        // prettier-ignore
        UD60x18[2][15] memory values = [
            [ud(995727814214145.735910195834782346e18), ud(18)],
            [ud(592103573508216.0011000056003e18), ud(13)],
            [ud(434.000005100560000000e18), ud(11)],
            [ud(0.000000000000000001e18), ud(18)],
            [ud(0.000000000000000111e18), ud(18)],
            [ud(0.999999999999999999e18), ud(18)],
            [ud(1.025778000099000111e18), ud(18)],
            [ud(10.05990000000000000e18), ud(4)],
            [ud(110.5990000000000000e18), ud(3)],
            [ud(110.5900000000000000e18), ud(2)],
            [ud(248.59e18), ud(2)],
            [ud(1e18), ud(0)],
            [ud(9999999e18), ud(0)],
            [ud(5524000051020708e18), ud(0)],
            [ud(0), ud(0)]
        ];

        for (uint256 i = 0; i < values.length; i++) {
            assertEq(OptionMath.countSignificantDigits(values[i][0]), uint8(values[i][1].unwrap()));
        }
    }
}
