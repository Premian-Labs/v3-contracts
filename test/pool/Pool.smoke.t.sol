// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSmokeTest is DeployTest {
    uint256 depositSize = 300000000 ether;
    uint256 tradeSizeR = 50000000 ether;
    string[3] public depositTypes;
    string[4] public actionTypes;

    function _isEqualString(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _runSmoke(string memory depositType, string memory actions) internal {
        bool isCS = _isEqualString(depositType, "CS");
        bool isLC = _isEqualString(depositType, "LC");
        bool isLCCS = _isEqualString(depositType, "LCCS");
        bool isBuy = _isEqualString(actions, "B");
        bool isBuySell = _isEqualString(actions, "BS");
        bool isSell = _isEqualString(actions, "S");
        bool isSellBuy = _isEqualString(actions, "SB");

        if (isLC || isLCCS) {
            posKey.orderType = Position.OrderType.LC;
            if (isBuy || isBuySell) {
                pool.mint(users.lp, PoolStorage.LONG, ud(depositSize));
                deposit(depositSize, false);
            } else {
                deposit(depositSize, true);
            }
        }
        if (isCS || isLCCS) {
            posKey.orderType = Position.OrderType.CS;
            if (isBuy || isBuySell) {
                deposit(depositSize, false);
            } else {
                pool.mint(users.lp, PoolStorage.SHORT, ud(depositSize));
                deposit(depositSize, true);
            }
        }

        if (isBuy || isBuySell) tradeOnly(tradeSizeR, true);
        if (isBuySell) tradeOnly(tradeSizeR, false);

        if (isSell || isSellBuy) tradeOnly(tradeSizeR, false);
        if (isSellBuy) tradeOnly(tradeSizeR, true);

        vm.warp(block.timestamp + 140);
        vm.startPrank(users.lp);

        if (isLC || isLCCS) {
            posKey.orderType = Position.OrderType.LC;
            pool.withdraw(posKey, ud(depositSize), ZERO, ONE);
        }
        if (isCS || isLCCS) {
            posKey.orderType = Position.OrderType.CS;
            pool.withdraw(posKey, ud(depositSize), ZERO, ONE);
        }

        vm.stopPrank();
    }

    function test_Smoke_Buy_CS() public {
        _runSmoke("CS", "B");
    }

    function test_Smoke_Buy_LC() public {
        _runSmoke("LC", "B");
    }

    function test_Smoke_Buy_LCCS() public {
        _runSmoke("LCCS", "B");
    }

    function test_Smoke_BuySell_CS() public {
        _runSmoke("CS", "BS");
    }

    function test_Smoke_BuySell_LC() public {
        _runSmoke("LC", "BS");
    }

    function test_Smoke_BuySell_LCCS() public {
        _runSmoke("LCCS", "BS");
    }

    function test_Smoke_Sell_CS() public {
        _runSmoke("CS", "S");
    }

    function test_Smoke_Sell_LC() public {
        _runSmoke("LC", "S");
    }

    function test_Smoke_Sell_LCCS() public {
        _runSmoke("LCCS", "S");
    }

    function test_Smoke_SellBuy_CS() public {
        _runSmoke("CS", "SB");
    }

    function test_Smoke_SellBuy_LC() public {
        _runSmoke("LC", "SB");
    }

    function test_Smoke_SellBuy_LCCS() public {
        _runSmoke("LCCS", "SB");
    }
}
