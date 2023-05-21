// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {Position} from "contracts/libraries/Position.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {FlashLoanMock} from "contracts/test/pool/FlashLoanMock.sol";
import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolFlashLoanTest is DeployTest {
    UD60x18 constant FLASH_LOAN_FEE = UD60x18.wrap(0.0009e18); // 0.09%

    function calculateFee(uint256 amount) internal view returns (uint256) {
        UD60x18 fee = scaleDecimals(amount) * FLASH_LOAN_FEE;
        return scaleDecimals(fee);
    }

    function test_maxFlashLoan_ReturnCorrectMax() public {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken();
        deal(poolToken, users.trader, 100 ether);

        assertEq(pool.maxFlashLoan(poolToken), initialCollateral);
    }

    function test_maxFlashLoan_RevertIf_NotPoolToken() public {
        address otherToken = address(0x111);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__NotPoolToken.selector, otherToken));
        pool.maxFlashLoan(otherToken);
    }

    function test_flashFee_ReturnCorrectFee() public {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken();
        deal(poolToken, users.trader, 100 ether);

        assertEq(pool.flashFee(poolToken, initialCollateral / 2), calculateFee(initialCollateral / 2));
    }

    function test_flashFee_RevertIf_NotPoolToken() public {
        address otherToken = address(0x111);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__NotPoolToken.selector, otherToken));
        pool.flashFee(otherToken, 1);
    }

    function test_flashLoan_Single_Success() public {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken();
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2);

        IERC20(poolToken).transfer(address(flashLoanMock), fee);

        flashLoanMock.singleFlashLoan(
            FlashLoanMock.FlashLoan({pool: address(pool), token: poolToken, amount: initialCollateral / 2}),
            true
        );

        assertEq(IERC20(poolToken).balanceOf(address(flashLoanMock)), 0);
        assertEq(IERC20(poolToken).balanceOf(address(pool)), initialCollateral + fee);
    }

    function test_flashLoan_Single_RevertIf_NotRepayed() public {
        posKey.orderType = Position.OrderType.CS;

        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        address poolToken = getPoolToken();
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2);

        IERC20(poolToken).transfer(address(flashLoanMock), fee);

        vm.expectRevert(IPoolInternal.Pool__FlashLoanNotRepayed.selector);

        flashLoanMock.singleFlashLoan(
            FlashLoanMock.FlashLoan({pool: address(pool), token: poolToken, amount: initialCollateral / 2}),
            false
        );
    }

    function test_flashLoan_Multi_Success() public {
        posKey.orderType = Position.OrderType.CS;

        IPoolFactory.PoolKey memory poolKeyTwo = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: ud(1100 ether),
            maturity: 1682668800,
            isCallPool: poolKey.isCallPool
        });

        IPoolFactory.PoolKey memory poolKeyThree = IPoolFactory.PoolKey({
            base: base,
            quote: quote,
            oracleAdapter: address(oracleAdapter),
            strike: ud(1200 ether),
            maturity: 1682668800,
            isCallPool: poolKey.isCallPool
        });

        IPoolMock poolTwo = IPoolMock(factory.deployPool{value: 1 ether}(poolKeyTwo));

        IPoolMock poolThree = IPoolMock(factory.deployPool{value: 1 ether}(poolKeyThree));

        //

        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(pool, poolKey.strike, depositSize);
        uint256 initialCollateralTwo = deposit(poolTwo, poolKeyTwo.strike, depositSize);
        uint256 initialCollateralThree = deposit(poolThree, poolKeyThree.strike, depositSize);

        //

        address poolToken = getPoolToken();
        deal(poolToken, users.trader, 100 ether);
        vm.startPrank(users.trader);

        uint256 fee = calculateFee(initialCollateral / 2);
        uint256 feeTwo = calculateFee(initialCollateralTwo / 2);
        uint256 feeThree = calculateFee(initialCollateralThree / 2);

        FlashLoanMock.FlashLoan[] memory flashLoans = new FlashLoanMock.FlashLoan[](3);
        flashLoans[0] = FlashLoanMock.FlashLoan({pool: address(pool), token: poolToken, amount: initialCollateral / 2});

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

        IERC20(poolToken).transfer(address(flashLoanMock), fee + feeTwo + feeThree);

        flashLoanMock.multiFlashLoan(flashLoans);

        //

        assertEq(IERC20(poolToken).balanceOf(address(flashLoanMock)), 0);
        assertEq(IERC20(poolToken).balanceOf(address(pool)), initialCollateral + fee);
        assertEq(IERC20(poolToken).balanceOf(address(poolTwo)), initialCollateralTwo + feeTwo);
        assertEq(IERC20(poolToken).balanceOf(address(poolThree)), initialCollateralThree + feeThree);
    }

    function test_flashLoan_RevertIf_NotPoolToken() public {
        address otherToken = address(0x111);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__NotPoolToken.selector, otherToken));
        pool.flashLoan(flashLoanMock, otherToken, 1, "");
    }
}
