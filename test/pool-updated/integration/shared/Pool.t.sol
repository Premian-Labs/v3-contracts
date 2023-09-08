// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

import {Pool_Integration_Test} from "../Integration.t.sol";

abstract contract Pool_Integration_Shared_Test is Pool_Integration_Test {
    bool internal isCallTest = true;
    uint256 internal maturity = 1682668800;
    IPoolFactory.PoolKey internal poolKey;
    Position.Key internal posKey;

    IPoolMock internal callPool;
    IPoolMock internal putPool;
    IPoolMock internal pool;
    IERC20 internal token;

    function setUp() public virtual override {
        Pool_Integration_Test.setUp();

        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });

        callPool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
        vm.label({account: address(callPool), newLabel: "CallPool(1000)"});

        poolKey.isCallPool = false;
        putPool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
        vm.label({account: address(putPool), newLabel: "PutPool(1000)"});

        poolKey.isCallPool = true;

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.1 ether),
            upper: ud(0.3 ether),
            orderType: Position.OrderType.LC
        });
    }

    function getStartTimestamp() internal virtual override returns (uint256) {
        return maturity - 2 weeks;
    }

    modifier givenCallOrPut() {
        emit log("givenCall");
        isCallTest = true;
        poolKey.isCallPool = true;
        pool = callPool;
        token = base;
        _;

        emit log("givenPut");
        isCallTest = false;
        poolKey.isCallPool = false;
        pool = putPool;
        token = quote;
        _;
    }

    function getPoolToken() internal view returns (address) {
        return isCallTest ? address(base) : address(quote);
    }

    function contractsToCollateral(UD60x18 amount) internal view returns (UD60x18) {
        return isCallTest ? amount : amount * poolKey.strike;
    }

    function collateralToContracts(UD60x18 amount) internal view returns (UD60x18) {
        return isCallTest ? amount : amount / poolKey.strike;
    }

    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function toTokenDecimals(UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function fromTokenDecimals(UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = ISolidStateERC20(getPoolToken()).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), decimals, 18);
    }

    function tokenId() internal view returns (uint256) {
        return PoolStorage.formatTokenId(posKey.operator, posKey.lower, posKey.upper, posKey.orderType);
    }

    function setActionAuthorization(address user, IUserSettings.Action action, bool authorization) internal {
        IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
        actions[0] = action;

        bool[] memory _authorization = new bool[](1);
        _authorization[0] = authorization;

        vm.prank(user);
        userSettings.setActionAuthorization(users.operator, actions, _authorization);
    }
}
