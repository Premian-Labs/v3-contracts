// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IVolatilityOracle} from "contracts/oracle/IVolatilityOracle.sol";

import {VolatilityOracleMock} from "contracts/test/oracle/VolatilityOracleMock.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {Base_Test} from "../Base.t.sol";

contract VolatilityOracle_Unit_Concrete_test is Base_Test {
    // Variables
    VolatilityOracleMock internal oracle;
    address internal token = address(1);

    int256[5] internal params = [
        int256(839159148341),
        int256(-59574226567),
        int256(20047063855),
        int256(148950384842),
        int256(34026549310)
    ];

    SD59x18[5] internal values = [
        sd(0.00273972602739726e18),
        sd(0.03561643835616438e18),
        sd(0.09315068493150686e18),
        sd(0.16986301369863013e18),
        sd(0.4191780821917808e18)
    ];

    // prettier-ignore
    function setUp() public virtual override {
        Base_Test.setUp();

        int256[5] memory tau =   [ int256(2739726027),  int256(35616438356), int256(93150684931),  int256(169863013698), int256(419178082191) ];
        int256[5] memory theta = [ int256(1769240990),  int256(19167659692), int256(50651452629),  int256(101097155795), int256(270899488797) ];
        int256[5] memory psi =   [ int256(37206384846), int256(91562361472), int256(161073555196), int256(282476089989), int256(357980351179) ];
        int256[5] memory rho =   [ int256(13478),       int256(2014542),     int256(29103450),     int256(376821442),    int256(253923469) ];

        address[] memory tokens = new address[](1);
        bytes32[] memory tauHex = new bytes32[](1);
        bytes32[] memory thetaHex = new bytes32[](1);
        bytes32[] memory psiHex = new bytes32[](1);
        bytes32[] memory rhoHex = new bytes32[](1);

        tokens[0] = token;
        tauHex[0] = oracle.formatParams(tau);
        thetaHex[0] = oracle.formatParams(theta);
        psiHex[0] = oracle.formatParams(psi);
        rhoHex[0] = oracle.formatParams(rho);

        changePrank({msgSender: users.relayer});

        oracle.updateParams(tokens, tauHex, thetaHex, psiHex, rhoHex, ud(0.01e18));
    }

    function deploy() internal virtual override {
        VolatilityOracleMock impl = new VolatilityOracleMock();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(impl));
        oracle = VolatilityOracleMock(address(proxy));

        address[] memory relayers = new address[](1);
        relayers[0] = users.relayer;

        oracle.addWhitelistedRelayers(relayers);
    }

    function test_formatParams_CorrectlyFormatParameters() public {
        bytes32 paramsFormatted = 0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8;

        int256[5] memory _params = oracle.parseParams(paramsFormatted);
        assertEq(oracle.formatParams(_params), paramsFormatted);
    }

    function test_formatParams_RevertIf_VariableOutOfBounds() public {
        params[4] = int256(1) << 51;
        vm.expectRevert(abi.encodeWithSelector(IVolatilityOracle.VolatilityOracle__OutOfBounds.selector, params[4]));
        oracle.formatParams(params);
    }

    function test_parseParams_CorrectlyParseParameters() public {
        bytes32 result = oracle.formatParams(params);
        int256[5] memory _params = oracle.parseParams(result);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(_params[i], params[i]);
        }
    }

    function test_findInterval_FindValue_IfInFirstInterval() public {
        assertEq(oracle.findInterval(values, sd(0.02e18)), 0);
    }

    function test_findInterval_FindValue_IfInLastInterval() public {
        assertEq(oracle.findInterval(values, sd(0.3e18)), 3);
    }

    function test_getVolatility_PerformExtrapolation_ShortTerm() public {
        UD60x18 iv = oracle.getVolatility(token, ud(2800e18), ud(3500e18), ud(0.001e18));

        uint256 expected = 1.3682433159664105e18;
        assertApproxEqAbs(iv.unwrap(), expected, 0.001e18);
    }

    function test_getVolatility_PerformInterpolation_OnFirstInterval() public {
        UD60x18 iv = oracle.getVolatility(token, ud(2800e18), ud(3500e18), ud(0.02e18));

        uint256 expected = 0.8541332587538256e18;
        assertApproxEqAbs(iv.unwrap(), expected, 0.001e18);
    }

    function test_getVolatility_PerformInterpolation_OnLastInterval() public {
        UD60x18 iv = oracle.getVolatility(token, ud(2800e18), ud(5000e18), ud(0.3e18));

        uint256 expected = 0.8715627609068288e18;
        assertApproxEqAbs(iv.unwrap(), expected, 0.001e18);
    }

    function test_getVolatility_PerformInterpolation_LongTerm() public {
        UD60x18 iv = oracle.getVolatility(token, ud(2800e18), ud(7000e18), ud(0.5e18));

        uint256 expected = 0.88798013e18;
        assertApproxEqAbs(iv.unwrap(), expected, 0.001e18);
    }
}
