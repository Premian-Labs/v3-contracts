// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {Integration_Test} from "../Integration.t.sol";
import {ISolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";

abstract contract Referral_Integration_Shared_Test is Integration_Test {
    IPoolFactory.PoolKey internal poolKey;
    uint256 internal maturity = 1682668800;

    address internal constant secondaryReferrer = address(0x999);
    IPoolMock pool;
    uint256 internal tradingFee = 200e18;
    UD60x18 internal _tradingFee;

    uint256 internal primaryRebate = 10e18;
    uint256 internal secondaryRebate = 1e18;
    uint256 internal totalRebate = primaryRebate + secondaryRebate;
    bool isCallTest;
    UD60x18 internal _primaryRebate;
    UD60x18 internal _secondaryRebate;
    UD60x18 internal _totalRebate;

    function setUp() public virtual override {
        Integration_Test.setUp();
        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });
        vm.warp(1679758940);
        isCallTest = true;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));

        _tradingFee = fromTokenDecimals(tradingFee);
        _primaryRebate = fromTokenDecimals(primaryRebate);
        _secondaryRebate = fromTokenDecimals(secondaryRebate);
        _totalRebate = _primaryRebate + _secondaryRebate;
    }

    function getPoolToken() internal view returns (address) {
        return isCallTest ? poolKey.base : poolKey.quote;
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
}
