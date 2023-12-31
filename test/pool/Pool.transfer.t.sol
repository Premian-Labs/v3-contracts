// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/IERC1155BaseInternal.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolBase} from "contracts/pool/IPoolBase.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTransferTest is DeployTest {
    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_SameOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.lp, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.lp,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), (protocolFees / 4) * 3);
        assertEq(pool.getClaimableFees(newKey), protocolFees / 4);
    }

    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_NewOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), (protocolFees / 4) * 3);
        assertEq(pool.getClaimableFees(newKey), protocolFees / 4);
    }

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_SameOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.lp, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.lp,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(newKey), protocolFees);
    }

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_NewOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(newKey), protocolFees);
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_SameOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(transferAmount));

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize - transferAmount);
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_NewOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize - transferAmount);
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_SameOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(depositSize));

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_NewOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(depositSize));

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_DoesNotDeletePosition_OnPartialTransfer() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        Position.KeyInternal memory pKeyInternal = Position.toKeyInternal(posKey, poolKey.strike, poolKey.isCallPool);
        pool.forceUpdateClaimableFees(pKeyInternal);

        {
            Position.Data memory data = pool.getPositionData(pKeyInternal);

            assertTrue(data.claimableFees.unwrap() != 0);
            assertTrue(data.lastFeeRate.unwrap() != 0);
            assertTrue(data.lastDeposit != 0);
        }

        vm.prank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        {
            Position.Data memory data = pool.getPositionData(pKeyInternal);

            assertTrue(data.claimableFees.unwrap() != 0);
            assertTrue(data.lastFeeRate.unwrap() != 0);
            assertTrue(data.lastDeposit != 0);
        }

        Position.KeyInternal memory newKeyInternal = Position.KeyInternal({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        {
            Position.Data memory data = pool.getPositionData(newKeyInternal);

            assertTrue(data.claimableFees.unwrap() != 0);
            assertTrue(data.lastFeeRate.unwrap() != 0);
            assertTrue(data.lastDeposit != 0);
        }
    }

    function test_transferPosition_DeletePosition_OnFullTransfer() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        Position.KeyInternal memory pKeyInternal = Position.toKeyInternal(posKey, poolKey.strike, poolKey.isCallPool);
        pool.forceUpdateClaimableFees(pKeyInternal);

        {
            Position.Data memory data = pool.getPositionData(pKeyInternal);

            assertTrue(data.claimableFees.unwrap() != 0);
            assertTrue(data.lastFeeRate.unwrap() != 0);
            assertTrue(data.lastDeposit != 0);
        }

        vm.prank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        {
            Position.Data memory data = pool.getPositionData(pKeyInternal);

            assertTrue(data.claimableFees.unwrap() == 0);
            assertTrue(data.lastFeeRate.unwrap() == 0);
            assertTrue(data.lastDeposit == 0);
        }

        Position.KeyInternal memory newKeyInternal = Position.KeyInternal({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        {
            Position.Data memory data = pool.getPositionData(newKeyInternal);

            assertTrue(data.claimableFees.unwrap() != 0);
            assertTrue(data.lastFeeRate.unwrap() != 0);
            assertTrue(data.lastDeposit != 0);
        }
    }

    function test_transferPosition_RevertIf_NotOperator() public {
        deposit(1000 ether);

        vm.startPrank(users.trader);

        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.trader));
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(200 ether));
    }

    function test_transferPosition_RevertIf_SameOwner_SameOperator() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__InvalidTransfer.selector);
        pool.transferPosition(posKey, users.lp, users.lp, ud(200 ether));
    }

    function test_transferPosition_RevertIf_SizeIsZero() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.transferPosition(posKey, users.trader, users.lp, ud(0));
    }

    function test_transferPosition_RevertIf_PositionDoesNotExist() public {
        deposit(1000 ether);

        uint256[] memory tokenIds = pool.tokensByAccount(users.otherLP);
        assertEq(tokenIds.length, 0);

        posKey.operator = users.otherLP; // otherLP creates a fake position

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__PositionDoesNotExist.selector, posKey.owner, tokenId())
        );

        vm.prank(users.otherLP);
        pool.transferPosition(posKey, users.trader, users.lp, ud(1000 ether + 1000));
    }

    function test_transferPosition_RevertIf_NotEnoughTokensToTransfer() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__NotEnoughTokens.selector, 1000 ether, 1000 ether + 1000)
        );
        pool.transferPosition(posKey, users.trader, users.lp, ud(1000 ether + 1000));
    }

    function test_safeTransferFrom_TransferLongToken() public {
        trade(1 ether, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), transferAmount);
    }

    function test_safeTransferFrom_TransferShortToken() public {
        trade(1 ether, false);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.SHORT, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), transferAmount);
    }

    function test_safeTransferFrom_TransferNonPositionToken_FromApprovedAddress() public {
        trade(1 ether, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.setApprovalForAll(users.otherTrader, true);

        vm.prank(users.otherTrader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), transferAmount);
    }

    function test_safeTransferFrom_RevertIf_TransferLpPosition() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        vm.prank(users.lp);
        vm.expectRevert(IPoolBase.Pool__UseTransferPositionToTransferLPTokens.selector);
        pool.safeTransferFrom(users.lp, users.trader, tokenId(), 200e18, "");
    }

    function test_safeTransferFrom_RevertIf_NotApproved() public {
        trade(1 ether, false);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.otherTrader);
        vm.expectRevert(IERC1155BaseInternal.ERC1155Base__NotOwnerOrApproved.selector);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.SHORT, transferAmount, "");
    }

    function test_transferPosition_RevertIf_InvalidSize() public {
        uint256 size = 1 ether + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, posKey.lower, posKey.upper, size)
        );
        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(size));
        vm.stopPrank();
        size = 1 ether + 199;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, posKey.lower, posKey.upper, size)
        );
        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(size));
        vm.stopPrank();
        // this one below is expected to pass as the range order has a width of 200 ticks
        size = 1 ether + 400;
        deposit(size);
        vm.startPrank(users.lp);
        size = 1 ether + 200;
        pool.transferPosition(posKey, users.trader, users.trader, ud(size));
        vm.stopPrank();
    }

    function test_getTokenIds_ReturnExpectedValue() public {
        uint256[] memory tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 0);

        deposit(1000 ether);

        tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], tokenId());

        // Trade
        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = toTokenDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, address(0));
        vm.stopPrank();

        //

        vm.prank(users.trader);
        pool.safeTransferFrom(users.trader, users.lp, PoolStorage.SHORT, 500e18, "");

        tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], tokenId());
        assertEq(tokenIds[1], PoolStorage.SHORT);
        assertEq(tokenIds[2], PoolStorage.LONG);

        vm.warp(block.timestamp + 60);

        vm.prank(users.lp);
        pool.withdraw(posKey, ud(1000 ether), ud(0), ud(1e18));

        tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], PoolStorage.LONG);
        assertEq(tokenIds[1], PoolStorage.SHORT);

        vm.prank(users.lp);
        pool.annihilate(ud(200e18));

        tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], PoolStorage.LONG);
        assertEq(tokenIds[1], PoolStorage.SHORT);

        vm.prank(users.lp);
        pool.annihilate(ud(300e18));

        tokenIds = pool.getTokenIds();
        assertEq(tokenIds.length, 0);
    }
}
