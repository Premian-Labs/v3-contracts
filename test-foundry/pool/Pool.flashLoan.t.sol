// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {Position} from "contracts/libraries/Position.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {FlashLoanMock} from "contracts/test/pool/FlashLoanMock.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolFlashLoanTest is DeployTest {
    UD60x18 constant FLASH_LOAN_FEE = UD60x18.wrap(0.0009e18); // 0.09%

    function calculateFee(
        uint256 amount,
        bool isCall
    ) internal view returns (uint256) {
        UD60x18 fee = scaleDecimals(amount, isCall) * FLASH_LOAN_FEE;
        return scaleDecimals(fee, isCall);
    }

    function _test_flashLoan_Single_Success(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken(isCall);
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2, isCall);

        IERC20(poolToken).transfer(address(flashLoanMock), fee);

        flashLoanMock.singleFlashLoan(
            FlashLoanMock.FlashLoan({
                pool: address(pool),
                token: poolToken,
                amount: initialCollateral / 2
            }),
            true
        );

        assertEq(IERC20(poolToken).balanceOf(address(flashLoanMock)), 0);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + fee
        );
    }

    function test_flashLoan_Single_Success() public {
        _test_flashLoan_Single_Success(poolKey.isCallPool);
    }

    function _test_flashLoan_Single_RevertIf_NotRepayed(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken(isCall);
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2, isCall);

        IERC20(poolToken).transfer(address(flashLoanMock), fee);

        vm.expectRevert(IPoolInternal.Pool__FlashLoanNotRepayed.selector);

        flashLoanMock.singleFlashLoan(
            FlashLoanMock.FlashLoan({
                pool: address(pool),
                token: poolToken,
                amount: initialCollateral / 2
            }),
            false
        );
    }

    function test_flashLoan_Single_RevertIf_NotRepayed() public {
        _test_flashLoan_Single_RevertIf_NotRepayed(poolKey.isCallPool);
    }

    function _test_flashLoan_Multi_Success(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;

        IPoolFactory.PoolKey memory poolKeyTwo = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1100 ether),
            maturity: 1682668800,
            isCallPool: poolKey.isCallPool
        });

        IPoolFactory.PoolKey memory poolKeyThree = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1200 ether),
            maturity: 1682668800,
            isCallPool: poolKey.isCallPool
        });

        IPoolMock poolTwo = IPoolMock(
            factory.deployPool{value: 1 ether}(poolKeyTwo)
        );

        IPoolMock poolThree = IPoolMock(
            factory.deployPool{value: 1 ether}(poolKeyThree)
        );

        //

        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(pool, poolKey.strike, depositSize);
        uint256 initialCollateralTwo = deposit(
            poolTwo,
            poolKeyTwo.strike,
            depositSize
        );
        uint256 initialCollateralThree = deposit(
            poolThree,
            poolKeyThree.strike,
            depositSize
        );

        //

        address poolToken = getPoolToken(isCall);
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2, isCall);
        uint256 feeTwo = calculateFee(initialCollateralTwo / 2, isCall);
        uint256 feeThree = calculateFee(initialCollateralThree / 2, isCall);

        FlashLoanMock.FlashLoan[]
            memory flashLoans = new FlashLoanMock.FlashLoan[](3);
        flashLoans[0] = FlashLoanMock.FlashLoan({
            pool: address(pool),
            token: poolToken,
            amount: initialCollateral / 2
        });

        flashLoans[1] = FlashLoanMock.FlashLoan({
            pool: address(poolTwo),
            token: poolToken,
            amount: initialCollateralTwo / 2
        });

        flashLoans[2] = FlashLoanMock.FlashLoan({
            pool: address(poolThree),
            token: poolToken,
            amount: initialCollateralThree / 2
        });

        IERC20(poolToken).transfer(
            address(flashLoanMock),
            fee + feeTwo + feeThree
        );

        flashLoanMock.multiFlashLoan(flashLoans);

        //

        assertEq(IERC20(poolToken).balanceOf(address(flashLoanMock)), 0);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + fee
        );
        assertEq(
            IERC20(poolToken).balanceOf(address(poolTwo)),
            initialCollateralTwo + feeTwo
        );
        assertEq(
            IERC20(poolToken).balanceOf(address(poolThree)),
            initialCollateralThree + feeThree
        );
    }

    function test_flashLoan_Multi_Success() public {
        _test_flashLoan_Multi_Success(poolKey.isCallPool);
    }
}
