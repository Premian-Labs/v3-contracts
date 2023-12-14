// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PoolName} from "contracts/libraries/PoolName.sol";
import {ERC20Mock} from "../token/ERC20Mock.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolNameMock} from "./PoolNameMock.sol";

import {Base_Test} from "../Base.t.sol";

contract PoolName_Unit_Test is Base_Test {
    // Test contracts
    PoolNameMock internal poolName;

    // Variables
    address internal weth;
    address internal wbtc;
    address internal usdc;
    address internal dai;

    function deploy() internal virtual override {
        poolName = new PoolNameMock();

        weth = address(new ERC20Mock("WETH", 18));
        wbtc = address(new ERC20Mock("WBTC", 8));
        usdc = address(new ERC20Mock("USDC", 6));
        dai = address(new ERC20Mock("DAI", 18));
    }

    function test_name_Success() public {
        assertEq(PoolName.name(weth, dai, 1260262160, 100.25e18, true), "WETH-DAI-08DEC2009-100.25-C");
        assertEq(PoolName.name(dai, wbtc, 1698190000, 1000e18, false), "DAI-WBTC-24OCT2023-1000-P");
        assertEq(PoolName.name(weth, usdc, 1709190000, 100000e18, true), "WETH-USDC-29FEB2024-100000-C");
    }

    function test_strikeToString_Success() public {
        assertEq(PoolName.strikeToString(1e18), "1");
        assertEq(PoolName.strikeToString(9e18), "9");
        assertEq(PoolName.strikeToString(10e18), "10");
        assertEq(PoolName.strikeToString(11e18), "11");
        assertEq(PoolName.strikeToString(123456789e18), "123456789");
        assertEq(PoolName.strikeToString(123456789.12345e18), "123456789.12");
        assertEq(PoolName.strikeToString(4.2e18), "4.2");
        assertEq(PoolName.strikeToString(4.25e18), "4.25");
        assertEq(PoolName.strikeToString(4.05e18), "4.05");
        assertEq(PoolName.strikeToString(4.25654e18), "4.25");
        assertEq(PoolName.strikeToString(0.9999999e18), "0.99");
        assertEq(PoolName.strikeToString(0.01e18), "0.01");
        assertEq(PoolName.strikeToString(0.01234e18), "0.012");
        assertEq(PoolName.strikeToString(0.21e18), "0.21");
        assertEq(PoolName.strikeToString(0.000000012345e18), "0.000000012");
    }

    function test_maturityToString_Success() public {
        assertEq(PoolName.maturityToString(1682093863), "21APR2023");
        assertEq(PoolName.maturityToString(1709190000), "29FEB2024");
        assertEq(PoolName.maturityToString(1641020400), "01JAN2022");
        assertEq(PoolName.maturityToString(1672470000), "31DEC2022");
        assertEq(PoolName.maturityToString(1211922922), "27MAY2008");
        assertEq(PoolName.maturityToString(1429216946), "16APR2015");
        assertEq(PoolName.maturityToString(1862320591), "05JAN2029");
        assertEq(PoolName.maturityToString(1327647158), "27JAN2012");
        assertEq(PoolName.maturityToString(1295367482), "18JAN2011");
        assertEq(PoolName.maturityToString(1050040629), "11APR2003");
        assertEq(PoolName.maturityToString(1652902913), "18MAY2022");
    }

    function test_monthToString_Success() public {
        assertEq(PoolName.monthToString(1), "JAN");
        assertEq(PoolName.monthToString(2), "FEB");
        assertEq(PoolName.monthToString(3), "MAR");
        assertEq(PoolName.monthToString(4), "APR");
        assertEq(PoolName.monthToString(5), "MAY");
        assertEq(PoolName.monthToString(6), "JUN");
        assertEq(PoolName.monthToString(7), "JUL");
        assertEq(PoolName.monthToString(8), "AUG");
        assertEq(PoolName.monthToString(9), "SEP");
        assertEq(PoolName.monthToString(10), "OCT");
        assertEq(PoolName.monthToString(11), "NOV");
        assertEq(PoolName.monthToString(12), "DEC");

        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidMonth.selector, 13));

        poolName.monthToString(13);

        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidMonth.selector, 0));

        poolName.monthToString(0);
    }
}
